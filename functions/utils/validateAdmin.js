/**
 * validateAdmin.js
 *
 * Utility to verify that a given UID belongs to a user with role === "admin"
 * in the Firestore `users` collection.
 *
 * Usage:
 *   const { validateAdmin } = require("../utils/validateAdmin");
 *   await validateAdmin(db, uid); // throws HttpsError if not admin
 */

const functions = require("firebase-functions/v1");

/**
 * Normalises a user document into its full set of (lower-cased) roles.
 * Combines the multi-role `roles` array with the legacy single `role` field.
 * @param {Object} userData - Firestore user document data
 * @returns {string[]} de-duplicated lower-cased roles
 */
function rolesOf(userData) {
  const list = Array.isArray(userData.roles) ? userData.roles : [];
  if (userData.role) list.push(userData.role);
  return [...new Set(list.map((r) => String(r).toLowerCase()))];
}

/**
 * Validates that the user identified by `uid` has admin role in Firestore.
 *
 * @param {FirebaseFirestore.Firestore} db - Firestore instance
 * @param {string} uid - Firebase Auth UID to verify
 * @returns {Promise<Object>} The user data if admin
 * @throws {functions.https.HttpsError} If not admin or user doesn't exist
 */
async function validateAdmin(db, uid) {
  if (!uid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentication required."
    );
  }

  const userDoc = await db.collection("users").doc(uid).get();

  if (!userDoc.exists) {
    console.error(`Admin validation failed: user ${uid} not found`);
    throw new functions.https.HttpsError(
      "not-found",
      "User profile not found."
    );
  }

  const userData = userDoc.data();
  // Consider the primary role AND every role in the multi-role `roles` array.
  const effectiveRoles = rolesOf(userData);

  const validAdminRoles = ["admin", "super_admin", "task_review_admin", "kyc_admin", "payment_admin"];

  if (!effectiveRoles.some((r) => validAdminRoles.includes(r))) {
    console.error(
      `Admin validation failed: user ${uid} has roles [${effectiveRoles.join(", ")}]`
    );
    throw new functions.https.HttpsError(
      "permission-denied",
      "Access denied. Admin role required."
    );
  }

  console.log(`Admin validated: ${uid}`);
  return userData;
}

// ── Two-stage review role sets ───────────────────────────────────────────────
// Stage 1 (recording QA): task reviewers and KYC admins may pass/fail calls.
// Stage 2 (payment): KYC & Withdrawals admins release money (the former separate
// payment_admin role was merged into kyc_admin). super_admin / admin can do both.
const REVIEW_ROLES = ["admin", "super_admin", "task_review_admin", "kyc_admin"];
const PAYMENT_ROLES = ["admin", "super_admin", "kyc_admin"];

/**
 * Validates that `uid` holds one of `allowedRoles` (Firestore users.role).
 * @throws {functions.https.HttpsError} If not authorized.
 */
async function validateRole(db, uid, allowedRoles) {
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) {
    console.error(`Role validation failed: user ${uid} not found`);
    throw new functions.https.HttpsError("not-found", "User profile not found.");
  }
  const effectiveRoles = rolesOf(userDoc.data());
  if (!effectiveRoles.some((r) => allowedRoles.includes(r))) {
    console.error(`Role validation failed: user ${uid} has roles [${effectiveRoles.join(", ")}], needs one of [${allowedRoles.join(", ")}]`);
    throw new functions.https.HttpsError("permission-denied", "Access denied. You do not have permission for this action.");
  }
  return userDoc.data();
}

module.exports = { validateAdmin, validateRole, REVIEW_ROLES, PAYMENT_ROLES };
