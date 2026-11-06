const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { validateActiveManager } = require("../utils/teamLeaderAccess");

const db = admin.firestore();
const MAX_LEADS = 200;
const MAX_SUBTASK_LEADS = 450;
const MAX_SUBTASKS = 49;
const MAX_STATUS_TASKS = 499;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{8,100}$/;

function invalid(message) {
    throw new functions.https.HttpsError("invalid-argument", message);
}

function requireObject(value, name) {
    if (!value || typeof value !== "object" || Array.isArray(value)) invalid(`${name} must be an object.`);
    return value;
}

function allowOnly(value, allowed, name) {
    const extra = Object.keys(value).filter((key) => !allowed.includes(key));
    if (extra.length) invalid(`${name} contains unsupported fields: ${extra.join(", ")}.`);
}

function text(value, name, { required = false, max = 500 } = {}) {
    if (value == null && !required) return "";
    if (typeof value !== "string") invalid(`${name} must be a string.`);
    const result = value.trim();
    if (required && !result) invalid(`${name} is required.`);
    if (result.length > max) invalid(`${name} must be ${max} characters or fewer.`);
    return result;
}

function positiveNumber(value, name) {
    if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
        invalid(`${name} must be a positive number.`);
    }
    return value;
}

function positiveInteger(value, name, max = Number.MAX_SAFE_INTEGER) {
    if (!Number.isInteger(value) || value <= 0 || value > max) {
        invalid(`${name} must be an integer from 1 to ${max}.`);
    }
    return value;
}

function requestId(value) {
    if (typeof value !== "string" || !REQUEST_ID_PATTERN.test(value)) {
        invalid("requestId must be 8-100 characters using letters, numbers, underscores, or hyphens.");
    }
    return value;
}

function campaignDate(value, name) {
    if (value == null || value === "") return "";
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        invalid(`${name} must be a valid date (YYYY-MM-DD) or empty.`);
    }
    const parsed = new Date(`${value}T00:00:00Z`);
    if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
        invalid(`${name} must be a valid date (YYYY-MM-DD) or empty.`);
    }
    return value;
}

function campaignStatus(value) {
    const status = value == null ? "active" : text(value, "campaign.status", { required: true, max: 20 });
    if (!["active", "paused"].includes(status)) invalid("campaign.status must be active or paused.");
    return status;
}

function optionalDeadline(value) {
    if (value == null || value === "") return null;
    if (typeof value !== "string") invalid("campaign.deadline must be an ISO date string.");
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) invalid("campaign.deadline must be a valid ISO date string.");
    return admin.firestore.Timestamp.fromDate(date);
}

function code(prefix, ref) {
    return `${prefix}-${ref.id.slice(0, 8).toUpperCase()}`;
}

function validateCreateCampaign(data, paymentsVisible = true) {
    allowOnly(data, ["action", "campaign"], "request");
    const campaign = requireObject(data.campaign, "campaign");
    allowOnly(campaign, ["title", "description", "clientName", "payout", "status", "startDate", "endDate", "slots", "tatHours", "deadline"], "campaign");
    const startDate = campaignDate(campaign.startDate, "campaign.startDate");
    const endDate = campaignDate(campaign.endDate, "campaign.endDate");
    if (startDate && endDate && endDate < startDate) invalid("campaign.endDate cannot be before campaign.startDate.");
    return {
        title: text(campaign.title, "campaign.title", { required: true, max: 120 }),
        description: text(campaign.description, "campaign.description", { max: 2000 }),
        clientName: text(campaign.clientName, "campaign.clientName", { required: true, max: 120 }),
        payout: paymentsVisible ? positiveNumber(campaign.payout, "campaign.payout") : 0,
        unpriced: !paymentsVisible,
        status: campaignStatus(campaign.status),
        startDate,
        endDate,
        slots: campaign.slots == null ? 1 : positiveInteger(campaign.slots, "campaign.slots", 1000),
        tatHours: campaign.tatHours == null ? 24 : positiveNumber(campaign.tatHours, "campaign.tatHours"),
        deadline: optionalDeadline(campaign.deadline),
    };
}

function validateCampaignClientLookup(data) {
    allowOnly(data, ["action", "campaignIds"], "request");
    if (!Array.isArray(data.campaignIds) || data.campaignIds.length < 1 || data.campaignIds.length > 100) {
        invalid("campaignIds must contain 1-100 campaign IDs.");
    }
    const campaignIds = [...new Set(data.campaignIds.map((value, index) =>
        text(value, `campaignIds[${index}]`, { required: true, max: 150 }))
    )];
    return { campaignIds };
}

