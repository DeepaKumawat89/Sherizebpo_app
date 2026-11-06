const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { validateActiveManager } = require("../utils/teamLeaderAccess");

const PENDING_STATUS = "pending_team_leader";

function buildDistributionUpdate(task, action, managerId, timestamp) {
    if (task.status !== PENDING_STATUS) {
        throw new functions.https.HttpsError("failed-precondition", "This task has already been distributed.");
    }

    if (action === "publish") {
        return {
            status: "active",
            distributionMode: "marketplace",
            remainingSlots: Math.max(0, Number(task.totalSlots ?? task.maxSlots ?? 1) - Number(task.acceptedCount || 0)),
            publishedByTeamLeaderId: managerId,
            publishedAt: timestamp,
        };
    }

    throw new functions.https.HttpsError("invalid-argument", "Action must be publish.");
}

exports.updateTaskDistribution = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }

    const taskId = String(data?.taskId || "").trim();
    const action = String(data?.action || "").trim().toLowerCase();
    if (!taskId || action !== "publish") {
        throw new functions.https.HttpsError("invalid-argument", "Task and a valid action are required.");
    }

    const db = admin.firestore();
    await validateActiveManager(db, context.auth.uid);
    const taskRef = db.collection("tasks").doc(taskId);

    await db.runTransaction(async (transaction) => {
        const taskSnap = await transaction.get(taskRef);
        if (!taskSnap.exists) {
            throw new functions.https.HttpsError("not-found", "Task not found.");
        }

        const task = taskSnap.data();
        if (action === "publish" && task.campaignId) {
            const campaignSnap = await transaction.get(db.collection("campaigns").doc(task.campaignId));
            if (!campaignSnap.exists || campaignSnap.data().status !== "active") {
                throw new functions.https.HttpsError("failed-precondition", "Activate the campaign before publishing this task.");
            }
        }

        const update = buildDistributionUpdate(
            task,
            action,
            context.auth.uid,
            admin.firestore.Timestamp.now()
        );
        if (Object.keys(update).length) transaction.update(taskRef, update);
    });

    return { success: true, action };
});

exports.buildDistributionUpdate = buildDistributionUpdate;