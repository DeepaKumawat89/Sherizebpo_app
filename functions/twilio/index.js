const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const twilio = require("twilio");
const cors = require("cors")({ origin: true });
const { leadAcceptsCallUpdate, twilioCallbackMatchesCall } = require("../recordings/recordingAccess");

// Shared secret appended to Twilio callback URLs and verified on inbound
// webhooks. Enforced only when configured (see WEBHOOK_SECRET in index.js).
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || "";

// Public base URL of the Express API (used to build Twilio callback URLs).
function apiBaseUrl() {
  return process.env.WEBHOOK_BASE_URL || `https://us-central1-sherize-bpo.cloudfunctions.net/api`;
}

// Normalize an Indian phone number to E.164 (+91XXXXXXXXXX) for Twilio.
function toE164India(raw) {
  let p = String(raw || "").trim();
  if (p.startsWith("+")) return p;
  p = p.replace(/\D/g, "");
  if (p.length === 10) return `+91${p}`;
  if (p.length === 11 && p.startsWith("0")) return `+91${p.substring(1)}`;
  if (p.length === 12 && p.startsWith("91")) return `+${p}`;
  return `+${p}`;
}

function twilioClient() {
  return twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
}

// Try to grab phone from users collection
async function getWorkerPhone(uid) {
  const userDoc = await admin.firestore().collection("users").doc(uid).get();
  if (!userDoc.exists) {
    throw new Error("Worker profile not found.");
  }
  const data = userDoc.data();
  if (!data.phone && !data.phoneNumber) {
    throw new Error("No phone number registered for this worker. Please update your profile.");
  }
  // Standardize the phone to +91 format if it's 10 digits
  let phone = data.phone || data.phoneNumber;
  if (/^\d{10}$/.test(phone)) {
    phone = `+91${phone}`;
  }
  return phone;
}

// 1. Initiate Call
exports.initiateTwilioCallHttp = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    if (req.method !== 'POST') {
      return res.status(405).json({ data: { error: 'Method Not Allowed' } });
    }

    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({ data: { error: "You must be logged in to initiate a call." } });
    }
    
    const idToken = authHeader.split("Bearer ")[1];
    let decodedToken;
    try {
      decodedToken = await admin.auth().verifyIdToken(idToken);
    } catch (error) {
      return res.status(401).json({ data: { error: "Unauthorized: Invalid or expired token." } });
    }

    const data = req.body.data || {};
    const { leadId, customerPhone, assignmentId, taskId } = data;
    
    if (!customerPhone) {
      return res.status(400).json({ data: { error: "Customer phone number is required." } });
    }

    try {
      const workerPhone = await getWorkerPhone(decodedToken.uid);

      const client = twilio(
        process.env.TWILIO_ACCOUNT_SID,
        process.env.TWILIO_AUTH_TOKEN
      );

      // We'll fallback to the actual deployed endpoint if WEBHOOK_BASE_URL isn't set
      const baseUrl = process.env.WEBHOOK_BASE_URL || `https://us-central1-sherize-bpo.cloudfunctions.net/api`;

      // Call the worker first
      const secretParam = WEBHOOK_SECRET ? `&token=${encodeURIComponent(WEBHOOK_SECRET)}` : "";
      const call = await client.calls.create({
        url: `${baseUrl}/twilio-webhook?customerPhone=${encodeURIComponent(customerPhone)}&leadId=${leadId}&assignmentId=${assignmentId || ""}&taskId=${taskId || ""}${secretParam}`,
        to: workerPhone,
        from: process.env.TWILIO_PHONE_NUMBER,
        record: true,
        statusCallbackEvent: ['completed'],
        statusCallback: `${baseUrl}/twilio-status-callback?leadId=${leadId}&assignmentId=${assignmentId || ""}&taskId=${taskId || ""}${secretParam}`,
        statusCallbackMethod: 'POST',
      });

      console.log(`Call initiated to worker ${workerPhone}. Twilio Call SID: ${call.sid}`);
      return res.status(200).json({ data: { success: true, callSid: call.sid, message: "Dialing your phone..." } });
    } catch (error) {
      console.error("Error initiating Twilio call:", error);
      return res.status(500).json({ data: { error: error.message || "Failed to initiate call." } });
    }
  });
});

// Helper for the Express app to handle the Twilio logic
async function handleTwilioWebhook(req, res) {  if (!WEBHOOK_SECRET || req.query.token !== WEBHOOK_SECRET) {
    return res.status(403).send("Forbidden");
  }
  const customerPhone = req.query.customerPhone;

  const VoiceResponse = twilio.twiml.VoiceResponse;
  const twiml = new VoiceResponse();

  if (!customerPhone) {
    twiml.say("Error: Missing customer phone number.");
    twiml.hangup();
    res.type("text/xml");
    res.send(twiml.toString());
    return;
  }

  let formattedCustomerPhone = customerPhone;
  if (/^\d{10}$/.test(customerPhone)) {
    formattedCustomerPhone = `+91${customerPhone}`;
  }

  twiml.say("Dialing customer now. The call is being recorded.");
  const dial = twiml.dial({
    callerId: process.env.TWILIO_PHONE_NUMBER,
    record: "record-from-answer", 
  });
  dial.number(formattedCustomerPhone);

  res.type("text/xml");
  res.send(twiml.toString());
}

