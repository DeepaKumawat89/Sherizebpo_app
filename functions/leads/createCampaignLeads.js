const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const crypto = require("node:crypto");

const db = admin.firestore();
const MAX_BATCH_SIZE = 100;
const ABSOLUTE_CAMPAIGN_LEAD_LIMIT = 100000;
const ID_PATTERN = /^[A-Za-z0-9_-]{8,100}$/;

function invalid(message) {
    throw new functions.https.HttpsError("invalid-argument", message);
}

function normalizePhone(value) {
    let phone = String(value ?? "").replace(/[\s\-.()]/g, "");
    if (phone.startsWith("+")) phone = phone.slice(1);
    if (phone.startsWith("91") && phone.length === 12) phone = phone.slice(2);
    if (phone.startsWith("0") && phone.length === 11) phone = phone.slice(1);
    return /^\d{10}$/.test(phone) && /^[6-9]/.test(phone) ? phone : "";
}

function cleanText(value, field, max, required = false) {
    if (value == null && !required) return "";
    if (typeof value !== "string") invalid(`${field} must be a string.`);
    const result = value.trim();
    if (required && !result) invalid(`${field} is required.`);
    if (result.length > max) invalid(`${field} must be ${max} characters or fewer.`);
    return result;
}

function normalizeLead(value, index) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        invalid(`leads[${index}] must be an object.`);
    }
    const allowed = ["name", "phone", "email", "city"];
    const extra = Object.keys(value).filter((key) => !allowed.includes(key));
    if (extra.length) invalid(`leads[${index}] contains unsupported fields.`);

    const name = cleanText(value.name, `leads[${index}].name`, 120, true);
    const phone = normalizePhone(value.phone);
    if (!phone) invalid(`leads[${index}].phone must be a valid 10-digit Indian mobile number.`);
    const email = cleanText(value.email, `leads[${index}].email`, 254).toLowerCase();
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        invalid(`leads[${index}].email is invalid.`);
    }
    return {
        name,
        phone,
        email,
        city: cleanText(value.city, `leads[${index}].city`, 120),
    };
}

function sha256(value) {
    return crypto.createHash("sha256").update(value).digest("hex");
}

function safeCount(value) {
    const count = Number(value);
    return Number.isSafeInteger(count) && count >= 0 ? count : 0;
}

function campaignCapacity(campaign) {
    const limits = [ABSOLUTE_CAMPAIGN_LEAD_LIMIT];
    for (const key of ["leadLimit", "maxLeads", "leadQuota"]) {
        const value = Number(campaign[key]);
        if (Number.isSafeInteger(value) && value >= 0) limits.push(value);
    }

    const budget = Number(campaign.budget);
    const price = Number(campaign.clientPricePerLead) > 0
        ? Number(campaign.clientPricePerLead)
        : Number(campaign.payout);
    if (Number.isFinite(budget) && budget > 0 && Number.isFinite(price) && price > 0) {
        limits.push(Math.floor(budget / price));
    }
    return Math.min(...limits);
}

