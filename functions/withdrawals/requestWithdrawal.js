/**
 * requestWithdrawal.js
 *
 * HTTPS Callable Cloud Function: requestWithdrawal
 *
 * Allows workers to request a withdrawal of their earnings:
 *   1. Authenticates user via Firebase Auth context
 *   2. Validates KYC status and sufficient earnings
 *   3. Rate limits: 1 request per 30 seconds
 *   4. Creates withdrawal request document
 *   5. Locks the amount (earnings -= amount, lockedBalance += amount)
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {
    runTransaction,
    serverTimestamp,
    increment,
} = require("../utils/firestoreTransaction");
const { generateUniqueFriendlyId } = require("../utils/friendlyId");

const db = admin.firestore();
const cors = require("cors")({ origin: true });

// ─── Rate Limiting (Shared via Firestore) ────────────────────────
/**
 * Checks if user has requested a withdrawal in the last `windowMs`.
 * @param {string} userId
 * @param {number} windowMs - Cooldown window in milliseconds
 * @returns {Promise<boolean>} true if allowed
 */
async function checkWithdrawalRateLimitFirestore(userId, windowMs = 30000) {
    const ref = db.collection("rate_limits").doc(`${userId}_withdrawal`);
    let allowed = false;

    await db.runTransaction(async (txn) => {
        const snap = await txn.get(ref);
        const now = Date.now();
        const lastRequest = snap.exists ? (snap.data().lastCallAt || 0) : 0;

        if (now - lastRequest < windowMs) {
            allowed = false;
        } else {
            txn.set(ref, { lastCallAt: now }, { merge: true });
            allowed = true;
        }
    });

    return allowed;
}

/**
 * requestWithdrawal — Callable Cloud Function
 *
 * @param {Object} data - { amount }
 * @param {Object} context - Firebase callable context with auth
 * @returns {Object} { success, message, withdrawRequestId }
 */
