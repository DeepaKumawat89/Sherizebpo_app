const functions = require("firebase-functions/v1");

const MANAGER_ROLES = ["admin", "super_admin", "team_leader"];

function rolesOf(user) {
    const roles = Array.isArray(user.roles) ? user.roles : [];
    return [...new Set([user.role, ...roles].filter(Boolean))];
}

async function validateActiveManager(db, uid) {
    const snapshot = await db.collection("users").doc(uid).get();
    const user = snapshot.data();
    if (!snapshot.exists || !rolesOf(user).some((role) => MANAGER_ROLES.includes(role))) {
        throw new functions.https.HttpsError("permission-denied", "Team leader access is required.");
    }
    if (user.isActive === false) {
        throw new functions.https.HttpsError("permission-denied", "This team leader account is inactive.");
    }

    const roles = rolesOf(user);
    return {
        isPlatformAdmin: roles.includes("admin") || roles.includes("super_admin"),
        roles,
        user,
    };
}

module.exports = { validateActiveManager };