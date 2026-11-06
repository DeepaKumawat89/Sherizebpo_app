const admin = require('firebase-admin');

// Initialize with default credentials
admin.initializeApp();

const db = admin.firestore();

async function deleteCollection(collectionPath) {
    const colRef = db.collection(collectionPath);
    const snapshot = await colRef.get();
    
    if (snapshot.empty) {
        console.log(`Collection ${collectionPath} is already empty.`);
        return;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
    });

    await batch.commit();
    console.log(`Deleted ${snapshot.size} documents from ${collectionPath}.`);
}

async function run() {
    try {
        console.log("Clearing all task and campaign data...");
        await deleteCollection('campaigns');
        await deleteCollection('campaign_leads');
        await deleteCollection('tasks');
        await deleteCollection('task_assignments');
        
        // Let's also check if there are any pending withdrawals or anything else we should clear?
        // The user specifically asked for "task and campaigns data i want to start with fresh data"
        console.log("Data cleared successfully.");
    } catch (e) {
        console.error("Error clearing data:", e);
    }
}

run();
