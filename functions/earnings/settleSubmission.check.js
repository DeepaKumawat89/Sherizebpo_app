const assert = require("node:assert/strict");
const Module = require("node:module");
const documents = new Map([
    ["task_submissions/submission-1", { status: "pending_admin_review", taskId: "task-1", userId: "worker-1", assignmentId: "assignment-1", leadId: "lead-1", payout: 10 }],
    ["tasks/task-1", { payout: 10, campaignId: "campaign-1" }],
    ["campaigns/campaign-1", { clientId: "client-1", clientPricePerLead: 15, reserved: 100, spentAmount: 0 }],
    ["client_wallets/client-1", { balance: 100, reservedBalance: 100 }],
    ["worker_wallets/worker-1", { balance: 0, totalEarned: 0 }],
    ["users/worker-1", { walletBalance: 0, earnings: 0 }],
    ["campaign_leads/lead-1", { status: "completed" }],
    ["task_assignments/assignment-1", { taskId: "task-1", userId: "worker-1", status: "in_progress", totalLeads: 5 }],
]);
let nextId = 0;
const reference = (path) => ({ path, get: async () => ({ exists: documents.has(path), data: () => documents.get(path), ref: reference(path) }) });
function apply(document, fields, merge = true) {
    const previous = documents.get(document.path) || {};
    const next = merge ? { ...previous } : {};
    for (const [key, value] of Object.entries(fields)) {
        next[key] = value && typeof value === "object" && "increment" in value
            ? Number(previous[key] || 0) + value.increment : value;
    }
    documents.set(document.path, next);
}
const db = {
    collection: (name) => {
        const query = { where: () => query, limit: () => query, get: async () => ({ empty: true }) };
        return { ...query, doc: (id = `auto-${++nextId}`) => reference(`${name}/${id}`) };
    },
    runTransaction: async (handler) => {
        const writes = [];
        await handler({
            get: (document) => document.get(),
            update: (document, fields) => writes.push(() => apply(document, fields)),
            set: (document, fields, options) => writes.push(() => apply(document, fields, options?.merge)),
        });
        writes.forEach((write) => write());
    },
};
const originalLoad = Module._load;
let settleSubmissionPayout;
try {
    Module._load = function (name, ...args) {
        if (name === "../utils/firestoreTransaction") return {
            runTransaction: (database, label, handler) => database.runTransaction(handler),
            serverTimestamp: () => "now", increment: (value) => ({ increment: value }),
        };
        return originalLoad.call(this, name, ...args);
    };
    ({ settleSubmissionPayout } = require("./settleSubmission"));
} finally {
    Module._load = originalLoad;
}
(async () => {
    const assignment = { ...documents.get("task_assignments/assignment-1") };
    await settleSubmissionPayout(db, { submissionId: "submission-1", adminId: "reviewer-1", allowedStatuses: ["pending_admin_review"] });
    assert.deepEqual(documents.get("task_assignments/assignment-1"), assignment);
    assert.equal(documents.get("task_submissions/submission-1").status, "approved");
    assert.equal(documents.get("campaign_leads/lead-1").status, "approved");
    assert.equal(documents.get("campaign_leads/lead-1").approvedAt, "now");
    assert.equal(documents.get("campaign_leads/lead-1").approvedBy, "reviewer-1");
    assert.equal(documents.get("client_wallets/client-1").balance, 85);
    assert.equal(documents.get("worker_wallets/worker-1").balance, 10);
    assert.equal(documents.get("super_admin_wallet/main").balance, 5);
    await assert.rejects(settleSubmissionPayout(db, { submissionId: "submission-1", adminId: "reviewer-1", allowedStatuses: ["pending_admin_review"] }),
        (error) => error.code === "failed-precondition");
    for (const status of ["revoked", "out_of_tat_processing", "out_of_tat", "in_progress"]) {
        documents.set("task_submissions/submission-1", { status: "pending_admin_review", taskId: "task-1",
            userId: "worker-1", assignmentId: "assignment-1", leadId: "lead-1", payout: 10 });
        documents.set("task_assignments/assignment-1", { ...assignment, status, leadsProcessed: 2,
            tatDeadline: { toMillis: () => Date.now() - 1000 } });
        const workerBefore = { ...documents.get("worker_wallets/worker-1") };
        const adminBefore = documents.get("super_admin_wallet/main").balance;
        await settleSubmissionPayout(db, { submissionId: "submission-1", adminId: "reviewer-1", allowedStatuses: ["pending_admin_review"] });
        assert.deepEqual(documents.get("worker_wallets/worker-1"), workerBefore);
        assert.equal(documents.get("users/worker-1").walletBalance, 10);
        assert.equal(documents.get("super_admin_wallet/main").balance, adminBefore + 15);
        assert.equal(documents.get("task_submissions/submission-1").payoutRecipient, "super_admin");
        assert.equal(documents.get("earnings/seized_submission-1").amount, 10);
        await assert.rejects(settleSubmissionPayout(db, { submissionId: "submission-1", adminId: "reviewer-1",
            allowedStatuses: ["pending_admin_review"] }), (error) => error.code === "failed-precondition");
        assert.equal(documents.get("super_admin_wallet/main").balance, adminBefore + 15);
    }
    console.log("settlement preserves assignment lifecycle and payout checks passed");
})().catch((error) => { console.error(error); process.exitCode = 1; });