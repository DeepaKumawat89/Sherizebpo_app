/**
 * diagnose_tasks.js  (READ-ONLY)
 *
 * Prints every task and explains whether it is visible in the worker
 * marketplace, using the same rule the Flutter app applies:
 *
 *   visible  ==  status === 'active'  AND  acceptedCount < totalSlots
 *
 * Also compares each task's stored totalLeads against the live count of
 * pending campaign_leads, so a stale count (the "1 per worker" bug) is obvious.
 *
 * Run:  node diagnose_tasks.js
 * Makes no writes.
 */
const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  const tasksSnap = await db.collection("tasks").get();
  console.log(`\nFound ${tasksSnap.size} task(s):\n`);

  for (const doc of tasksSnap.docs) {
    const t = doc.data();
    const status = t.status || "(none)";
    const totalSlots = Number(t.totalSlots ?? t.maxSlots ?? 1);
    const acceptedCount = Number(t.acceptedCount ?? 0);
    const totalLeads = Number(t.totalLeads ?? 0);
    const campaignId = t.campaignId || "(none)";

    // Live pending-lead count for this campaign.
    let pendingLeads = "n/a";
    if (campaignId !== "(none)") {
      try {
        const c = await db.collection("campaign_leads")
          .where("campaignId", "==", campaignId)
          .where("status", "==", "pending")
          .count().get();
        pendingLeads = c.data().count;
      } catch (e) {
        pendingLeads = `err(${e.message})`;
      }
    }

    const visible = status === "active" && acceptedCount < totalSlots;
    let reason = "VISIBLE in marketplace";
    if (!visible) {
      if (status !== "active") reason = `HIDDEN — status is "${status}" (not "active")`;
      else if (acceptedCount >= totalSlots) reason = `HIDDEN — slots full (${acceptedCount}/${totalSlots} accepted)`;
    }

    console.log(`• ${t.title || "(untitled)"}  [task ${doc.id}]`);
    console.log(`    status=${status}  slots=${acceptedCount}/${totalSlots}  totalLeads=${totalLeads}  pendingLeads=${pendingLeads}  campaignId=${campaignId}`);
    console.log(`    → ${reason}`);
    if (totalLeads !== pendingLeads && pendingLeads !== "n/a" && typeof pendingLeads === "number") {
      console.log(`    ⚠ totalLeads (${totalLeads}) != live pending leads (${pendingLeads}) — count is stale.`);
    }
    console.log("");
  }
  process.exit(0);
}

main().catch((e) => { console.error(e); process.exit(1); });
