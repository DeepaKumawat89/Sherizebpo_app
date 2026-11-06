const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { reconcileTaskAvailability } = require("./syncTaskLeadCounts");

/**
 * Scheduled function running every 5 minutes.
 * Checks for expired or partially processed task assignments.
 * Marks them as out_of_tat.
 * Allocates formal Earnings Record for the super_admin.
 * Releases the worker's locked leads back to their original task.
 */
exports.enforceTatAndRecreate = functions.pubsub
    .schedule("every 5 minutes")
    .onRun(async () => {
        const db = admin.firestore();
        const now = admin.firestore.Timestamp.now();

        const snapshot = await db.collection("task_assignments")
            .where("status", "in", ["active", "in_progress", "out_of_tat_processing"])
            .where("tatDeadline", "<", now)
            .limit(200) // Bound work per run; the 5-min schedule catches up over time.
            .get();

        if (snapshot.empty) {
            return null;
        }

        for (const doc of snapshot.docs) {
            const assignment = doc.data();
            const taskRef = db.collection("tasks").doc(assignment.taskId);
            const expiry = await db.runTransaction(async (transaction) => {
                const [freshAssignmentSnap, taskSnap] = await Promise.all([
                    transaction.get(doc.ref),
                    transaction.get(taskRef),
                ]);
                if (!freshAssignmentSnap.exists) return null;

                const freshAssignment = freshAssignmentSnap.data();
                const deadline = freshAssignment.tatDeadline;
                if (!["active", "in_progress", "out_of_tat_processing"].includes(freshAssignment.status) ||
                    !deadline || deadline.toMillis() >= now.toMillis()) {
                    return null;
                }

                if (freshAssignment.status !== "out_of_tat_processing") {
                    transaction.update(doc.ref, {
                        status: "out_of_tat_processing",
                        payoutRecipient: "super_admin",
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }

                return true;
            });

            // Another scheduler run or a just-completed submission won the
            // transaction. In either case, this assignment needs no work.
            if (!expiry) continue;

            const lockedLeadsSnap = await db.collection("campaign_leads")
                    .where("taskId", "==", assignment.taskId)
                    .where("assignedTo", "==", assignment.userId)
                    .where("status", "in", ["pending", "assigned", "in_progress"])
                    .get();

            for (const leadDoc of lockedLeadsSnap.docs) {
                await db.runTransaction(async (transaction) => {
                    const [freshLeadSnap, freshAssignmentSnap] = await Promise.all([
                        transaction.get(leadDoc.ref), transaction.get(doc.ref),
                    ]);
                    if (!freshLeadSnap.exists || !freshAssignmentSnap.exists ||
                        freshAssignmentSnap.data().status !== "out_of_tat_processing") return;
                    const lead = freshLeadSnap.data();
                    if (lead.taskId !== assignment.taskId ||
                        lead.assignedTo !== assignment.userId ||
                        !["pending", "assigned", "in_progress"].includes(lead.status) ||
                        (lead.activeAssignmentId && lead.activeAssignmentId !== doc.id)) {
                        return;
                    }
                    transaction.update(leadDoc.ref, {
                        status: "pending",
                        assignedTo: null,
                        lockedAt: null,
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                });
            }

            await db.runTransaction(async (transaction) => {
                const [freshAssignmentSnap, taskSnap] = await Promise.all([
                    transaction.get(doc.ref), transaction.get(taskRef),
                ]);
                if (!freshAssignmentSnap.exists ||
                    freshAssignmentSnap.data().status !== "out_of_tat_processing") {
                    return;
                }
                transaction.update(doc.ref, {
                    status: "out_of_tat",
                    payoutRecipient: "super_admin",
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                if (taskSnap.exists) transaction.update(taskRef, {
                    acceptedCount: Math.max(0, Number(taskSnap.data().acceptedCount || 0) - 1),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            });
            await reconcileTaskAvailability(db, assignment.taskId);
        }
        
        console.log(`Processed ${snapshot.size} out of TAT assignments.`);
        return null;
    });