function clientSummary(client = {}) {
    const kyc = client.kycData && typeof client.kycData === "object" ? client.kycData : {};
    const legacyName = String(kyc.legalName || "").trim().split(/\s+/).filter(Boolean);
    const firstName = String(kyc.firstName || client.firstName || legacyName[0] || "").trim();
    const lastName = String(kyc.lastName || client.lastName || legacyName.slice(1).join(" ") || "").trim();
    const contactName = `${firstName} ${lastName}`.trim();
    const accountType = String(client.accountType || "").toLowerCase();
    const companyName = String(kyc.companyLegalName || client.companyName || "").trim();
    const email = String(client.email || kyc.email || "").trim();
    return {
        name: accountType === "individual" ? (contactName || email || "Unnamed Client")
            : (companyName || contactName || email || "Unnamed Client"),
        email,
    };
}

async function getCampaignClients(input) {
    const campaignRefs = input.campaignIds.map((id) => db.collection("campaigns").doc(id));
    const campaignSnapshots = await db.getAll(...campaignRefs);
    const clientIds = [...new Set(campaignSnapshots
        .map((snapshot) => snapshot.exists ? snapshot.data().clientId : "")
        .filter(Boolean))];
    const clientSnapshots = clientIds.length
        ? await db.getAll(...clientIds.map((id) => db.collection("clients").doc(id)))
        : [];
    const clientsById = new Map(clientSnapshots
        .filter((snapshot) => snapshot.exists)
        .map((snapshot) => [snapshot.id, clientSummary(snapshot.data())]));
    const clients = {};
    const campaignUpdates = db.batch();
    let updateCount = 0;

    for (const campaignSnapshot of campaignSnapshots) {
        if (!campaignSnapshot.exists) continue;
        const campaign = campaignSnapshot.data();
        const resolved = clientsById.get(campaign.clientId);
        clients[campaignSnapshot.id] = resolved || {
            name: String(campaign.clientName || "").trim() || "Client not assigned",
            email: String(campaign.clientEmail || "").trim(),
        };
        if (resolved && (campaign.clientName !== resolved.name || campaign.clientEmail !== resolved.email)) {
            campaignUpdates.update(campaignSnapshot.ref, {
                clientName: resolved.name,
                clientEmail: resolved.email,
                clientDetailsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            updateCount++;
        }
    }
    if (updateCount) await campaignUpdates.commit();
    return { clients };
}

function validateLead(value, index) {
    const lead = requireObject(value, `leads[${index}]`);
    allowOnly(lead, ["name", "phone", "email", "notes"], `leads[${index}]`);
    const phone = text(lead.phone, `leads[${index}].phone`, { required: true, max: 30 }).replace(/\D/g, "");
    if (phone.length < 10 || phone.length > 15) invalid(`leads[${index}].phone must contain 10-15 digits.`);
    const email = text(lead.email, `leads[${index}].email`, { max: 254 });
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) invalid(`leads[${index}].email is invalid.`);
    return {
        name: text(lead.name, `leads[${index}].name`, { max: 120 }) || "Unknown",
        phone,
        email,
        notes: text(lead.notes, `leads[${index}].notes`, { max: 1000 }),
    };
}

function validateImport(data) {
    allowOnly(data, ["action", "campaignId", "leads", "requestId"], "request");
    const campaignId = text(data.campaignId, "campaignId", { required: true, max: 150 });
    if (!Array.isArray(data.leads) || data.leads.length < 1 || data.leads.length > MAX_LEADS) {
        invalid(`leads must contain 1-${MAX_LEADS} rows.`);
    }
    return { campaignId, leads: data.leads.map(validateLead), requestId: requestId(data.requestId) };
}

function validateSubtask(data) {
    allowOnly(data, ["action", "campaignId", "title", "description", "leadCount", "payout", "tatHours", "requestId"], "request");
    return {
        campaignId: text(data.campaignId, "campaignId", { required: true, max: 150 }),
        title: text(data.title, "title", { required: true, max: 120 }),
        description: data.description == null ? null : text(data.description, "description", { max: 2000 }),
        leadCount: positiveInteger(data.leadCount, "leadCount", MAX_LEADS),
        payout: data.payout == null ? null : positiveNumber(data.payout, "payout"),
        tatHours: data.tatHours == null ? null : positiveNumber(data.tatHours, "tatHours"),
        requestId: requestId(data.requestId),
    };
}

function validateTaskImport(data) {
    allowOnly(data, ["action", "campaignId", "leads", "requestId", "taskRequestId"], "request");
    const imported = validateImport({
        action: "importLeads",
        campaignId: data.campaignId,
        leads: data.leads,
        requestId: data.requestId,
    });
    return { ...imported, taskRequestId: requestId(data.taskRequestId) };
}

function validateCreateSubtasks(data) {
    allowOnly(data, ["action", "campaignId", "subtasksCount", "tatHours", "requestId"], "request");
    return {
        campaignId: text(data.campaignId, "campaignId", { required: true, max: 150 }),
        subtasksCount: positiveInteger(data.subtasksCount, "subtasksCount", MAX_SUBTASKS),
        tatHours: positiveNumber(data.tatHours, "tatHours"),
        requestId: requestId(data.requestId),
    };
}

function validateSetStatus(data) {
    allowOnly(data, ["action", "campaignId", "status"], "request");
    const status = text(data.status, "status", { required: true, max: 20 });
    if (!["active", "paused"].includes(status)) invalid("status must be active or paused.");
    return {
        campaignId: text(data.campaignId, "campaignId", { required: true, max: 150 }),
        status,
    };
}

async function requireCampaign(transaction, campaignId, allowedStatuses = ["active"]) {
    const ref = db.collection("campaigns").doc(campaignId);
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Campaign not found.");
    if (!allowedStatuses.includes(snapshot.data().status)) {
        throw new functions.https.HttpsError("failed-precondition", `Campaign status must be ${allowedStatuses.join(" or ")}.`);
    }
    return { ref, campaign: snapshot.data() };
}

function receiptRef(uid, requestIdValue) {
    return db.collection("team_campaign_requests").doc(`${uid}_${requestIdValue}`);
}

function taskUploadRef(uid, taskRequestId) {
    return db.collection("team_campaign_task_uploads").doc(`${uid}_${taskRequestId}`);
}

async function withIdempotency(uid, action, requestIdValue, work, binding = null) {
    return db.runTransaction(async (transaction) => {
        const ref = receiptRef(uid, requestIdValue);
        const snapshot = await transaction.get(ref);
        if (snapshot.exists) {
            const receipt = snapshot.data();
            if (receipt.action !== action) {
                throw new functions.https.HttpsError("already-exists", "requestId was already used for another action.");
            }
            if (binding && JSON.stringify(receipt.binding) !== JSON.stringify(binding)) {
                throw new functions.https.HttpsError("already-exists", "requestId was already used with different request data.");
            }
            return receipt.response;
        }
        const response = await work(transaction);
        transaction.create(ref, {
            action,
            ...(binding ? { binding } : {}),
            response,
            createdBy: uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return response;
    });
}

async function createCampaign(uid, campaign) {
    const ref = db.collection("campaigns").doc();
    const campaignCode = code("CMP", ref);
    await ref.create({
        name: campaign.title,
        title: campaign.title,
        description: campaign.description,
        clientName: campaign.clientName,
        payout: campaign.payout,
        unpriced: campaign.unpriced,
        slots: campaign.slots,
        totalSlots: campaign.slots,
        tatHours: campaign.tatHours,
        deadline: campaign.deadline,
        campaignCode,
        status: campaign.status,
        startDate: campaign.startDate,
        endDate: campaign.endDate,
        leadCount: 0,
        createdBy: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { campaignId: ref.id, campaignCode };
}

function taskFields(uid, campaignId, campaign, taskRef, taskCode, totalLeads, tatHours) {
    return {
        title: campaign.name || campaign.title || "Untitled Task",
        clientName: campaign.clientName || "Sherize Direct",
        campaignId,
        taskCode,
        description: campaign.description || "",
        payout: Number(campaign.payout || 0),
        totalLeads,
        totalSlots: 1,
        remainingSlots: 1,
        priority: "medium",
        status: "pending_team_leader",
        requiresAdminApproval: true,
        tatHours,
        createdBy: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
}

async function importTaskLeads(uid, input) {
    return withIdempotency(uid, "importTaskLeads", input.requestId, async (transaction) => {
        const { ref: campaignRef, campaign } = await requireCampaign(transaction, input.campaignId, ["active", "paused"]);
        const uploadRef = taskUploadRef(uid, input.taskRequestId);
        const uploadSnapshot = await transaction.get(uploadRef);
        let taskRef;
        let taskCode;

        if (uploadSnapshot.exists) {
            const upload = uploadSnapshot.data();
            if (upload.campaignId !== input.campaignId || upload.taskRequestId !== input.taskRequestId) {
                throw new functions.https.HttpsError("failed-precondition", "taskRequestId is already bound to another campaign upload.");
            }
            taskRef = db.collection("tasks").doc(upload.taskId);
            taskCode = upload.taskCode;
            const taskSnapshot = await transaction.get(taskRef);
            if (!taskSnapshot.exists || taskSnapshot.data().campaignId !== input.campaignId) {
                throw new functions.https.HttpsError("failed-precondition", "Upload task is missing or has an invalid campaign binding.");
            }
            if (taskSnapshot.data().status !== "pending_team_leader") {
                throw new functions.https.HttpsError("failed-precondition", "Cannot append leads after the upload task has been dispatched.");
            }
        } else {
            taskRef = db.collection("tasks").doc();
            taskCode = code("TSK", taskRef);
            transaction.create(taskRef, taskFields(uid, input.campaignId, campaign, taskRef, taskCode, 0, 24));
            transaction.create(uploadRef, {
                campaignId: input.campaignId,
                taskRequestId: input.taskRequestId,
                taskId: taskRef.id,
                taskCode,
                createdBy: uid,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }

        const now = admin.firestore.FieldValue.serverTimestamp();
        for (const lead of input.leads) {
            const leadRef = db.collection("campaign_leads").doc();
            transaction.create(leadRef, {
                campaignId: input.campaignId,
                campaignName: campaign.name || campaign.title || "",
                taskId: taskRef.id,
                ...lead,
                status: "pending",
                assignedTo: null,
                assignedAt: null,
                completedAt: null,
                uploadBatch: input.requestId,
                uploadedBy: uid,
                createdAt: now,
            });
        }
        transaction.update(taskRef, { totalLeads: admin.firestore.FieldValue.increment(input.leads.length) });
        transaction.update(campaignRef, {
            leadCount: admin.firestore.FieldValue.increment(input.leads.length),
            lastUploadedAt: now,
        });
        return { taskId: taskRef.id, taskCode, imported: input.leads.length };
    }, { campaignId: input.campaignId, taskRequestId: input.taskRequestId });
}

async function importLeads(uid, input) {
    return withIdempotency(uid, "importLeads", input.requestId, async (transaction) => {
        const { ref: campaignRef, campaign } = await requireCampaign(transaction, input.campaignId, ["active", "paused"]);
        const now = admin.firestore.FieldValue.serverTimestamp();
        for (const lead of input.leads) {
            const leadRef = db.collection("campaign_leads").doc();
            transaction.create(leadRef, {
                campaignId: input.campaignId,
                campaignName: campaign.name || campaign.title || "",
                taskId: null,
                ...lead,
                status: "pending",
                assignedTo: null,
                assignedAt: null,
                completedAt: null,
                uploadBatch: input.requestId,
                uploadedBy: uid,
                createdAt: now,
            });
        }
        transaction.update(campaignRef, {
            leadCount: admin.firestore.FieldValue.increment(input.leads.length),
            lastUploadedAt: now,
        });
        return { imported: input.leads.length };
    });
}

async function createSubtask(uid, input) {
    return withIdempotency(uid, "createSubtask", input.requestId, async (transaction) => {
        const { campaign } = await requireCampaign(transaction, input.campaignId);
        const leadsQuery = db.collection("campaign_leads")
            .where("campaignId", "==", input.campaignId)
            .where("status", "==", "pending")
            .where("taskId", "==", null)
            .limit(input.leadCount);
        const leadsSnapshot = await transaction.get(leadsQuery);
        if (leadsSnapshot.size !== input.leadCount) {
            throw new functions.https.HttpsError("failed-precondition", `Only ${leadsSnapshot.size} unallocated pending leads are available.`);
        }

        const taskRef = db.collection("tasks").doc();
        const taskCode = code("TSK", taskRef);
        const totalSlots = positiveInteger(campaign.slots || campaign.totalSlots || 1, "campaign slots", 1000);
        transaction.create(taskRef, {
            title: input.title,
            clientName: campaign.clientName || "Sherize Direct",
            campaignId: input.campaignId,
            taskCode,
            description: input.description == null ? (campaign.description || "") : input.description,
            payout: input.payout == null ? Number(campaign.payout || 0) : input.payout,
            totalLeads: input.leadCount,
            totalSlots,
            remainingSlots: totalSlots,
            priority: "medium",
            status: "pending_team_leader",
            requiresAdminApproval: true,
            tatHours: input.tatHours == null ? Number(campaign.tatHours || 0) : input.tatHours,
            createdBy: uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        for (const lead of leadsSnapshot.docs) transaction.update(lead.ref, { taskId: taskRef.id });
        return { taskId: taskRef.id, taskCode, totalLeads: input.leadCount };
    });
}

async function createSubtasks(uid, input) {
    return withIdempotency(uid, "createSubtasks", input.requestId, async (transaction) => {
        const { campaign } = await requireCampaign(transaction, input.campaignId, ["active", "paused"]);
        const leadsQuery = db.collection("campaign_leads")
            .where("campaignId", "==", input.campaignId)
            .where("status", "==", "pending");
        const leadsSnapshot = await transaction.get(leadsQuery);
        const unallocated = leadsSnapshot.docs.filter((leadSnapshot) => !leadSnapshot.data().taskId);
        if (unallocated.length > MAX_SUBTASK_LEADS) {
            throw new functions.https.HttpsError("resource-exhausted", `createSubtasks supports at most ${MAX_SUBTASK_LEADS} unallocated leads per request. Split larger lead sheets into subtasks during upload.`);
        }
        if (!unallocated.length) {
            throw new functions.https.HttpsError("failed-precondition", "No unallocated pending leads are available.");
        }
        const taskCount = Math.min(input.subtasksCount, unallocated.length);
        if (unallocated.length + taskCount + 1 > 500) {
            throw new functions.https.HttpsError("resource-exhausted", "The requested allocation exceeds Firestore's 500-write transaction limit.");
        }
        const groups = Array.from({ length: taskCount }, () => []);
        unallocated.forEach((leadSnapshot, index) => groups[index % taskCount].push(leadSnapshot));
        const tasks = groups.map((group) => {
            const taskRef = db.collection("tasks").doc();
            const taskCode = code("TSK", taskRef);
            transaction.create(taskRef, taskFields(uid, input.campaignId, campaign, taskRef, taskCode, group.length, input.tatHours));
            for (const leadSnapshot of group) transaction.update(leadSnapshot.ref, { taskId: taskRef.id });
            return { taskId: taskRef.id, taskCode, totalLeads: group.length };
        });
        return { tasks, created: tasks.length, allocated: unallocated.length };
    }, {
        campaignId: input.campaignId,
        subtasksCount: input.subtasksCount,
        tatHours: input.tatHours,
    });
}

async function setStatus(input) {
    return db.runTransaction(async (transaction) => {
        const campaignRef = db.collection("campaigns").doc(input.campaignId);
        const campaignSnapshot = await transaction.get(campaignRef);
        if (!campaignSnapshot.exists) throw new functions.https.HttpsError("not-found", "Campaign not found.");
        const tasksQuery = db.collection("tasks").where("campaignId", "==", input.campaignId).limit(MAX_STATUS_TASKS + 1);
        const tasksSnapshot = await transaction.get(tasksQuery);
        if (tasksSnapshot.size > MAX_STATUS_TASKS) {
            throw new functions.https.HttpsError("resource-exhausted", `setStatus supports campaigns with at most ${MAX_STATUS_TASKS} tasks.`);
        }
        transaction.update(campaignRef, { status: input.status });
        let updatedTasks = 0;
        for (const taskSnapshot of tasksSnapshot.docs) {
            if (["active", "paused"].includes(taskSnapshot.data().status)) {
                transaction.update(taskSnapshot.ref, { status: input.status });
                updatedTasks++;
            }
        }
        return { campaignId: input.campaignId, status: input.status, updatedTasks };
    });
}

const manageTeamCampaign = functions.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in is required.");
    const payload = requireObject(data, "request");
    await validateActiveManager(db, context.auth.uid);

    if (payload.action === "createCampaign") {
        const settings = await db.collection("platform_settings").doc("main").get();
        return createCampaign(context.auth.uid, validateCreateCampaign(payload, settings.data()?.clientPaymentsVisible !== false));
    }
    if (payload.action === "getCampaignClients") return getCampaignClients(validateCampaignClientLookup(payload));
    if (payload.action === "importLeads") return importLeads(context.auth.uid, validateImport(payload));
    if (payload.action === "importTaskLeads") return importTaskLeads(context.auth.uid, validateTaskImport(payload));
    if (payload.action === "createSubtask") return createSubtask(context.auth.uid, validateSubtask(payload));
    if (payload.action === "createSubtasks") return createSubtasks(context.auth.uid, validateCreateSubtasks(payload));
    if (payload.action === "setStatus") return setStatus(validateSetStatus(payload));
    invalid("action must be createCampaign, getCampaignClients, importLeads, importTaskLeads, createSubtask, createSubtasks, or setStatus.");
});

module.exports = {
    MAX_LEADS,
    MAX_SUBTASK_LEADS,
    MAX_SUBTASKS,
    MAX_STATUS_TASKS,
    manageTeamCampaign,
    validateCreateCampaign,
    validateCampaignClientLookup,
    validateImport,
    validateTaskImport,
    validateSubtask,
    validateCreateSubtasks,
    validateSetStatus,
};
