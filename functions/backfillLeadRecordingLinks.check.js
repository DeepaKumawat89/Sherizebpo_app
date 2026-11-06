const assert = require("node:assert/strict");
const { buildRecordingLink } = require("./backfillLeadRecordingLinks");

const submission = {
  callSid: "SID123",
  userId: "worker-1",
  leadId: "lead-1",
  taskId: "task-1",
  assignmentId: "assignment-1",
};
const call = {
  exotelCallSid: "SID123",
  userId: "worker-1",
  leadId: "lead-1",
  taskId: "task-1",
  assignmentId: "assignment-1",
  duration: 42,
};
const lead = { taskId: "task-1" };

const linked = buildRecordingLink({ submission, callId: "call-1", call, lead });
assert.equal(linked.callId, "call-1");
assert.equal(linked.callDuration, 42);
assert.match(linked.recordingUrl, /callId=call-1$/);

assert.equal(buildRecordingLink({ submission, callId: "call-1", call, lead: { ...lead, callId: "new-call" } }), null);
assert.equal(buildRecordingLink({ submission, callId: "call-1", call: { ...call, userId: "other-worker" }, lead }), null);
assert.equal(buildRecordingLink({ submission, callId: "call-1", call: { ...call, taskId: "old-task" }, lead }), null);
assert.equal(buildRecordingLink({ submission, callId: "call-1", call: { ...call, assignmentId: "old-assignment" }, lead }), null);

console.log("backfillLeadRecordingLinks checks passed");