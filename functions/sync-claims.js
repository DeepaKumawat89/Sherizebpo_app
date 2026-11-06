const admin = require("firebase-admin");

// Initialize Firebase Admin (make sure you run this via service account 
// or locally using `firebase login` credentials).
// Require the explicitly available serviceAccountKey.json to bypass local environment failures
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function syncAllClaims() {
    console.log("Starting to sync Firebase Auth custom claims based on Firestore 'users' collection...");
    
    let count = 0;
    try {
        const usersSnapshot = await db.collection("users").get();
        
        for (const doc of usersSnapshot.docs) {
            const uid = doc.id;
            const data = doc.data();
            
            if (data.role) {
                // Read current claims
                try {
                    const userRecord = await admin.auth().getUser(uid);
                    const currentClaims = userRecord.customClaims || {};
                    
                    if (currentClaims.role !== data.role) {
                        currentClaims.role = data.role;
                        await admin.auth().setCustomUserClaims(uid, currentClaims);
                        console.log(`Updated user ${uid} to role '${data.role}'`);
                        count++;
                    }
                } catch (authErr) {
                    console.error(`Skipping ${uid}: ${authErr.message}`);
                }
            }
        }
        
        console.log(`\nSync complete! Updated custom claims for ${count} users.`);
        process.exit(0);
    } catch (e) {
        console.error("Failed to sync claims:", e);
        process.exit(1);
    }
}

syncAllClaims();
