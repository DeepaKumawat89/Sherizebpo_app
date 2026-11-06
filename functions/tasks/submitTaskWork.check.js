const assert = require("node:assert");
const admin = require("firebase-admin");
// submitTaskWork.js calls admin.firestore() at load; a credential-less app is
// enough since the helper under test never touches Firestore.
if (!admin.apps.length) admin.initializeApp({ projectId: "demo-test" });
const { buildLeadCompletionUpdate } = require("./submitTaskWork");

const base = {
    userId: "worker-1",
    leadId: "lead-1",
    taskId: "task-1",
    assignmentId: "assignment-1",
};
const matchingCall = {
    userId: "worker-1",
    leadId: "lead-1",
    taskId: "task-1",
    assignmentId: "assignment-1",
    exotelCallSid: "SID123",
};

// Links the recording when the call belongs to this worker + lead and has a SID.
const linked = buildLeadCompletionUpdate({
    ...base,
    callId: "call-1",
    callData: matchingCall,
});
assert.strictEqual(linked.status, "completed");
assert.strictEqual(linked.callId, "call-1");
assert.ok(linked.recordingUrl.includes("callId=call-1"));

// No SID yet → do not link a recording that cannot be resolved.
assert.strictEqual(buildLeadCompletionUpdate({
    ...base,
    callId: "call-1",
    callData: { ...matchingCall, exotelCallSid: null },
}).callId, undefined);

// Call belongs to a different worker or lead → never cross-link.
assert.strictEqual(buildLeadCompletionUpdate({
    ...base,
    callId: "call-1",
    callData: { ...matchingCall, userId: "worker-2" },
}).recordingUrl, undefined);
assert.strictEqual(buildLeadCompletionUpdate({
    ...base,
    callId: "call-1",
    callData: { ...matchingCall, leadId: "other-lead" },
}).recordingUrl, undefined);
assert.strictEqual(buildLeadCompletionUpdate({
    ...base,
    callId: "call-1",
    callData: { ...matchingCall, taskId: "old-task" },
}).recordingUrl, undefined);
assert.strictEqual(buildLeadCompletionUpdate({
    ...base,
    callId: "call-1",
    callData: { ...matchingCall, assignmentId: "old-assignment" },
}).recordingUrl, undefined);

// No call reference (e.g. non-app submission) → plain completion.
assert.strictEqual(buildLeadCompletionUpdate({ ...base, callId: "", callData: null }).callId, undefined);

console.log("submitTaskWork lead completion checks passed");