async function handleTwilioStatusCallback(req, res) {
  try {
    if (!WEBHOOK_SECRET || req.query.token !== WEBHOOK_SECRET) {
      return res.status(403).send("Forbidden");
    }
    const { leadId, assignmentId, taskId, callId } = req.query;
    const { CallSid, CallDuration, RecordingUrl, CallStatus } = req.body;

    console.log(`Call finished: ${CallSid}. Duration: ${CallDuration}. Status: ${CallStatus}`);

    const resolvedRecordingUrl = RecordingUrl ? `${RecordingUrl}.mp3` : null;
    const proxyRecordingUrl = CallSid
      ? `${apiBaseUrl()}/recording?callSid=${CallSid}`
      : null;

    if (callId) {
      const callDoc = await admin.firestore().collection("calls").doc(callId).get();
      if (!callDoc.exists) return res.status(404).send("Call not found");

      const callData = callDoc.data();
      if (!twilioCallbackMatchesCall(callData, {
        callSid: CallSid, leadId, assignmentId, taskId,
      })) return res.status(403).send("Call mismatch");
    }

    if (leadId) {
      await admin.firestore().collection("call_logs").doc(CallSid).set({
        leadId: leadId || null,
        assignmentId: assignmentId || null,
        taskId: taskId || null,
        callSid: CallSid,
        durationSeconds: parseInt(CallDuration || "0", 10),
        recordingUrl: resolvedRecordingUrl,
        status: CallStatus,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Sync the app-facing `calls/{callId}` doc so app-initiated Twilio calls
    // land the same status/duration/recording as the Exotel path.
    if (callId) {
      const statusMap = {
        completed: "completed",
        busy: "failed",
        "no-answer": "failed",
        failed: "failed",
        canceled: "failed",
      };
      const mapped = statusMap[String(CallStatus || "").toLowerCase()] || "completed";
      const update = {
        status: mapped,
        endedAt: admin.firestore.FieldValue.serverTimestamp(),
        duration: parseInt(CallDuration || "0", 10),
      };
      if (proxyRecordingUrl && resolvedRecordingUrl) update.recordingUrl = proxyRecordingUrl;
      await admin.firestore().collection("calls").doc(callId).update(update)
        .catch((e) => { console.warn("Could not update calls doc from Twilio status:", e.message); });

      if (leadId && resolvedRecordingUrl) {
        const db = admin.firestore();
        const leadRef = db.collection("campaign_leads").doc(leadId);
        await db.runTransaction(async (txn) => {
          const leadSnap = await txn.get(leadRef);
          if (leadSnap.exists && leadAcceptsCallUpdate(leadSnap.data(), callId)) {
            txn.update(leadRef, {
              callId,
              callDuration: parseInt(CallDuration || "0", 10),
              recordingUrl: `${apiBaseUrl()}/recording?callId=${encodeURIComponent(callId)}`,
            });
          }
        }).catch((e) => { console.warn("Could not update campaign lead from Twilio status:", e.message); });
      }
    }

    // Back-fill recordingUrl on the matching task_submission (if the worker already submitted)
    if (CallSid && resolvedRecordingUrl) {
      const proxyRecordingUrl = `https://us-central1-sherize-bpo.cloudfunctions.net/api/recording?callSid=${CallSid}`;
      try {
        const submissionsSnap = await admin.firestore()
          .collection("task_submissions")
          .where("callSid", "==", CallSid)
          .limit(1)
          .get();

        if (!submissionsSnap.empty) {
          await submissionsSnap.docs[0].ref.update({
            recordingUrl: proxyRecordingUrl,
          });
          console.log(`Updated task_submission ${submissionsSnap.docs[0].id} with proxy recordingUrl.`);
        }
      } catch (updateError) {
        console.warn("Could not back-fill recordingUrl on task_submission:", updateError);
      }
    }

    res.status(200).send("OK");
  } catch (error) {
    console.error("Error in status callback:", error);
    res.status(500).send("Internal Server Error");
  }
}

exports.handleTwilioWebhook = handleTwilioWebhook;
exports.handleTwilioStatusCallback = handleTwilioStatusCallback;

// ─── App integration helpers (called from /start-call & /end-call) ──────────
// Initiate a worker→customer bridged, recorded call for an existing
// calls/{callId} document. Returns the Twilio Call SID.
async function initiateAppTwilioCall({ workerPhone, customerPhone, callId, leadId, assignmentId, taskId }) {
  const client = twilioClient();
  const baseUrl = apiBaseUrl();
  const secretParam = WEBHOOK_SECRET ? `&token=${encodeURIComponent(WEBHOOK_SECRET)}` : "";
  const q =
    `customerPhone=${encodeURIComponent(toE164India(customerPhone))}` +
    `&callId=${encodeURIComponent(callId || "")}` +
    `&leadId=${encodeURIComponent(leadId || "")}` +
    `&assignmentId=${encodeURIComponent(assignmentId || "")}` +
    `&taskId=${encodeURIComponent(taskId || "")}${secretParam}`;

  const call = await client.calls.create({
    url: `${baseUrl}/twilio-webhook?${q}`,
    to: toE164India(workerPhone),
    from: process.env.TWILIO_PHONE_NUMBER,
    record: true,
    statusCallbackEvent: ["completed"],
    statusCallback: `${baseUrl}/twilio-status-callback?${q}`,
    statusCallbackMethod: "POST",
  });
  return call.sid;
}

// Hang up an active Twilio call by completing it.
async function endTwilioCall(callSid) {
  const client = twilioClient();
  await client.calls(callSid).update({ status: "completed" });
}

async function getTwilioRecordingUrl(callSid) {
  const recordings = await twilioClient().recordings.list({ callSid, limit: 1 });
  if (!recordings.length) return null;
  return `https://api.twilio.com${recordings[0].uri.replace(/\.json$/, ".mp3")}`;
}

exports.initiateAppTwilioCall = initiateAppTwilioCall;
exports.endTwilioCall = endTwilioCall;
exports.getTwilioRecordingUrl = getTwilioRecordingUrl;
exports.toE164India = toE164India;
