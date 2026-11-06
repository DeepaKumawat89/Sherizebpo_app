/**
 * submitPublicApplication — Callable Cloud Function
 *
 * Public (no-login) job application endpoint used by the careers web page.
 * Anyone can call it — there is no auth requirement — so we validate strictly
 * and de-duplicate by phone+job. Writes to `job_applications` with
 * source='public' and NO applicantUid (the applicant has no account yet; one is
 * created by the super admin at hire time via hireWorker).
 *
 * Called from the web:
 *   httpsCallable(functions, 'submitPublicApplication')({ jobId, jobTitle,
 *     name, phone, email })
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

exports.submitPublicApplication = functions
    .runWith({ timeoutSeconds: 20, memory: "128MB" })
    .https.onCall(async (data) => {
        const jobId = data && typeof data.jobId === "string" ? data.jobId.trim() : "";
        const jobTitle = data && typeof data.jobTitle === "string" ? data.jobTitle.trim() : "";
        const name = data && typeof data.name === "string" ? data.name.trim() : "";
        const email = data && typeof data.email === "string" ? data.email.trim().toLowerCase() : "";
        const phoneRaw = data && typeof data.phone === "string" ? data.phone : "";
        const phone = String(phoneRaw).replace(/[^0-9]/g, "").replace(/^0+/, "").replace(/^91(?=\d{10}$)/, "");

        // ── Validation ───────────────────────────────────────────
        if (!jobId) throw new functions.https.HttpsError("invalid-argument", "Job is required.");
        if (name.length < 2) throw new functions.https.HttpsError("invalid-argument", "Enter your full name.");
        if (!/^[6-9]\d{9}$/.test(phone)) {
            throw new functions.https.HttpsError("invalid-argument", "Enter a valid 10-digit mobile number.");
        }
        if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            throw new functions.https.HttpsError("invalid-argument", "Enter a valid email address.");
        }

        const db = admin.firestore();

        // Confirm the opening exists and is open (avoid applications to closed/fake jobs).
        const jobSnap = await db.collection("job_postings").doc(jobId).get();
        if (!jobSnap.exists || jobSnap.data().status !== "open") {
            throw new functions.https.HttpsError("failed-precondition", "This opening is no longer accepting applications.");
        }

        // De-duplicate: one application per phone per job.
        const dup = await db.collection("job_applications")
            .where("jobId", "==", jobId)
            .where("applicantPhone", "==", phone)
            .limit(1)
            .get();
        if (!dup.empty) {
            throw new functions.https.HttpsError("already-exists", "You've already applied to this opening.");
        }

        const ref = await db.collection("job_applications").add({
            jobId,
            jobTitle: jobTitle || jobSnap.data().title || "",
            applicantName: name,
            applicantPhone: phone,
            applicantEmail: email,
            applicantUid: null,      // public applicant — account created at hire time
            source: "public",
            status: "applied",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return { id: ref.id, success: true };
    });