// ── Handler regression: task_assignments date semantics (startedAt / completedAt) ──
// Runs the ACTUAL getTaskAssignmentProgress/submitTaskWork callables against an
// in-memory Firestore double (no real Firebase/emulator), the same technique used
// in assignEmployeeTask.check.js, to verify the new startedAt/completedAt writes.
(async () => {
    const Module = require("node:module");
    const documents = new Map();
    let nextId = 0;
    function collection(name, filters = [], limitValue = Infinity) {
        return {
            doc: (id = `date-check-${++nextId}`) => ({
                id,
                path: `${name}/${id}`,
                get: async () => ({ id, exists: documents.has(`${name}/${id}`), data: () => documents.get(`${name}/${id}`) }),
            }),
            where: (field, operator, value) => collection(name, [...filters, { field, operator, value }], limitValue),
            get: async () => {
                const docs = [...documents.entries()].filter(([path, data]) => path.startsWith(`${name}/`) &&
                    filters.every(({ field, operator, value }) => operator === "in"
                        ? value.includes(data[field]) : data[field] === value))
                    .slice(0, limitValue).map(([path, data]) => ({ id: path.split("/")[1], ref: { path }, data: () => data }));
                return { empty: docs.length === 0, size: docs.length, docs };
            },
        };
    }
    const fakeDb = {
        collection,
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
    const firestore = () => fakeDb;
    firestore.Timestamp = admin.firestore.Timestamp;
    firestore.FieldValue = admin.firestore.FieldValue;

    // submitTaskWork.js was already required above against the real (credential-less)
    // admin app; drop it from the cache so it re-executes `admin.firestore()` against
    // our fake db instead of the previously-captured real one.
    const modulePath = require.resolve("./submitTaskWork");
    const originalLoad = Module._load;
    delete require.cache[modulePath];
    let getTaskAssignmentProgress, submitTaskWork;
    try {
        Module._load = function (name, ...args) {
            if (name === "firebase-admin") return { firestore };
            return originalLoad.call(this, name, ...args);
        };
        ({ getTaskAssignmentProgress, submitTaskWork } = require("./submitTaskWork"));
    } finally {
        Module._load = originalLoad;
        delete require.cache[modulePath];
    }

    const seedBase = () => {
        documents.set("users/worker-1", { kycStatus: "approved", isActive: true });
        documents.set("tasks/task-1", { status: "active", campaignId: "campaign-1", payout: 10 });
        documents.set("campaigns/campaign-1", { status: "active", payout: 10 });
    };
    const context = { auth: { uid: "worker-1" } };

    // ── First claim: active assignment with no startedAt gets one stamped ──
    documents.clear();
    seedBase();
    documents.set("task_assignments/assignment-1", { taskId: "task-1", userId: "worker-1", status: "active", totalLeads: 5 });
    documents.set("campaign_leads/lead-1", { taskId: "task-1", campaignId: "campaign-1", status: "pending", assignedTo: null });
    const firstClaim = await getTaskAssignmentProgress.run({ assignmentId: "assignment-1", claimLead: true }, context);
    assert.ok(firstClaim.lead, "first claim should lock a lead");
    const afterFirstClaim = documents.get("task_assignments/assignment-1");
    assert.strictEqual(afterFirstClaim.status, "in_progress");
    assert.ok(afterFirstClaim.startedAt, "startedAt must be stamped on first claim while the assignment was active");
    assert.ok(documents.get("campaign_leads/lead-1").lockedAt);
    const originalLeadStart = admin.firestore.Timestamp.fromMillis(Date.now() - 30000);
    documents.get("campaign_leads/lead-1").lockedAt = originalLeadStart;

    // ── Repeated claim on the now in_progress assignment must not error and
    //    must not re-lose the lock (smoke check; strict preservation is proven
    //    below against a concrete, non-sentinel timestamp). ──
    const secondClaim = await getTaskAssignmentProgress.run({ assignmentId: "assignment-1", claimLead: true }, context);
    assert.ok(secondClaim.lead, "repeated claim should still return the locked lead");
    assert.strictEqual(documents.get("campaign_leads/lead-1").lockedAt, originalLeadStart,
        "fetching existing work must not move the lead start time forward");

    // ── Legacy-style assignment: startedAt already present as a real Timestamp
    //    (not the serverTimestamp sentinel) and processedLeadIds missing, which
    //    forces the recompute/update branch to run → the guard must still skip
    //    re-stamping startedAt. A real Timestamp lets us prove non-overwrite by
    //    reference, unlike the singleton serverTimestamp() sentinel. ──
    documents.clear();
    seedBase();
    const presetStartedAt = admin.firestore.Timestamp.fromMillis(Date.now() - 60000);
    documents.set("task_assignments/assignment-legacy", { taskId: "task-1", userId: "worker-1", status: "active",
        totalLeads: 5, startedAt: presetStartedAt });
    documents.set("campaign_leads/lead-legacy", { taskId: "task-1", campaignId: "campaign-1", status: "pending", assignedTo: null });
    const legacyClaim = await getTaskAssignmentProgress.run({ assignmentId: "assignment-legacy", claimLead: true }, context);
    assert.ok(legacyClaim.lead, "legacy assignment should still claim a lead");
    assert.strictEqual(documents.get("task_assignments/assignment-legacy").startedAt, presetStartedAt,
        "recompute path must preserve a pre-existing startedAt even though the update branch runs");

    // ── submitTaskWork: completedAt is stamped only on the submission that
    //    reaches totalLeads; the lead's lastOutcomeAt is written on every
    //    submission, independent of whether the assignment completes. ──
    documents.clear();
    seedBase();
    documents.set("task_assignments/assignment-submit", { taskId: "task-1", userId: "worker-1", status: "in_progress",
        totalLeads: 2, processedLeadIds: [], leadsProcessed: 0 });
    documents.set("campaign_leads/lead-a", { taskId: "task-1", campaignId: "campaign-1", status: "in_progress",
        assignedTo: "worker-1", activeAssignmentId: "assignment-submit" });
    documents.set("campaign_leads/lead-b", { taskId: "task-1", campaignId: "campaign-1", status: "in_progress",
        assignedTo: "worker-1", activeAssignmentId: "assignment-submit" });

    await submitTaskWork.run({ taskId: "task-1", assignmentId: "assignment-submit", leadId: "lead-a",
        outcome: "interested", callDuration: 20 }, context);
    const afterPartial = documents.get("task_assignments/assignment-submit");
    assert.strictEqual(afterPartial.status, "in_progress");
    assert.strictEqual(afterPartial.completedAt, undefined, "a partial (non-final-quota) submission must not stamp completedAt");
    assert.ok(documents.get("campaign_leads/lead-a").lastOutcomeAt,
        "lead outcome time is recorded on this submission even though the assignment has not completed");

    await submitTaskWork.run({ taskId: "task-1", assignmentId: "assignment-submit", leadId: "lead-b",
        outcome: "interested", callDuration: 20 }, context);
    const afterFinal = documents.get("task_assignments/assignment-submit");
    assert.strictEqual(afterFinal.status, "completed");
    assert.ok(afterFinal.completedAt, "the final-quota submission must stamp completedAt");
    assert.ok(documents.get("campaign_leads/lead-a").lastOutcomeAt,
        "the earlier lead's outcome time is unaffected by the assignment completing later");

    console.log("submitTaskWork date-semantics checks passed: first-claim startedAt, repeated-claim smoke, "
        + "legacy-recompute startedAt preservation, partial-vs-final completedAt, independent lead outcome time");
})().catch((error) => { console.error(error); process.exitCode = 1; });
