/**
 * backfillReviewedBy.js
 *
 * One-time migration: the approve path historically stored the reviewer in
 * `approvedBy` while the reject path used `reviewedBy`. The admin "Review
 * History" now filters by `reviewedBy`, so older APPROVED submissions (which
 * only have `approvedBy`) would not appear for the admin who approved them.
 *
 * This copies `approvedBy` → `reviewedBy` for approved submissions missing it.
 * Idempotent: skips docs that already have `reviewedBy`.
 *
 * Usage (from human_bpo/functions/):
 *   node backfillReviewedBy.js
 *
 * Requires Google Application Default Credentials for the project, e.g.:
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
  console.log(`Scanning ${snap.size} submission(s).`);

  let batch = db.batch();
  let ops = 0;
  let updated = 0;

  for (const d of snap.docs) {
    const data = d.data();
    if (data.reviewedBy) continue;          // already attributed
    if (!data.approvedBy) continue;         // never reviewed via approve path
    batch.update(d.ref, { reviewedBy: data.approvedBy });
    updated++;
    if (++ops >= 400) { await batch.commit(); batch = db.batch(); ops = 0; }
  }
  if (ops > 0) await batch.commit();

  console.log(`reviewedBy: backfilled ${updated} approved submission(s).`);
}

backfill()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Backfill failed:", err);
    process.exit(1);
  });
