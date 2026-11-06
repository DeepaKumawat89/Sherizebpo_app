const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const MAX_REQUEUE = 3;          // After this many retries → mark unreachable

/**
 * Scheduled function running every minute.
 *
 * Finds all campaign_leads where:
 *   status == "requeue_pending"  AND
 *   requeueAfter <= NOW()
 *
 * For each such lead:
 *   - If requeueCount >= MAX_REQUEUE → mark as "unreachable"
 *   - Otherwise → reset to "pending" under the original task's distribution
 *
 * The lead retains:
 *   - isRequeued: true       → Flutter app shows a "Retry Call" badge
 *   - requeueReason          → "no_answer" | "callback"
 *   - requeueCount           → incremented each cycle
 *   - lastCalledBy           → UID of last worker who attempted
 */
exports.requeueLeads = functions.pubsub
    .schedule("every 1 minutes")
    .onRun(async () => {
        const db = admin.firestore();
        const now = admin.firestore.Timestamp.now();

        const snapshot = await db
            .collection("campaign_leads")
            .where("status", "==", "requeue_pending")
            .where("requeueAfter", "<=", now)
            .limit(300)
            .get();

        if (snapshot.empty) {
            console.log("requeueLeads: nothing to requeue.");
            return null;
        }

        let requeued = 0;
        let unreached = 0;

        for (const doc of snapshot.docs) {
            const status = await db.runTransaction(async (transaction) => {
                const fresh = await transaction.get(doc.ref);
                if (!fresh.exists) return null;
                const data = fresh.data();
                if (data.status !== "requeue_pending" || !data.requeueAfter ||
                    data.requeueAfter.toMillis() > now.toMillis()) return null;
                const currentCount = Number(data.requeueCount || 0);
                const nextStatus = currentCount >= MAX_REQUEUE ? "unreachable" : "pending";
                transaction.update(doc.ref, {
                    status: nextStatus,
                    assignedTo: null,
                    lockedAt: null,
                    isRequeued: true,
                    requeueCount: nextStatus === "pending" ? currentCount + 1 : currentCount,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                return nextStatus;
            });
            if (status === "pending") requeued++;
            if (status === "unreachable") unreached++;
        }

        console.log(
            `requeueLeads: requeued=${requeued}, unreachable=${unreached}, total=${snapshot.size}`
        );
        return null;
    });
