/**
 * hireWorker — Callable Cloud Function
 *
 * Called by the Super Admin Portal to HIRE an applicant. After an offline
 * interview, the super admin issues login credentials and activates the worker.
 *
 * Two applicant kinds:
 *   1. In-app applicant (has `uid`): they registered by phone, so we simply
 *      ATTACH an email + password to their existing Auth account.
 *   2. Public applicant (no `uid`, applied via the careers web page): they have
 *      no account, so we CREATE one (email + password + worker profile).
 *
 * Either way we mark them active + KYC approved (hiring replaces KYC in the
 * closed-platform model) so the task marketplace unlocks, and mark the linked
 * job application as "hired". The worker then signs in with the issued
 * email + password and starts tasks.
 *
 * Security: only super_admin / admin.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { generateUniqueEmployeeId, idToEmail } = require("../utils/employeeId");

// Workers log in with an automatically generated Employee ID — never an email.
// Firebase Auth requires an email, so we map the ID to a stable internal
// address `<employeeId>@sherize.app`. Both hire + login normalise the ID the
// same way (lowercase, strip anything not [a-z0-9._-]) so they always match.

exports.hireWorker = functions.https.onCall(async (data, context) => {
    // ── Auth check ───────────────────────────────────────────────
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }
    const callerRole = context.auth.token.role;
    const callerRoles = context.auth.token.roles || [];
    const allowed = ["super_admin", "admin"];
    if (!allowed.includes(callerRole) && !callerRoles.some((r) => allowed.includes(r))) {
        throw new functions.https.HttpsError("permission-denied", "Only super admins can hire workers.");
    }

    // ── Input validation ─────────────────────────────────────────
    const password = data && typeof data.password === "string" ? data.password : "";
    const applicationId = data && typeof data.applicationId === "string" ? data.applicationId.trim() : "";

    if (!applicationId) {
        throw new functions.https.HttpsError("invalid-argument", "A job application is required.");
    }
    if (!password || password.length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "Password must be at least 6 characters.");
    }

    const db = admin.firestore();
    const applicationRef = db.collection("job_applications").doc(applicationId);
    const applicationSnap = await applicationRef.get();
    if (!applicationSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Job application not found.");
    }

    const application = applicationSnap.data();
    if (application.status === "hired" && application.applicantUid) {
        const hiredWorker = await db.collection("users").doc(application.applicantUid).get();
        const existingEmployeeId = hiredWorker.data()?.employeeId || hiredWorker.data()?.workerId;
        if (existingEmployeeId) {
            return { uid: application.applicantUid, employeeId: existingEmployeeId, success: true };
        }
        throw new functions.https.HttpsError("failed-precondition", "Hired worker profile has no Employee ID.");
    }
    if (!["applied", "interviewing"].includes(application.status)) {
        throw new functions.https.HttpsError("failed-precondition", "This application cannot be hired in its current status.");
    }

    const employeeId = await generateUniqueEmployeeId(db);
    if (!employeeId) {
        throw new functions.https.HttpsError("resource-exhausted", "No four-digit Employee IDs are currently available.");
    }
    const email = idToEmail(employeeId);
    const claimedApplication = await db.runTransaction(async (transaction) => {
        const currentSnap = await transaction.get(applicationRef);
        if (!currentSnap.exists) {
            throw new functions.https.HttpsError("not-found", "Job application not found.");
        }
        const current = currentSnap.data();
        if (current.status === "hiring") {
            throw new functions.https.HttpsError("aborted", "This application is already being hired.");
        }
        if (!["applied", "interviewing"].includes(current.status)) {
            throw new functions.https.HttpsError("failed-precondition", "This application cannot be hired in its current status.");
        }
        transaction.update(applicationRef, {
            status: "hiring",
            hiringEmployeeId: employeeId,
            hiringBy: context.auth.uid,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return current;
    });

    const name = String(claimedApplication.applicantName || "").trim();
    const phone = String(claimedApplication.applicantPhone || "").trim();
    const contactEmail = String(claimedApplication.applicantEmail || "").trim().toLowerCase();
    let targetUid = String(claimedApplication.applicantUid || "").trim();
    let createdPublicAccount = false;

    try {
        if (targetUid) {
            const workerRef = db.collection("users").doc(targetUid);
            const workerSnap = await workerRef.get();
            const workerData = workerSnap.data();
            if (!workerSnap.exists || String(workerData.role || "").toLowerCase() !== "worker") {
                throw new functions.https.HttpsError("failed-precondition", "The application is not linked to a worker account.");
            }

            // ── Existing in-app applicant: attach email + password ───
            try {
                await admin.auth().updateUser(targetUid, { email, password, emailVerified: true });
            } catch (err) {
                if (err.code === "auth/email-already-exists") {
                    throw new functions.https.HttpsError("already-exists", "That Employee ID is already in use. Choose a different ID.");
                }
                if (err.code === "auth/user-not-found") {
                    throw new functions.https.HttpsError("not-found", "No worker account found for this uid.");
                }
                throw new functions.https.HttpsError("internal", `Failed to set credentials: ${err.message}`);
            }
            try {
                const previousEmail = String(workerData.email || "").trim().toLowerCase();
                await workerRef.set({
                    email,
                    loginEmail: email,
                    contactEmail: contactEmail || (previousEmail.endsWith("@sherize.app") ? "" : previousEmail),
                    employeeId,
                    workerId: employeeId,
                    onboardingStatus: "active",
                    kycStatus: "approved",
                    hiredAt: admin.firestore.FieldValue.serverTimestamp(),
                    hiredBy: context.auth.uid,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            } catch (err) {
                throw new functions.https.HttpsError("internal", `Failed to activate worker: ${err.message}`);
            }
        } else {
            // ── Public applicant: create a brand-new worker account ──
            let userRecord;
            try {
                userRecord = await admin.auth().createUser({
                    email,
                    password,
                    displayName: name || undefined,
                    emailVerified: true,
                });
            } catch (err) {
                if (err.code === "auth/email-already-exists") {
                    throw new functions.https.HttpsError("already-exists", "That Employee ID is already in use. Choose a different ID.");
                }
                throw new functions.https.HttpsError("internal", `Failed to create account: ${err.message}`);
            }
            targetUid = userRecord.uid;
            createdPublicAccount = true;
            try {
                await db.collection("users").doc(targetUid).set({
                    uid: targetUid,
                    email,
                    loginEmail: email,
                    contactEmail,
                    employeeId,
                    name: name || "",
                    fullName: name || "",
                    phone: phone || "",
                    role: "worker",
                    roles: ["worker"],
                    workerId: employeeId,
                    onboardingStatus: "active",
                    kycStatus: "approved",
                    walletBalance: 0,
                    totalTasksCompleted: 0,
                    rating: 0,
                    hiredAt: admin.firestore.FieldValue.serverTimestamp(),
                    hiredBy: context.auth.uid,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            } catch (err) {
                throw new functions.https.HttpsError("internal", `Failed to create worker profile: ${err.message}`);
            }
        }

        // ── Mark the application hired + link the account ────────────
        await applicationRef.set({
            status: "hired",
            applicantUid: targetUid,
            employeeId,
            hiringEmployeeId: admin.firestore.FieldValue.delete(),
            hiringBy: admin.firestore.FieldValue.delete(),
            hiredAt: admin.firestore.FieldValue.serverTimestamp(),
            hiredBy: context.auth.uid,
        }, { merge: true });
    } catch (error) {
        if (createdPublicAccount && targetUid) {
            await Promise.all([
                admin.auth().deleteUser(targetUid).catch(() => {}),
                db.collection("users").doc(targetUid).delete().catch(() => {}),
            ]);
        }
        await db.runTransaction(async (transaction) => {
            const currentSnap = await transaction.get(applicationRef);
            const current = currentSnap.data();
            if (current?.status === "hiring" && current.hiringEmployeeId === employeeId) {
                transaction.update(applicationRef, {
                    status: claimedApplication.status,
                    hiringEmployeeId: admin.firestore.FieldValue.delete(),
                    hiringBy: admin.firestore.FieldValue.delete(),
                });
            }
        }).catch(() => {});
        throw error;
    }

    console.log(`[hireWorker] Hired ${targetUid} as ${employeeId} (${email}) by ${context.auth.uid}`);
    return { uid: targetUid, employeeId, success: true };
});
