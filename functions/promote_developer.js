/**
 * promote_developer.js
 * ---------------------------------------------------------------------------
 * Grants the DEVELOPER role to a user. Developer is the highest privilege and
 * is the only role that can manage the app branding / credit (app_config).
 *
 * Setting `role: 'developer'` on the Firestore user doc triggers
 * `syncUserClaims`, which mirrors it into the Firebase Auth custom claim so
 * that Firestore security rules recognise the developer.
 *
 * IMPORTANT: The email you promote MUST match `AppConstants.developerEmail`
 * in the Flutter app (lib/core/constants/app_constants.dart), otherwise the
 * in-app developer login will reject it.
 *
 * Usage:
 *   node promote_developer.js dev@novantixtech.com
 * ---------------------------------------------------------------------------
 */
const admin = require("firebase-admin");

if (!admin.apps.length) {
  const serviceAccount = require("./serviceAccountKey.json");
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: "sherize-bpo",
  });
}

const db = admin.firestore();
const auth = admin.auth();

async function promoteToDeveloper(email) {
  if (!email) {
    console.error("Usage: node promote_developer.js <email>");
    process.exit(1);
  }

  try {
    console.log(`Searching for user with email: ${email}...`);

    // 1. Find the user in Firebase Auth
    const userRecord = await auth.getUserByEmail(email);
    const uid = userRecord.uid;
    console.log(`✅ Found Auth user: ${uid}`);

    // 2. Update the role in Firestore (triggers syncUserClaims → custom claim)
    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      console.log("⚠️ User document not found in Firestore. Creating one...");
      await userRef.set({
        email: email,
        role: "developer",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      console.log(`Current role: ${userDoc.data().role || "none"}`);
      await userRef.update({
        role: "developer",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // 3. Set the custom claim immediately too (don't wait for the trigger).
    const currentClaims = userRecord.customClaims || {};
    await auth.setCustomUserClaims(uid, { ...currentClaims, role: "developer" });

    console.log(`\n🎉 SUCCESS: ${email} is now a DEVELOPER.`);
    console.log("They must sign out and back in for the new claim to take effect.");
    console.log("Log in via the hidden route: /dev/access");
  } catch (error) {
    if (error.code === "auth/user-not-found") {
      console.error(`\n❌ ERROR: User ${email} not found in Firebase Auth.`);
      console.error("Create the account first (sign up), then re-run this script.");
    } else if (
      error.message &&
      error.message.includes("Could not load the default credentials")
    ) {
      console.error("\n❌ ERROR: Firebase Admin SDK could not find credentials.");
      console.error("Ensure ./serviceAccountKey.json exists in this folder.");
    } else {
      console.error("\n❌ ERROR:", error.message || error);
    }
  }
}

const targetEmail = process.argv[2];
promoteToDeveloper(targetEmail);
