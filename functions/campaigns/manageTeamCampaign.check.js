const assert = require("node:assert");
const Module = require("node:module");

const documents = new Map([
    ["users/leader-1", { role: "team_leader", isActive: true, teamId: "team-a" }],
    ["users/leader-2", { role: "team_leader", isActive: true, teamId: "team-b" }],
    ["users/inactive-leader", { role: "team_leader", isActive: false }],
    ["users/worker-1", { role: "worker", isActive: true }],
    ["users/client-1", { role: "client", isActive: true }],
]);
let nextId = 0;
let transactionQueue = Promise.resolve();

function snapshot(ref, value) {
    return { id: ref.id, ref, exists: value !== undefined, data: () => value };
}

function makeQuery(name, filters = [], orderField = null, limitValue = Infinity) {
    return {
        _query: true,
        name,
        filters,
        orderField,
        limitValue,
        where(field, operator, value) {
            return makeQuery(name, [...filters, { field, operator, value }], orderField, limitValue);
        },
        orderBy(field) {
            return makeQuery(name, filters, field, limitValue);
        },
        limit(value) {
            return makeQuery(name, filters, orderField, value);
        },
    };
}

function docRef(name, id = `auto-${String(++nextId).padStart(4, "0")}`) {
    const path = `${name}/${id}`;
    return {
        id,
        path,
        async get() {
            return snapshot(this, documents.get(path));
        },
        async create(data) {
            if (documents.has(path)) throw new Error(`Document already exists: ${path}`);
            documents.set(path, data);
        },
    };
}

function readQuery(query, source = documents) {
    const docs = [...source.entries()]
        .filter(([path, data]) => path.startsWith(`${query.name}/`) && query.filters.every(({ field, operator, value }) => {
            assert.strictEqual(operator, "==");
            return data[field] === value;
        }))
        .sort((left, right) => query.orderField ? Number(left[1][query.orderField]) - Number(right[1][query.orderField]) : 0)
        .slice(0, query.limitValue)
        .map(([path, data]) => snapshot(docRef(query.name, path.split("/")[1]), data));
    return { empty: docs.length === 0, size: docs.length, docs };
}

const db = {
    collection(name) {
        return { ...makeQuery(name), doc: (id) => docRef(name, id) };
    },
    runTransaction(handler) {
        const run = transactionQueue.then(async () => {
            const working = new Map(documents);
            const transaction = {
                async get(target) {
                    if (target._query) return readQuery(target, working);
                    return snapshot(target, working.get(target.path));
                },
                create(ref, data) {
                    if (working.has(ref.path)) throw new Error(`Document already exists: ${ref.path}`);
                    working.set(ref.path, data);
                },
                update(ref, update) {
                    const current = working.get(ref.path);
                    if (!current) throw new Error(`Missing document: ${ref.path}`);
                    const resolved = Object.fromEntries(Object.entries(update).map(([key, value]) => [
                        key,
                        value && value.__increment ? Number(current[key] || 0) + value.value : value,
                    ]));
                    working.set(ref.path, { ...current, ...resolved });
                },
            };
            const result = await handler(transaction);
            documents.clear();
            for (const entry of working) documents.set(...entry);
            return result;
        });
        transactionQueue = run.catch(() => {});
        return run;
    },
};

let clock = 1000;
const firestore = () => db;
firestore.FieldValue = {
    serverTimestamp: () => ++clock,
    increment: (value) => ({ __increment: true, value }),
};
firestore.Timestamp = { fromDate: (date) => ({ seconds: Math.floor(date.getTime() / 1000) }) };

const originalLoad = Module._load;
let manageTeamCampaign;
try {
    Module._load = function (name, ...args) {
        if (name === "firebase-admin") return { firestore };
        return originalLoad.call(this, name, ...args);
    };
    ({ manageTeamCampaign } = require("./manageTeamCampaign"));
} finally {
    Module._load = originalLoad;
}

const context = (uid) => uid ? { auth: { uid } } : {};
const campaignInput = {
    action: "createCampaign",
    campaign: {
        title: "Renewals",
        description: "Call renewal leads",
        clientName: "Sherize Direct",
        payout: 15,
        slots: 2,
        tatHours: 24,
        deadline: "2026-10-01T12:00:00.000Z",
    },
};
const lead = (number) => ({ name: `Lead ${number}`, phone: `9876543${String(number).padStart(3, "0")}`, email: `lead${number}@example.com`, notes: "CSV" });

