/**
 * payoutHelpers.js
 *
 * Shared helpers for RazorpayX payouts, used by:
 *   - processWithdrawalPayout.js  (auto-payout Firestore trigger)
 *   - retryWithdrawalPayout.js    (manual admin retry)
 *   - razorpayPayoutWebhook.js    (settlement reconciliation)
 *
 * Provides:
 *   - getPayoutCredentials()  → { keyId, keySecret } from env / functions config
 *   - resolveAccountNumber(db) → RazorpayX source account (THROWS if unconfigured,
 *                                 no hardcoded fallback)
 *   - isTerminalPayoutError(err) → true if a retry cannot possibly succeed
 *   - refundWithdrawal(...)   → atomically returns funds to a worker's ledger
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

/** Razorpay API credentials from env or `firebase functions:config`. */
function getPayoutCredentials() {
    const cfg = (functions.config().razorpay) || {};
    const keyId = process.env.RAZORPAY_KEY_ID || cfg.key_id || "";
    const keySecret = process.env.RAZORPAY_KEY_SECRET || cfg.key_secret || "";
    return { keyId, keySecret };
}

/**
 * Resolve the RazorpayX source account number.
 * Priority: platform_settings/main.razorpayAccountNumber → env → functions config.
 * Throws if none is configured — we NEVER fall back to a hardcoded account,
 * as that could route real money from the wrong/unfunded account.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<string>}
 */
async function resolveAccountNumber(db) {
    let configuredAccount = "";
    try {
        const cfgSnap = await db.collection("platform_settings").doc("main").get();
        if (cfgSnap.exists) configuredAccount = cfgSnap.data().razorpayAccountNumber || "";
    } catch (cfgErr) {
        console.warn("Could not read razorpayAccountNumber config:", cfgErr.message);
    }

    const cfg = (functions.config().razorpay) || {};
    const accountNumber = configuredAccount || process.env.RAZORPAY_ACCOUNT_NUMBER || cfg.account || "";

    if (!accountNumber) {
        throw new Error(
            "RazorpayX account number is not configured. Set platform_settings/main.razorpayAccountNumber, " +
            "RAZORPAY_ACCOUNT_NUMBER env, or functions config razorpay.account."
        );
    }
    return accountNumber;
}

/**
 * Classify a payout error as terminal (a retry cannot succeed) vs transient.
 * Terminal → HTTP 4xx (except 429 rate-limit): invalid UPI/VPA, bad fund account,
 *            validation errors, or our own "no UPI configured" precondition.
 * Transient → network errors, HTTP 5xx, 429, or missing source-account config
 *            (all fixable, so the payout stays retryable).
 *
 * @param {Error} error
 * @returns {boolean}
 */
function isTerminalPayoutError(error) {
    const status = error.response && error.response.status;
    if (status && status >= 400 && status < 500 && status !== 429) return true;
    // Pre-HTTP precondition thrown by our code when the worker has no UPI id.
    if (!error.response && /UPI/i.test(error.message || "")) return true;
    return false;
}

/**
 * Atomically return a withdrawal's funds to the worker after a terminal payout
 * failure or a settlement reversal. Mirrors the request-time lock:
 *   request locked:  earnings -X, walletBalance -X, worker_wallets.balance -X
 *   approval spent:  lockedBalance -X   (already applied before payout)
 * so a refund restores earnings/wallet/worker_wallet by +X (lockedBalance is
 * already settled at approval time and is left untouched).
 *
 * Idempotent: a request already marked refunded is a no-op.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} withdrawalId
 * @param {string} userId
 * @param {number} amount
 * @param {string} reason
 */
async function refundWithdrawal(db, withdrawalId, userId, amount, reason) {
    if (!userId || !amount || !isFinite(amount) || amount <= 0) {
        console.error(`[Refund] Invalid data for ${withdrawalId}: userId=${userId} amount=${amount}`);
        return;
    }

    const withdrawRef = db.collection("withdraw_requests").doc(withdrawalId);
    const userRef = db.collection("users").doc(userId);
    const workerWalletRef = db.collection("worker_wallets").doc(userId);

    await db.runTransaction(async (txn) => {
        // ── Reads first ──
        const wSnap = await txn.get(withdrawRef);
        if (!wSnap.exists) throw new Error(`Withdrawal ${withdrawalId} not found for refund.`);
        const wData = wSnap.data();
        if (wData.refunded === true || wData.status === "refunded") return; // idempotent

        const userSnap = await txn.get(userRef);
        const workerWalletSnap = await txn.get(workerWalletRef);

        // ── Writes after reads ──
        txn.update(withdrawRef, {
            status: "refunded",
            refunded: true,
            processing: false,
            error: reason || wData.error || "Payout failed — funds returned.",
            refundedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (userSnap.exists) {
            txn.update(userRef, {
                earnings: admin.firestore.FieldValue.increment(amount),
                walletBalance: admin.firestore.FieldValue.increment(amount),
            });
        }

        if (workerWalletSnap.exists) {
            txn.update(workerWalletRef, {
                balance: admin.firestore.FieldValue.increment(amount),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        } else {
            txn.set(workerWalletRef, {
                balance: amount,
                totalEarned: 0,
                totalWithdrawn: 0,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    });

    // Best-effort: flip the linked debit transaction to refunded (outside txn).
    try {
        const txQuery = await db.collection("transactions")
            .where("referenceId", "==", withdrawalId)
            .where("userId", "==", userId)
            .limit(1)
            .get();
        if (!txQuery.empty) {
            await txQuery.docs[0].ref.update({
                status: "refunded",
                description: `Withdrawal of ₹${amount} failed — refunded`,
            });
        }
    } catch (err) {
        console.warn(`[Refund] Failed to update transaction for ${withdrawalId}:`, err.message);
    }

    console.log(JSON.stringify({
        event: "WITHDRAWAL_REFUNDED",
        withdrawalId, userId, amount, reason: reason || null,
        timestamp: new Date().toISOString(),
    }));
}

module.exports = {
    getPayoutCredentials,
    resolveAccountNumber,
    isTerminalPayoutError,
    refundWithdrawal,
};
