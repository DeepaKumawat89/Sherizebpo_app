/**
 * cleanup_tasks.js  (DESTRUCTIVE — deletes duplicate task docs)
 *
 * One-time repair for the marketplace after testing left many duplicate/stale
 * tasks. For every campaign that has tasks:
 *   1. Keeps ONE task (prefers an active one), deletes the duplicates.
 *   2. On the kept task:
 *        - totalLeads   = live count of pending campaign_leads
 *        - acceptedCount = 0            (release the stuck slot so it reappears)
 *        - totalSlots    = 1            (single worker per task, as requested)
 *        - status        = 'completed'  if 0 pending leads remain
 *                          else left as-is (paused stays paused → low balance)
 *
 * Run:  node cleanup_tasks.js
 *
 * NOTE: deleting a duplicate task does not remove any task_assignments that
 * referenced it; those stale "My Tasks" entries are harmless but can be cleared
 * separately if needed.
 */
const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function pendingCount(campaignId) {
  const c = await db.collection("campaign_leads")
    .where("campaignId", "==", campaignId)
    .where("status", "==", "pending")
    .count().get();
  return c.data().count;
}

async function main() {
  const tasksSnap = await db.collection("tasks").get();

  // Group tasks by campaignId.
  const byCampaign = new Map();
  for (const doc of tasksSnap.docs) {
    const cid = doc.data().campaignId;
    if (!cid) continue; // leave tasks with no campaign untouched
    if (!byCampaign.has(cid)) byCampaign.set(cid, []);
    byCampaign.get(cid).push(doc);
  }

  let kept = 0, deleted = 0, completed = 0, reopened = 0;

  for (const [cid, docs] of byCampaign) {
    const pending = await pendingCount(cid);

    // Prefer keeping an active task; otherwise keep the first one.
    docs.sort((a, b) => {
      const aActive = (a.data().status === "active") ? 0 : 1;
      const bActive = (b.data().status === "active") ? 0 : 1;
      return aActive - bActive;
    });
    const keep = docs[0];
    const dupes = docs.slice(1);

    // Delete duplicates.
    for (const d of dupes) {
      await d.ref.delete();
      deleted++;
    }

    // Repair the kept task.
    const cur = keep.data();
    const update = {
      totalLeads: pending,
      totalSlots: 1,
      acceptedCount: 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (pending === 0) {
      update.status = "completed";
      completed++;
    } else if (cur.status === "active") {
      reopened++;
    }
    await keep.ref.update(update);
    kept++;

    console.log(`Campaign ${cid} ("${cur.title || "?"}"): kept ${keep.id}, deleted ${dupes.length} dup(s), pending=${pending}, status=${update.status || cur.status}`);
  }

  console.log(`\nDone. kept=${kept}, deleted=${deleted}, markedCompleted=${completed}, reopened(active w/ leads)=${reopened}`);
  process.exit(0);
}

main().catch((e) => { console.error(e); process.exit(1); });
