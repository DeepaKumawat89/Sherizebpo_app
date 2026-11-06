const admin = require("firebase-admin");

// Initialize with the correct project ID using a service account
if (!admin.apps.length) {
  const serviceAccount = require("./serviceAccountKey.json");
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: "sherize-bpo"
  });
}

const db = admin.firestore();
const auth = admin.auth();

async function promoteToSuperAdmin(email) {
  if (!email) {
    console.error("Usage: node promote_super_admin.js <email>");
    process.exit(1);
  }

  try {
    console.log(`Searching for user with email: ${email}...`);
    
    // 1. Find the user in Firebase Auth
    const userRecord = await auth.getUserByEmail(email);
    const uid = userRecord.uid;
    console.log(`✅ Found Auth user: ${uid}`);

    // 2. Update the role in Firestore
    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      console.log("⚠️ User document not found in Firestore. Creating one...");
      await userRef.set({
        email: email,
        role: "super_admin",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } else {
      console.log(`Current role: ${userDoc.data().role || 'none'}`);
      await userRef.update({
        role: "super_admin",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    console.log(`\n🎉 SUCCESS: ${email} has been promoted to Super Admin.`);
    console.log("You can now log in to the portal at http://localhost:5174/");
    
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      console.error(`\n❌ ERROR: User ${email} not found in Firebase Auth.`);
      console.error("Please sign up in the app or portal first.");
    } else if (error.message && error.message.includes("Could not load the default credentials")) {
      console.error("\n❌ ERROR: Firebase Admin SDK could not find credentials.");
      console.error("Try running: firebase login:ci (and set the token) OR ensure you are logged in via 'firebase login'.");
    } else {
      console.error("\n❌ ERROR:", error.message || error);
    }
  }
}

const targetEmail = process.argv[2];
promoteToSuperAdmin(targetEmail);
