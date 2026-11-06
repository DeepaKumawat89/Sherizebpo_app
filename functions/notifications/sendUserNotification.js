const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

/**
 * Utility to create a notification in Firestore and optionally send a push message
 * @param {Object} params
 * @param {string} params.userId - User to notify
 * @param {string} params.title - Notification title
 * @param {string} params.message - Notification body
 * @param {string} params.type - Notification type
 * @param {string} [params.relatedTaskId] - Associated Task
 * @param {string} [params.relatedSubmissionId] - Associated Submission
 */
async function sendUserNotification({ userId, title, message, type, relatedTaskId, relatedSubmissionId }) {
    if (!admin.apps.length) {
        admin.initializeApp();
    }
    const db = admin.firestore();

    try {
        // 1. Save to standard notifications collection (for in-app display)
        const notificationRef = db.collection("notifications").doc();
        await notificationRef.set({
            userId,
            title,
            message,
            type,
            relatedTaskId: relatedTaskId || null,
            relatedSubmissionId: relatedSubmissionId || null,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // 2. Fetch User's FCM Token
        const userDoc = await db.collection("users").doc(userId).get();
        if (!userDoc.exists) {
            console.log(`User ${userId} not found, skipping push notification.`);
            return;
        }

        const fcmToken = userDoc.data().fcmToken;
        if (!fcmToken) {
            console.log(`User ${userId} has no FCM token. Push skipped.`);
            return;
        }

        // 3. Send Push via Firebase Admin
        const payload = {
            notification: {
                title,
                body: message,
            },
            data: {
                type: type || "",
                relatedTaskId: relatedTaskId || "",
                relatedSubmissionId: relatedSubmissionId || "",
                click_action: "FLUTTER_NOTIFICATION_CLICK"
            },
            token: fcmToken,
        };

        const response = await admin.messaging().send(payload);
        console.log(`Successfully sent push notification to ${userId}: ${response}`);
    } catch (error) {
        console.error(`Error sending notification to ${userId}:`, error);
    }
}

exports.sendUserNotification = sendUserNotification;
