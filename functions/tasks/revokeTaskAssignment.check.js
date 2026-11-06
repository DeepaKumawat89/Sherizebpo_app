const assert = require("node:assert/strict");
const admin = require("firebase-admin");
// revokeTaskAssignment.js calls admin.firestore() lazily inside the handler, but
// the module loads fine without credentials since we only test the pure helpers.
if (!admin.apps.length) admin.initializeApp({ projectId: "demo-test" });
const { shouldReleaseLead, buildLeadReleaseUpdate } = require("./revokeTaskAssignment");

// Unfinished work the employee still holds → released back to the pool.
assert.equal(shouldReleaseLead({ status: "pending" }), true);
assert.equal(shouldReleaseLead({ status: "assigned" }), true);
assert.equal(shouldReleaseLead({ status: "in_progress" }), true);
assert.equal(shouldReleaseLead({ status: "requeue_pending" }), false);
assert.equal(shouldReleaseLead({ status: "IN_PROGRESS" }), true);

// Finished work → preserved so it is never reworked after a revoke.
assert.equal(shouldReleaseLead({ status: "completed" }), false);
assert.equal(shouldReleaseLead({ status: "approved" }), false);
assert.equal(shouldReleaseLead({ status: "rejected" }), false);
assert.equal(shouldReleaseLead({ status: "wrong_number" }), false);
assert.equal(shouldReleaseLead({ status: "unreachable" }), false);

const release = buildLeadReleaseUpdate();
assert.equal(release.status, "pending");
assert.equal(release.assignedTo, null);
assert.equal(release.lockedAt, null);

console.log("revokeTaskAssignment checks passed");
