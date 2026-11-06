/**
 * retryWithdrawalPayout.js
 *
 * Callable Cloud Function: retryWithdrawalPayout
 * Triggered manually by Admin from Dashboard.
 * Fetches latest UPI details of the user and retries Razorpay payout.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const axios = require("axios");
const { getPayoutCredentials, resolveAccountNumber } = require("./payoutHelpers");
/* global Buffer */

const db = admin.firestore();

exports.retryWithdrawalPayout = functions
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (data, context) => {
        // 1. Validate caller is admin
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'You must be authenticated to perform this action.');
        }
        
        const callerSnap = await db.collection("users").doc(context.auth.uid).get();
        if (!callerSnap.exists || callerSnap.data().role !== "admin") {
            throw new functions.https.HttpsError('permission-denied', 'Only administrators can retry payouts.');
        }

        const withdrawalId = data.withdrawalId;
        if (!withdrawalId) {
            throw new functions.https.HttpsError('invalid-argument', 'Mising withdrawalId parameter.');
        }

        // 2 & 3. Fetch withdrawal and ensure failed status
        const withdrawalRef = db.collection("withdraw_requests").doc(withdrawalId);
        const withdrawalSnap = await withdrawalRef.get();

        if (!withdrawalSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Withdrawal request not found.');
        }

        const withdrawalData = withdrawalSnap.data();
        if (withdrawalData.status !== "failed") {
            throw new functions.https.HttpsError('failed-precondition', `Withdrawal status is ${withdrawalData.status}, only failed payouts can be retried.`);
        }
        
        if (withdrawalData.processing) {
            throw new functions.https.HttpsError('failed-precondition', 'Payout is currently being processed by another worker.');
        }

        const { userId, amount } = withdrawalData;

        // Lock document for processing
        await withdrawalRef.update({ processing: true });

        try {
            // 4. Fetch User's latest UPI ID
            const userSnap = await db.collection("users").doc(userId).get();
            if (!userSnap.exists) {
                throw new Error(`User ${userId} not found.`);
            }

            const userData = userSnap.data();
            const upiId = userData.bankDetails && userData.bankDetails.upiId;

            // 5. Still missing UPI ID error out early
            if (!upiId) {
                throw new Error(`User ${userId} still has no UPI ID configured in Bank Details.`);
            }

            // RazorpayX composite payouts require a contact nested in fund_account.
            const rawName = (userData.fullName || userData.name || "").toString().trim();
            const contactName = rawName.length >= 3 ? rawName.slice(0, 50) : "Sherize Worker";

            // 6. Call Razorpay API
            const { keyId: razorpayKeyId, keySecret: razorpayKeySecret } = getPayoutCredentials();
            const authHeader = `Basic ${Buffer.from(`${razorpayKeyId}:${razorpayKeySecret}`).toString("base64")}`;
            const accountNumber = await resolveAccountNumber(db);
            
            // Append retry timestamp for Idempotency to prevent duplicate error
            const idempotencyKey = `${withdrawalId}-retry-${Date.now()}`;

            console.log(`[RETRY] Initiating Razorpay payout of ₹${amount} for user ${userId} to UPI: ${upiId}. Idempotency: ${idempotencyKey}`);

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
                        "X-Payout-Idempotency": idempotencyKey
                    }
                }
            );

            const payoutData = response.data;
            const razorpayId = payoutData.id;

            console.log(`[RETRY] Razorpay payout successful for ${withdrawalId}. Razorpay ID: ${razorpayId}`);

            // 7. Success!
            await withdrawalRef.update({
                status: "paid",
                processing: false,
                razorpayPayoutId: razorpayId,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
                upiId: upiId // Save the upiId that succeeded on the doc record
            });

            return { success: true, message: `Payout successful. Transation ID: ${razorpayId}` };

        } catch (error) {
            let errorMessage = error.message;
            if (error.response && error.response.data && error.response.data.error) {
                errorMessage = error.response.data.error.description || errorMessage;
            }
            
            console.error(`[RETRY] Razorpay payout failed for ${withdrawalId}:`, errorMessage);

            // 8. Handle Failure Update
            await withdrawalRef.update({
                processing: false,
                error: errorMessage, // update the latest error
                failedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            // Re-throw for caller application
            throw new functions.https.HttpsError('internal', errorMessage);
        }
    });