(async () => {
    await assert.rejects(manageTeamCampaign.run(campaignInput, context()), (error) => error.code === "unauthenticated");
    for (const uid of ["worker-1", "client-1", "inactive-leader", "missing-user"]) {
        await assert.rejects(manageTeamCampaign.run(campaignInput, context(uid)), (error) => error.code === "permission-denied");
    }

    const created = await manageTeamCampaign.run(campaignInput, context("leader-1"));
    assert.match(created.campaignCode, /^CMP-/);
    assert.deepStrictEqual(Object.keys(created).sort(), ["campaignCode", "campaignId"]);
    const campaign = documents.get(`campaigns/${created.campaignId}`);
    assert.equal(campaign.status, "active");
    assert.equal(campaign.leadCount, 0);
    assert.equal(campaign.createdBy, "leader-1");
    assert.equal(campaign.totalSlots, 2);
    assert.equal(campaign.tatHours, 24);
    assert.equal(campaign.clientId, undefined);

    const withoutPayout = { ...campaignInput, campaign: { ...campaignInput.campaign } };
    delete withoutPayout.campaign.payout;
    await assert.rejects(manageTeamCampaign.run(withoutPayout, context("leader-1")),
        (error) => error.code === "invalid-argument");
    documents.set("platform_settings/main", { clientPaymentsVisible: false });
    for (const request of [withoutPayout, campaignInput]) {
        const unpriced = await manageTeamCampaign.run(request, context("leader-1"));
        const saved = documents.get(`campaigns/${unpriced.campaignId}`);
        assert.equal(saved.payout, 0, "Payment-off mode ignores even a stale positive payout");
        assert.equal(saved.unpriced, true);
    }
    documents.set("platform_settings/main", { clientPaymentsVisible: true });
    await assert.rejects(manageTeamCampaign.run(withoutPayout, context("leader-1")),
        (error) => error.code === "invalid-argument");
    documents.delete("platform_settings/main");

    await assert.rejects(manageTeamCampaign.run({ ...campaignInput, status: "approved" }, context("leader-1")),
        (error) => error.code === "invalid-argument");
    await assert.rejects(manageTeamCampaign.run({ action: "createCampaign", campaign: { ...campaignInput.campaign, createdBy: "spoofed" } }, context("leader-1")),
        (error) => error.code === "invalid-argument");
    await assert.rejects(manageTeamCampaign.run({ action: "importLeads", campaignId: created.campaignId, leads: Array(201).fill(lead(1)), requestId: "import-too-many" }, context("leader-1")),
        (error) => error.code === "invalid-argument");
    await assert.rejects(manageTeamCampaign.run({ action: "importLeads", campaignId: created.campaignId, leads: [{ ...lead(1), taskId: "spoofed" }], requestId: "import-spoofed" }, context("leader-1")),
        (error) => error.code === "invalid-argument");

    const importRequest = {
        action: "importLeads",
        campaignId: created.campaignId,
        leads: [lead(1), lead(2), lead(3)],
        requestId: "import-request-001",
    };
    assert.deepStrictEqual(await manageTeamCampaign.run(importRequest, context("leader-2")), { imported: 3 });
    assert.deepStrictEqual(await manageTeamCampaign.run(importRequest, context("leader-2")), { imported: 3 });
    const importedLeads = [...documents.entries()].filter(([path]) => path.startsWith("campaign_leads/"));
    assert.equal(importedLeads.length, 3, "retry must not duplicate imported rows");
    assert(importedLeads.every(([, value]) => value.taskId === null && value.status === "pending" && value.uploadedBy === "leader-2"));
    assert.equal(documents.get(`campaigns/${created.campaignId}`).leadCount, 3);

    const firstRequest = {
        action: "createSubtask",
        campaignId: created.campaignId,
        title: "Renewal batch A",
        leadCount: 2,
        requestId: "subtask-request-001",
    };
    const first = await manageTeamCampaign.run(firstRequest, context("leader-1"));
    assert.deepStrictEqual(await manageTeamCampaign.run(firstRequest, context("leader-1")), first);
    const firstLeadIds = [...documents.entries()]
        .filter(([path, value]) => path.startsWith("campaign_leads/") && value.taskId === first.taskId)
        .map(([path]) => path);
    assert.equal(firstLeadIds.length, 2);
    assert.equal(documents.get(`tasks/${first.taskId}`).totalSlots, 2);
    assert.equal(documents.get(`tasks/${first.taskId}`).remainingSlots, 2);
    assert.equal(documents.get(`tasks/${first.taskId}`).status, "pending_team_leader");

    await assert.rejects(manageTeamCampaign.run({ ...firstRequest, requestId: "subtask-request-002", leadCount: 2 }, context("leader-2")),
        (error) => error.code === "failed-precondition");
    assert(firstLeadIds.every((path) => documents.get(path).taskId === first.taskId), "allocated taskId must remain immutable");

    const secondCampaign = await manageTeamCampaign.run({ ...campaignInput, campaign: { ...campaignInput.campaign, title: "Concurrent" } }, context("leader-1"));
    await manageTeamCampaign.run({ action: "importLeads", campaignId: secondCampaign.campaignId, leads: [lead(4), lead(5)], requestId: "import-request-002" }, context("leader-1"));
    const competing = (requestId) => manageTeamCampaign.run({
        action: "createSubtask",
        campaignId: secondCampaign.campaignId,
        title: requestId,
        leadCount: 2,
        requestId,
    }, context("leader-1"));
    const results = await Promise.allSettled([competing("concurrent-task-a"), competing("concurrent-task-b")]);
    assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
    assert.equal(results.filter((result) => result.status === "rejected" && result.reason.code === "failed-precondition").length, 1);
    const concurrentLeads = [...documents.values()].filter((value) => value.campaignId === secondCampaign.campaignId && value.phone);
    assert.equal(new Set(concurrentLeads.map((value) => value.taskId)).size, 1, "concurrent allocation must have one owner");

    await assert.rejects(manageTeamCampaign.run({ ...firstRequest, requestId: "import-request-001" }, context("leader-2")),
        (error) => error.code === "already-exists");

    const defaultCampaignInput = {
        action: "createCampaign",
        campaign: {
            title: "Default fields",
            description: "Defaults check",
            clientName: "Sherize Direct",
            payout: 20,
        },
    };
    const defaultCreated = await manageTeamCampaign.run(defaultCampaignInput, context("leader-1"));
    const defaultCampaign = documents.get(`campaigns/${defaultCreated.campaignId}`);
    assert.equal(defaultCampaign.status, "active");
    assert.equal(defaultCampaign.startDate, "");
    assert.equal(defaultCampaign.endDate, "");
    assert.equal(defaultCampaign.slots, 1);
    assert.equal(defaultCampaign.totalSlots, 1);
    assert.equal(defaultCampaign.tatHours, 24);

    const pausedCreated = await manageTeamCampaign.run({
        ...defaultCampaignInput,
        campaign: {
            ...defaultCampaignInput.campaign,
            title: "Paused dated campaign",
            status: "paused",
            startDate: "2026-09-24",
            endDate: "2026-10-31",
            slots: 4,
            tatHours: 36,
        },
    }, context("leader-1"));
    const pausedCampaign = documents.get(`campaigns/${pausedCreated.campaignId}`);
    assert.equal(pausedCampaign.status, "paused");
    assert.equal(pausedCampaign.startDate, "2026-09-24");
    assert.equal(pausedCampaign.endDate, "2026-10-31");
    assert.equal(pausedCampaign.totalSlots, 4);
    assert.equal(pausedCampaign.tatHours, 36);
    for (const campaignPatch of [
        { status: "completed" },
        { startDate: "2026-02-29" },
        { endDate: "2026-04-31" },
        { startDate: "2026-10-02", endDate: "2026-10-01" },
    ]) {
        await assert.rejects(manageTeamCampaign.run({
            ...defaultCampaignInput,
            campaign: { ...defaultCampaignInput.campaign, ...campaignPatch },
        }, context("leader-1")), (error) => error.code === "invalid-argument");
    }

    const taskImportTemplate = {
        action: "importTaskLeads",
        campaignId: pausedCreated.campaignId,
        leads: [lead(101)],
        requestId: "task-chunk-template",
        taskRequestId: "task-upload-template",
    };
    const createSubtasksTemplate = {
        action: "createSubtasks",
        campaignId: pausedCreated.campaignId,
        subtasksCount: 2,
        tatHours: 24,
        requestId: "create-many-template",
    };
    const setStatusTemplate = { action: "setStatus", campaignId: pausedCreated.campaignId, status: "active" };
    for (const payload of [taskImportTemplate, createSubtasksTemplate, setStatusTemplate]) {
        for (const uid of ["worker-1", "client-1", "inactive-leader", "missing-user"]) {
            await assert.rejects(manageTeamCampaign.run(payload, context(uid)), (error) => error.code === "permission-denied");
        }
        await assert.rejects(manageTeamCampaign.run({ ...payload, createdBy: "spoofed" }, context("leader-1")),
            (error) => error.code === "invalid-argument");
    }
    await assert.rejects(manageTeamCampaign.run({ ...taskImportTemplate, leads: Array(201).fill(lead(101)) }, context("leader-1")),
        (error) => error.code === "invalid-argument");
    await assert.rejects(manageTeamCampaign.run({ ...taskImportTemplate, leads: [{ ...lead(101), taskId: "spoofed" }] }, context("leader-1")),
        (error) => error.code === "invalid-argument");

    const firstChunk = {
        action: "importTaskLeads",
        campaignId: pausedCreated.campaignId,
        leads: [lead(101), lead(102)],
        requestId: "task-chunk-0001",
        taskRequestId: "task-upload-0001",
    };
    const uploadedFirst = await manageTeamCampaign.run(firstChunk, context("leader-1"));
    assert.deepStrictEqual(await manageTeamCampaign.run(firstChunk, context("leader-1")), uploadedFirst);
    assert.match(uploadedFirst.taskCode, /^TSK-/);
    assert.equal(uploadedFirst.imported, 2);
    const uploadedSecond = await manageTeamCampaign.run({
        ...firstChunk,
        leads: [lead(103)],
        requestId: "task-chunk-0002",
    }, context("leader-1"));
    assert.equal(uploadedSecond.taskId, uploadedFirst.taskId);
    assert.equal(uploadedSecond.taskCode, uploadedFirst.taskCode);
    const uploadTask = documents.get(`tasks/${uploadedFirst.taskId}`);
    assert.deepStrictEqual({
        title: uploadTask.title,
        clientName: uploadTask.clientName,
        description: uploadTask.description,
        payout: uploadTask.payout,
        totalLeads: uploadTask.totalLeads,
        totalSlots: uploadTask.totalSlots,
        remainingSlots: uploadTask.remainingSlots,
        priority: uploadTask.priority,
        status: uploadTask.status,
        requiresAdminApproval: uploadTask.requiresAdminApproval,
        tatHours: uploadTask.tatHours,
        createdBy: uploadTask.createdBy,
    }, {
        title: "Paused dated campaign",
        clientName: "Sherize Direct",
        description: "Defaults check",
        payout: 20,
        totalLeads: 3,
        totalSlots: 1,
        remainingSlots: 1,
        priority: "medium",
        status: "pending_team_leader",
        requiresAdminApproval: true,
        tatHours: 24,
        createdBy: "leader-1",
    });
    const taskImportedLeads = [...documents.values()].filter((value) => value.taskId === uploadedFirst.taskId && value.phone);
    assert.equal(taskImportedLeads.length, 3, "chunk retry must not duplicate task leads");
    assert(taskImportedLeads.every((value) => value.campaignId === pausedCreated.campaignId && value.status === "pending" && value.uploadedBy === "leader-1"));
    assert.equal(documents.get(`campaigns/${pausedCreated.campaignId}`).leadCount, 3);
    const uploadReceipt = documents.get("team_campaign_task_uploads/leader-1_task-upload-0001");
    assert.deepStrictEqual({
        campaignId: uploadReceipt.campaignId,
        taskRequestId: uploadReceipt.taskRequestId,
        taskId: uploadReceipt.taskId,
        taskCode: uploadReceipt.taskCode,
        createdBy: uploadReceipt.createdBy,
    }, {
        campaignId: pausedCreated.campaignId,
        taskRequestId: "task-upload-0001",
        taskId: uploadedFirst.taskId,
        taskCode: uploadedFirst.taskCode,
        createdBy: "leader-1",
    });
    await assert.rejects(manageTeamCampaign.run({ ...firstChunk, taskRequestId: "task-upload-other" }, context("leader-1")),
        (error) => error.code === "already-exists");
    await assert.rejects(manageTeamCampaign.run({
        ...firstChunk,
        campaignId: defaultCreated.campaignId,
        requestId: "task-chunk-binding",
    }, context("leader-1")), (error) => error.code === "failed-precondition");
    documents.set(`tasks/${uploadedFirst.taskId}`, { ...uploadTask, status: "active" });
    await assert.rejects(manageTeamCampaign.run({ ...firstChunk, requestId: "task-chunk-dispatch" }, context("leader-1")),
        (error) => error.code === "failed-precondition");

    documents.set(`campaigns/${defaultCreated.campaignId}`, { ...defaultCampaign, status: "paused" });
    assert.deepStrictEqual(await manageTeamCampaign.run({
        action: "importLeads",
        campaignId: defaultCreated.campaignId,
        leads: [lead(104)],
        requestId: "paused-old-upload",
    }, context("leader-1")), { imported: 1 });
    documents.set(`campaigns/${defaultCreated.campaignId}`, { ...documents.get(`campaigns/${defaultCreated.campaignId}`), status: "completed" });
    await assert.rejects(manageTeamCampaign.run({
        ...taskImportTemplate,
        campaignId: defaultCreated.campaignId,
        requestId: "completed-upload",
        taskRequestId: "completed-task-upload",
    }, context("leader-1")), (error) => error.code === "failed-precondition");

    const concurrentUploadCampaign = await manageTeamCampaign.run({
        ...defaultCampaignInput,
        campaign: { ...defaultCampaignInput.campaign, title: "Concurrent task upload" },
    }, context("leader-1"));
    const concurrentChunks = [201, 202].map((number) => manageTeamCampaign.run({
        action: "importTaskLeads",
        campaignId: concurrentUploadCampaign.campaignId,
        leads: [lead(number)],
        requestId: `concurrent-chunk-${number}`,
        taskRequestId: "concurrent-upload-task",
    }, context("leader-2")));
    const concurrentUploadResults = await Promise.all(concurrentChunks);
    assert.equal(new Set(concurrentUploadResults.map((result) => result.taskId)).size, 1);
    const concurrentUploadTask = documents.get(`tasks/${concurrentUploadResults[0].taskId}`);
    assert.equal(concurrentUploadTask.totalLeads, 2);

    const allocationCampaign = await manageTeamCampaign.run({
        ...defaultCampaignInput,
        campaign: { ...defaultCampaignInput.campaign, title: "Legacy allocation", status: "paused" },
    }, context("leader-1"));
    const allocationLeadIds = [];
    for (let index = 0; index < 5; index++) {
        const id = `legacy-${index}`;
        allocationLeadIds.push(id);
        documents.set(`campaign_leads/${id}`, {
            campaignId: allocationCampaign.campaignId,
            name: `Legacy ${index}`,
            phone: `9000000${String(index).padStart(3, "0")}`,
            status: "pending",
            ...(index % 2 === 0 ? {} : { taskId: null }),
        });
    }
    documents.set("campaign_leads/already-allocated", {
        campaignId: allocationCampaign.campaignId,
        name: "Allocated",
        phone: "9000000999",
        status: "pending",
        taskId: "existing-task",
    });
    for (let index = 0; index < 500; index++) {
        documents.set(`campaign_leads/existing-pending-${index}`, {
            campaignId: allocationCampaign.campaignId, status: "pending", taskId: "existing-task",
        });
    }
    const createManyRequest = {
        action: "createSubtasks",
        campaignId: allocationCampaign.campaignId,
        subtasksCount: 2,
        tatHours: 48,
        requestId: "create-many-0001",
    };
    const createdMany = await manageTeamCampaign.run(createManyRequest, context("leader-2"));
    assert.deepStrictEqual(await manageTeamCampaign.run(createManyRequest, context("leader-2")), createdMany);
    assert.equal(createdMany.created, 2);
    assert.equal(createdMany.allocated, 5);
    assert.deepStrictEqual(createdMany.tasks.map((task) => task.totalLeads), [3, 2]);
    assert.deepStrictEqual(allocationLeadIds.map((id) => documents.get(`campaign_leads/${id}`).taskId), [
        createdMany.tasks[0].taskId,
        createdMany.tasks[1].taskId,
        createdMany.tasks[0].taskId,
        createdMany.tasks[1].taskId,
        createdMany.tasks[0].taskId,
    ]);
    assert.equal(documents.get("campaign_leads/already-allocated").taskId, "existing-task");
    for (const result of createdMany.tasks) {
        const task = documents.get(`tasks/${result.taskId}`);
        assert.equal(task.title, "Legacy allocation");
        assert.equal(task.clientName, "Sherize Direct");
        assert.equal(task.campaignId, allocationCampaign.campaignId);
        assert.equal(task.taskCode, result.taskCode);
        assert.equal(task.totalLeads, result.totalLeads);
        assert.equal(task.totalSlots, 1);
        assert.equal(task.remainingSlots, 1);
        assert.equal(task.status, "pending_team_leader");
        assert.equal(task.tatHours, 48);
        assert.equal(task.createdBy, "leader-2");
    }
    await assert.rejects(manageTeamCampaign.run({ ...createManyRequest, tatHours: 72 }, context("leader-2")),
        (error) => error.code === "already-exists");

    const allocationRaceCampaign = await manageTeamCampaign.run({
        ...defaultCampaignInput,
        campaign: { ...defaultCampaignInput.campaign, title: "Allocation race" },
    }, context("leader-1"));
    for (let index = 0; index < 2; index++) {
        documents.set(`campaign_leads/race-${index}`, {
            campaignId: allocationRaceCampaign.campaignId,
            phone: `911111100${index}`,
            status: "pending",
        });
    }
    const allocationRace = await Promise.allSettled(["allocation-race-a", "allocation-race-b"].map((id) => manageTeamCampaign.run({
        action: "createSubtasks",
        campaignId: allocationRaceCampaign.campaignId,
        subtasksCount: 2,
        tatHours: 24,
        requestId: id,
    }, context("leader-1"))));
    assert.equal(allocationRace.filter((result) => result.status === "fulfilled").length, 1);
    assert.equal(allocationRace.filter((result) => result.status === "rejected" && result.reason.code === "failed-precondition").length, 1);

    const oversizedCampaign = await manageTeamCampaign.run({
        ...defaultCampaignInput,
        campaign: { ...defaultCampaignInput.campaign, title: "Oversized allocation" },
    }, context("leader-1"));
    for (let index = 0; index < 451; index++) {
        documents.set(`campaign_leads/oversized-${index}`, {
            campaignId: oversizedCampaign.campaignId,
            phone: `9222${String(index).padStart(6, "0")}`,
            status: "pending",
        });
    }
    await assert.rejects(manageTeamCampaign.run({
        action: "createSubtasks",
        campaignId: oversizedCampaign.campaignId,
        subtasksCount: 1,
        tatHours: 24,
        requestId: "oversized-create",
    }, context("leader-1")), (error) => error.code === "resource-exhausted" && error.message.includes("450"));
    assert([...documents.values()].filter((value) => value.campaignId === oversizedCampaign.campaignId && value.taskCode).length === 0,
        "oversized allocation must not partially create tasks");

    const statusCampaign = await manageTeamCampaign.run({
        ...defaultCampaignInput,
        campaign: { ...defaultCampaignInput.campaign, title: "Status propagation" },
    }, context("leader-1"));
    for (const [id, status] of [["status-active", "active"], ["status-paused", "paused"], ["status-pending", "pending_team_leader"], ["status-complete", "completed"]]) {
        documents.set(`tasks/${id}`, { campaignId: statusCampaign.campaignId, status });
    }
    assert.deepStrictEqual(await manageTeamCampaign.run({
        action: "setStatus",
        campaignId: statusCampaign.campaignId,
        status: "paused",
    }, context("leader-1")), { campaignId: statusCampaign.campaignId, status: "paused", updatedTasks: 2 });
    assert.equal(documents.get(`campaigns/${statusCampaign.campaignId}`).status, "paused");
    assert.equal(documents.get("tasks/status-active").status, "paused");
    assert.equal(documents.get("tasks/status-paused").status, "paused");
    assert.equal(documents.get("tasks/status-pending").status, "pending_team_leader");
    assert.equal(documents.get("tasks/status-complete").status, "completed");
    assert.deepStrictEqual(await manageTeamCampaign.run({
        action: "setStatus",
        campaignId: statusCampaign.campaignId,
        status: "active",
    }, context("leader-2")), { campaignId: statusCampaign.campaignId, status: "active", updatedTasks: 2 });
    await assert.rejects(manageTeamCampaign.run({
        action: "setStatus",
        campaignId: statusCampaign.campaignId,
        status: "completed",
    }, context("leader-1")), (error) => error.code === "invalid-argument");

    console.log("manageTeamCampaign checks passed: legacy compatibility, auth, allowlists, campaign fields/dates/defaults, active-paused uploads, task receipts, chunk retry/concurrency, dispatch rejection, exact round-robin allocation, legacy leads, workload limits, and status preservation");
})().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});