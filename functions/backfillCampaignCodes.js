/**
 * backfillCampaignCodes.js
 *
 * One-time migration: assigns a human-friendly campaignCode (CMP-XXXX) to every
 * campaign document that does not already have one. This lets the UI reference
 * campaigns by a short code instead of exposing the raw Firestore document ID.
 *
 * Usage (from human_bpo/functions/):
 *   node backfillCampaignCodes.js
 *
 * Requires Google Application Default Credentials for the project, e.g.:
 *   gcloud auth application-default login
 *   set GOOGLE_CLOUD_PROJECT=sherize-bpo   (Windows)   or
 *   export GOOGLE_CLOUD_PROJECT=sherize-bpo (macOS/Linux)
 */
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.GOOGLE_CLOUD_PROJECT || "sherize-bpo",
  });
}

const db = admin.firestore();

function randomCode(width) {
  const min = Math.pow(10, width - 1);
  return `CMP-${Math.floor(min + Math.random() * (min * 9))}`;
}

async function backfill() {
  const snap = await db.collection("campaigns").get();
  console.log(`Found ${snap.size} campaign(s).`);

  // Seed the used-code set with codes already assigned so we never collide.
  const used = new Set();
  snap.forEach((d) => {
    const code = d.data().campaignCode;
    if (code) used.add(code);
  });

  const uniqueCode = () => {
    for (let i = 0; i < 20; i++) {
      const code = randomCode(4);
      if (!used.has(code)) { used.add(code); return code; }
    }
    // 4-digit space getting crowded — widen to 6 digits.
    for (;;) {
      const code = randomCode(6);
      if (!used.has(code)) { used.add(code); return code; }
    }
  };

  let updated = 0;
  let batch = db.batch();
  let ops = 0;

  for (const d of snap.docs) {
    if (d.data().campaignCode) continue; // already has one
    batch.update(d.ref, { campaignCode: uniqueCode() });
    updated++;
    ops++;
    if (ops >= 400) { // stay under the 500-op batch limit
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();

  console.log(`Assigned campaignCode to ${updated} campaign(s). ${snap.size - updated} already had one.`);
}

backfill()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Backfill failed:", err);
    process.exit(1);
  });
