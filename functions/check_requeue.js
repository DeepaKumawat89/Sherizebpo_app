/**
 * check_requeue.js (READ-ONLY) — verifies the requeueLeads query works and
 * lists any leads stuck in requeue_pending.
 */
const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  const now = admin.firestore.Timestamp.now();

  // 1) All requeue_pending leads (single-field, always works).
  const allPending = await db.collection("campaign_leads")
    .where("status", "==", "requeue_pending").get();
  console.log(`\nrequeue_pending leads: ${allPending.size}`);
  allPending.forEach(d => {
    const x = d.data();
    const after = x.requeueAfter?.toDate?.();
    const due = after ? (after <= now.toDate() ? "DUE" : `waits until ${after.toISOString()}`) : "no requeueAfter";
    console.log(`  • ${d.id} campaign=${x.campaignId} reason=${x.requeueReason} count=${x.requeueCount || 0} → ${due}`);
  });

  // 2) The exact scheduled-job query (needs composite index).
  try {
    const snap = await db.collection("campaign_leads")
      .where("status", "==", "requeue_pending")
      .where("requeueAfter", "<=", now)
      .limit(300).get();
    console.log(`\n✅ requeue query OK — ${snap.size} lead(s) due for requeue now.`);
  } catch (e) {
    console.log(`\n❌ requeue query FAILED: ${e.message}`);
    if (String(e.message).toLowerCase().includes("index")) {
      console.log("   → This confirms the missing composite index (status + requeueAfter).");
    }
  }
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
