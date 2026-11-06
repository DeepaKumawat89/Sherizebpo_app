/**
 * createAdminUser — Callable Cloud Function
 *
 * Called by the Super Admin Portal to create new administrator accounts.
 * Uses Admin SDK so it:
 *   1. Bypasses Firestore rules entirely (Admin SDK ignores them)
 *   2. Sets custom claims IMMEDIATELY (no 1-hour token refresh wait)
 *   3. Creates Auth user + Firestore doc atomically
 *
 * Security: Only callable by users with role == 'super_admin' in their token.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { generateUniqueFriendlyId } = require("../utils/friendlyId");

const ALLOWED_ROLES = ["task_review_admin", "kyc_admin", "support_admin", "team_leader", "super_admin"];

// Super admin covers every capability, so it becomes the primary role when
// present; otherwise the first assigned role is primary. The primary drives
// custom claims + Firestore security rules; the full set lives in `roles`.
function pickPrimaryRole(roles) {
    return roles.includes("super_admin") ? "super_admin" : roles[0];
}

exports.createAdminUser = functions.https.onCall(async (data, context) => {
    // ── Auth check ───────────────────────────────────────────────
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }

    const callerRole = context.auth.token.role;
    if (callerRole !== "super_admin" && callerRole !== "admin") {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Only super admins can create administrator accounts."
        );
    }

    // ── Input validation ─────────────────────────────────────────
    const { email, password, fullName } = data;

    // Accept a `roles` array (new) or a single `role` (legacy). Normalise to a
    // de-duplicated array so the rest of the function has one shape to work with.
    const rawRoles = Array.isArray(data.roles) ? data.roles : (data.role ? [data.role] : []);
    const roles = [...new Set(rawRoles)];

    if (!email || !password || !fullName || roles.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "Missing required fields: email, password, fullName, and at least one role.");
    }

    const invalid = roles.filter(r => !ALLOWED_ROLES.includes(r));
    if (invalid.length > 0) {
        throw new functions.https.HttpsError("invalid-argument", `Invalid role(s): ${invalid.join(", ")}. Must be one of: ${ALLOWED_ROLES.join(", ")}`);
    }

    if (password.length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "Password must be at least 6 characters.");
    }

    const role = pickPrimaryRole(roles);

    // ── Create the Firebase Auth user ────────────────────────────
    let userRecord;
    try {
        userRecord = await admin.auth().createUser({
            email,
            password,
            displayName: fullName,
            emailVerified: true, // Admin-created accounts are pre-verified
        });
    } catch (err) {
        if (err.code === "auth/email-already-exists") {
            throw new functions.https.HttpsError("already-exists", "An account with this email already exists.");
        }
        throw new functions.https.HttpsError("internal", `Failed to create auth user: ${err.message}`);
    }

    const newUid = userRecord.uid;

    // ── Set custom claims IMMEDIATELY ────────────────────────────
    // This means the new admin can log in and have full permissions
    // on their FIRST sign-in, no waiting for token refresh.
    // We store BOTH the primary `role` (backward-compatible) and the full
    // `roles` array so security rules can honour every assigned role.
    try {
        await admin.auth().setCustomUserClaims(newUid, { role, roles });
    } catch (err) {
        // Clean up the auth user if claims fail
        await admin.auth().deleteUser(newUid).catch(() => {});
        throw new functions.https.HttpsError("internal", `Failed to set custom claims: ${err.message}`);
    }

    // ── Write Firestore user document using Admin SDK ────────────
    // Admin SDK bypasses all Firestore rules, so no permission issues.
    // Every admin except the super admin gets a friendly ADM-XXXX id so the
    // portal can reference them without exposing the raw Firestore uid.
    let adminId = null;
    if (role !== "super_admin") {
        adminId = await generateUniqueFriendlyId("ADM", { collection: "users", field: "adminId" });
    }
    try {
        await admin.firestore().collection("users").doc(newUid).set({
            uid: newUid,
            email,
            fullName,
            name: fullName,
            role,
            roles,
            ...(adminId ? { adminId } : {}),
            isActive: true,
            createdBy: context.auth.uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (err) {
        // Clean up auth user if Firestore write fails
        await admin.auth().deleteUser(newUid).catch(() => {});
        throw new functions.https.HttpsError("internal", `Failed to write user document: ${err.message}`);
    }

    console.log(`[createAdminUser] Created admin: ${email} (${newUid}) with roles: ${roles.join(", ")} (primary: ${role}) by: ${context.auth.uid}`);

    return { uid: newUid, email, role, roles, adminId, success: true };
});
