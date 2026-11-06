const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { generateUniqueEmployeeId, idToEmail } = require("../utils/employeeId");
const { validateActiveManager } = require("../utils/teamLeaderAccess");

exports.createEmployeeAccount = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }
    const fullName = String(data?.fullName || "").trim();
    const password = typeof data?.password === "string" ? data.password : "";
    const contactEmail = String(data?.contactEmail || "").trim().toLowerCase();
    const phone = String(data?.phone || "").trim();

    if (!fullName) {
        throw new functions.https.HttpsError("invalid-argument", "Employee name is required.");
    }
    if (password.length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "Password must be at least 6 characters.");
    }

    const db = admin.firestore();
    await validateActiveManager(db, context.auth.uid);

    const employeeId = await generateUniqueEmployeeId(db);
    if (!employeeId) {
        throw new functions.https.HttpsError("resource-exhausted", "No Employee IDs are currently available.");
    }

    const loginEmail = idToEmail(employeeId);
    let userRecord;
    try {
        userRecord = await admin.auth().createUser({
            email: loginEmail,
            password,
            displayName: fullName,
            emailVerified: true,
        });
        await admin.auth().setCustomUserClaims(userRecord.uid, { role: "worker", roles: ["worker"] });
        await db.collection("users").doc(userRecord.uid).set({
            uid: userRecord.uid,
            name: fullName,
            fullName,
            email: loginEmail,
            loginEmail,
            contactEmail,
            phone,
            employeeId,
            workerId: employeeId,
            role: "worker",
            roles: ["worker"],
            onboardingStatus: "active",
            kycStatus: "approved",
            isActive: true,
            walletBalance: 0,
            totalTasksCompleted: 0,
            rating: 0,
            teamLeaderId: context.auth.uid,
            createdBy: context.auth.uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (error) {
        if (userRecord?.uid) {
            await admin.auth().deleteUser(userRecord.uid).catch(() => {});
        }
        throw new functions.https.HttpsError("internal", `Failed to create employee: ${error.message}`);
    }

    return { uid: userRecord.uid, employeeId, success: true };
});