/**
 * Sherize — Backend Cloud Functions
 *
 * ═══════════════════════════════════════════════════════════════
 * API (Express):
 *   POST /start-call        — Initiates an outbound call via Exotel
 *   POST /end-call          — Ends an active call
 *   POST /exotel-webhook    — Receives Exotel status callback events
 *   GET  /health            — Health check
 *
 * CALLABLE FUNCTIONS (Earnings & Withdrawals):
 *   approveTaskSubmission   — Admin approves a pending submission
 *   rejectTaskSubmission    — Admin rejects a pending submission
 *   requestWithdrawal       — Worker requests earnings withdrawal
 *   processWithdrawal       — Admin approves/rejects withdrawal
 *
 * SECURITY:
 *   - Exotel credentials stored in Firebase Functions config / env
 *   - All client endpoints validate Firebase Auth token
 *   - Rate limiting on /start-call and withdrawals
 *   - Admin role validated from Firestore users collection
 *   - All earnings mutations happen in atomic transactions
 * ═══════════════════════════════════════════════════════════════
 * Exotel account: sherize1m — Mumbai region, api.in.exotel.com (updated 2026-07-24).
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const axios = require("axios");
const express = require("express");
const cors = require("cors");
const { URL } = require("node:url");
const { parsePhonePool, selectPhoneNumber } = require("./exotel/phonePool");
const { claimCallStart } = require("./voip/claimCallStart");
const {
    clientOwnsLeadRecording,
    isAllowedRecordingUrl,
    callStartMatchesResources,
    leadAcceptsCallUpdate,
} = require("./recordings/recordingAccess");

admin.initializeApp();
const db = admin.firestore();

// ─────────────────────────────────────────────────────────────────
// SECTION 1: EXOTEL VOIP API (Express)
// ─────────────────────────────────────────────────────────────────

// ─── Exotel Configuration ─────────────────────────────────────
const EXOTEL_SID =
    process.env.EXOTEL_SID ||
    (functions.config().exotel && functions.config().exotel.sid) ||
    "";
const EXOTEL_API_KEY =
    process.env.EXOTEL_API_KEY ||
    (functions.config().exotel && functions.config().exotel.api_key) ||
    "";
const EXOTEL_API_TOKEN =
    process.env.EXOTEL_API_TOKEN ||
    (functions.config().exotel && functions.config().exotel.api_token) ||
    "";
const EXOTEL_PHONE_NUMBER =
    process.env.EXOTEL_PHONE_NUMBER ||
    (functions.config().exotel && functions.config().exotel.phone_number) ||
    "";
const EXOTEL_PHONE_NUMBERS =
    process.env.EXOTEL_PHONE_NUMBERS ||
    (functions.config().exotel && functions.config().exotel.phone_numbers) ||
    "";
const EXOTEL_PHONE_POOL = parsePhonePool(EXOTEL_PHONE_NUMBERS, EXOTEL_PHONE_NUMBER);
const EXOTEL_SUBDOMAIN =
    process.env.EXOTEL_SUBDOMAIN ||
    (functions.config().exotel && functions.config().exotel.subdomain) ||
    "api.in.exotel.com";

const WEBHOOK_BASE_URL =
    process.env.WEBHOOK_BASE_URL ||
    (functions.config().app && functions.config().app.webhook_url) ||
    "";

// Shared secret used to authenticate inbound VOIP webhooks (Exotel/Twilio).
// We append this token to the StatusCallback URLs we register with the
// providers, then verify it on every inbound webhook. Enforced only when set,
// so an unconfigured deploy keeps working (a warning is logged) until the
// secret is provisioned.
const WEBHOOK_SECRET =
    process.env.WEBHOOK_SECRET ||
    (functions.config().app && functions.config().app.webhook_secret) ||
    "";

// Which telephony provider handles outbound calls: "exotel" (default) or
// "twilio". Set CALL_PROVIDER=twilio (env or functions config app.call_provider)
// to route app calls through Twilio for temporary testing WITHOUT removing
// Exotel. A per-request `provider` field on /start-call overrides this default,
// so a single worker can be tested on Twilio while everyone else stays on Exotel.
const CALL_PROVIDER =
    process.env.CALL_PROVIDER ||
    (functions.config().app && functions.config().app.call_provider) ||
    "exotel";

// ─── Rate Limiting (shared across instances via Firestore) ──────
async function checkRateLimitFirestore(userId, maxCalls = 5, windowMs = 60000) {
    const ref = db.collection("rate_limits").doc(userId);
    let allowed = false;

    await db.runTransaction(async (txn) => {
        const snap = await txn.get(ref);
        const now = Date.now();
        let userCalls = snap.exists ? (snap.data().calls || []) : [];

        // Filter out calls older than the window
        userCalls = userCalls.filter((ts) => now - ts < windowMs);

        if (userCalls.length >= maxCalls) {
            allowed = false;
        } else {
            userCalls.push(now);
            txn.set(ref, { calls: userCalls }, { merge: true });
            allowed = true;
        }
    });

    return allowed;
}

// ─── Firebase Auth Middleware ──────────────────────────────────
// Accepts the token from:
//   1. Authorization: Bearer <token>  (standard, used by most endpoints)
//   2. ?token=<token>  (fallback for audio/video players that cannot set headers)
async function validateAuth(req, res, next) {
    let idToken = null;

    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith("Bearer ")) {
        idToken = authHeader.split("Bearer ")[1];
    } else if (req.query.token) {
        // Fallback: token in query string (for audio players like just_audio)
        idToken = req.query.token;
    }

    if (!idToken) {
        return res.status(401).json({ error: "Unauthorized — missing token" });
    }

    try {
        const decoded = await admin.auth().verifyIdToken(idToken);
        req.uid = decoded.uid;
        next();
    } catch (err) {
        return res.status(401).json({ error: "Unauthorized — invalid token" });
    }
}

// ─── Express App ──────────────────────────────────────────────
const app = express();
app.use(cors({ origin: true }));

app.use("/start-call", express.json());
app.use("/end-call", express.json());
app.use("/exotel-webhook", express.urlencoded({ extended: true }));
app.use("/twilio-webhook", express.urlencoded({ extended: true }));
app.use("/twilio-status-callback", express.urlencoded({ extended: true }));

// ═══════════════════════════════════════════════════════════════
// POST /start-call — Initiate outbound call via Exotel
// ═══════════════════════════════════════════════════════════════
app.post("/start-call", validateAuth, async (req, res) => {
    try {
        const { callId, userId, taskId, assignmentId, leadId, customerPhone } =
            req.body;

        if (!callId || !userId || !taskId || !assignmentId || !leadId || !customerPhone) {
            return res.status(400).json({ error: "Missing required fields" });
        }

        if (req.uid !== userId) {
            return res.status(403).json({ error: "User mismatch" });
        }

        const [callDoc, assignmentDoc, leadDoc] = await Promise.all([
            db.collection("calls").doc(callId).get(),
            db.collection("task_assignments").doc(assignmentId).get(),
            db.collection("campaign_leads").doc(leadId).get(),
        ]);
        if (!callDoc.exists || !assignmentDoc.exists || !leadDoc.exists) {
            return res.status(404).json({ error: "Call assignment or lead not found" });
        }

        const callData = callDoc.data();
        const assignmentData = assignmentDoc.data();
        const leadData = leadDoc.data();
        if (!callStartMatchesResources(callData, assignmentData, leadData, req.body)) {
            return res.status(403).json({ error: "Call is not authorized for this assignment and lead" });
        }

        const provider = String(req.body.provider || CALL_PROVIDER || "exotel").toLowerCase();
        const exotelPhoneNumber = provider === "twilio"
            ? ""
            : selectPhoneNumber(EXOTEL_PHONE_POOL, callId);

        if (provider !== "twilio" && !exotelPhoneNumber) {
            const configError = new Error("Exotel phone number is not configured");
            configError.statusCode = 503;
            throw configError;
        }

        const isAllowed = await checkRateLimitFirestore(userId);
        if (!isAllowed) {
            return res.status(429).json({
                error: "Too many calls. Please wait before trying again.",
            });
        }

        // The worker/agent's own phone — Exotel rings this FIRST, then dials the
        // customer and bridges both legs (this is the call that gets recorded).
        const workerSnap = await db.collection("users").doc(userId).get();
        const workerPhone = workerSnap.exists ? (workerSnap.data().phone || "") : "";
        if (!workerPhone) {
            return res.status(400).json({
                error: "No phone number on your profile. Add one in Settings to make calls.",
            });
        }

        // Format an Indian number the way Exotel expects (0XXXXXXXXXX / 91XXXXXXXXXX).
        const formatIN = (raw) => {
            let p = String(raw || "").trim();
            if (p.startsWith("+")) p = p.substring(1);
            if (p.length === 10) p = "0" + p;
            return p;
        };
        const formattedWorker = formatIN(workerPhone);
        const formattedCustomer = formatIN(customerPhone);

        const callRef = db.collection("calls").doc(callId);
        const claimed = await claimCallStart(
            db,
            callRef,
            assignmentData,
            leadData,
            req.body,
            provider,
            exotelPhoneNumber
        );

        if (!claimed) {
            return res.status(409).json({ error: "Call has already been started" });
        }

        // ── Provider switch ───────────────────────────────────────
        // Default from CALL_PROVIDER; a `provider` field in the request wins.
        if (provider === "twilio") {
            // Twilio wants E.164 (+91XXXXXXXXXX) — the helper reformats the raw
            // numbers, so pass the un-Exotel-formatted values.
            const { initiateAppTwilioCall } = require("./twilio");
            const twilioSid = await initiateAppTwilioCall({
                workerPhone,
                customerPhone,
                callId,
                leadId,
                assignmentId,
                taskId,
            });

            // Reuse the existing `exotelCallSid` field as the generic provider
            // SID so the app + /recording proxy keep working unchanged.
            await callRef.update({
                exotelCallSid: twilioSid || null,
                status: "ringing",
            });

            console.log(
                `Call initiated (twilio): ${callId} → SID: ${twilioSid} → worker ${workerPhone} → customer ${customerPhone}`
            );

            return res.status(200).json({
                success: true,
                callSid: twilioSid,
                callId: callId,
                provider: "twilio",
            });
        }

        // Build the Exotel API URL
        // Exotel Connect API: connects two phone numbers via the ExoPhone
        const exotelUrl = `https://${EXOTEL_API_KEY}:${EXOTEL_API_TOKEN}@${EXOTEL_SUBDOMAIN}/v1/Accounts/${EXOTEL_SID}/Calls/connect.json`;

        // Build webhook URL for status updates
        const statusCallbackUrl = WEBHOOK_BASE_URL
            ? `${WEBHOOK_BASE_URL}/exotel-webhook${WEBHOOK_SECRET ? `?token=${encodeURIComponent(WEBHOOK_SECRET)}` : ""}`
            : "";

        // Make the Exotel API call
        const callPayload = new URLSearchParams({
            From: formattedWorker,          // Worker/agent — Exotel rings them first
            To: formattedCustomer,          // Customer — dialed once the worker answers
            CallerId: exotelPhoneNumber,    // Selected ExoPhone masks both real numbers
            CallType: "trans",              // Transactional call
            Record: "true",                 // Enable call recording
        });

        // Add status callback if webhook URL is configured
        if (statusCallbackUrl) {
            callPayload.append("StatusCallback", statusCallbackUrl);
        }

        const exotelResponse = await axios({
            method: "post",
            url: exotelUrl,
            data: callPayload.toString(),
            headers: {
                "Content-Type": "application/x-www-form-urlencoded",
            },
            timeout: 15000,
        });

        const exotelCallSid = exotelResponse.data?.Call?.Sid;
        const exotelStatus = exotelResponse.data?.Call?.Status;

        // Update Firestore with Exotel Call SID
        await callRef.update({
            exotelCallSid: exotelCallSid || null,
            status: "ringing",
        });

        console.log(
            `Call initiated: ${callId} → Exotel SID: ${exotelCallSid} → ExoPhone ${exotelPhoneNumber} → worker ${formattedWorker} → customer ${formattedCustomer}`
        );

        return res.status(200).json({
            success: true,
            callSid: exotelCallSid,
            callId: callId,
        });
    } catch (err) {
        console.error("start-call error:", err.response?.data || err.message);

        if (req.body && req.body.callId) {
            await db
                .collection("calls")
                .doc(req.body.callId)
                .update({
                    status: "failed",
                    endedAt: admin.firestore.FieldValue.serverTimestamp(),
                })
                .catch((e) => { console.warn("Failed to update call as failed:", e); });
        }

        const errorMsg = err.response?.data?.RestException?.Message
            || err.message
            || "Call initiation failed";

        return res.status(err.statusCode || 500).json({ error: errorMsg });
    }
});

// ═══════════════════════════════════════════════════════════════
// POST /end-call — End an active Exotel call
// ═══════════════════════════════════════════════════════════════
app.post("/end-call", validateAuth, async (req, res) => {
    try {
        const { callId, userId } = req.body;

        if (!callId) {
            return res.status(400).json({ error: "Missing callId" });
        }

        if (req.uid !== userId) {
            return res.status(403).json({ error: "User mismatch" });
        }

        const callDoc = await db.collection("calls").doc(callId).get();
        if (!callDoc.exists) {
            return res.status(404).json({ error: "Call not found" });
        }

        const callData = callDoc.data();
        const exotelCallSid = callData.exotelCallSid;

        if (callData.provider === "twilio") {
            // Twilio: hang up by moving the call to "completed".
            if (exotelCallSid) {
                try {
                    const { endTwilioCall } = require("./twilio");
                    await endTwilioCall(exotelCallSid);
                } catch (endErr) {
                    console.warn("Twilio end-call warning:", endErr.message);
                }
            }
        } else if (exotelCallSid) {
            // Exotel: End a call by updating its status to "completed"
            try {
                const endCallUrl = `https://${EXOTEL_API_KEY}:${EXOTEL_API_TOKEN}@${EXOTEL_SUBDOMAIN}/v1/Accounts/${EXOTEL_SID}/Calls/${exotelCallSid}.json`;

                await axios({
                    method: "post",
                    url: endCallUrl,
                    data: new URLSearchParams({
                        Status: "completed",
                    }).toString(),
                    headers: {
                        "Content-Type": "application/x-www-form-urlencoded",
                    },
                    timeout: 10000,
                });
            } catch (endErr) {
                console.warn("Exotel end-call warning:", endErr.response?.data || endErr.message);
            }
        }

        await db.collection("calls").doc(callId).update({
            status: "completed",
            endedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`Call ended: ${callId}`);

        return res.status(200).json({ success: true });
    } catch (err) {
        console.error("end-call error:", err);
        return res.status(500).json({ error: err.message || "Failed to end call" });
    }
});

// ═══════════════════════════════════════════════════════════════
// POST /exotel-webhook — Exotel status callback
// ═══════════════════════════════════════════════════════════════
//
// Exotel sends these parameters in the webhook:
//   CallSid, Status, Direction, From, To, StartTime, EndTime,
//   Duration, RecordingUrl, etc.
//
// Exotel statuses: ringing, in-progress, completed, failed,
//                  busy, no-answer, canceled
// ═══════════════════════════════════════════════════════════════
app.post("/exotel-webhook", async (req, res) => {
    try {
        // Verify shared-secret token (enforced only when WEBHOOK_SECRET is set)
        if (!WEBHOOK_SECRET || req.query.token !== WEBHOOK_SECRET) {
            console.warn("exotel-webhook: rejected request with invalid/missing token");
            return res.status(403).send("Forbidden");
        }
        // Exotel sends data as form-urlencoded or JSON
        const webhookData = req.body;

        const callSid = webhookData.CallSid || webhookData.callsid;
        const callStatus = webhookData.Status || webhookData.status;
        const callDuration = webhookData.Duration || webhookData.duration;
        const recordingUrl = webhookData.RecordingUrl || webhookData.recordingurl;

        if (!callSid) {
            return res.status(400).send("Missing CallSid");
        }

        // Find the call in Firestore by Exotel SID
        const callSnapshot = await db
            .collection("calls")
            .where("exotelCallSid", "==", callSid)
            .limit(1)
            .get();

        if (callSnapshot.empty) {
            console.warn(`No Firestore call found for Exotel SID: ${callSid}`);
            return res.status(200).send("OK");
        }

        const callDoc = callSnapshot.docs[0];

        // Map Exotel statuses to our internal statuses
        const statusMap = {
            "ringing": "ringing",
            "in-progress": "in_progress",
            "completed": "completed",
            "failed": "failed",
            "busy": "failed",
            "no-answer": "failed",
            "canceled": "failed",
        };

        const mappedStatus = statusMap[callStatus?.toLowerCase()] || callStatus;

        const updateData = {
            status: mappedStatus,
        };

        // If call has ended, update duration and endedAt
        const terminalStatuses = ["completed", "failed", "busy", "no-answer", "canceled"];
        if (terminalStatuses.includes(callStatus?.toLowerCase())) {
            updateData.endedAt = admin.firestore.FieldValue.serverTimestamp();
            if (callDuration) {
                updateData.duration = parseInt(callDuration, 10);
            }
        }

        await callDoc.ref.update(updateData);

        // Update lead document with call metadata
        if (updateData.endedAt || recordingUrl) {
            const callData = callDoc.data();
            if (callData.leadId) {
                const leadUpdate = {};
                if (updateData.duration) leadUpdate.callDuration = updateData.duration;
                if (recordingUrl) {
                    const apiBaseUrl = (WEBHOOK_BASE_URL || "https://us-central1-sherize-bpo.cloudfunctions.net/api").replace(/\/+$/, "");
                    leadUpdate.recordingUrl = `${apiBaseUrl}/recording?callId=${encodeURIComponent(callDoc.id)}`;
                }
                if (Object.keys(leadUpdate).length > 0) {
                    leadUpdate.callId = callDoc.id;
                    const leadRef = db.collection("campaign_leads").doc(callData.leadId);
                    await db.runTransaction(async (txn) => {
                        const leadSnap = await txn.get(leadRef);
                        if (leadSnap.exists && leadAcceptsCallUpdate(leadSnap.data(), callDoc.id)) {
                            txn.update(leadRef, leadUpdate);
                        }
                    }).catch((e) => { console.warn("Failed to update campaign_lead:", e); });
                }
            }
        }

        console.log(`Exotel Webhook: ${callSid} → ${callStatus} → ${mappedStatus}`);
        return res.status(200).send("OK");
    } catch (err) {
        console.error("exotel-webhook error:", err);
        return res.status(500).send("Error");
    }
});

// ═══════════════════════════════════════════════════════════════
// POST /confirm-email-verified — REST fallback for Flutter Web
// ═══════════════════════════════════════════════════════════════
// This mirrors the onCall `confirmEmailVerified` function but is
// accessible via the Express `api` endpoint which already has CORS
// configured via cors({ origin: true }). Used as a fallback when
// the browser blocks the onCall function due to CORS/IAM issues.
// ═══════════════════════════════════════════════════════════════
app.post("/confirm-email-verified", express.json(), validateAuth, async (req, res) => {
    try {
        const uid = req.uid;

        // Read the authoritative Firebase Auth user record via Admin SDK.
        const userRecord = await admin.auth().getUser(uid);

        if (!userRecord.emailVerified) {
            return res.status(400).json({
                error: "failed-precondition",
                message: "Email not yet verified. Please click the link in your inbox first.",
            });
        }

        // Write emailVerified=true to Firestore using Admin SDK.
        await admin.firestore().collection("users").doc(uid).set(
            {
                emailVerified: true,
                emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                email: userRecord.email || "",
            },
            { merge: true }
        );

        console.log(`confirm-email-verified REST: Firestore updated for user ${uid}`);
        return res.status(200).json({ success: true });
    } catch (err) {
        console.error("confirm-email-verified REST error:", err);
        return res.status(500).json({ error: err.message || "Failed to confirm email verification." });
    }
});

// ─── Twilio Webhooks ───────────────────────────────────────────
const { handleTwilioWebhook, handleTwilioStatusCallback } = require("./twilio");
app.post("/twilio-webhook", handleTwilioWebhook);
app.post("/twilio-status-callback", handleTwilioStatusCallback);

// ─── Call Recording Proxy (AUTHENTICATED) ─────────────────────
// Streams an Exotel or Twilio call recording as audio/mpeg.
// Requires a valid Firebase Auth token.
// Verifies the requesting user is either:
//   1. An admin (role == 'admin' in Firestore), OR
//   2. The client who owns the call lead's campaign, OR
//   3. The worker who made the call (call_logs.callSid match + task_submissions.userId match)
app.get("/recording", validateAuth, async (req, res) => {
    let { callSid } = req.query;
    const { callId } = req.query;
    const uid = req.uid;

    if (!callSid && !callId) {
        return res.status(400).json({ error: "Missing callSid or callId" });
    }

    try {
        let callDoc = null;
        if (callId) {
            const directCallDoc = await db.collection("calls").doc(callId).get();
            if (directCallDoc.exists) callDoc = directCallDoc;
        } else {
            const callSnap = await db
                .collection("calls")
                .where("exotelCallSid", "==", callSid)
                .limit(1)
                .get();
            if (!callSnap.empty) callDoc = callSnap.docs[0];
        }

        if (!callDoc) {
            return res.status(404).json({ error: "Call not found" });
        }

        const callData = callDoc.data();
        if (callSid && callData.exotelCallSid !== callSid) {
            return res.status(400).json({ error: "callSid does not match callId" });
        }
        callSid = callData.exotelCallSid;
        if (!callSid) {
            return res.status(404).json({ error: "Call recording is not ready yet" });
        }

        // ── Ownership Check ───────────────────────────────────────
        // First check if the user is a review/admin staff member — they can
        // access any recording. Mirrors the review roles the app grants QA/payment
        // access to (admin_review_screen.dart _reviewRoles / _paymentRoles).
        const REVIEW_ROLES = ["admin", "super_admin", "task_review_admin", "kyc_admin"];
        const userSnap = await db.collection("users").doc(uid).get();
        const userData = userSnap.exists ? userSnap.data() : {};
        const userRoles = [userData.role, ...(Array.isArray(userData.roles) ? userData.roles : [])];
        const isAdmin = userRoles.some((role) => REVIEW_ROLES.includes(role));

        if (!isAdmin) {
            const ownsAsClient = await clientOwnsLeadRecording(db, uid, callData.leadId, callDoc.id);
            const ownsCallDirectly = callData.userId === uid;

            // Non-admins must own the call: check call_logs (callSid === uid's call)
            // OR task_submissions that reference the same callSid
            let ownsViaSubmission = false;
            let ownsViaCallLog = false;
            if (!ownsAsClient && !ownsCallDirectly) {
                const [callLogSnap, submissionSnap] = await Promise.all([
                    db.collection("call_logs")
                        .where("callSid", "==", callSid)
                        .limit(1)
                        .get(),
                    db.collection("task_submissions")
                        .where("callSid", "==", callSid)
                        .where("userId", "==", uid)
                        .limit(1)
                        .get(),
                ]);

                // Check call_logs: assignmentId won't have userId directly,
                // so also check task_submissions for same callSid + this user.
                ownsViaSubmission = !submissionSnap.empty;

                // As a fallback, also allow if the call_log references their assignment
                if (!callLogSnap.empty) {
                    const callLogData = callLogSnap.docs[0].data();
                    // If assignment belongs to this user, verify it
                    if (callLogData.assignmentId) {
                        const assignmentSnap = await db
                            .collection("task_assignments")
                            .doc(callLogData.assignmentId)
                            .get();
                        ownsViaCallLog =
                            assignmentSnap.exists &&
                            assignmentSnap.data().userId === uid;
                    }
                }
            }

            if (!ownsAsClient && !ownsCallDirectly && !ownsViaSubmission && !ownsViaCallLog) {
                console.warn(`[Recording] Unauthorized access attempt by uid=${uid} for callSid=${callSid}`);
                return res.status(403).json({ error: "Forbidden — you do not have access to this recording." });
            }
        }

        // Never trust calls.recordingUrl here: workers can update their own call
        // documents. Resolve the recording from the provider using the call SID.
        const provider = String(callData.provider || "exotel").toLowerCase();
        let recordingUrl = null;
        let providerAuth = null;
        if (provider === "twilio") {
            try {
                const { getTwilioRecordingUrl } = require("./twilio");
                recordingUrl = await getTwilioRecordingUrl(callSid);
                providerAuth = {
                    username: process.env.TWILIO_ACCOUNT_SID,
                    password: process.env.TWILIO_AUTH_TOKEN,
                };
            } catch (e) {
                console.warn(`[Recording] Twilio lookup failed for ${callSid}:`, e.status || e.message);
            }
        } else {
            try {
                const detailsUrl = `https://${EXOTEL_SUBDOMAIN}/v1/Accounts/${EXOTEL_SID}/Calls/${callSid}.json`;
                const details = await axios.get(detailsUrl, {
                    auth: { username: EXOTEL_API_KEY, password: EXOTEL_API_TOKEN },
                    timeout: 15000,
                });
                recordingUrl = details.data?.Call?.RecordingUrl || null;
                providerAuth = { username: EXOTEL_API_KEY, password: EXOTEL_API_TOKEN };
            } catch (e) {
                console.warn(`[Recording] Exotel details lookup failed for ${callSid}:`, e.response?.status || e.message);
            }
        }

        if (!recordingUrl) {
            return res.status(404).json({ error: "No recording found for this call yet. Try again shortly." });
        }

        if (!isAllowedRecordingUrl(recordingUrl, provider, EXOTEL_SUBDOMAIN)) {
            console.error(`[Recording] Rejected unexpected ${provider} recording URL`);
            return res.status(502).json({ error: "Recording provider returned an invalid URL" });
        }

        // S3 recording links are signed and must not receive Exotel credentials.
        const isS3Host = new URL(recordingUrl).hostname.endsWith("amazonaws.com");
        const audioResp = await axios.get(recordingUrl, {
            ...(isS3Host ? {} : { auth: providerAuth }),
            responseType: "stream",
            timeout: 30000,
            maxRedirects: 0,
        });

        res.setHeader("Content-Type", "audio/mpeg");
        res.setHeader("Accept-Ranges", "bytes");
        res.setHeader("Cache-Control", "private, no-store");
        res.setHeader("Vary", "Authorization");
        audioResp.data.pipe(res);
    } catch (err) {
        console.error("Recording proxy error:", err.response?.data || err.message);
        res.status(500).json({ error: "Failed to fetch recording" }); // Don't leak internal error
    }
});


// ─── Health Check ─────────────────────────────────────────────
app.get("/health", (req, res) => {
    res.status(200).json({ status: "ok", timestamp: new Date().toISOString() });
});

// ═══════════════════════════════════════════════════════════════
// EXPORT: Express API (Exotel VOIP)
// ═══════════════════════════════════════════════════════════════
exports.api = functions.https.onRequest(app);

// ─────────────────────────────────────────────────────────────────
// SECTION 2: CALLABLE FUNCTIONS (Earnings & Withdrawals)
// ─────────────────────────────────────────────────────────────────

const { approveTaskSubmission } = require("./earnings/approveSubmission");
const { rejectTaskSubmission } = require("./earnings/rejectSubmission");
const { reviewSubmissionQA } = require("./earnings/reviewSubmissionQA");
const { requestWithdrawal } = require("./withdrawals/requestWithdrawal");
const { processWithdrawal } = require("./withdrawals/processWithdrawal");
const { processWithdrawalPayout } = require("./withdrawals/processWithdrawalPayout");
const { retryWithdrawalPayout } = require("./withdrawals/retryWithdrawalPayout");
const { razorpayPayoutWebhook } = require("./withdrawals/razorpayPayoutWebhook");

exports.approveTaskSubmission = approveTaskSubmission;
exports.rejectTaskSubmission = rejectTaskSubmission;
exports.reviewSubmissionQA = reviewSubmissionQA;
exports.requestWithdrawal = requestWithdrawal;
exports.processWithdrawal = processWithdrawal;
exports.processWithdrawalPayout = processWithdrawalPayout;
exports.retryWithdrawalPayout = retryWithdrawalPayout;
exports.razorpayPayoutWebhook = razorpayPayoutWebhook;

const { sendEmailOtp, verifyEmailOtp } = require("./auth/emailOtp");

exports.sendEmailOtp = sendEmailOtp;
exports.verifyEmailOtp = verifyEmailOtp;


// ─────────────────────────────────────────────────────────────────
// SECTION 3: AUTOMATED NOTIFICATION TRIGGERS
// ─────────────────────────────────────────────────────────────────
const {
    onTaskAssigned,
    onTaskSubmissionReceived,
    onSubmissionUpdated,
    onWithdrawalUpdated,
    onTransactionCreated,
    onSupportRequestSubmitted
} = require("./notifications/triggers");

exports.onTaskAssigned = onTaskAssigned;
exports.onTaskSubmissionReceived = onTaskSubmissionReceived;
exports.onSubmissionUpdated = onSubmissionUpdated;
exports.onWithdrawalUpdated = onWithdrawalUpdated;
exports.onTransactionCreated = onTransactionCreated;
exports.onSupportRequestSubmitted = onSupportRequestSubmitted;

const { onClientWalletUpdated } = require("./campaigns/walletTriggers");
const { onCampaignDeleted } = require("./campaigns/onCampaignDeleted");
const { createCampaign } = require("./campaigns/createCampaign");
const { editCampaign } = require("./campaigns/editCampaign");
const { setClientCampaignStatus } = require("./campaigns/setClientCampaignStatus");
const { syncCampaignLeadCounts } = require("./campaigns/syncCampaignLeadCounts");
const { manageTeamCampaign } = require("./campaigns/manageTeamCampaign");
const { deleteExpiredCampaigns } = require("./campaigns/deleteExpiredCampaigns");
exports.onClientWalletUpdated = onClientWalletUpdated;
exports.onCampaignDeleted = onCampaignDeleted;
exports.createCampaign = createCampaign;
exports.editCampaign = editCampaign;
exports.setClientCampaignStatus = setClientCampaignStatus;
exports.syncCampaignLeadCounts = syncCampaignLeadCounts;
exports.manageTeamCampaign = manageTeamCampaign;
exports.deleteExpiredCampaigns = deleteExpiredCampaigns;

// ─────────────────────────────────────────────────────────────────
// SECTION 4: LEAD INGESTION (Storage-triggered)
// ─────────────────────────────────────────────────────────────────
const { processLeadSheet } = require("./leads/processLeadSheet");
const { createCampaignLeads } = require("./leads/createCampaignLeads");
exports.processLeadSheet = processLeadSheet;
exports.createCampaignLeads = createCampaignLeads;

// ─────────────────────────────────────────────────────────────────
// SECTION 5: PAYMENTS & WALLET
// ─────────────────────────────────────────────────────────────────
const { createRazorpayOrder, verifyPayment } = require("./payments/razorpay");
exports.createRazorpayOrder = createRazorpayOrder;
exports.verifyPayment = verifyPayment;

// ─────────────────────────────────────────────────────────────────
// SECTION 6: CLIENT PORTAL KYC & RECORDING BILLING
// ─────────────────────────────────────────────────────────────────
const {
    submitClientKyc,
    clientRecording,
    onCallRecordingFinalized,
    onCallLogRecordingFinalized,
    retryPendingRecordingBilling,
    addDemoRecordingCredits,
    reviewClientKyc,
    setClientAccountActivation,
    updateRecordingBillingSettings,
} = require("./client/portal");

exports.submitClientKyc = submitClientKyc;
exports.clientRecording = clientRecording;
exports.onCallRecordingFinalized = onCallRecordingFinalized;
exports.onCallLogRecordingFinalized = onCallLogRecordingFinalized;
exports.retryPendingRecordingBilling = retryPendingRecordingBilling;
exports.addDemoRecordingCredits = addDemoRecordingCredits;
exports.reviewClientKyc = reviewClientKyc;
exports.setClientAccountActivation = setClientAccountActivation;
exports.updateRecordingBillingSettings = updateRecordingBillingSettings;

// ─────────────────────────────────────────────────────────────────
// SECTION 7: SUPER ADMIN KYC & JOB LIFECYCLE
// ─────────────────────────────────────────────────────────────────
const {
    manageClientKyc,
    getClientKycDocumentUrl,
    expireJobOpenings,
} = require("./superAdmin/portal");

exports.manageClientKyc = manageClientKyc;
exports.getClientKycDocumentUrl = getClientKycDocumentUrl;
exports.expireJobOpenings = expireJobOpenings;

// ─────────────────────────────────────────────────────────────────
// SECTION 8: TWILIO INTEGRATION
// ─────────────────────────────────────────────────────────────────
const { initiateTwilioCallHttp } = require("./twilio");
exports.initiateTwilioCallHttp = initiateTwilioCallHttp;

// ─────────────────────────────────────────────────────────────────
// SECTION 9: SCHEDULED TASKS (Cron Jobs)
// ─────────────────────────────────────────────────────────────────
const { enforceTatAndRecreate } = require("./tasks/enforceTatAndRecreate");
exports.enforceTatAndRecreate = enforceTatAndRecreate;

// Server-authoritative worker submission (pause + funds re-check).
const { submitTaskWork, getTaskAssignmentProgress } = require("./tasks/submitTaskWork");
exports.submitTaskWork = submitTaskWork;
exports.getTaskAssignmentProgress = getTaskAssignmentProgress;

// Requeues leads marked as "no_answer" or "callback" back to "pending"
// after a 2-hour delay so another worker can attempt them.
// Leads are marked "unreachable" after 3 failed requeue cycles.
const { requeueLeads } = require("./tasks/requeueLeads");
exports.requeueLeads = requeueLeads;

// Keeps each active task's `totalLeads` (the marketplace "per worker" count and
// the Accept-flow quota) in sync with the live number of `pending` leads, so
// re-queued callback/no_answer leads reappear in the marketplace instead of
// being orphaned by a stale count.
const { syncTaskLeadCounts, syncTaskAssignmentAvailability } = require("./tasks/syncTaskLeadCounts");
exports.syncTaskLeadCounts = syncTaskLeadCounts;
exports.syncTaskAssignmentAvailability = syncTaskAssignmentAvailability;

// Scheduled safety-net that backfills any task whose marketplace lead count
// drifted from the live pending count (e.g. tasks that were already stale
// before the real-time trigger existed).
const { reconcileTaskLeadCounts } = require("./tasks/reconcileTaskLeadCounts");
exports.reconcileTaskLeadCounts = reconcileTaskLeadCounts;

// ─────────────────────────────────────────────────────────────────
// SECTION 8: AUTH & SECURITY
// ─────────────────────────────────────────────────────────────────
const { syncUserClaims } = require("./auth/syncUserClaims");
exports.syncUserClaims = syncUserClaims;

const { createAdminUser } = require("./auth/createAdminUser");
exports.createAdminUser = createAdminUser;

const { deleteUserAccount } = require("./auth/deleteUserAccount");
exports.deleteUserAccount = deleteUserAccount;

const { resetUserPassword } = require("./auth/resetUserPassword");
exports.resetUserPassword = resetUserPassword;

const { createEmployeeAccount } = require("./auth/createEmployeeAccount");
exports.createEmployeeAccount = createEmployeeAccount;

const { hireWorker } = require("./auth/hireWorker");
exports.hireWorker = hireWorker;

const { resolveEmployeeLogin } = require("./auth/resolveEmployeeLogin");
exports.resolveEmployeeLogin = resolveEmployeeLogin;

const { assignEmployeeTask, getTaskAssignmentEmployees, getTeamLeaderEmployees } = require("./tasks/assignEmployeeTask");
exports.assignEmployeeTask = assignEmployeeTask;
exports.getTaskAssignmentEmployees = getTaskAssignmentEmployees;
exports.getTeamLeaderEmployees = getTeamLeaderEmployees;
exports.acceptMarketplaceTask = require("./tasks/acceptMarketplaceTask").acceptMarketplaceTask;

const { updateTaskDistribution } = require("./tasks/updateTaskDistribution");
exports.updateTaskDistribution = updateTaskDistribution;

const { revokeTaskAssignment } = require("./tasks/revokeTaskAssignment");
exports.revokeTaskAssignment = revokeTaskAssignment;

const { submitPublicApplication } = require("./auth/submitPublicApplication");
exports.submitPublicApplication = submitPublicApplication;
