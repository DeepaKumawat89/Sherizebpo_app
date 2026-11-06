/**
 * razorpayPayoutWebhook.js
 *
 * HTTPS endpoint that receives RazorpayX payout webhooks and reconciles the
 * final settlement state of a withdrawal. A payout is accepted asynchronously,
 * so the initial "paid" status set at API-acceptance time is optimistic — a
 * payout can later be reversed by the bank/UPI network. This webhook is the
 * source of truth for terminal outcomes:
 *
 *   payout.processed  → confirm status "paid"
 *   payout.reversed   → money returned to your RazorpayX balance → refund worker
 *   payout.failed     → refund worker
 *   payout.rejected   → refund worker
 *
 * Configure in RazorpayX Dashboard → Settings → Webhooks:
 *   URL:    https://<region>-<project>.cloudfunctions.net/razorpayPayoutWebhook
 *   Secret: same value as RAZORPAY_WEBHOOK_SECRET
 *   Events: payout.processed, payout.reversed, payout.failed, payout.rejected
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const crypto = require("crypto");
const { refundWithdrawal } = require("./payoutHelpers");
/* global Buffer */

const db = admin.firestore();

function getWebhookSecret() {
    const cfg = (functions.config().razorpay) || {};
    return process.env.RAZORPAY_WEBHOOK_SECRET || cfg.webhook_secret || "";
}

const razorpayPayoutWebhook = functions
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onRequest(async (req, res) => {
        if (req.method !== "POST") {
            res.status(405).send("Method Not Allowed");
            return;
        }

        const webhookSecret = getWebhookSecret();
        if (!webhookSecret) {
            console.error("RAZORPAY_WEBHOOK_SECRET is not configured.");
            res.status(500).send("Webhook not configured");
            return;
        }

        // ── Verify HMAC-SHA256 signature over the raw request body ──
        const signature = req.headers["x-razorpay-signature"];
        const raw = req.rawBody; // Firebase provides the raw Buffer
        if (!signature || !raw) {
            res.status(400).send("Missing signature or body");
            return;
        }
        const expected = crypto.createHmac("sha256", webhookSecret).update(raw).digest("hex");
        const sigBuf = Buffer.from(String(signature), "utf8");
        const expBuf = Buffer.from(expected, "utf8");
        if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
            console.error("Invalid Razorpay webhook signature.");
            res.status(400).send("Invalid signature");
            return;
        }

        const event = req.body && req.body.event;
        const payoutEntity =
            req.body && req.body.payload && req.body.payload.payout && req.body.payload.payout.entity;

        if (!payoutEntity) {
            res.status(200).send("ignored (no payout entity)");
            return;
        }

        // We tag every payout with reference_id = withdrawalId.
        const withdrawalId = payoutEntity.reference_id;
        if (!withdrawalId) {
            res.status(200).send("ignored (no reference_id)");
            return;
        }

        const withdrawRef = db.collection("withdraw_requests").doc(withdrawalId);
        const snap = await withdrawRef.get();
        if (!snap.exists) {
            console.warn(`Webhook for unknown withdrawal ${withdrawalId} (event=${event}).`);
            res.status(200).send("ignored (unknown reference)");
            return;
        }
        const data = snap.data();

        try {
            if (event === "payout.processed") {
                await withdrawRef.update({
                    status: "paid",
                    processing: false,
                    razorpayPayoutId: payoutEntity.id,
                    settledAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            } else if (
                event === "payout.reversed" ||
                event === "payout.failed" ||
                event === "payout.rejected"
            ) {
                const reason = `Payout ${event.split(".")[1]}`;
                await refundWithdrawal(db, withdrawalId, data.userId, Number(data.amount), reason);
            }
            // Other events (payout.queued/initiated/updated) need no ledger action.
            res.status(200).send("ok");
        } catch (err) {
            console.error(`Webhook handling failed for ${withdrawalId} (event=${event}):`, err.message);
            res.status(500).send("error");
        }
    });

module.exports = { razorpayPayoutWebhook };
