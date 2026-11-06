/**
 * One-time repair for completed campaign leads whose recording was stored on
 * task_submissions but never linked back to campaign_leads.
 *
 * Dry run:
 *   node backfillLeadRecordingLinks.js
 * Apply:
 *   node backfillLeadRecordingLinks.js --apply
 */
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.GOOGLE_CLOUD_PROJECT || "sherize-bpo",
  });
}

const db = admin.firestore();
const RECORDING_API_BASE = "https://us-central1-sherize-bpo.cloudfunctions.net/api";

function buildRecordingLink({ submission, callId, call, lead }) {
  if (!submission.callSid || !callId || !call || !lead || lead.callId) return null;
  if (call.exotelCallSid !== submission.callSid
    || call.userId !== submission.userId
    || call.leadId !== submission.leadId
    || call.taskId !== submission.taskId
    || call.assignmentId !== submission.assignmentId
    || lead.taskId !== submission.taskId) return null;

  return {
    callId,
    recordingUrl: `${RECORDING_API_BASE}/recording?callId=${encodeURIComponent(callId)}`,
    ...(Number(call.duration) > 0 ? { callDuration: Number(call.duration) } : {}),
  };
}

function timestampMillis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : 0;
}

async function backfill({ apply }) {
  const submissionsSnap = await db.collection("task_submissions").get();
  const submissions = submissionsSnap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((submission) => submission.callSid && submission.leadId)
    .sort((left, right) => timestampMillis(right.submittedAt) - timestampMillis(left.submittedAt));

  const plannedLeadIds = new Set();
  const updates = [];
  let unmatched = 0;

  for (const submission of submissions) {
    if (plannedLeadIds.has(submission.leadId)) continue;
    plannedLeadIds.add(submission.leadId);

    const [callsSnap, leadSnap] = await Promise.all([
      db.collection("calls").where("exotelCallSid", "==", submission.callSid).limit(2).get(),
      db.collection("campaign_leads").doc(submission.leadId).get(),
    ]);
    if (callsSnap.size !== 1 || !leadSnap.exists) {
      unmatched++;
      continue;
    }

    const callDoc = callsSnap.docs[0];
    const update = buildRecordingLink({
      submission,
      callId: callDoc.id,
      call: callDoc.data(),
      lead: leadSnap.data(),
    });
    if (!update) continue;

    updates.push({ leadRef: leadSnap.ref, leadId: submission.leadId, update });
  }

  console.log(`${apply ? "Applying" : "Dry run:"} ${updates.length} recording link(s); ${unmatched} unmatched submission(s).`);
  if (!apply) return;

  let updated = 0;
  for (const item of updates) {
    await db.runTransaction(async (transaction) => {
      const currentLead = await transaction.get(item.leadRef);
      if (!currentLead.exists || currentLead.data().callId) return;
      transaction.update(item.leadRef, item.update);
      updated++;
    });
  }
  console.log(`Updated ${updated} campaign lead(s); skipped ${updates.length - updated} changed concurrently.`);
}

if (require.main === module) {
  backfill({ apply: process.argv.includes("--apply") })
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Recording link backfill failed:", error);
      process.exit(1);
    });
}

module.exports = { buildRecordingLink };