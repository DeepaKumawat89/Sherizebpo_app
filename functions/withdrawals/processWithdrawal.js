/**
 * processWithdrawal.js
 *
 * HTTPS Callable Cloud Function: processWithdrawal
 *
 * Admin-only function to approve or reject a pending withdrawal:
 *
 * If APPROVED:
 *   - Update request status → approved
 *   - Create payout_history record
 *   - Decrease lockedBalance
 *
 * If REJECTED:
 *   - Return funds: earnings += amount, lockedBalance -= amount
 *   - Update request status → rejected
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { validateAdmin } = require("../utils/validateAdmin");
const {
    runTransaction,
    serverTimestamp,
    increment,
} = require("../utils/firestoreTransaction");

const db = admin.firestore();

/**
 * processWithdrawal — Callable Cloud Function
 *
 * @param {Object} data - { withdrawRequestId, adminId, status }
 * @param {Object} context - Firebase callable context with auth
 * @returns {Object} { success, message }
 */
const processWithdrawal = functions
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (data, context) => {
    // ─── Input Validation ────────────────────────────────────────
    const { withdrawRequestId, adminId, status } = data || {};

    if (!withdrawRequestId || typeof withdrawRequestId !== "string") {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "withdrawRequestId is required and must be a string."
        );
    }

    if (!adminId || typeof adminId !== "string") {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "adminId is required and must be a string."
        );
    }

    if (!status || !["approved", "rejected"].includes(status)) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            'status must be "approved" or "rejected".'
        );
    }

    // ─── Auth Check ──────────────────────────────────────────────
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Authentication required."
        );
    }

    if (context.auth.uid !== adminId) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Admin ID does not match authenticated user."
        );
    }

    // ─── Validate Admin Role ─────────────────────────────────────
    await validateAdmin(db, adminId);

    // ─── Fetch Withdrawal Request ────────────────────────────────
    const withdrawRef = db.collection("withdraw_requests").doc(withdrawRequestId);
    const withdrawSnap = await withdrawRef.get();

    if (!withdrawSnap.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            `Withdrawal request ${withdrawRequestId} not found.`
        );
    }

    const withdrawData = withdrawSnap.data();

    // PHASE 1 & 2: Pre-check Idempotency
    if (withdrawData.status !== "pending" || withdrawData.processed === true) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            `Request is already "${withdrawData.status}" or previously processed. Cannot process again.`
        );
    }

    const { userId, amount } = withdrawData;

    // PHASE 9: Strict Data Validation
    if (!userId || !amount || typeof amount !== "number" || amount <= 0 || !isFinite(amount)) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Withdrawal request has strict invalid data (userId or amount)."
        );
    }

    const userRef = db.collection("users").doc(userId);

    // ─── Process Based on Status ─────────────────────────────────
    if (status === "approved") {
        await _processApproval(withdrawRef, userRef, withdrawRequestId, adminId, userId, amount);
    } else {
        await _processRejection(withdrawRef, userRef, withdrawRequestId, adminId, userId, amount);
    }

    // PHASE 12: Write native audit log outside primary transaction block.
    try {
        await db.collection("audit_logs").add({
            action: status === "approved" ? "approve_withdrawal" : "reject_withdrawal",
            adminId: adminId,
            targetUserId: userId,
            targetDocumentId: withdrawRequestId,
            amount: amount,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });
    } catch (auditErr) {
        console.error("Failed to write audit log:", auditErr);
    }

    return {
        success: true,
        message:
            status === "approved"
                ? `Withdrawal of ₹${amount} approved and queued for payout.`
                : `Withdrawal of ₹${amount} rejected. Funds returned.`,
    };
});

