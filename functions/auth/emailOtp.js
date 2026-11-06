const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const cors = require("cors")({ origin: true });
const crypto = require("crypto");

// ─── Setup Nodemailer Transporter ─────────────────────────────
// Credentials come from function-scoped Secret Manager values
// (SMTP_EMAIL / SMTP_PASSWORD).
// Gmail App Passwords are shown by Google as four space-separated groups
// (e.g. "abcd efgh ijkl mnop"). Those display spaces are NOT part of the
// password — leaving them in causes "535-5.7.8 Username and Password not
// accepted". Strip all whitespace so a pasted-with-spaces app password still
// authenticates.
const SMTP_EMAIL = (process.env.SMTP_EMAIL || "").trim();
const SMTP_PASSWORD = (process.env.SMTP_PASSWORD || "").replace(/\s+/g, "");

const mailTransport = nodemailer.createTransport({
    service: "gmail",
    auth: {
        user: SMTP_EMAIL,
        pass: SMTP_PASSWORD,
    },
});

// A helper function to generate a 6-digit number string
function generateOTP() {
    return Math.floor(100000 + Math.random() * 900000).toString();
}

// ═══════════════════════════════════════════════════════════════
// CALLABLE: sendEmailOtp
// ───────────────────────────────────────────────────────────────
exports.sendEmailOtp = functions
    .runWith({ secrets: ["SMTP_EMAIL", "SMTP_PASSWORD"] })
    .https.onCall(async (data, context) => {
        try {
            if (!context.auth) {
                throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
            }

        const uid = context.auth.uid;
        const email = (data.email || "").trim().toLowerCase();

        if (!email || !/^[\w.-]+@([\w-]+\.)+[\w-]{2,4}$/.test(email)) {
            throw new functions.https.HttpsError("invalid-argument", "Valid email required.");
        }

        if (!SMTP_EMAIL || !SMTP_PASSWORD) {
            console.error("sendEmailOtp configuration error: SMTP secrets are unavailable.");
            throw new functions.https.HttpsError(
                "internal",
                "Couldn't send the verification email right now. Please try again in a moment."
            );
        }

        try {
            // Check if the email is already in use by another user
            try {
                const existingUser = await admin.auth().getUserByEmail(email);
                if (existingUser.uid !== uid) {
                    throw new functions.https.HttpsError(
                        "already-exists",
                        "This email is already registered to another phone number. Please use a different email."
                    );
                }
            } catch (error) {
                if (error.code !== "auth/user-not-found") {
                    throw error;
                }
            }

            const otp = generateOTP();
            const otpHash = crypto.createHash("sha256").update(otp).digest("hex");
            const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

            await admin.firestore().collection("email_otps").doc(email).set({
                otpHash: otpHash,
                attempts: 0,
                uid: uid,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                expiresAt: expiresAt,
            });

            const mailOptions = {
                from: `"Human BPO" <${SMTP_EMAIL}>`,
                to: email,
                subject: "Your Email Verification Code",
                html: `
                    <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
                        <h2 style="color: #4F46E5;">Email Verification</h2>
                        <p>Hello,</p>
                        <p>Use the following 6-digit code to verify your email address on Human BPO. This code expires in 5 minutes.</p>
                        <div style="background-color: #F3F4F6; padding: 15px; border-radius: 8px; text-align: center; margin: 20px 0;">
                            <h1 style="letter-spacing: 5px; margin: 0; color: #111827;">${otp}</h1>
                        </div>
                        <p>If you didn't request this code, you can safely ignore this email.</p>
                    </div>
                `,
            };

            await mailTransport.sendMail(mailOptions);
            console.log("sendEmailOtp: OTP email accepted by the provider.");

            return { success: true };
        } catch (err) {
            console.error("sendEmailOtp provider error:", {
                code: err?.code,
                responseCode: err?.responseCode,
                command: err?.command,
            });
            if (err instanceof functions.https.HttpsError) throw err;
            if (err?.code === "EAUTH" || err?.responseCode === 535) {
                console.error("sendEmailOtp configuration error: SMTP authentication was rejected.");
            }
            // Never surface raw SMTP/internal errors (e.g. "Invalid login: 535 …")
            // to the app — they are logged above; the user sees a friendly message.
            throw new functions.https.HttpsError("internal", "Couldn't send the verification email right now. Please try again in a moment.");
        }
        } catch (externalErr) {
            console.error("sendEmailOtp request failed:", { code: externalErr?.code });
            if (externalErr instanceof functions.https.HttpsError) throw externalErr;
            throw new functions.https.HttpsError("internal", "Internal server error");
        }
    });

// ═══════════════════════════════════════════════════════════════
// CALLABLE: verifyEmailOtp
// ───────────────────────────────────────────────────────────────
exports.verifyEmailOtp = functions.https.onCall(async (data, context) => {
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
        }

        const uid = context.auth.uid;
        const otp = (data.otp || "").trim();
        const email = (data.email || "").trim().toLowerCase();

        if (!otp || otp.length !== 6) {
            throw new functions.https.HttpsError("invalid-argument", "Valid 6-digit OTP required.");
        }

        if (!email) {
            throw new functions.https.HttpsError("invalid-argument", "Email address is required.");
        }

        try {
            console.log(`verifyEmailOtp: Verifying OTP for uid ${uid} with email ${email}`);

            const docRef = admin.firestore().collection("email_otps").doc(email);
            const docSnap = await docRef.get();

            if (!docSnap.exists) {
                throw new functions.https.HttpsError("not-found", "Invalid or expired OTP.");
            }

            const otpData = docSnap.data();

            const now = new Date();
            const expiresAt = otpData.expiresAt.toDate();
            if (now > expiresAt) {
                await docRef.delete();
                throw new functions.https.HttpsError("failed-precondition", "OTP has expired.");
            }

            if (otpData.attempts >= 5) {
                await docRef.delete();
                throw new functions.https.HttpsError("resource-exhausted", "Too many incorrect attempts. Please request a new OTP.");
            }

            const inputHash = crypto.createHash("sha256").update(otp).digest("hex");

            if (otpData.otpHash !== inputHash) {
                await docRef.update({
                    attempts: admin.firestore.FieldValue.increment(1)
                });
                throw new functions.https.HttpsError("invalid-argument", "Incorrect OTP. Please try again.");
            }

            if (otpData.uid !== uid) {
                throw new functions.https.HttpsError("permission-denied", "OTP mismatch.");
            }

            try {
                await admin.auth().updateUser(uid, { email: email, emailVerified: true });
            } catch (error) {
                if (error.code === "auth/email-already-exists") {
                    throw new functions.https.HttpsError(
                        "already-exists",
                        "This email is already registered to another phone number. Please use a different email."
                    );
                }
                throw error;
            }
            
            await admin.firestore().collection("users").doc(uid).set(
                {
                    email: email,
                    emailVerified: true,
                    emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true }
            );

            await docRef.delete();

            console.log(`verifyEmailOtp: Successfully verified user ${uid}`);
            return { success: true };
        } catch (err) {
            console.error("verifyEmailOtp error:", err);
            if (err instanceof functions.https.HttpsError) throw err;
            throw new functions.https.HttpsError("internal", err.message || "Verification failed.");
        }
    } catch (externalErr) {
        console.error("verifyEmailOtp external error:", externalErr);
        if (externalErr instanceof functions.https.HttpsError) throw externalErr;
        throw new functions.https.HttpsError("internal", "Internal server error");
    }
});

