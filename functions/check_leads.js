const admin = require("firebase-admin");
admin.initializeApp({
  projectId: "human-bpo" // Or whatever the local project ID is
});
const db = admin.firestore();

async function checkLeads() {
  const campaignId = "WMhN4VZCm154CvCkYS7Be";
  const snap = await db.collection("campaign_leads")
    .where("campaignId", "==", campaignId)
    .get();

  console.log(`Total leads for campaign ${campaignId}: ${snap.docs.length}`);

  let pending = 0;
  let otherStatus = {};

  snap.forEach(doc => {
    const data = doc.data();
    if (data.status === "pending") pending++;
    else {
      otherStatus[data.status] = (otherStatus[data.status] || 0) + 1;
    }
  });

  console.log(`Pending leads: ${pending}`);
  console.log(`Other statuses:`, otherStatus);
}

checkLeads().catch(console.error);
