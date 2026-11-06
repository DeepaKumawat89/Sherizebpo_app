const admin = require("firebase-admin");
try {
  const serviceAccount = require("../../human-cold-bpo-firebase-adminsdk.json");
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
} catch (e) {
  admin.initializeApp();
}

const db = admin.firestore();

async function check() {
  const snap = await db.collection("withdraw_requests").orderBy("requestedAt", "desc").limit(5).get();
  console.log(`Found ${snap.size} withdraw_requests`);
  snap.forEach(doc => {
    console.log(doc.id, "=>", doc.data());
  });
}

check().catch(console.error);
