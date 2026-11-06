/**
 * deleteUserAccount — Callable Cloud Function
 *
 * Called by the Super Admin Portal to permanently delete a user
 * (administrator or worker). Uses the Admin SDK so it:
 *   1. Deletes the Firebase Auth account (frees the email, blocks re-login)
 *   2. Deletes the Firestore user document
 *
 * Without this, a client-side deleteDoc() would leave an ORPHANED Auth
 * account: the email stays occupied and the user could still authenticate.
 *
 * The `syncUserClaims` onWrite trigger also fires on the doc deletion and
 * clears any custom claims — but only removing the Auth account fully
 * deprovisions the user.
 *
 * Security: Only callable by users with role == 'super_admin' in their token.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

exports.deleteUserAccount = functions.https.onCall(async (data, context) => {
    // ── Auth check ───────────────────────────────────────────────
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }

    const callerRole = context.auth.token.role;
    if (callerRole !== "super_admin" && callerRole !== "admin") {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Only super admins can delete user accounts."
        );
    }

    // ── Input validation ─────────────────────────────────────────
    const { uid } = data || {};

    if (!uid || typeof uid !== "string") {
        throw new functions.https.HttpsError("invalid-argument", "A valid 'uid' is required.");
    }

    // Prevent a super admin from deleting their own account.
    if (uid === context.auth.uid) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "You cannot delete your own account."
        );
    }

    // ── Delete the Firestore user document ───────────────────────
    // Admin SDK bypasses all Firestore rules, so no permission issues.
    try {
        await admin.firestore().collection("users").doc(uid).delete();
    } catch (err) {
        throw new functions.https.HttpsError("internal", `Failed to delete user document: ${err.message}`);
    }

    // ── Delete the Firebase Auth account ─────────────────────────
    // If the auth record is already gone, treat it as success.
    try {
        await admin.auth().deleteUser(uid);
    } catch (err) {
        if (err.code !== "auth/user-not-found") {
            throw new functions.https.HttpsError("internal", `Failed to delete auth account: ${err.message}`);
        }
    }

    console.log(`[deleteUserAccount] Deleted user ${uid} by: ${context.auth.uid}`);

    return { uid, success: true };
});