const createCampaignLeads = functions
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "You must be logged in.");
        }
        if (!data || typeof data !== "object" || Array.isArray(data)) invalid("Request must be an object.");
        const allowedRequestFields = ["campaignId", "uploadId", "batchKey", "isFinalBatch", "leads"];
        if (Object.keys(data).some((key) => !allowedRequestFields.includes(key))) {
            invalid("Request contains unsupported fields.");
        }

        const uid = context.auth.uid;
        const campaignId = cleanText(data.campaignId, "campaignId", 150, true);
        const uploadId = cleanText(data.uploadId, "uploadId", 100, true);
        const batchKey = cleanText(data.batchKey, "batchKey", 100, true);
        if (!ID_PATTERN.test(uploadId) || !ID_PATTERN.test(batchKey)) {
            invalid("uploadId and batchKey must be 8-100 characters using letters, numbers, underscores, or hyphens.");
        }
        if (typeof data.isFinalBatch !== "boolean") invalid("isFinalBatch must be a boolean.");
        if (!Array.isArray(data.leads) || data.leads.length < 1 || data.leads.length > MAX_BATCH_SIZE) {
            invalid(`leads must contain 1-${MAX_BATCH_SIZE} rows.`);
        }

        const normalized = data.leads.map(normalizeLead);
        const uniqueByPhone = new Map();
        for (const lead of normalized) {
            if (!uniqueByPhone.has(lead.phone)) uniqueByPhone.set(lead.phone, lead);
        }
        const leads = [...uniqueByPhone.values()];
        const withinBatchDuplicates = normalized.length - leads.length;
        const fingerprint = sha256(JSON.stringify(leads));
        const batchReceiptId = sha256(`${uid}|${campaignId}|${uploadId}|${batchKey}`);
        const uploadDocumentId = sha256(`${uid}|${campaignId}|${uploadId}`);

        // Reconcile legacy/random-ID leads into the transaction's authoritative
        // starting count. Concurrent uploads are serialized by the campaign write.
        const countSnapshot = await db.collection("campaign_leads")
            .where("campaignId", "==", campaignId)
            .count()
            .get();
        const liveCount = safeCount(countSnapshot.data().count);

        const clientRef = db.collection("clients").doc(uid);
        const campaignRef = db.collection("campaigns").doc(campaignId);
        const receiptRef = db.collection("campaign_lead_batches").doc(batchReceiptId);
        const uploadRef = db.collection("lead_uploads").doc(uploadDocumentId);
        const leadRefs = leads.map((lead) => db.collection("campaign_leads")
            .doc(sha256(`${campaignId}|${lead.phone}`)));

        return db.runTransaction(async (transaction) => {
            const snapshots = await Promise.all([
                transaction.get(clientRef),
                transaction.get(campaignRef),
                transaction.get(receiptRef),
                transaction.get(uploadRef),
                ...leadRefs.map((ref) => transaction.get(ref)),
            ]);
            const [clientSnapshot, campaignSnapshot, receiptSnapshot, uploadSnapshot, ...leadSnapshots] = snapshots;

            if (receiptSnapshot.exists) {
                const receipt = receiptSnapshot.data();
                if (receipt.fingerprint !== fingerprint) {
                    throw new functions.https.HttpsError(
                        "already-exists",
                        "This batch key was already used with different lead data."
                    );
                }
                return receipt.response;
            }
            if (!clientSnapshot.exists) {
                throw new functions.https.HttpsError("failed-precondition", "Client profile not found.");
            }
            const client = clientSnapshot.data();
            if (client.kycStatus !== "approved" || client.accountActive !== true) {
                throw new functions.https.HttpsError(
                    "permission-denied",
                    "Your client account must be approved and active before uploading leads."
                );
            }
            if (!campaignSnapshot.exists) {
                throw new functions.https.HttpsError("not-found", "Campaign not found.");
            }
            const campaign = campaignSnapshot.data();
            if (campaign.clientId !== uid) {
                throw new functions.https.HttpsError("permission-denied", "You can only upload leads to your own campaign.");
            }
            if (!["active", "paused"].includes(campaign.status)) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Leads can only be uploaded to an active or paused campaign."
                );
            }

            const newLeads = leads.filter((lead, index) => !leadSnapshots[index].exists);
            const existingCount = Math.max(
                liveCount,
                safeCount(campaign.leadCount),
                safeCount(campaign.totalLeads)
            );
            const capacity = campaignCapacity(campaign);
            if (existingCount + newLeads.length > capacity) {
                throw new functions.https.HttpsError(
                    "resource-exhausted",
                    `This campaign can accept ${Math.max(0, capacity - existingCount)} more lead(s).`
                );
            }

            const now = admin.firestore.FieldValue.serverTimestamp();
            for (const lead of newLeads) {
                const leadRef = db.collection("campaign_leads").doc(sha256(`${campaignId}|${lead.phone}`));
                transaction.create(leadRef, {
                    ...lead,
                    campaignId,
                    clientId: uid,
                    taskId: null,
                    status: "pending",
                    uploadId,
                    uploadedBy: uid,
                    createdAt: now,
                });
            }

            const totalLeads = existingCount + newLeads.length;
            transaction.update(campaignRef, {
                leadCount: totalLeads,
                totalLeads,
                lastUploadedAt: now,
                lastUploadAt: now,
            });

            const duplicatesSkipped = withinBatchDuplicates + leads.length - newLeads.length;
            const uploadStatus = {
                campaignId,
                clientId: uid,
                uploadId,
                status: data.isFinalBatch ? "completed" : "processing",
                progress: data.isFinalBatch ? 100 : 60,
                progressLabel: data.isFinalBatch ? "Complete!" : "Processing batches...",
                updatedAt: now,
            };
            if (data.isFinalBatch) uploadStatus.completedAt = now;
            if (uploadSnapshot.exists) {
                transaction.update(uploadRef, {
                    ...uploadStatus,
                    validLeads: admin.firestore.FieldValue.increment(newLeads.length),
                    duplicatesSkipped: admin.firestore.FieldValue.increment(duplicatesSkipped),
                    receivedRows: admin.firestore.FieldValue.increment(normalized.length),
                });
            } else {
                transaction.create(uploadRef, {
                    ...uploadStatus,
                    validLeads: newLeads.length,
                    duplicatesSkipped,
                    receivedRows: normalized.length,
                    startedAt: now,
                    errorsSkipped: 0,
                });
            }

            const response = {
                createdCount: newLeads.length,
                duplicatesSkipped,
                totalLeads,
                capacity,
            };
            transaction.create(receiptRef, {
                clientId: uid,
                campaignId,
                uploadId,
                batchKey,
                fingerprint,
                response,
                createdAt: now,
            });
            return response;
        });
    });

module.exports = { createCampaignLeads };
