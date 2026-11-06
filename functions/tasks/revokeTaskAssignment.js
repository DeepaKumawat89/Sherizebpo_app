const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { validateActiveManager } = require("../utils/teamLeaderAccess");
const { reconcileTaskAvailability } = require("./syncTaskLeadCounts");

// Leads in these states are finished work — revoking must never reset them,
// otherwise already-completed calls would be reworked. Everything else the
// employee still holds is released back to the pending pool.
const RELEASABLE_LEAD_STATUSES = ["pending", "assigned", "in_progress"];

function shouldReleaseLead(lead) {
    return RELEASABLE_LEAD_STATUSES.includes(String(lead.status || "").toLowerCase());
}

// The write that hands an unfinished lead back to the shared pool.
function buildLeadReleaseUpdate() {
    return { status: "pending", assignedTo: null, lockedAt: null };
}

exports.revokeTaskAssignment = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }

    const taskId = String(data?.taskId || "").trim();
    const employeeUid = String(data?.employeeUid || "").trim();
    const assignmentId = String(data?.assignmentId || "").trim();
    if (!taskId || !employeeUid) {
        throw new functions.https.HttpsError("invalid-argument", "A task and an employee are required.");
    }

    const db = admin.firestore();
    await validateActiveManager(db, context.auth.uid);

    const taskRef = db.collection("tasks").doc(taskId);

    const result = await db.runTransaction(async (transaction) => {
        // Bounded by the employee's own assignments (few) and this task's leads.
        const [assignmentsSnap, leadsSnap, taskSnap] = await Promise.all([
            transaction.get(db.collection("task_assignments").where("userId", "==", employeeUid)),
            transaction.get(db.collection("campaign_leads")
                .where("taskId", "==", taskId)
                .where("assignedTo", "==", employeeUid)),
            transaction.get(taskRef),
        ]);

        const assignments = assignmentsSnap.docs.filter((doc) => doc.data().taskId === taskId &&
            ["active", "in_progress"].includes(doc.data().status));
        if (assignmentId && !assignments.some((doc) => doc.id === assignmentId)) {
            throw new functions.https.HttpsError("failed-precondition", "This assignment is no longer active. Refresh the assignment list.");
        }
        if (assignmentsSnap.docs.some((doc) => doc.data().taskId === taskId && doc.data().status === "out_of_tat_processing")) {
            throw new functions.https.HttpsError("failed-precondition", "Expiry cleanup is in progress. Try again shortly.");
        }
        if (assignments.length === 0) {
            throw new functions.https.HttpsError("not-found", "This employee has no active assignment for this task.");
        }

        let released = 0;
        let kept = 0;
        leadsSnap.docs.forEach((leadDoc) => {
            if (shouldReleaseLead(leadDoc.data())) {
                transaction.update(leadDoc.ref, buildLeadReleaseUpdate());
                released += 1;
            } else {
                kept += 1;
            }
        });

        // Free the slot so the task can be re-accepted/re-assigned later, without
        // recreating the task or disturbing the completed leads.
        if (taskSnap.exists) {
            const accepted = Number(taskSnap.data().acceptedCount || 0);
            if (accepted > 0) {
                transaction.update(taskRef, {
                    acceptedCount: Math.max(0, accepted - assignments.length),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        }

        assignments.forEach((assignmentDoc) => transaction.update(assignmentDoc.ref, {
            status: "revoked",
            payoutRecipient: "super_admin",
            revokedBy: context.auth.uid,
            revokedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }));

        return { released, kept };
    });

    await reconcileTaskAvailability(db, taskId);
    return { success: true, taskId, employeeUid, ...result };
});

exports.shouldReleaseLead = shouldReleaseLead;
exports.buildLeadReleaseUpdate = buildLeadReleaseUpdate;
