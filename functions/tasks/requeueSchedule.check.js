const assert = require("node:assert/strict");
const {
	parseRequeueAt,
	MIN_REQUEUE_DELAY_MS,
	MAX_REQUEUE_DELAY_MS,
} = require("./requeueSchedule");

const now = 1_700_000_000_000;
assert.equal(
	parseRequeueAt(now + MIN_REQUEUE_DELAY_MS, now),
	now + MIN_REQUEUE_DELAY_MS
);
assert.equal(
	parseRequeueAt(now + MAX_REQUEUE_DELAY_MS, now),
	now + MAX_REQUEUE_DELAY_MS
);
assert.throws(
	() => parseRequeueAt(now + MIN_REQUEUE_DELAY_MS - 1, now),
	/at least 1 minute/i
);
assert.throws(
	() => parseRequeueAt(now + MAX_REQUEUE_DELAY_MS + 1, now),
	/365 days/i
);
assert.throws(() => parseRequeueAt("not-a-time", now), /at least 1 minute/i);

console.log("requeue schedule check: OK");