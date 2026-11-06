const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { validateRole, PAYMENT_ROLES } = require("../utils/validateAdmin");
const { settleSubmissionPayout } = require("./settleSubmission");

const db = admin.firestore();

/**
 * approveTaskSubmission — Callable Cloud Function (onCall)
 *
 * Legacy payment approval for submissions still sitting in "pending_payment".
 * The normal flow now credits the worker at QA accept (reviewSubmissionQA), so
 * this exists only to clear any already-queued pending_payment items.
 *
 * Called by Flutter via: FirebaseFunctions.instance.httpsCallable('approveTaskSubmission')
 */
const approveTaskSubmission = functions
    .runWith({ timeoutSeconds: 60, memory: "512MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "You must be logged in to approve submissions."
            );
        }

        const authUid = context.auth.uid;
        const submissionId = data && data.submissionId;
        const adminId = data && data.adminId;
        const rating = data && data.rating != null ? Number(data.rating) : null;

        if (!submissionId || typeof submissionId !== "string") {
            throw new functions.https.HttpsError("invalid-argument", "submissionId is required and must be a string.");
        }
        if (!adminId || typeof adminId !== "string") {
            throw new functions.https.HttpsError("invalid-argument", "adminId is required and must be a string.");
        }
        if (authUid !== adminId) {
            throw new functions.https.HttpsError("permission-denied", "You are not authorized to approve submissions.");
        }
        if (rating == null || !isFinite(rating) || rating < 1 || rating > 5) {
            throw new functions.https.HttpsError("invalid-argument", "A rating between 1 and 5 is required to approve.");
        }

        await validateRole(db, adminId, PAYMENT_ROLES);

        const { payout } = await settleSubmissionPayout(db, {
            submissionId,
            adminId,
            allowedStatuses: ["pending_payment"],
            rating,
        });

        console.log(`[ApproveSuccess] Submission ${submissionId} approved & credited ₹${payout}.`);

        return {
            success: true,
            message: "Task submission approved and payout credited to wallet.",
            submissionId,
            payout,
        };
    });

module.exports = { approveTaskSubmission };
