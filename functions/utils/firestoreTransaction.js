/**
 * firestoreTransaction.js
 *
 * Shared Firestore transaction helpers for safe, atomic operations
 * across earnings, submissions, and withdrawals.
 */

const admin = require("firebase-admin");

/**
 * Runs a Firestore transaction with retry logic and structured logging.
 *
 * @param {FirebaseFirestore.Firestore} db - Firestore instance
 * @param {string} operationName - Human-readable name for logging
 * @param {Function} transactionFn - Async function receiving the transaction object
 * @returns {Promise<*>} Result of the transaction function
 */
async function runTransaction(db, operationName, transactionFn) {
    console.log(`[Transaction] Starting: ${operationName}`);
    const startTime = Date.now();

    try {
        const result = await db.runTransaction(transactionFn);
        const duration = Date.now() - startTime;
        console.log(
            `[Transaction] Completed: ${operationName} (${duration}ms)`
        );
        return result;
    } catch (error) {
        const duration = Date.now() - startTime;
        console.error(
            `[Transaction] Failed: ${operationName} (${duration}ms)`,
            error.message
        );
        throw error;
    }
}

/**
 * Returns a Firestore server timestamp.
 * @returns {FieldValue}
 */
function serverTimestamp() {
    return admin.firestore.FieldValue.serverTimestamp();
}

/**
 * Returns a Firestore increment value.
 * @param {number} value
 * @returns {FieldValue}
 */
function increment(value) {
    return admin.firestore.FieldValue.increment(value);
}

module.exports = { runTransaction, serverTimestamp, increment };
