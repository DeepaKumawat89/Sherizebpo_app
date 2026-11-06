const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { validateRole, REVIEW_ROLES } = require("../utils/validateAdmin");
const { settleSubmissionPayout } = require("./settleSubmission");
const { leadUpdateForRejection } = require("./leadRejection");
const { isUnpricedCampaign } = require("../campaigns/pricing");
const { parseRequeueAt } = require("../tasks/requeueSchedule");

const db = admin.firestore();

// Whether a submission belongs to a closed-platform (unpriced) campaign, which
// pays nothing and must be QA-approved without any wallet movement.
async function submissionIsUnpriced(database, submissionId) {
    const subSnap = await database.collection("task_submissions").doc(submissionId).get();
    const taskId = subSnap.exists ? subSnap.data().taskId : null;
    if (!taskId) return false;
    const taskSnap = await database.collection("tasks").doc(taskId).get();
    const campaignId = taskSnap.exists ? taskSnap.data().campaignId : null;
    if (!campaignId) return false;
    const campSnap = await database.collection("campaigns").doc(campaignId).get();
    return campSnap.exists && isUnpricedCampaign(campSnap.data());
}

// QA-pass a closed-platform submission: mark it approved and approve the lead,
// with NO client debit, worker credit, or platform commission.
async function approveUnpricedSubmission(database, { submissionId, reviewerId, notes, rating }) {
    const hasRating = typeof rating === "number" && isFinite(rating) && rating >= 1 && rating <= 5;
    const submissionRef = database.collection("task_submissions").doc(submissionId);
    await database.runTransaction(async (txn) => {
        const snap = await txn.get(submissionRef);
        if (!snap.exists) {
            throw new functions.https.HttpsError("not-found", "Submission not found.");
        }
        const submission = snap.data();
        if (submission.status !== "pending_admin_review") {
            throw new functions.https.HttpsError(
                "failed-precondition",
                `Submission is "${submission.status}". Only submissions awaiting QA review can be processed here.`
            );
        }
        let leadRef = null;
        let leadSnap = null;
        if (submission.leadId) {
            leadRef = database.collection("campaign_leads").doc(submission.leadId);
            leadSnap = await txn.get(leadRef);
        }
        txn.update(submissionRef, {
            status: "approved",
            qaResult: "passed",
            qaBy: reviewerId,
            qaAt: admin.firestore.FieldValue.serverTimestamp(),
            qaNotes: notes,
            approvedBy: reviewerId,
            reviewedBy: reviewerId,
            reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
            unpricedApproval: true, // approved with no payout (closed-platform mode)
            ...(hasRating ? { rating } : {}),
        });
        if (leadRef && leadSnap && leadSnap.exists && leadSnap.data().status !== "approved") {
            txn.update(leadRef, {
                status: "approved",
                approvedAt: admin.firestore.FieldValue.serverTimestamp(),
                approvedBy: reviewerId,
            });
        }
    });
}

/**
 * reviewSubmissionQA — Callable Cloud Function (onCall)
 *
 * Single-step review. A reviewer (task_review_admin / kyc_admin / super_admin /
 * admin) listens to the call recording and either:
 *   - PASSES it  → the worker's wallet is credited immediately (settled), the
 *                  submission is marked "approved".
 *   - FAILS it   → status "rejected" (rejectedStage: "qa", no payout). The
 *                  reviewer also chooses what happens to the lead:
 *                    reassign=true  → lead returns to the marketplace so
 *                                     another worker can call it again,
 *                    reassign=false → lead is closed as "rejected".
 *
 * The payment team no longer approves task payouts — they only process
 * withdrawal requests.
 *
 * Called from Flutter:
 *   FirebaseFunctions.instance.httpsCallable('reviewSubmissionQA')
 *     .call({ submissionId, pass: true|false, notes, reassign: true|false });
 */
