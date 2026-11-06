const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

async function cleanupOrphanedLeads() {
    let deleteCount = 0;
    let batch = db.batch();
    let batchCount = 0;

    // Fetch all campaigns and build a set of valid IDs
    const campaignsSnap = await db.collection("campaigns").get();
    const validCampaignIds = new Set(campaignsSnap.docs.map(d => d.id));

    // Fetch all campaign_leads
    const leadsSnap = await db.collection("campaign_leads").get();
    for (const doc of leadsSnap.docs) {
        if (!validCampaignIds.has(doc.data().campaignId)) {
            batch.delete(doc.ref);
            deleteCount++;
            batchCount++;
            
            if (batchCount >= 400) {
                await batch.commit();
                batch = db.batch();
                batchCount = 0;
            }
        }
    }

    if (batchCount > 0) {
        await batch.commit();
    }

    if (deleteCount > 0) {
        console.log(`Cleaned up ${deleteCount} orphaned leads.`);
    } else {
        console.log("No orphaned leads found.");
    }
}

cleanupOrphanedLeads().catch(console.error);
