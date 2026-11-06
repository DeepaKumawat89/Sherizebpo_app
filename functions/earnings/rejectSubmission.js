const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { validateAdmin } = require("../utils/validateAdmin");
const {
    runTransaction,
    serverTimestamp,
} = require("../utils/firestoreTransaction");

const db = admin.firestore();

/**
 * rejectTaskSubmission — Callable Cloud Function (onCall)
 *
 * Called by Flutter via: FirebaseFunctions.instance.httpsCallable('rejectTaskSubmission')
 */
const rejectTaskSubmission = functions
    .runWith({ timeoutSeconds: 60, memory: "512MB" })
    .https.onCall(async (data, context) => {
        // ─── Auth Check ──────────────────────────────────────────────
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "You must be logged in to reject submissions."
            );
        }

        const authUid = context.auth.uid;

        // ─── Input Validation ────────────────────────────────────────
        const submissionId = data && data.submissionId;
        const adminId = data && data.adminId;
        const reason = (data && data.reason) || "No reason provided";

        if (!submissionId || typeof submissionId !== "string") {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "submissionId is required and must be a string."
            );
        }

        if (!adminId || typeof adminId !== "string") {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "adminId is required and must be a string."
            );
        }

        if (authUid !== adminId) {
            throw new functions.https.HttpsError(
                "permission-denied",
                "You are not authorized to reject submissions."
            );
        }

        // ─── Validate Admin Role ─────────────────────────────────────
        await validateAdmin(db, adminId);

        // ─── Fetch Submission ────────────────────────────────────────
        const submissionRef = db.collection("task_submissions").doc(submissionId);
        const submissionSnap = await submissionRef.get();

        if (!submissionSnap.exists) {
            throw new functions.https.HttpsError(
                "not-found",
                `Submission ${submissionId} not found.`
            );
        }

        const submission = submissionSnap.data();

        if (submission.status !== "pending_admin_review" && submission.status !== "pending_payment") {
            throw new functions.https.HttpsError(
                "failed-precondition",
                `Submission is already "${submission.status}". Cannot reject.`
            );
        }

        const { userId } = submission;

        // ─── Atomic Transaction ──────────────────────────────────────
        await runTransaction(
            db,
            `Reject submission ${submissionId}`,
            async (transaction) => {
                // ── READS ──
                const freshSnap = await transaction.get(submissionRef);
                if (!freshSnap.exists) {
                    throw new functions.https.HttpsError(
                        "not-found",
                        "Submission document disappeared during processing."
                    );
                }

                const freshData = freshSnap.data();
                if (freshData.status !== "pending_admin_review" && freshData.status !== "pending_payment") {
                    throw new functions.https.HttpsError(
                        "failed-precondition",
                        `Submission status changed to "${freshData.status}" during processing.`
                    );
                }

                const pendingQuery = await transaction.get(
                    db.collection("earnings_pending")
                        .where("submissionId", "==", submissionId)
                        .limit(1)
                );

                // ── WRITES ──
                transaction.update(submissionRef, {
                    status: "rejected",
                    reviewedBy: adminId,
                    reviewedAt: serverTimestamp(),
                    reason: reason,
                    rejectedStage: freshData.status === "pending_payment" ? "payment" : "qa",
                });

                if (!pendingQuery.empty) {
                    transaction.update(pendingQuery.docs[0].ref, {
                        status: "rejected",
                        rejectedAt: serverTimestamp(),
                        reason: reason,
                    });
                }
            }
        );

        console.log(`[RejectSuccess] Submission ${submissionId} rejected by admin ${adminId}. Reason: ${reason}`);

        return {
            success: true,
            message: "Submission rejected.",
            submissionId,
            userId,
        };
    });

module.exports = { rejectTaskSubmission };
