/**
 * backfillSubmissionWorkerIds.js
 *
 * One-time migration: denormalizes each worker's friendly workerId (SHR######)
 * onto existing task_submissions that were created before the field was added,
 * so reviewers can display it without reading the restricted users collection.
 *
 * Usage (from human_bpo/functions/):
 *   node backfillSubmissionWorkerIds.js
 *
 * Requires Application Default Credentials, e.g.:
 *   gcloud auth application-default login
 *   set GOOGLE_CLOUD_PROJECT=sherize-bpo   (Windows)
 */
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.GOOGLE_CLOUD_PROJECT || "sherize-bpo",
  });
}

const db = admin.firestore();

async function backfill() {
  const snap = await db.collection("task_submissions").get();
  console.log(`Found ${snap.size} submission(s).`);

  const codeCache = new Map(); // userId -> workerId (avoid re-reading users)

  const codeFor = async (userId) => {
    if (!userId) return "";
    if (codeCache.has(userId)) return codeCache.get(userId);
    let code = "";
    try {
      const u = await db.collection("users").doc(userId).get();
      if (u.exists) {
        const d = u.data();
        code = String(d.systemWorkerId || d.workerId || "");
      }
    } catch (e) {
      console.warn(`  could not read user ${userId}: ${e.message}`);
    }
    codeCache.set(userId, code);
    return code;
  };

  let updated = 0;
  let batch = db.batch();
  let ops = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.workerId) continue; // already denormalized
    const code = await codeFor(data.userId);
    if (!code) continue; // nothing to write
    batch.update(doc.ref, { workerId: code });
    updated++;
    ops++;
    if (ops >= 400) { // stay under the 500-op batch limit
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();

  console.log(`Denormalized workerId onto ${updated} submission(s).`);
}

backfill()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Backfill failed:", err);
    process.exit(1);
  });
