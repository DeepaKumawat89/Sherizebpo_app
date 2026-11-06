const assert = require("node:assert/strict");
const Module = require("node:module");

let task = {
    status: "active",
    distributionMode: "individual",
    totalSlots: 1,
    acceptedCount: 1,
    remainingSlots: 0,
    totalLeads: 0,
};
let pendingCount = 1;
let occupiedCount = 0;
let writes = 0;
const taskRef = {
    get: async () => ({ exists: true, data: () => ({ ...task }) }),
    update: async (update) => { writes++; Object.assign(task, update); },
};
const db = {
    runTransaction: async (handler) => handler({
        get: (ref) => ref.get(),
        update: (ref, update) => ref.update(update),
    }),
    collection(name) {
        if (name === "tasks") return { doc: () => taskRef };
        if (["campaign_leads", "task_assignments"].includes(name)) {
            const query = {
                where: () => query,
                count: () => ({ get: async () => ({ data: () => ({
                    count: name === "campaign_leads" ? pendingCount : occupiedCount,
                }) }) }),
            };
            return query;
        }
        throw new Error(`Unexpected collection: ${name}`);
    },
};
const firestore = () => db;
firestore.FieldValue = { serverTimestamp: () => "now" };
const originalLoad = Module._load;
let syncTaskLeadCounts;
let syncTaskAssignmentAvailability;
let reconcileTaskAvailability;
try {
    Module._load = function (name, ...args) {
        if (name === "firebase-admin") return { firestore };
        if (name === "firebase-functions/v1") {
            return { firestore: { document: () => ({ onWrite: (handler) => handler }) } };
        }
        return originalLoad.call(this, name, ...args);
    };
    ({ syncTaskLeadCounts, syncTaskAssignmentAvailability, reconcileTaskAvailability } = require("./syncTaskLeadCounts"));
} finally {
    Module._load = originalLoad;
}

(async () => {
    await syncTaskLeadCounts({
        before: { exists: true, data: () => ({ taskId: "task-1", status: "requeue_pending" }) },
        after: { exists: true, data: () => ({ taskId: "task-1", status: "pending" }) },
    });
    assert.equal(task.totalLeads, 1);
    assert.equal(task.status, "pending_team_leader",
        "A returned individual lead with no live assignment must reappear for team-leader distribution");
    assert.equal(task.acceptedCount, 0);
    assert.equal(task.distributionMode, "individual");
    const firstWrites = writes;
    await reconcileTaskAvailability(db, "task-1");
    assert.equal(writes, firstWrites, "Repeated reconciliation must be idempotent");

    task = { status: "active", distributionMode: "marketplace", totalSlots: 2, acceptedCount: 2 };
    await reconcileTaskAvailability(db, "task-1");
    assert.equal(task.acceptedCount, 0);
    assert.equal(task.remainingSlots, 2);
    assert.equal(task.status, "active");

    occupiedCount = 1;
    task = { status: "active", distributionMode: "individual", totalSlots: 2 };
    await reconcileTaskAvailability(db, "task-1");
    assert.equal(task.status, "active", "Do not redistribute an individual task still being worked");
    assert.equal(task.acceptedCount, 1);
    assert.equal(task.remainingSlots, 0);

    for (const status of ["paused", "completed", "cancelled", "pending_team_leader"]) {
        task = { status, distributionMode: "individual", acceptedCount: 2 };
        await reconcileTaskAvailability(db, "task-1");
        assert.equal(task.status, status, "Never reopen explicitly inactive or unpublished work");
        assert.equal(task.acceptedCount, 2);
    }

    occupiedCount = 0;
    pendingCount = 0;
    task = { status: "active", distributionMode: "individual", totalSlots: 1 };
    await reconcileTaskAvailability(db, "task-1");
    assert.equal(task.status, "active", "Do not put empty tasks in the team-leader queue");

    pendingCount = 1;
    task = { status: "active", distributionMode: "individual", totalSlots: 1 };
    await syncTaskLeadCounts({
        before: { exists: false },
        after: { exists: true, data: () => ({ taskId: "task-1", status: "pending" }) },
    });
    assert.equal(task.status, "pending_team_leader");
    for (const finalStatus of ["completed", "out_of_tat", null]) {
        task = { status: "active", distributionMode: "individual", acceptedCount: 1 };
        await syncTaskAssignmentAvailability({
            before: { exists: true, data: () => ({ taskId: "task-1", status: "in_progress" }) },
            after: { exists: !!finalStatus, data: () => ({ taskId: "task-1", status: finalStatus }) },
        });
        assert.equal(task.status, "pending_team_leader");
        assert.equal(task.acceptedCount, 0);
    }
    console.log("task lead recovery checks passed");
})().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});