const admin = require("firebase-admin");

/**
 * Shared by the QA-review reject path.
 *
 * When a reviewer rejects a submission they choose whether to reassign the lead:
 *   - reassign === true  → lead waits in "requeue_pending" until the reviewer's
 *                          selected time, then the scheduler republishes it.
 *   - reassign === false → lead is closed as "rejected" and never re-listed;
 *
 * Either way the worker lock (assignedTo/lockedAt) is cleared so the lead is
 * never left stuck holding a slot.
 */
function leadUpdateForRejection(reassign, requeueAfter = null) {
    return {
        status: reassign ? "requeue_pending" : "rejected",
        assignedTo: null,
        lockedAt: null,
        isRequeued: reassign,
        rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(reassign ? {
            requeueAfter,
            requeueReason: "qa_rejected",
            requeueCount: 0,
        } : {}),
        lastOutcome: "qa_failed",
    };
}

module.exports = { leadUpdateForRejection };
