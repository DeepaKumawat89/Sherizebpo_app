const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { reconcileTaskAvailability } = require("./syncTaskLeadCounts");

/**
 * reconcileTaskLeadCounts.js
 *
 * Scheduled safety-net (every 5 minutes).
 *
 * The real-time `syncTaskLeadCounts` trigger keeps a task's `totalLeads` in
 * sync with its own live `pending` lead count on every lead change. This
 * scheduled job backfills any task that drifted out of sync — most importantly
 * tasks that were already stale BEFORE the trigger existed (their count never
 * gets recomputed until a lead changes, which may be never).
 *
 * It only writes when counts, occupied capacity, or distribution need repair.
 */
exports.reconcileTaskLeadCounts = functions.pubsub
    .schedule("every 5 minutes")
    .onRun(async () => {
        const db = admin.firestore();

        const tasksSnap = await db
            .collection("tasks")
            .where("status", "==", "active")
            .get();

        if (tasksSnap.empty) return null;

        let fixed = 0;

        for (const task of tasksSnap.docs) {
            if (await reconcileTaskAvailability(db, task.id)) fixed++;
        }

        if (fixed > 0) {
            console.log(`reconcileTaskLeadCounts: corrected ${fixed} task(s).`);
        }
        return null;
    });
