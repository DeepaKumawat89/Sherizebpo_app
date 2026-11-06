const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const db = admin.firestore();
const MAX_TASK_UPDATES = 450;

const setClientCampaignStatus = functions
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "You must be logged in.");
        }
        const allowed = ["campaignId", "status"];
        if (!data || typeof data !== "object" || Array.isArray(data)
            || Object.keys(data).some((key) => !allowed.includes(key))) {
            throw new functions.https.HttpsError("invalid-argument", "Invalid campaign status request.");
        }
        const campaignId = typeof data.campaignId === "string" ? data.campaignId.trim() : "";
        const status = data.status;
        if (!campaignId || campaignId.length > 150 || !["active", "paused"].includes(status)) {
            throw new functions.https.HttpsError("invalid-argument", "A valid campaign and active/paused status are required.");
        }

        const uid = context.auth.uid;
        const clientRef = db.collection("clients").doc(uid);
        const campaignRef = db.collection("campaigns").doc(campaignId);
        const tasksQuery = db.collection("tasks").where("campaignId", "==", campaignId).limit(MAX_TASK_UPDATES + 1);

        return db.runTransaction(async (transaction) => {
            const clientSnapshot = await transaction.get(clientRef);
            const campaignSnapshot = await transaction.get(campaignRef);
            const tasksSnapshot = await transaction.get(tasksQuery);
            if (!clientSnapshot.exists
                || clientSnapshot.data().kycStatus !== "approved"
                || clientSnapshot.data().accountActive !== true) {
                throw new functions.https.HttpsError("permission-denied", "Your client account must be approved and active.");
            }
            if (!campaignSnapshot.exists) {
                throw new functions.https.HttpsError("not-found", "Campaign not found.");
            }
            const campaign = campaignSnapshot.data();
            if (campaign.clientId !== uid) {
                throw new functions.https.HttpsError("permission-denied", "You can only manage your own campaign.");
            }
            if (!["active", "paused"].includes(campaign.status)) {
                throw new functions.https.HttpsError("failed-precondition", "Only active or paused campaigns can change status.");
            }
            if (tasksSnapshot.size > MAX_TASK_UPDATES) {
                throw new functions.https.HttpsError("resource-exhausted", "This campaign has too many tasks to update safely.");
            }

            const now = admin.firestore.FieldValue.serverTimestamp();
            transaction.update(campaignRef, { status, updatedAt: now });
            let updatedTasks = 0;
            for (const taskSnapshot of tasksSnapshot.docs) {
                if (["active", "paused"].includes(taskSnapshot.data().status)) {
                    transaction.update(taskSnapshot.ref, { status, updatedAt: now });
                    updatedTasks++;
                }
            }
            return { campaignId, status, updatedTasks };
        });
    });

module.exports = { setClientCampaignStatus };
