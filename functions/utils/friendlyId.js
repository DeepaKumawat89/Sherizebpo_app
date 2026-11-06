/**
 * friendlyId.js
 *
 * Shared helper for human-friendly, prefixed short IDs (e.g. TSK-1234,
 * ADM-1234, PAY-1234). These are surfaced in the UI instead of raw Firestore
 * document IDs, mirroring the employee (SHR-XXXX) and campaign (CMP-XXXX) codes.
 *
 * `generateUniqueFriendlyId` verifies uniqueness against an existing collection
 * with bounded retries, then widens the digit-width if the small space is
 * crowded — the same strategy used by campaigns/createCampaign.js.
 */
const admin = require("firebase-admin");

// Random `PREFIX-<width digits>` code (no uniqueness guarantee).
function generateFriendlyId(prefix, width = 4) {
    const min = Math.pow(10, width - 1);
    return `${prefix}-${Math.floor(min + Math.random() * (min * 9))}`;
}

/**
 * Generate a `prefix`-XXXX code that is not already present in
 * `collection`.`field`. Falls back to 6 digits if the 4-digit space is crowded.
 *
 * ponytail: bounded retries then a widened fallback — good enough until a single
 * entity type exceeds a few thousand rows, at which point bump the default width.
 */
async function generateUniqueFriendlyId(prefix, { collection, field }, db) {
    const firestore = db || admin.firestore();
    for (let i = 0; i < 8; i++) {
        const code = generateFriendlyId(prefix, 4);
        const dup = await firestore.collection(collection).where(field, "==", code).limit(1).get();
        if (dup.empty) return code;
    }
    for (;;) {
        const code = generateFriendlyId(prefix, 6);
        const dup = await firestore.collection(collection).where(field, "==", code).limit(1).get();
        if (dup.empty) return code;
    }
}

module.exports = { generateFriendlyId, generateUniqueFriendlyId };
