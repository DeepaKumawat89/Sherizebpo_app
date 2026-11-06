const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const Razorpay = require("razorpay");
const crypto = require("crypto");
const { generateUniqueFriendlyId } = require("../utils/friendlyId");

// Fetching config from environment or Firebase config
const razorpayKeyId = process.env.RAZORPAY_KEY_ID || (functions.config().razorpay && functions.config().razorpay.key_id) || "rzp_test_mock";
const razorpayKeySecret = process.env.RAZORPAY_KEY_SECRET || (functions.config().razorpay && functions.config().razorpay.key_secret) || "rzp_mock_secret";

const razorpay = new Razorpay({
  key_id: razorpayKeyId,
  key_secret: razorpayKeySecret,
});

const cors = require("cors")({ origin: true });

exports.createRazorpayOrder = functions.https.onCall(async (data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
      }

      const uid = context.auth.uid;
      const { amount } = data || {}; // amount in INR (rupees)

      if (!amount || amount <= 0) {
        throw new functions.https.HttpsError("invalid-argument", "Valid amount is required.");
      }

      // Razorpay requires amount in paise
      const amountInPaise = Math.round(amount * 100);

      // Generate a shorter receipt ID (max 40 chars)
      const shortUid = uid.substring(0, 8);
      const receiptId = `rcpt_${shortUid}_${Date.now()}`;

      const order = await razorpay.orders.create({
        amount: amountInPaise,
        currency: "INR",
        receipt: receiptId
      });

      return {
        id: order.id,
        amount: order.amount,
        currency: order.currency,
        keyId: razorpayKeyId
      };
    } catch (error) {
      console.error("Razorpay order creation failed:", error);
      if (error instanceof functions.https.HttpsError) throw error;
      if (error && error.statusCode === 401) {
        throw new functions.https.HttpsError("failed-precondition", "Payment gateway is not configured correctly. Please contact support.");
      }
      throw new functions.https.HttpsError("internal", error.message || "Unable to create payment order.");
    }
});

exports.verifyPayment = functions.https.onCall(async (data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
      }

      const userId = context.auth.uid;
      const { razorpay_order_id, razorpay_payment_id, razorpay_signature, amount } = data || {};

      if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature || !amount) {
        throw new functions.https.HttpsError("invalid-argument", "Missing payment verification parameters.");
      }

      // Verify signature
      const hmac = crypto.createHmac("sha256", razorpayKeySecret);
      hmac.update(razorpay_order_id + "|" + razorpay_payment_id);
      const generatedSignature = hmac.digest("hex");

      if (generatedSignature !== razorpay_signature) {
        throw new functions.https.HttpsError("permission-denied", "Payment verification failed.");
      }

      // ─── Fetch authoritative payment details from Razorpay ───────
      // Never trust the client-supplied `amount`: a client could pay ₹1 and
      // claim a ₹10,000 credit. Use the captured amount reported by Razorpay.
      let payment;
      try {
        payment = await razorpay.payments.fetch(razorpay_payment_id);
      } catch (fetchErr) {
        console.error("Failed to fetch Razorpay payment:", fetchErr);
        throw new functions.https.HttpsError("internal", "Could not verify payment with gateway.");
      }

      if (!payment || payment.order_id !== razorpay_order_id) {
        throw new functions.https.HttpsError("permission-denied", "Payment does not match the order.");
      }

      if (payment.status !== "captured") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          `Payment is not captured (status: ${payment.status}).`
        );
      }

      // Razorpay returns the amount in paise; convert to rupees.
      const creditAmount = Number(payment.amount) / 100;

      const db = admin.firestore();

      // Friendly PAY-XXXX id shown in the UI/payment reports instead of the raw
      // gateway id. Uniqueness is checked against the shared `transactions`
      // collection so deposits and withdrawals never clash. Generated before the
      // transaction (queries aren't allowed inside a Firestore transaction body).
      const paymentCode = await generateUniqueFriendlyId("PAY", { collection: "transactions", field: "paymentCode" }, db);

      try {
        const alreadyProcessed = await db.runTransaction(async (transaction) => {
          const txRef = db.collection("transactions").doc(razorpay_payment_id);

          // ── READS FIRST ──
          const txSnap = await transaction.get(txRef);
          if (txSnap.exists) {
            // Idempotency: this payment was already credited — do nothing.
            return true;
          }

          const walletRef = db.collection("client_wallets").doc(userId);
          const walletSnap = await transaction.get(walletRef);

          // ── WRITES ──
          if (!walletSnap.exists) {
            transaction.set(walletRef, {
              clientId: userId,
              balance: creditAmount,
              reservedBalance: 0,
              totalDeposited: creditAmount,
              totalSpent: 0,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
          } else {
            transaction.update(walletRef, {
              balance: admin.firestore.FieldValue.increment(creditAmount),
              totalDeposited: admin.firestore.FieldValue.increment(creditAmount),
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
          }

          transaction.set(txRef, {
            userId: userId,
            role: "client",
            type: "credit",
            amount: creditAmount,
            source: "topup",
            referenceId: razorpay_order_id,
            paymentId: razorpay_payment_id,
            paymentCode: paymentCode,
            status: "success",
            description: `Wallet recharge via Razorpay`,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
          });

          return false;
        });

        return { success: true, alreadyProcessed };
      } catch (err) {
        console.error("Error updating wallet:", err);
        if (err instanceof functions.https.HttpsError) throw err;
        throw new functions.https.HttpsError("internal", "Failed to update wallet after payment verification.");
      }
    } catch (outerErr) {
      console.error("Outer error in verifyPayment:", outerErr);
      if (outerErr instanceof functions.https.HttpsError) throw outerErr;
      throw new functions.https.HttpsError("internal", "Payment verification error.");
    }
});
