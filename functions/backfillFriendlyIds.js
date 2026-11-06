/**
 * backfillFriendlyIds.js
 *
 * One-time migration: assigns the human-friendly prefixed IDs to records that
 * were created before those fields existed, so nothing shows "Pending":
 *
 *   • adminId    (ADM-XXXX)  on users with an admin role (NOT super_admin)
 *   • taskCode   (TSK-XXXX)  on tasks
 *   • paymentCode(PAY-XXXX)  on withdraw_requests + payment transactions
 *
 * Codes are generated locally against a seeded "used" set (mirrors
 * backfillCampaignCodes.js) so we don't run a query per document.
 *
 * Usage (from human_bpo/functions/):
 *   node backfillFriendlyIds.js
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

// Admin roles that should receive an ADM- id. Super admin is intentionally
// excluded (matches createAdminUser.js).
const ADMIN_ROLES = ["admin", "task_review_admin", "kyc_admin", "payment_admin", "support_admin", "developer"];

function randomCode(prefix, width) {
  const min = Math.pow(10, width - 1);
  return `${prefix}-${Math.floor(min + Math.random() * (min * 9))}`;
}

// Build a generator that yields codes not already in `used`, widening the digit
// space if the small one gets crowded.
function makeUniqueCodeFn(prefix, used) {
  return () => {
    for (let i = 0; i < 20; i++) {
      const code = randomCode(prefix, 4);
      if (!used.has(code)) { used.add(code); return code; }
    }
    for (;;) {
      const code = randomCode(prefix, 6);
      if (!used.has(code)) { used.add(code); return code; }
    }
  };
}

// Commit `updates` (array of { ref, data }) in batches under the 500-op limit.
async function commitInBatches(updates) {
  let batch = db.batch();
  let ops = 0;
  for (const u of updates) {
    batch.update(u.ref, u.data);
    if (++ops >= 400) { await batch.commit(); batch = db.batch(); ops = 0; }
  }
  if (ops > 0) await batch.commit();
}

// ── Admin IDs (users with an admin role, excluding super_admin) ──────────────
async function backfillAdminIds() {
  const snap = await db.collection("users").get();
  const used = new Set();
  snap.forEach((d) => { if (d.data().adminId) used.add(d.data().adminId); });
  const nextCode = makeUniqueCodeFn("ADM", used);

  const isAdmin = (data) => {
    const roles = Array.isArray(data.roles) ? data.roles : [data.role];
    const list = roles.filter(Boolean);
    if (list.includes("super_admin")) return false; // excluded by design
    return list.some((r) => ADMIN_ROLES.includes(r));
  };

  const updates = [];
  snap.forEach((d) => {
    const data = d.data();
    if (data.adminId) return;
    if (!isAdmin(data)) return;
    updates.push({ ref: d.ref, data: { adminId: nextCode() } });
  });

  await commitInBatches(updates);
  console.log(`adminId: assigned to ${updates.length} admin(s).`);
}

// ── Task codes ───────────────────────────────────────────────────────────────
async function backfillTaskCodes() {
  const snap = await db.collection("tasks").get();
  const used = new Set();
  snap.forEach((d) => { if (d.data().taskCode) used.add(d.data().taskCode); });
  const nextCode = makeUniqueCodeFn("TSK", used);

  const updates = [];
  snap.forEach((d) => {
    if (d.data().taskCode) return;
    updates.push({ ref: d.ref, data: { taskCode: nextCode() } });
  });

  await commitInBatches(updates);
  console.log(`taskCode: assigned to ${updates.length} task(s).`);
}

// ── Payment codes (withdraw_requests + topup/withdrawal transactions) ────────
// Codes are unique across the shared `transactions` space (deposits +
// withdrawals) so a PAY- code never refers to two different payments.
async function backfillPaymentCodes() {
  const txSnap = await db.collection("transactions").get();
  const wrSnap = await db.collection("withdraw_requests").get();

  const used = new Set();
  txSnap.forEach((d) => { if (d.data().paymentCode) used.add(d.data().paymentCode); });
  wrSnap.forEach((d) => { if (d.data().paymentCode) used.add(d.data().paymentCode); });
  const nextCode = makeUniqueCodeFn("PAY", used);

  // A withdraw_request and its debit transaction should share one code. Map by
  // the transaction's referenceId (= withdraw_request doc id).
  const codeByWithdrawId = new Map();
  const updates = [];

  // Assign to transactions that represent a payment (topup or withdrawal).
  txSnap.forEach((d) => {
    const data = d.data();
    if (data.paymentCode) {
      if (data.source === "withdrawal" && data.referenceId) codeByWithdrawId.set(data.referenceId, data.paymentCode);
      return;
    }
    if (data.source !== "topup" && data.source !== "withdrawal") return;
    const code = nextCode();
    if (data.source === "withdrawal" && data.referenceId) codeByWithdrawId.set(data.referenceId, code);
    updates.push({ ref: d.ref, data: { paymentCode: code } });
  });

  // Assign to withdraw_requests, reusing the code from their debit transaction
  // when one exists so both records match.
  wrSnap.forEach((d) => {
    if (d.data().paymentCode) return;
    const code = codeByWithdrawId.get(d.id) || nextCode();
    updates.push({ ref: d.ref, data: { paymentCode: code } });
  });

  await commitInBatches(updates);
  console.log(`paymentCode: assigned to ${updates.length} payment record(s).`);
}

async function main() {
  await backfillAdminIds();
  await backfillTaskCodes();
  await backfillPaymentCodes();
  console.log("Backfill complete.");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Backfill failed:", err);
    process.exit(1);
  });
