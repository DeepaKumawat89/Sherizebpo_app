const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { sendUserNotification } = require("./sendUserNotification");

// 1. Task Assigned
exports.onTaskAssigned = functions.firestore
    .document("task_assignments/{assignmentId}")
    .onCreate(async (snap, context) => {
        const data = snap.data();
        const userId = data.workerId; // Assuming workerId holds the assignee

        if (!userId) return null;

        return sendUserNotification({
            userId,
            title: "New Task Assigned",
            message: "You have been assigned a new task.",
            type: "task_assigned",
            relatedTaskId: data.taskId,
        });
    });

// 2. Task Submission Received (Admin)
exports.onTaskSubmissionReceived = functions.firestore
    .document("task_submissions/{submissionId}")
    .onCreate(async (snap, context) => {
        const data = snap.data();

        // Find admins
        if (!admin.apps.length) admin.initializeApp();
        const db = admin.firestore();

        const adminSnapshot = await db.collection("users").where("role", "==", "admin").get();

        const promises = [];
        adminSnapshot.forEach((adminDoc) => {
            promises.push(sendUserNotification({
                userId: adminDoc.id,
                title: "New Task Submission",
                message: "A worker has submitted a task for review.",
                type: "task_submission_received",
                relatedTaskId: data.taskId,
                relatedSubmissionId: snap.id,
            }));
        });

        await Promise.all(promises);
    });

// 3. Submission Approved
// 4. Submission Rejected
exports.onSubmissionUpdated = functions.firestore
    .document("task_submissions/{submissionId}")
    .onUpdate(async (change, context) => {
        const before = change.before.data();
        const after = change.after.data();

        if (before.status !== after.status) {
            const targetUserId = after.userId || after.workerId;
            if (!targetUserId) return null;

            if (after.status === "approved" || after.status === "completed") {
                return sendUserNotification({
                    userId: targetUserId,
                    title: "Task Approved",
                    message: "Your task has been approved.",
                    type: "submission_approved",
                    relatedTaskId: after.taskId,
                    relatedSubmissionId: change.after.id,
                });
            } else if (after.status === "rejected") {
                return sendUserNotification({
                    userId: targetUserId,
                    title: "Task Rejected",
                    message: "Your submission was rejected.",
                    type: "submission_rejected",
                    relatedTaskId: after.taskId,
                    relatedSubmissionId: change.after.id,
                });
            }
        }
        return null;
    });

// 5. Withdrawal Approved
exports.onWithdrawalUpdated = functions.firestore
    .document("withdraw_requests/{requestId}")
    .onUpdate(async (change, context) => {
        const before = change.before.data();
        const after = change.after.data();

        if (before.status !== after.status) {
            if (after.status === "approved" || after.status === "processed") {
                return sendUserNotification({
                    userId: after.userId || after.workerId,
                    title: "Withdrawal Approved",
                    message: "Your withdrawal request has been processed.",
                    type: "withdrawal_approved",
                });
            } else if (after.status === "rejected") {
                return sendUserNotification({
                    userId: after.userId || after.workerId,
                    title: "Withdrawal Rejected",
                    message: "Your withdrawal request was rejected. Please check for details.",
                    type: "withdrawal_rejected",
                });
            }
        }
        return null;
    });

// 6. Payment Released
// Suppose this means payout transactions? The prompt asks for Payment Released. 
// "Your earnings have been credited to your balance."
// Since earnings usually get credited when submission is approved, we could wait for
// an update on transactions or just rely on the Submission Approved trigger, but the spec
// requires a specific push.
// We'll create a trigger on transactions where type is 'credit'.
exports.onTransactionCreated = functions.firestore
    .document("transactions/{transactionId}")
    .onCreate(async (snap, context) => {
        const data = snap.data();
        if (data.type === "credit" && !data.isWithdrawal) {
            if (!admin.apps.length) admin.initializeApp();
            const settings = await admin.firestore()
                .collection("platform_settings").doc("main").get();
            if (settings.data()?.earningsSystemEnabled === false) return null;
            return sendUserNotification({
                userId: data.workerId || data.userId,
                title: "Payment Credited",
                message: "Your earnings have been credited to your balance.",
                type: "payment_released",
                relatedTaskId: data.taskId,
            });
        }
        return null;
    });

// 7. Support Request Submitted (Admin)
exports.onSupportRequestSubmitted = functions.firestore
    .document("support_requests/{requestId}")
    .onCreate(async (snap, context) => {
        if (!admin.apps.length) admin.initializeApp();
        const db = admin.firestore();

        const adminSnapshot = await db.collection("users").where("role", "==", "admin").get();

        const promises = [];
        adminSnapshot.forEach((adminDoc) => {
            promises.push(sendUserNotification({
                userId: adminDoc.id,
                title: "New Support Request",
                message: "A user has submitted a support ticket.",
                type: "support_request_received",
            }));
        });

        await Promise.all(promises);
    });