// ─── Private: Approve Withdrawal ─────────────────────────────
async function _processApproval(
    withdrawRef,
    userRef,
    withdrawRequestId,
    adminId,
    userId,
    amount
) {
    const result = await runTransaction(
        db,
        `Approve withdrawal ${withdrawRequestId}`,
        async (transaction) => {
            // Re-read request inside transaction
            const freshWithdraw = await transaction.get(withdrawRef);
            // Strict transaction Idempotency
            if (!freshWithdraw.exists || freshWithdraw.data().status !== "pending" || freshWithdraw.data().processed === true) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Withdrawal request status changed during processing or already completed."
                );
            }

            // Update request → approved & mark processed
            transaction.update(withdrawRef, {
                status: "approved",
                processedBy: adminId,
                processedAt: serverTimestamp(),
                processed: true
            });

            // Create payout_history record
            const payoutRef = db.collection("payout_history").doc();
            transaction.set(payoutRef, {
                userId: userId,
                amount: amount,
                withdrawRequestId: withdrawRequestId,
                paidBy: adminId,
                paidAt: serverTimestamp(),
            });

            // Decrease lockedBalance (funds leave the system)
            transaction.update(userRef, {
                lockedBalance: increment(-amount),
            });

            return { payoutId: payoutRef.id };
        }
    );

    // Update the pending transaction to success (outside main transaction)
    try {
        const txQuery = await db.collection("transactions")
            .where("referenceId", "==", withdrawRequestId)
            .where("userId", "==", userId)
            .where("status", "==", "pending")
            .limit(1)
            .get();
        if (!txQuery.empty) {
            await txQuery.docs[0].ref.update({
                status: "success",
                description: `Withdrawal of ₹${amount} approved`,
            });
        }
    } catch (err) {
        console.warn(`[Approve] Failed to update transaction status for withdrawal ${withdrawRequestId}:`, err.message);
    }

    console.log(
        JSON.stringify({
            event: "WITHDRAWAL_APPROVED",
            withdrawRequestId,
            userId,
            amount,
            adminId,
            payoutId: result.payoutId,
            timestamp: new Date().toISOString(),
        })
    );
}

// ─── Private: Reject Withdrawal ──────────────────────────────
async function _processRejection(
    withdrawRef,
    userRef,
    withdrawRequestId,
    adminId,
    userId,
    amount
) {
    await runTransaction(
        db,
        `Reject withdrawal ${withdrawRequestId}`,
        async (transaction) => {
            // 1. ALL READS FIRST
            // Re-read request inside transaction
            const freshWithdraw = await transaction.get(withdrawRef);
            if (!freshWithdraw.exists || freshWithdraw.data().status !== "pending") {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Withdrawal request status changed during processing."
                );
            }

            // Read user doc safely
            const userSnap = await transaction.get(userRef);
            let currentEarnings = 0;
            let currentLocked = 0;
            let currentWalletBalance = 0;
            if (userSnap.exists) {
                currentEarnings = Number(userSnap.data().earnings || 0);
                currentLocked = Number(userSnap.data().lockedBalance || 0);
                currentWalletBalance = Number(userSnap.data().walletBalance || 0);
            }

            // Read worker wallet safely
            const workerWalletRef = db.collection("worker_wallets").doc(userId);
            const workerWalletSnap = await transaction.get(workerWalletRef);

            // 2. ALL WRITES AFTER READS

            // Update request → rejected & mark processed
            transaction.update(withdrawRef, {
                status: "rejected",
                processedBy: adminId,
                processedAt: serverTimestamp(),
                processed: true
            });

            // Return funds explicitly
            transaction.update(userRef, {
                earnings: currentEarnings + amount,
                lockedBalance: currentLocked - amount, // Unlock
                walletBalance: currentWalletBalance + amount,
            });

            // Restore worker_wallets balance safely
            let currentWorkerBalance = 0;
            if (!workerWalletSnap.exists) {
                transaction.set(workerWalletRef, {
                    balance: amount,
                    totalEarned: 0,
                    totalWithdrawn: 0,
                    createdAt: serverTimestamp(),
                    updatedAt: serverTimestamp()
                });
            } else {
                currentWorkerBalance = Number(workerWalletSnap.data()?.balance || 0);
                transaction.update(workerWalletRef, {
                    balance: currentWorkerBalance + amount,
                    updatedAt: serverTimestamp(),
                });
            }
        }
    );

    // Update the pending transaction to failed (outside main transaction)
    try {
        const txQuery = await db.collection("transactions")
            .where("referenceId", "==", withdrawRequestId)
            .where("userId", "==", userId)
            .where("status", "==", "pending")
            .limit(1)
            .get();
        if (!txQuery.empty) {
            await txQuery.docs[0].ref.update({
                status: "failed",
                description: `Withdrawal of ₹${amount} rejected`,
            });
        }
    } catch (err) {
        console.warn(`[Reject] Failed to update transaction status for withdrawal ${withdrawRequestId}:`, err.message);
    }

    console.log(
        JSON.stringify({
            event: "WITHDRAWAL_REJECTED",
            withdrawRequestId,
            userId,
            amount,
            adminId,
            timestamp: new Date().toISOString(),
        })
    );
}

module.exports = { processWithdrawal };
