const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const crypto = require("crypto");
const { EMPLOYEE_LOGIN_DOMAIN, employeeIdCandidates } = require("../utils/employeeId");

const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000;
const MAX_RESOLVES_PER_WINDOW = 20;

async function enforceRateLimit(db, context) {
    const forwardedFor = String(context.rawRequest?.headers?.["x-forwarded-for"] || "").split(",")[0].trim();
    const clientAddress = forwardedFor || context.rawRequest?.ip || "unknown";
    const addressHash = crypto.createHash("sha256").update(clientAddress).digest("hex");
    const ref = db.collection("rate_limits").doc(`employee_login_${addressHash}`);
    let allowed = false;

    await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        const now = Date.now();
        const attempts = snapshot.exists
            ? (snapshot.data().attempts || []).filter((time) => now - time < RATE_LIMIT_WINDOW_MS)
            : [];
        if (attempts.length < MAX_RESOLVES_PER_WINDOW) {
            attempts.push(now);
            transaction.set(ref, { attempts }, { merge: true });
            allowed = true;
        }
    });

    if (!allowed) {
        throw new functions.https.HttpsError("resource-exhausted", "Too many login attempts. Try again later.");
    }
}

exports.resolveEmployeeLogin = functions.https.onCall(async (data, context) => {
    const candidates = employeeIdCandidates(data && data.employeeId);
    if (candidates.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "Enter a valid Employee ID.");
    }

    const db = admin.firestore();
    await enforceRateLimit(db, context);
    for (const field of ["employeeId", "workerId"]) {
        for (const candidate of candidates) {
            const snapshot = await db.collection("users").where(field, "==", candidate).limit(10).get();
            if (snapshot.empty) continue;

            for (const document of snapshot.docs) {
                const user = document.data();
                const loginEmail = String(user.loginEmail || user.email || "").trim().toLowerCase();
                if (loginEmail.endsWith(`@${EMPLOYEE_LOGIN_DOMAIN}`)) {
                    return { loginEmail };
                }
            }
        }
    }

    return { loginEmail: `${candidates[0].toLowerCase()}@${EMPLOYEE_LOGIN_DOMAIN}` };
});