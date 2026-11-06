const assert = require("node:assert/strict");
const Module = require("node:module");
const records = new Map();
const timestamp = (millis) => ({ toMillis: () => millis });
let beforeTransaction = null;
let beforeLeadRead = null;
const snapshot = (path) => ({
    exists: records.has(path), id: path.split("/")[1], ref: ref(path),
    data: () => records.get(path),
});
function ref(path) {
    return { path, get: async () => snapshot(path), set: async (data) => records.set(path, data) };
}
function collection(name, filters = [], maximum = Infinity) {
    return {
        doc: (id) => ref(`${name}/${id}`),
        where: (field, operator, value) => collection(name, [...filters, { field, operator, value }], maximum),
        limit: (value) => collection(name, filters, value),
        get: async () => {
            const docs = [...records.keys()].filter((path) => path.startsWith(`${name}/`) &&
                filters.every(({ field, operator, value }) => {
                    const actual = records.get(path)[field];
                    if (operator === "in") return value.includes(actual);
                    if (operator === "<=") return actual?.toMillis() <= value.toMillis();
                    if (operator === "<") return actual?.toMillis() < value.toMillis();
                    return actual === value;
                })).slice(0, maximum).map(snapshot);
            return { docs, empty: !docs.length, size: docs.length };
        },
    };
}
const db = {
    collection,
    runTransaction: async (handler) => {
        if (beforeTransaction) { const hook = beforeTransaction; beforeTransaction = null; hook(); }
        const writes = [];
        const result = await handler({
            get: (document) => {
                if (beforeLeadRead && document.path.startsWith("campaign_leads/")) {
                    const hook = beforeLeadRead;
                    beforeLeadRead = null;
                    hook();
                }
                return document.get();
            },
            update: (document, data) => writes.push(() => records.set(document.path, { ...records.get(document.path), ...data })),
        });
        writes.forEach((write) => write());
        return result;
    },
};
const firestore = () => db;
firestore.Timestamp = { now: () => timestamp(1000) };
firestore.FieldValue = { serverTimestamp: () => timestamp(1000) };
const originalLoad = Module._load;
let requeueLeads;
let enforceTatAndRecreate;
try {
    Module._load = function (name, ...args) {
        if (name === "firebase-admin") return { firestore };
        if (name === "./syncTaskLeadCounts") return { reconcileTaskAvailability: async () => {} };
        if (name === "firebase-functions/v1") {
            return { pubsub: { schedule: () => ({ onRun: (handler) => handler }) } };
        }
        return originalLoad.call(this, name, ...args);
    };
    ({ requeueLeads } = require("./requeueLeads"));
    ({ enforceTatAndRecreate } = require("./enforceTatAndRecreate"));
} finally {
    Module._load = originalLoad;
}

(async () => {
    for (const reason of ["callback", "no_answer", "qa_rejected"]) {
        records.set(`campaign_leads/${reason}`, {
            taskId: "task-1", status: "requeue_pending", requeueReason: reason,
            requeueAfter: timestamp(900), requeueCount: 0,
        });
    }
    records.set("campaign_leads/future", { status: "requeue_pending", requeueAfter: timestamp(1100) });
    records.set("campaign_leads/limit", { status: "requeue_pending", requeueAfter: timestamp(900), requeueCount: 3 });
    records.set("campaign_leads/reject-only", { status: "rejected", requeueAfter: timestamp(900) });
    await requeueLeads();
    for (const reason of ["callback", "no_answer", "qa_rejected"]) {
        const lead = records.get(`campaign_leads/${reason}`);
        assert.equal(lead.status, "pending");
        assert.equal(lead.taskId, "task-1");
        assert.equal(lead.requeueCount, 1);
    }
    assert.equal(records.get("campaign_leads/future").status, "requeue_pending");
    assert.equal(records.get("campaign_leads/limit").status, "unreachable");
    assert.equal(records.get("campaign_leads/reject-only").status, "rejected");
    await requeueLeads();
    assert.equal(records.get("campaign_leads/callback").requeueCount, 1);

    for (const concurrentChange of [{ status: "in_progress", assignedTo: "worker-2" }, { requeueAfter: timestamp(1100) }]) {
        records.clear();
        const path = "campaign_leads/concurrent";
        records.set(path, { taskId: "task-1", status: "requeue_pending", requeueAfter: timestamp(900) });
        beforeTransaction = () => records.set(path, { ...records.get(path), ...concurrentChange });
        await requeueLeads();
        for (const [key, value] of Object.entries(concurrentChange)) assert.equal(records.get(path)[key], value);
        assert.equal(records.get(path).requeueCount, undefined);
    }

    for (const status of ["active", "in_progress", "out_of_tat_processing"]) {
        records.clear();
        records.set("tasks/task-1", { acceptedCount: 1, payout: 10 });
        records.set("task_assignments/retry-1", { taskId: "task-1", userId: "worker-1", status, tatDeadline: timestamp(900) });
        records.set("task_submissions/previous", { taskId: "task-1", userId: "worker-1", assignmentId: "old-1", outcome: "interested" });
        records.set("campaign_leads/locked", { taskId: "task-1", assignedTo: "worker-1", status: "in_progress" });
        await enforceTatAndRecreate();
        assert.equal(records.get("task_assignments/retry-1").status, "out_of_tat");
        assert.equal(records.get("tasks/task-1").acceptedCount, 0);
        assert.equal(records.get("campaign_leads/locked").status, "pending");
        assert.equal(records.get("campaign_leads/locked").taskId, "task-1");
        assert.equal(records.has("earnings/tat_retry-1"), false, "Do not count a previous assignment's submissions");
        await enforceTatAndRecreate();
        assert.equal([...records.keys()].filter((path) => path.startsWith("tasks/")).length, 1);
    }
    records.clear();
    records.set("tasks/task-1", { acceptedCount: 1, payout: 10 });
    records.set("task_assignments/old-1", { taskId: "task-1", userId: "worker-1", status: "out_of_tat_processing", tatDeadline: timestamp(900) });
    records.set("campaign_leads/reclaimed", { taskId: "task-1", assignedTo: "worker-1", status: "in_progress" });
    beforeLeadRead = () => {
        records.get("task_assignments/old-1").status = "out_of_tat";
        records.set("task_assignments/new-1", { taskId: "task-1", userId: "worker-1", status: "in_progress", tatDeadline: timestamp(2000) });
    };
    await enforceTatAndRecreate();
    assert.equal(records.get("campaign_leads/reclaimed").status, "in_progress", "A stale cleanup run must not release the new attempt's lead");
    assert.equal(records.get("tasks/task-1").acceptedCount, 1);
    console.log("retry scheduler and assignment expiry checks passed");
})().catch((error) => { console.error(error); process.exitCode = 1; });