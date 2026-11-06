const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

async function cleanupOrphaned() {
    let deleteCount = 0;
    const batch = db.batch();

    // Fetch all campaigns and build a set of valid IDs
    const campaignsSnap = await db.collection("campaigns").get();
    const validCampaignIds = new Set(campaignsSnap.docs.map(d => d.id));

    // Fetch all tasks
    const tasksSnap = await db.collection("tasks").get();
    for (const doc of tasksSnap.docs) {
        if (!validCampaignIds.has(doc.data().campaignId)) {
            batch.delete(doc.ref);
            deleteCount++;
            console.log(`Orphaned task deleted: ${doc.id}`);
        }
    }

    if (deleteCount > 0) {
        await batch.commit();
        console.log(`Cleaned up ${deleteCount} orphaned tasks.`);
    } else {
        console.log("No orphaned tasks found.");
    }
}

cleanupOrphaned().catch(console.error);
