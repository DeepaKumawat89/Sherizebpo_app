const assert = require("node:assert");
const Module = require("node:module");
const admin = require("firebase-admin");
const documents = new Map([
    ["users/manager-1", { role: "admin", isActive: true }],
    ["users/leader-1", { role: "team_leader", isActive: true, adminId: "ADM-1001", fullName: "Dispatch Leader" }],
    ["users/inactive-leader", { role: "team_leader", isActive: false }],
    ["tasks/task-1", { status: "pending_team_leader", totalLeads: 99, campaignId: "campaign-1" }],
    ["campaigns/campaign-1", { status: "active" }],
    ["users/worker-1", { role: "worker", kycStatus: "approved", teamLeaderId: "another-leader", bankAccount: "PRIVATE", aadhaarUrl: "PRIVATE" }],
    ["users/another-leader", { role: "team_leader", adminId: "ADM-2002", name: "Original Leader" }],
    ["task_assignments/worker-1_task-1", { taskId: "task-1", userId: "worker-1", status: "completed" }],
    ["campaign_leads/lead-1", { taskId: "task-1", status: "pending" }],
]);
let nextId = 0;
function collection(name, filters = [], limit = Infinity) {
    return {
        doc: (id = `retry-${++nextId}`) => ({
            id,
            path: `${name}/${id}`,
            get: async () => ({ id, exists: documents.has(`${name}/${id}`), data: () => documents.get(`${name}/${id}`) }),
        }),
        where: (field, operator, value) => collection(name, [...filters, { field, operator, value }], limit),
        limit: (value) => collection(name, filters, value),
        select: (...fields) => ({ get: async () => {
            const result = await collection(name, filters, limit).get();
            return { ...result, docs: result.docs.map((snapshot) => ({ ...snapshot,
                data: () => Object.fromEntries(Object.entries(snapshot.data()).filter(([key]) => fields.includes(key))),
            })) };
        } }),
        get: async () => {
            const docs = [...documents.entries()].filter(([path, data]) => path.startsWith(`${name}/`) &&
                filters.every(({ field, operator, value }) => operator === "in"
                    ? value.includes(data[field]) : data[field] === value))
                .slice(0, limit).map(([path, data]) => ({ id: path.split("/")[1], ref: { path }, data: () => data }));
            return { empty: docs.length === 0, size: docs.length, docs };
        },
        count: () => ({ get: async () => ({ data: () => ({ count: [...documents.entries()].filter(([path, data]) =>
            path.startsWith(`${name}/`) && filters.every(({ field, value }) => data[field] === value)).length }) }) }),
    };
}
const db = {
    collection,
    getAll: async (...refs) => Promise.all(refs.filter((ref) => !ref.fieldMask).map((ref) => ref.get())),
    runTransaction: async (handler) => {
        const writes = [];
        const result = await handler({
            get: (ref) => ref.get(),
            update: (ref, update) => writes.push(() => documents.set(ref.path, { ...documents.get(ref.path), ...update })),
            set: (ref, data) => writes.push(() => documents.set(ref.path, data)),
        });
        writes.forEach((write) => write());
        return result;
    },
};
const firestore = () => db;
firestore.Timestamp = admin.firestore.Timestamp;
firestore.FieldValue = admin.firestore.FieldValue;
const originalLoad = Module._load;
let assignmentPlan;
let assignEmployeeTask;
let getTaskAssignmentEmployees;
let getTeamLeaderEmployees;
let acceptMarketplaceTask;
let revokeTaskAssignment;
try {
    Module._load = function (name, ...args) {
        if (name === "firebase-admin") return { firestore };
        return originalLoad.call(this, name, ...args);
    };
    ({ assignmentPlan, assignEmployeeTask, getTaskAssignmentEmployees, getTeamLeaderEmployees } = require("./assignEmployeeTask"));
    ({ acceptMarketplaceTask } = require("./acceptMarketplaceTask"));
    ({ revokeTaskAssignment } = require("./revokeTaskAssignment"));
} finally {
    Module._load = originalLoad;
}

const plan = assignmentPlan({ status: "pending_team_leader", totalLeads: 11 }, 3);
assert.deepStrictEqual(plan.taskUpdate, {
    status: "active",
    distributionMode: "individual",
    totalSlots: 3,
    remainingSlots: 0,
    acceptedCount: 3,
});
assert.strictEqual(plan.quota, 4);

assert.throws(
    () => assignmentPlan({ status: "active", totalSlots: 1, acceptedCount: 0 }, 2),
    (error) => error.code === "failed-precondition"
);

