const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

async function reconcileTaskAvailability(db, taskId) {
    const taskRef = db.collection("tasks").doc(taskId);
    return db.runTransaction(async (transaction) => {
        const taskSnap = await transaction.get(taskRef);
        if (!taskSnap.exists) return false;
        const task = taskSnap.data();
        const [pendingSnap, assignmentsSnap] = await Promise.all([
            transaction.get(db.collection("campaign_leads")
                .where("taskId", "==", taskId)
                .where("status", "==", "pending").count()),
            transaction.get(db.collection("task_assignments")
                .where("taskId", "==", taskId)
                .where("status", "in", ["active", "in_progress", "out_of_tat_processing"]).count()),
        ]);
        const pending = pendingSnap.data().count;
        const occupied = assignmentsSnap.data().count;
        const update = { totalLeads: pending };

        if (task.status === "active") {
            update.acceptedCount = occupied;
            update.remainingSlots = task.distributionMode === "individual"
                ? 0 : Math.max(0, Number(task.totalSlots ?? task.maxSlots ?? 1) - occupied);
            if (pending > 0 && occupied === 0 && task.distributionMode === "individual") {
                update.status = "pending_team_leader";
            }
        }

        if (Object.entries(update).every(([key, value]) => task[key] === value)) return false;
        transaction.update(taskRef, {
            ...update,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
    });
}

exports.reconcileTaskAvailability = reconcileTaskAvailability;

exports.syncTaskAssignmentAvailability = functions.firestore
    .document("task_assignments/{assignmentId}")
    .onWrite(async (change) => {
        const before = change.before.exists ? change.before.data() : null;
        const after = change.after.exists ? change.after.data() : null;
        if (before?.status === after?.status && before?.taskId === after?.taskId) return null;
        const taskId = after?.taskId || before?.taskId;
        if (taskId) await reconcileTaskAvailability(admin.firestore(), taskId);
        return null;
    });

/**
 * syncTaskLeadCounts.js
 *
 * Firestore onWrite trigger: campaign_leads/{leadId}
 *
 * Keeps each task's `totalLeads` equal to the LIVE number of `pending`
 * (available) leads that BELONG TO THAT TASK. That count is what the worker
 * marketplace renders as "X per worker" and what the Accept flow uses to size
 * the worker's lead quota.
 *
 * Per-task ownership: every lead is tagged with exactly one taskId at upload
 * and that tag is never re-stamped, so a lead only ever affects its own task's
 * count. Leads move in and out of the `pending` pool constantly — accepted,
 * completed, marked wrong number, and (crucially) re-queued after a
 * "callback" / "no_answer" outcome. Re-queued leads return to `pending` at
 * their selected retry time via requeueLeads; this trigger recomputes the
 * owning task's count on the transitions that actually change availability (a
 * lead entering or leaving `pending`).
 *
 * Counts and distribution are reconciled without changing lead ownership.
 */
exports.syncTaskLeadCounts = functions.firestore
    .document("campaign_leads/{leadId}")
    .onWrite(async (change) => {
        const before = change.before.exists ? change.before.data() : null;
        const after = change.after.exists ? change.after.data() : null;

        // Normalize uploads from older clients that omitted taskId. Explicit
        // null means "not allocated yet" and lets the one-time allocation
        // query find the lead without assigning it to any task.
        if (!before && after && !Object.prototype.hasOwnProperty.call(after, "taskId")) {
            await change.after.ref.update({ taskId: null });
            return null;
        }

        const beforeStatus = before ? before.status || null : null;
        const afterStatus = after ? after.status || null : null;

        // Only a transition that adds or removes an AVAILABLE (pending) lead can
        // change the marketplace count. Everything else (e.g. in_progress →
        // completed, or → requeue_pending) leaves the pending pool untouched.
        const affectsAvailability =
            (beforeStatus !== afterStatus || before?.taskId !== after?.taskId) &&
            (beforeStatus === "pending" || afterStatus === "pending");
        if (!affectsAvailability) return null;

        const db = admin.firestore();

        // Per-task ownership: a lead belongs to exactly one task (tagged at
        // upload, never re-stamped), so only that task's available count can
        // change. Recompute just that task's pending leads and update it alone.
        const taskId = (after && after.taskId) || (before && before.taskId) || null;
        if (!taskId) return null;

        await reconcileTaskAvailability(db, taskId);

        console.log(
            `syncTaskLeadCounts: task=${taskId} ` +
            `(${beforeStatus}→${afterStatus})`
        );
        return null;
    });