const reviewSubmissionQA = functions
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "You must be logged in to review submissions."
            );
        }
        const reviewerId = context.auth.uid;

        const submissionId = data && data.submissionId;
        const pass = data && data.pass === true;
        const notes = (data && typeof data.notes === "string") ? data.notes.trim() : "";
        // Optional reviewer rating (1–5). Consolidated into the worker profile by
        // the shared settlement helper when the submission passes.
        const rating = data && data.rating != null ? Number(data.rating) : null;
        // reassign defaults to true (back to marketplace) for backward
        // compatibility; the reviewer can opt out to reject without re-listing.
        const reassign = !data || data.reassign !== false;
        let requeueAfter = null;

        if (!submissionId || typeof submissionId !== "string") {
            throw new functions.https.HttpsError("invalid-argument", "submissionId is required.");
        }
        if (!pass && !notes) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "A reason is required when failing QA review."
            );
        }
        if (!pass && reassign) {
            try {
                requeueAfter = admin.firestore.Timestamp.fromMillis(
                    parseRequeueAt(data && data.requeueAt)
                );
            } catch (error) {
                throw new functions.https.HttpsError("invalid-argument", error.message);
            }
        }

        // ─── Only recording-review roles may act here ───────────────
        await validateRole(db, reviewerId, REVIEW_ROLES);

        const submissionRef = db.collection("task_submissions").doc(submissionId);

        if (pass) {
            const normalizedRating = (rating != null && isFinite(rating) && rating >= 1 && rating <= 5) ? rating : null;
            // Closed-platform (unpriced) campaigns pay nothing — money is hidden
            // from workers too — so QA-approve without touching any wallet.
            if (await submissionIsUnpriced(db, submissionId)) {
                await approveUnpricedSubmission(db, { submissionId, reviewerId, notes, rating: normalizedRating });
            } else {
                // PASS → credit the worker's wallet immediately and mark approved.
                // Money settlement (client debit, worker credit, platform commission,
                // lead → approved) is handled by the shared settlement helper.
                await settleSubmissionPayout(db, {
                    submissionId,
                    adminId: reviewerId,
                    allowedStatuses: ["pending_admin_review"],
                    rating: normalizedRating,
                    extraSubmissionFields: {
                        qaResult: "passed",
                        qaBy: reviewerId,
                        qaAt: admin.firestore.FieldValue.serverTimestamp(),
                        qaNotes: notes,
                    },
                });
            }
        } else {
            // FAIL → reject (no payout). Depending on the reviewer's choice the
            // lead is either returned to the marketplace or closed as rejected.
            await db.runTransaction(async (txn) => {
                const snap = await txn.get(submissionRef);
                if (!snap.exists) {
                    throw new functions.https.HttpsError("not-found", "Submission not found.");
                }
                const submission = snap.data();

                if (submission.status !== "pending_admin_review") {
                    throw new functions.https.HttpsError(
                        "failed-precondition",
                        `Submission is "${submission.status}". Only submissions awaiting QA review can be processed here.`
                    );
                }
                if (reassign) {
                    try {
                        parseRequeueAt(requeueAfter.toMillis());
                    } catch (error) {
                        throw new functions.https.HttpsError("invalid-argument", error.message);
                    }
                }

                // Reads must precede writes.
                let leadRef = null;
                let leadSnap = null;
                if (submission.leadId) {
                    leadRef = db.collection("campaign_leads").doc(submission.leadId);
                    leadSnap = await txn.get(leadRef);
                }

                txn.update(submissionRef, {
                    status: "rejected",
                    qaResult: "failed",
                    qaBy: reviewerId,
                    qaAt: admin.firestore.FieldValue.serverTimestamp(),
                    qaNotes: notes,
                    rejectedStage: "qa",
                    reason: notes || "Failed recording QA review",
                    reviewedBy: reviewerId,
                    reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
                    reassigned: reassign,
                    ...(reassign ? { requeueAfter } : {}),
                });

                // reassign → scheduler republishes at the selected time;
                // otherwise the lead is closed and never re-listed.
                if (leadRef && leadSnap && leadSnap.exists &&
                    leadSnap.data().status !== "approved") {
                    txn.update(leadRef, leadUpdateForRejection(reassign, requeueAfter));
                }
            });
        }

        console.log(`[reviewSubmissionQA] ${submissionId} ${pass ? "PASSED -> approved (paid)" : `FAILED -> rejected (${reassign ? "reassigned to marketplace" : "closed"})`} by ${reviewerId}`);

        return {
            success: true,
            submissionId,
            status: pass ? "approved" : "rejected",
            reassigned: !pass && reassign,
        };
    });

module.exports = { reviewSubmissionQA };
