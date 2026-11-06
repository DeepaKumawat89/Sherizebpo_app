const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp({ projectId: "human-cold-bpo" });
const db = admin.firestore();

async function checkTxs() {
  const snap = await db.collection("transactions").get();
  console.log(`\n--- ALL TRANSACTIONS (TOTAL: ${snap.docs.length}) ---`);
  snap.docs.forEach(doc => {
    let d = doc.data();
    console.log(doc.id, "=> userId:", d.userId, "role:", d.role, "amount:", d.amount, "type:", d.type, "ref:", d.referenceId);
  });
  process.exit(0);
}

checkTxs();
