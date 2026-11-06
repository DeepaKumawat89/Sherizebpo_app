const assert = require("node:assert");
const { buildDistributionUpdate } = require("./updateTaskDistribution");

const timestamp = { seconds: 123 };
const published = buildDistributionUpdate(
    { status: "pending_team_leader" },
    "publish",
    "leader-1",
    timestamp
);
assert.strictEqual(published.status, "active");
assert.strictEqual(published.distributionMode, "marketplace");
assert.strictEqual(published.publishedByTeamLeaderId, "leader-1");
assert.strictEqual(published.remainingSlots, 1);
const republished = buildDistributionUpdate(
    { status: "pending_team_leader", distributionMode: "individual", totalSlots: 3, acceptedCount: 0, remainingSlots: 0 },
    "publish", "leader-1", timestamp
);
assert.strictEqual(republished.remainingSlots, 3);
assert.strictEqual(republished.distributionMode, "marketplace");

console.log("task distribution checks passed");