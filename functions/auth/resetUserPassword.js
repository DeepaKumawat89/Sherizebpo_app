/**
 * resetUserPassword — Callable Cloud Function
 *
 * Called by the Super Admin Portal to reset an administrator's password when
 * they report a login/password issue or forget their password. Uses the Admin
 * SDK so it can set a new password directly without the user's current one.
 *
 * Security: Active managers only; team leaders may reset employee-only accounts.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { employeeIdCandidates, idToEmail } = require("../utils/employeeId");
const { validateActiveManager } = require("../utils/teamLeaderAccess");

exports.resetUserPassword = functions.https.onCall(async (data, context) => {
    // ── Auth check ───────────────────────────────────────────────
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }

    const db = admin.firestore();
    const { isPlatformAdmin } = await validateActiveManager(db, context.auth.uid);

    // ── Input validation ─────────────────────────────────────────
    const { uid, newPassword } = data || {};

    if (!uid || typeof uid !== "string") {
        throw new functions.https.HttpsError("invalid-argument", "A valid 'uid' is required.");
    }
    if (!newPassword || typeof newPassword !== "string" || newPassword.length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "Password must be at least 6 characters.");
    }

    const targetRef = db.collection("users").doc(uid);
    const target = await targetRef.get();
    const targetData = target.data();
    if (!isPlatformAdmin) {
        if (!target.exists || targetData.role !== "worker" ||
            (Array.isArray(targetData.roles) && targetData.roles.some(role => role !== "worker"))) {
            throw new functions.https.HttpsError("permission-denied", "You can reset passwords only for employee accounts without privileged roles.");
        }
    }

    // ── Set the new password ─────────────────────────────────────
    const authUpdate = { password: newPassword };
    let loginEmail;
    if (target.exists && String(targetData.role || "").toLowerCase() === "worker") {
        const employeeId = employeeIdCandidates(targetData.employeeId || targetData.workerId)[0];
        if (!employeeId) {
            throw new functions.https.HttpsError("failed-precondition", "This worker has no valid Employee ID.");
        }
        loginEmail = idToEmail(employeeId);
        authUpdate.email = loginEmail;
        authUpdate.emailVerified = true;
    }

    try {
        await admin.auth().updateUser(uid, authUpdate);
        if (loginEmail) {
            await targetRef.set({ email: loginEmail, loginEmail }, { merge: true });
        }
    } catch (err) {
        if (err.code === "auth/user-not-found") {
            throw new functions.https.HttpsError("not-found", "No account found for this user.");
        }
        throw new functions.https.HttpsError("internal", `Failed to reset password: ${err.message}`);
    }

    console.log(`[resetUserPassword] Password reset for ${uid} by: ${context.auth.uid}`);

    return { uid, success: true };
});
