/**
 * processWithdrawalPayout.js
 *
 * Background Cloud Function: processWithdrawalPayout
 * Triggered when a withdraw_request document is updated.
 * If status changes to 'approved', it triggers a payout via Razorpay API.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const axios = require("axios");
const {
    getPayoutCredentials,
    resolveAccountNumber,
    isTerminalPayoutError,
    refundWithdrawal,
} = require("./payoutHelpers");
/* global Buffer */

const db = admin.firestore();

/**
 * processWithdrawalPayout - Firestore onUpdate Trigger
 */
const processWithdrawalPayout = functions
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .firestore
    .document("withdraw_requests/{withdrawalId}")
    .onUpdate(async (change, context) => {
        const before = change.before.data();
        const after = change.after.data();
        const withdrawalId = context.params.withdrawalId;

        // STEP 3 — ADD CHECK: Prevent duplicate payouts
        if (after.status !== "approved" || after.processing === true) {
            return null;
        }

        const { userId, amount } = after;

        if (!userId || !amount) {
            console.error(`Withdrawal ${withdrawalId} missing userId or amount.`);
            return null;
        }

        // STEP 2 — ATOMIC CLAIM: only one invocation may set processing:true.
        // Prevents a check-then-write race between concurrent trigger runs
        // (defense-in-depth alongside the Razorpay idempotency key below).
        const claimed = await db.runTransaction(async (txn) => {
            const snap = await txn.get(change.after.ref);
            const d = snap.data() || {};
            if (d.status !== "approved" || d.processing === true || d.razorpayPayoutId) {
                return false;
            }
            txn.update(change.after.ref, { processing: true });
            return true;
        });

        if (!claimed) {
            console.log(`Withdrawal ${withdrawalId} already claimed/processed; skipping.`);
            return null;
        }

        try {
            // Fetch User's UPI ID
            const userSnap = await db.collection("users").doc(userId).get();
            if (!userSnap.exists) {
                throw new Error(`User ${userId} not found.`);
            }

            const userData = userSnap.data();
            const upiId = after.upiId || (userData.bankDetails && userData.bankDetails.upiId);

            if (!upiId) {
                throw new Error(`No UPI ID configured for user ${userId}.`);
            }

            // RazorpayX composite payouts require a contact nested in fund_account.
            const rawName = (userData.fullName || userData.name || "").toString().trim();
            const contactName = rawName.length >= 3 ? rawName.slice(0, 50) : "Sherize Worker";

            // Call Razorpay API
            const { keyId: razorpayKeyId, keySecret: razorpayKeySecret } = getPayoutCredentials();
            const authHeader = `Basic ${Buffer.from(`${razorpayKeyId}:${razorpayKeySecret}`).toString("base64")}`;

            // RazorpayX source account — throws if unconfigured (no hardcoded fallback).
            const accountNumber = await resolveAccountNumber(db);

            console.log(`Initiating Razorpay payout of ₹${amount} for user ${userId} to UPI: ${upiId}`);

            const response = await axios.post(
                "https://api.razorpay.com/v1/payouts",
                {
                    account_number: accountNumber,
                    amount: Math.round(amount * 100), // convert to paise
                    currency: "INR",
                    mode: "UPI",
                    purpose: "payout",
                    queue_if_low_balance: true,
                    fund_account: {
                        account_type: "vpa",
                        vpa: {
                            address: upiId
                        },
                        contact: {
                            name: contactName,
                            type: "employee",
                            reference_id: userId
                        }
                    },
                    reference_id: withdrawalId, // link for tracking
                    narration: "Sherize Payout" // RazorpayX caps narration at 30 chars; withdrawalId is carried by reference_id
                },
                {
                    headers: {
                        "Authorization": authHeader,
                        "Content-Type": "application/json",
                        "X-Payout-Idempotency": withdrawalId // STEP 1 — ADD IDEMPOTENCY HEADER
                    }
                }
            );

            const payoutData = response.data;
            const razorpayId = payoutData.id;

            console.log(`Razorpay payout successful for ${withdrawalId}. Razorpay ID: ${razorpayId}`);

            // STEP 4 — UPDATE AFTER SUCCESS
            await change.after.ref.update({
                status: "paid",
                processing: false,
                razorpayPayoutId: razorpayId,
                processedAt: admin.firestore.FieldValue.serverTimestamp()
            });

        } catch (error) {
            // Determine razorpay error messages safely
            let errorMessage = error.message;
            if (error.response && error.response.data && error.response.data.error) {
                errorMessage = error.response.data.error.description || errorMessage;
            }
            
            console.error(`Razorpay payout failed for ${withdrawalId}:`, errorMessage);

            // STEP 5 — HANDLE FAILURE
            // Terminal errors (bad UPI, invalid fund account, 4xx) can never succeed on
            // retry, so return the funds to the worker immediately instead of stranding
            // them in a "failed" limbo (the ledger was already debited at approval).
            // Transient errors (network, 5xx, 429, missing source-account config) stay
            // "failed" so an admin can fix the cause and use retryWithdrawalPayout.
            if (isTerminalPayoutError(error)) {
                try {
                    await refundWithdrawal(db, withdrawalId, userId, amount, errorMessage);
                } catch (refundErr) {
                    console.error(`Auto-refund failed for ${withdrawalId}:`, refundErr.message);
                    await change.after.ref.update({
                        status: "failed",
                        processing: false,
                        error: `${errorMessage} (auto-refund failed: ${refundErr.message})`,
                        failedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                }
            } else {
                await change.after.ref.update({
                    status: "failed",
                    processing: false,
                    error: errorMessage,
                    failedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            }
        }
        
        return null;
    });

module.exports = { processWithdrawalPayout };