const requestWithdrawal = functions
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (data, context) => {
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
        }

        const userId = context.auth.uid;

    // ─── Input Validation ────────────────────────────────────────
    const { amount, paymentMethod, paymentDetails } = data || {};

    // Configurable minimum withdrawal — super-admin controlled via
    // platform_settings/main.minWithdrawalAmount. Falls back to 100 if unset so
    // this stays the single source of truth (the app reads the same field).
    let MIN_WITHDRAWAL = 100;
    try {
        const cfgSnap = await db.collection("platform_settings").doc("main").get();
        if (cfgSnap.exists && cfgSnap.data().minWithdrawalAmount != null) {
            MIN_WITHDRAWAL = Number(cfgSnap.data().minWithdrawalAmount) || 100;
        }
    } catch (cfgErr) {
        console.warn("Could not read minWithdrawalAmount config:", cfgErr.message);
    }
    const MAX_WITHDRAWAL = 1000;

    if (!amount || typeof amount !== "number" || !isFinite(amount)) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "amount must be a positive number."
        );
    }

    if (amount < MIN_WITHDRAWAL || amount > MAX_WITHDRAWAL) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            `Withdrawal amount must be between ₹${MIN_WITHDRAWAL} and ₹${MAX_WITHDRAWAL}.`
        );
    }

    if (!paymentMethod || !paymentDetails || typeof paymentDetails !== "string" || paymentDetails.trim().length === 0) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Valid payment method and details (e.g. UPI ID or Bank Account) must be provided."
        );
    }

    // Round to 2 decimal places
    const withdrawAmount = Math.round(amount * 100) / 100;

    // ─── Rate Limiting ───────────────────────────────────────────
    const isAllowed = await checkWithdrawalRateLimitFirestore(userId);
    if (!isAllowed) {
        throw new functions.https.HttpsError(
            "resource-exhausted",
            "Please wait 30 seconds between withdrawal requests."
        );
    }

    // ─── Fetch User & Validate ───────────────────────────────────
    const userRef = db.collection("users").doc(userId);
    const userSnap = await userRef.get();

    if (!userSnap.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "User profile not found."
        );
    }

    const userData = userSnap.data();

    // KYC Check
    if (userData.kycStatus !== "approved") {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "KYC verification must be approved before withdrawals."
        );
    }

    // Profile Completion Check — payouts require a 100% complete profile.
    // Mirrors lib/core/utils/profile_completion.dart — keep in sync.
    const hasVal = (v) => v !== undefined && v !== null && String(v).trim().length > 0;
    const bank = userData.bankDetails || {};
    const hasPaymentDetails = String(bank.paymentMode || "upi") === "upi"
        ? hasVal(bank.upiId)
        : (hasVal(bank.accountNumber) && hasVal(bank.ifscCode));
    const profileComplete =
        (hasVal(userData.fullName) || hasVal(userData.name)) &&
        hasVal(userData.email) &&
        (hasVal(userData.phone) || hasVal(userData.phoneNumber)) &&
        hasVal(userData.gender) &&
        hasVal(userData.dateOfBirth) &&
        hasVal(userData.city) &&
        hasPaymentDetails;
    if (!profileComplete) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Complete your profile (100%) — personal details and bank/UPI info — before requesting a withdrawal."
        );
    }

    // Earnings Check
    const currentEarnings = userData.earnings || 0;
    if (currentEarnings < withdrawAmount) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            `Insufficient balance. Current: ₹${currentEarnings}, Requested: ₹${withdrawAmount}`
        );
    }

    // ─── Atomic Transaction ──────────────────────────────────────
    // Friendly PAY-XXXX id shown in the UI/payment reports instead of the raw
    // Firestore doc id. Generated before the transaction (queries aren't allowed
    // inside a Firestore transaction body). Uniqueness is checked against the
    // shared `transactions` collection so deposits and withdrawals never clash.
    const paymentCode = await generateUniqueFriendlyId("PAY", { collection: "transactions", field: "paymentCode" });

    const result = await runTransaction(
        db,
        `Withdrawal request by ${userId} for ₹${withdrawAmount}`,
        async (transaction) => {
            // Re-read user to ensure balance hasn't changed
            const freshUser = await transaction.get(userRef);
            if (!freshUser.exists) {
                throw new functions.https.HttpsError("not-found", "User not found.");
            }

            const freshData = freshUser.data();
            const freshEarnings = freshData.earnings || 0;

            if (freshEarnings < withdrawAmount) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    `Insufficient balance during processing. Balance: ₹${freshEarnings}`
                );
            }

            // Read the worker wallet BEFORE any writes
            const workerWalletRef = db.collection("worker_wallets").doc(userId);
            const workerWalletSnap = await transaction.get(workerWalletRef);

            // Create withdraw_requests document
            const withdrawRef = db.collection("withdraw_requests").doc();
            transaction.set(withdrawRef, {
                userId: userId,
                amount: withdrawAmount,
                paymentCode: paymentCode,
                paymentMethod: paymentMethod.trim(),
                paymentDetails: paymentDetails.trim(),
                status: "pending",
                requestedAt: serverTimestamp(),
            });

            // Record pending debit transaction (Step 4 & 6)
            const txRef = db.collection("transactions").doc();
            transaction.set(txRef, {
                userId: userId,
                role: "worker",
                type: "debit",
                amount: withdrawAmount,
                source: "withdrawal",
                referenceId: withdrawRef.id,
                paymentCode: paymentCode,
                status: "pending",
                description: `Withdrawal request of ₹${withdrawAmount}`,
                createdAt: serverTimestamp(),
            });
            console.log("Transaction created for:", userId, withdrawAmount); // Step 7

            // Lock amount: earnings -= amount, lockedBalance += amount
            transaction.update(userRef, {
                earnings: increment(-withdrawAmount),
                lockedBalance: increment(withdrawAmount),
                walletBalance: increment(-withdrawAmount),
            });

            // Also update worker_wallets to stay in sync
            if (workerWalletSnap.exists) {
                transaction.update(workerWalletRef, {
                    balance: increment(-withdrawAmount),
                    updatedAt: serverTimestamp(),
                });
            }

            return { withdrawRequestId: withdrawRef.id, transactionId: txRef.id };
        }
    );

    // ─── Structured Logging ──────────────────────────────────────
    const maskedDetails = paymentDetails.length > 4 
       ? paymentDetails.slice(0, 4) + "****" : "****";
       
    console.log(
        JSON.stringify({
            event: "WITHDRAWAL_REQUESTED",
            userId,
            amount: withdrawAmount,
            paymentMethod,
            paymentDetails: maskedDetails,
            withdrawRequestId: result.withdrawRequestId,
            timestamp: new Date().toISOString(),
        })
    );

    return {
        success: true,
        message: `Withdrawal of ₹${withdrawAmount} requested successfully.`,
        withdrawRequestId: result.withdrawRequestId,
        paymentCode: paymentCode,
    };
    } catch (err) {
        console.error("requestWithdrawal error:", err);
        if (err instanceof functions.https.HttpsError) {
            throw err;
        }
        throw new functions.https.HttpsError("internal", err.message || "Withdrawal request failed.");
    }
});

module.exports = { requestWithdrawal };

