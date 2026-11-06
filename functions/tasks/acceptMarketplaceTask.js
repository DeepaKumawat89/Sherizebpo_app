const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

exports.acceptMarketplaceTask = functions.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in to accept tasks.");
    const taskId = typeof data?.taskId === "string" ? data.taskId.trim() : "";
    if (!taskId || taskId.includes("/")) throw new functions.https.HttpsError("invalid-argument", "A valid task is required.");
    const db = admin.firestore();
    const userId = context.auth.uid;
    const taskRef = db.collection("tasks").doc(taskId);
    const assignmentRef = db.collection("task_assignments").doc();
    return db.runTransaction(async (transaction) => {
        const [userSnap, taskSnap] = await Promise.all([
            transaction.get(db.collection("users").doc(userId)),
            transaction.get(taskRef),
        ]);
        const user = userSnap.data();
        if (!userSnap.exists || user.isActive === false ||
            !["approved", "verified"].includes(String(user.kycStatus || user.kyc_status || "").toLowerCase())) {
            throw new functions.https.HttpsError("permission-denied", "Approved KYC and an active account are required.");
        }
        if (!taskSnap.exists) throw new functions.https.HttpsError("not-found", "Task no longer exists.");
        const task = taskSnap.data();
        if (task.status !== "active" || task.distributionMode === "individual") {
            throw new functions.https.HttpsError("failed-precondition", "This task is not available in the marketplace.");
        }
        if (task.campaignId) {
            const campaign = await transaction.get(db.collection("campaigns").doc(task.campaignId));
            if (!campaign.exists || campaign.data().status !== "active") {
                throw new functions.https.HttpsError("failed-precondition", "This campaign is not active.");
            }
        }
        const [assignments, pending] = await Promise.all([
            transaction.get(db.collection("task_assignments").where("taskId", "==", taskId)
                .where("status", "in", ["active", "in_progress", "out_of_tat_processing"])),
            transaction.get(db.collection("campaign_leads").where("taskId", "==", taskId)
                .where("status", "==", "pending").count()),
        ]);
        if (assignments.docs.some((doc) => doc.data().userId === userId)) {
            throw new functions.https.HttpsError("already-exists", "Already accepted this task. Finish the current attempt first.");
        }
        const slots = Number(task.totalSlots ?? task.maxSlots ?? 1);
        if (!Number.isInteger(slots) || slots <= assignments.size) {
            throw new functions.https.HttpsError("resource-exhausted", "No slots available.");
        }
        const totalLeads = pending.data().count;
        if (!totalLeads) throw new functions.https.HttpsError("failed-precondition", "No leads available");
        const quota = Math.ceil(totalLeads / (slots - assignments.size));
        const acceptedAt = admin.firestore.Timestamp.now();
        const tatHours = Math.max(0.25, Number(task.tatHours) || 3);
        transaction.update(taskRef, {
            acceptedCount: assignments.size + 1,
            remainingSlots: Math.max(0, slots - assignments.size - 1),
            totalLeads,
            updatedAt: acceptedAt,
        });
        transaction.set(assignmentRef, {
            taskId, userId, status: "active", acceptedAt,
            tatDeadline: admin.firestore.Timestamp.fromMillis(acceptedAt.toMillis() + tatHours * 3600000),
            title: task.title || "", payout: task.payout || 0,
            clientName: task.clientName || "", campaignId: task.campaignId || "",
            totalLeads: quota,
            leadsProcessed: 0,
            processedLeadIds: [],
        });
        return { assignmentId: assignmentRef.id, acceptedCount: assignments.size + 1 };
    });
});