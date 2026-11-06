/**
 * Standalone assert check (no test framework) for the reject/reassign decision.
 * Run: node earnings/leadRejection.check.js
 */
const assert = require("assert");
const { leadUpdateForRejection } = require("./leadRejection");

// Reject & reassign → lead waits until its selected marketplace return time.
const scheduled = leadUpdateForRejection(true, "scheduled-time");
assert.strictEqual(scheduled.status, "requeue_pending");
assert.strictEqual(scheduled.requeueAfter, "scheduled-time");
assert.strictEqual(scheduled.requeueReason, "qa_rejected");
assert.strictEqual(scheduled.requeueCount, 0);

// Reject only → lead is closed as "rejected", never re-listed to workers.
const closed = leadUpdateForRejection(false);
assert.strictEqual(closed.status, "rejected");
assert.ok(closed.rejectedAt, "final reject must stamp rejectedAt (client-visible decision date)");

assert.ok(scheduled.rejectedAt, "QA rejection must keep its decision date separately from the retry schedule");

// Both paths must release the worker lock so the lead is never stuck.
for (const reassign of [true, false]) {
    const update = leadUpdateForRejection(reassign, "scheduled-time");
    assert.strictEqual(update.assignedTo, null, "assignedTo must be cleared");
    assert.strictEqual(update.lockedAt, null, "lockedAt must be cleared");
}

console.log("leadRejection reassign check: OK");
