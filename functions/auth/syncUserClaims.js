const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

exports.syncUserClaims = functions.firestore
    .document("users/{uid}")
    .onWrite(async (change, context) => {
        const uid = context.params.uid;

        // Document was deleted
        if (!change.after.exists) {
            console.log(`User ${uid} deleted. Removing custom claims.`);
            try {
                await admin.auth().setCustomUserClaims(uid, null);
            } catch (error) {
                console.error(`Failed to remove claims for deleted user ${uid}:`, error);
            }
            return;
        }

        const dataAfter = change.after.data();

        const roleAfter = dataAfter.role || null;

        // Normalise the roles array (multi-role support). Falls back to the
        // single primary role so single-role admins always have a roles claim.
        const rolesAfter = Array.isArray(dataAfter.roles) && dataAfter.roles.length
            ? dataAfter.roles
            : (roleAfter ? [roleAfter] : []);

        try {
            // Reconcile against the ACTUAL current claims (not just the doc diff)
            // so re-saving an admin repairs stale claims left by older versions.
            const userRecord = await admin.auth().getUser(uid);
            const currentClaims = userRecord.customClaims || {};

            const claimRole = currentClaims.role || null;
            const claimRoles = Array.isArray(currentClaims.roles) ? currentClaims.roles : [];

            const roleChanged = claimRole !== roleAfter;
            const rolesChanged = JSON.stringify(claimRoles) !== JSON.stringify(rolesAfter);

            if (!roleChanged && !rolesChanged) {
                return; // Claims already up to date — nothing to do.
            }

            const newClaims = {
                ...currentClaims,
                role: roleAfter,
                roles: rolesAfter,
            };

            await admin.auth().setCustomUserClaims(uid, newClaims);
            console.log(`Synced claims for ${uid}. role: ${roleAfter}, roles: ${JSON.stringify(rolesAfter)}`);
        } catch (error) {
            console.error(`Error syncing role claims for ${uid}:`, error);
        }
    });