(async () => {
    documents.set("users/outside-worker", { name: "  Sai  ", employeeId: " SHR-4049 ", phone: "PRIVATE", kycDocument: "PRIVATE" });
    documents.set("users/legacy-worker", { fullName: "Gayatri", workerId: "SHR-9002" });
    documents.set("task_assignments/outside-live", { userId: "outside-worker", status: "in_progress" });
    documents.set("task_assignments/own-history", { userId: "legacy-worker", status: "completed", assignedBy: "leader-1" });
    documents.set("task_assignments/private-history", { userId: "outside-worker", status: "completed", assignedBy: "another-leader" });
    documents.set("task_assignments/missing-user", { userId: "deleted-user", status: "active" });
    const employeeRequest = { assignmentIds: ["outside-live", "outside-live", "own-history", "private-history", "missing-user", "nonexistent"] };
    const leaderContext = { auth: { uid: "leader-1" } };
    assert.deepStrictEqual(await getTaskAssignmentEmployees.run(employeeRequest, leaderContext), { employees: [
        { assignmentId: "outside-live", employeeName: "Sai", employeeId: "SHR-4049" },
        { assignmentId: "own-history", employeeName: "Gayatri", employeeId: "SHR-9002", assignedByName: "Dispatch Leader", assignedByAdminId: "ADM-1001" },
        { assignmentId: "private-history", employeeName: "Sai", employeeId: "SHR-4049", assignedByName: "Original Leader", assignedByAdminId: "ADM-2002" },
        { assignmentId: "missing-user", employeeName: "", employeeId: "" },
    ] });
    assert.equal((await getTaskAssignmentEmployees.run({ assignmentIds: ["private-history"] }, leaderContext)).employees.length, 1);
    assert.equal((await getTaskAssignmentEmployees.run({ assignmentIds: ["private-history"] }, { auth: { uid: "manager-1" } })).employees.length, 1);
    for (const uid of ["worker-1", "inactive-leader", "missing-manager"]) {
        await assert.rejects(getTaskAssignmentEmployees.run(employeeRequest, { auth: { uid } }),
            (error) => error.code === "permission-denied");
    }
    await assert.rejects(getTaskAssignmentEmployees.run(employeeRequest, {}), (error) => error.code === "unauthenticated");
    for (const assignmentIds of [[], [""], ["users/outside-worker"], ["."], [7], Array(51).fill("outside-live")]) {
        await assert.rejects(getTaskAssignmentEmployees.run({ assignmentIds }, leaderContext),
            (error) => error.code === "invalid-argument");
    }
    documents.set("users/outside-worker", { name: "outside-worker", workerId: "outside-worker" });
    assert.deepStrictEqual(await getTaskAssignmentEmployees.run({ assignmentIds: ["outside-live"] }, leaderContext), {
        employees: [{ assignmentId: "outside-live", employeeName: "", employeeId: "" }],
    });
    console.log("assignment employee labels passed: bounded authorized lookup, legacy codes, missing users, no private fields or UID labels");
    const roster = await getTeamLeaderEmployees.run({}, leaderContext);
    assert.equal(roster.employees.length, 1);
    assert.equal(roster.employees[0].id, "worker-1");
    assert.equal(roster.employees[0].creatorAdminId, "ADM-2002");
    assert.equal(roster.employees[0].creatorName, "Original Leader");
    assert.equal(roster.employees[0].bankAccount, undefined);
    assert.equal(roster.employees[0].aadhaarUrl, undefined);
    await assert.rejects(getTeamLeaderEmployees.run({}, {}), (error) => error.code === "unauthenticated");
    for (const uid of ["worker-1", "inactive-leader", "missing-manager"]) {
        await assert.rejects(getTeamLeaderEmployees.run({}, { auth: { uid } }), (error) => error.code === "permission-denied");
    }
    console.log("shared roster passed: cross-team visibility, creator ADM attribution, private-field exclusion and unauthorized denials");
    const previous = { ...documents.get("task_assignments/worker-1_task-1") };
    for (const uid of ["worker-1", "inactive-leader", "missing-manager"]) {
        await assert.rejects(assignEmployeeTask.run({ taskId: "task-1", employeeUids: ["worker-1"] }, { auth: { uid } }),
            (error) => error.code === "permission-denied");
    }
    const result = await assignEmployeeTask.run(
        { taskId: "task-1", employeeUids: ["worker-1"] },
        leaderContext
    );
    assert.equal(result.success, true);
    assert.notEqual(result.assignmentIds[0], "worker-1_task-1");
    assert.deepStrictEqual(documents.get("task_assignments/worker-1_task-1"), previous);
    const nextAssignment = documents.get(`task_assignments/${result.assignmentIds[0]}`);
    assert.equal(nextAssignment.status, "active");
    assert.equal(nextAssignment.totalLeads, 1);
    assert.equal(nextAssignment.leadsProcessed, 0);
    assert.deepStrictEqual(nextAssignment.processedLeadIds, []);
    assert.equal(nextAssignment.taskId, "task-1");
    assert.equal(nextAssignment.assignedBy, "leader-1");
    assert.equal(nextAssignment.assignedByAdminId, "ADM-1001");
    assert.equal(nextAssignment.assignedByName, "Dispatch Leader");
    assert.equal(documents.get("tasks/task-1").status, "active");
    await assert.rejects(assignEmployeeTask.run(
        { taskId: "task-1", employeeUids: ["worker-1"] }, { auth: { uid: "manager-1" } }
    ), (error) => error.code === "failed-precondition");
    documents.set("tasks/task-1", { status: "active", distributionMode: "marketplace", campaignId: "campaign-1", totalSlots: 2, acceptedCount: 99 });
    documents.get(`task_assignments/${result.assignmentIds[0]}`).status = "completed";
    const accepted = await acceptMarketplaceTask.run({ taskId: "task-1", userId: "spoofed" }, { auth: { uid: "worker-1" } });
    assert.equal(accepted.acceptedCount, 1, "Use live capacity, not a stale stored count");
    assert.equal(documents.get(`task_assignments/${accepted.assignmentId}`).userId, "worker-1");
    assert.equal(documents.get(`task_assignments/${accepted.assignmentId}`).totalLeads, 1);
    for (const status of ["active", "in_progress", "out_of_tat_processing"]) {
        documents.get(`task_assignments/${accepted.assignmentId}`).status = status;
        await assert.rejects(acceptMarketplaceTask.run({ taskId: "task-1" }, { auth: { uid: "worker-1" } }),
            (error) => error.code === "already-exists");
    }
    documents.set("users/worker-2", { kycStatus: "approved" });
    documents.get("tasks/task-1").totalSlots = 1;
    await assert.rejects(acceptMarketplaceTask.run({ taskId: "task-1" }, { auth: { uid: "worker-2" } }),
        (error) => error.code === "resource-exhausted");
    documents.get("tasks/task-1").totalSlots = 2;
    documents.get("campaigns/campaign-1").status = "paused";
    await assert.rejects(acceptMarketplaceTask.run({ taskId: "task-1" }, { auth: { uid: "worker-2" } }),
        (error) => error.code === "failed-precondition");
    documents.get("campaigns/campaign-1").status = "active";
    documents.get("users/worker-2").kycStatus = "pending";
    await assert.rejects(acceptMarketplaceTask.run({ taskId: "task-1" }, { auth: { uid: "worker-2" } }),
        (error) => error.code === "permission-denied");
    await assert.rejects(acceptMarketplaceTask.run({ taskId: "task-1" }, {}), (error) => error.code === "unauthenticated");
    const historical = { ...documents.get("task_assignments/worker-1_task-1") };
    documents.get(`task_assignments/${accepted.assignmentId}`).status = "in_progress";
    documents.get("campaign_leads/lead-1").assignedTo = "worker-1";
    documents.get("campaign_leads/lead-1").status = "in_progress";
    documents.set("campaign_leads/finished", { taskId: "task-1", assignedTo: "worker-1", status: "approved" });
    const revokeData = { taskId: "task-1", employeeUid: "worker-1", assignmentId: accepted.assignmentId };
    await assert.rejects(revokeTaskAssignment.run(revokeData, {}), (error) => error.code === "unauthenticated");
    for (const uid of ["worker-1", "inactive-leader"]) {
        await assert.rejects(revokeTaskAssignment.run(revokeData, { auth: { uid } }),
            (error) => error.code === "permission-denied");
    }
    await assert.rejects(revokeTaskAssignment.run({ ...revokeData, assignmentId: "worker-1_task-1" },
        { auth: { uid: "leader-1" } }), (error) => error.code === "failed-precondition");
    assert.equal(documents.get(`task_assignments/${accepted.assignmentId}`).status, "in_progress");
    const revoked = await revokeTaskAssignment.run(revokeData, { auth: { uid: "leader-1" } });
    assert.equal(revoked.released, 1);
    assert.equal(revoked.kept, 1);
    assert.deepStrictEqual(documents.get("task_assignments/worker-1_task-1"), historical);
    assert.equal(documents.get(`task_assignments/${accepted.assignmentId}`).status, "revoked");
    assert.equal(documents.get(`task_assignments/${accepted.assignmentId}`).revokedBy, "leader-1");
    assert.equal(documents.get("campaign_leads/finished").status, "approved");
    assert.equal(documents.get("campaign_leads/lead-1").status, "pending");
    assert.equal(documents.get("campaign_leads/lead-1").taskId, "task-1");
    await assert.rejects(revokeTaskAssignment.run(revokeData, { auth: { uid: "leader-1" } }),
        (error) => error.code === "failed-precondition");
    console.log("employee reassignment and marketplace acceptance checks passed");
})().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});