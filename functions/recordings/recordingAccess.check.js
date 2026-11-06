const assert = require("node:assert/strict");
const {
    clientOwnsLeadRecording,
    isAllowedRecordingUrl,
    callStartMatchesResources,
    twilioCallbackMatchesCall,
    leadAcceptsCallUpdate,
} = require("./recordingAccess");

function fakeDb(documents) {
    return {
        collection: (collectionName) => ({
            doc: (documentId) => ({
                get: async () => {
                    const data = documents[`${collectionName}/${documentId}`];
                    return { exists: Boolean(data), data: () => data };
                },
            }),
        }),
    };
}

async function run() {
    const db = fakeDb({
        "campaign_leads/lead-1": { campaignId: "campaign-1", callId: "call-1" },
        "campaign_leads/orphan-lead": { campaignId: "missing-campaign", callId: "call-2" },
        "campaign_leads/unlinked-lead": { campaignId: "campaign-1" },
        "campaigns/campaign-1": { clientId: "client-1" },
    });

    assert.equal(await clientOwnsLeadRecording(db, "client-1", "lead-1", "call-1"), true);
    assert.equal(await clientOwnsLeadRecording(db, "client-2", "lead-1", "call-1"), false);
    assert.equal(await clientOwnsLeadRecording(db, "client-1", "lead-1", "other-call"), false);
    assert.equal(await clientOwnsLeadRecording(db, "client-1", "unlinked-lead", "call-1"), false);
    assert.equal(await clientOwnsLeadRecording(db, "client-1", "missing-lead", "call-1"), false);
    assert.equal(await clientOwnsLeadRecording(db, "client-1", "orphan-lead", "call-2"), false);
    assert.equal(await clientOwnsLeadRecording(db, "client-1", null, "call-1"), false);

    assert.equal(isAllowedRecordingUrl("https://api.in.exotel.com/recording.mp3", "exotel", "api.in.exotel.com"), true);
    assert.equal(isAllowedRecordingUrl("https://s3-ap-southeast-1.amazonaws.com/bucket/recording.mp3", "exotel", "api.in.exotel.com"), true);
    assert.equal(isAllowedRecordingUrl("https://bucket.s3.ap-south-1.amazonaws.com/recording.mp3", "exotel", "api.in.exotel.com"), true);
    assert.equal(isAllowedRecordingUrl("https://api.twilio.com/recording.mp3", "twilio", "api.in.exotel.com"), true);
    assert.equal(isAllowedRecordingUrl("https://api.twilio.com.evil.example/recording.mp3", "twilio", "api.in.exotel.com"), false);
    assert.equal(isAllowedRecordingUrl("http://api.in.exotel.com/recording.mp3", "exotel", "api.in.exotel.com"), false);
    assert.equal(isAllowedRecordingUrl("https://169.254.169.254/metadata", "exotel", "api.in.exotel.com"), false);

    const requestData = {
        userId: "worker-1", taskId: "task-1", assignmentId: "assignment-1",
        leadId: "lead-1", customerPhone: "9999999999",
    };
    const callData = { ...requestData, status: "initiated", exotelCallSid: null };
    const assignmentData = { userId: "worker-1", taskId: "task-1", status: "active" };
    const leadData = { assignedTo: "worker-1", taskId: "task-1", status: "in_progress", phone: "9999999999" };
    assert.equal(callStartMatchesResources(callData, assignmentData, leadData, requestData), true);
    assert.equal(callStartMatchesResources(callData, { ...assignmentData, status: "in_progress" }, leadData, requestData), true);
    assert.equal(callStartMatchesResources(callData, { ...assignmentData, status: "completed" }, leadData, requestData), false);
    assert.equal(callStartMatchesResources({ ...callData, leadId: "other-lead" }, assignmentData, leadData, requestData), false);
    assert.equal(callStartMatchesResources(callData, assignmentData, { ...leadData, assignedTo: "other-worker" }, requestData), false);
    assert.equal(callStartMatchesResources({ ...callData, exotelCallSid: "already-started" }, assignmentData, leadData, requestData), false);

    const callbackData = { callSid: "CA123", leadId: "lead-1", assignmentId: "assignment-1", taskId: "task-1" };
    const twilioCall = { exotelCallSid: "CA123", provider: "twilio", leadId: "lead-1", assignmentId: "assignment-1", taskId: "task-1" };
    assert.equal(twilioCallbackMatchesCall(twilioCall, callbackData), true);
    assert.equal(twilioCallbackMatchesCall(twilioCall, { ...callbackData, callSid: "CA999" }), false);
    assert.equal(twilioCallbackMatchesCall({ ...twilioCall, leadId: "other-lead" }, callbackData), false);

    assert.equal(leadAcceptsCallUpdate({}, "call-1"), true);
    assert.equal(leadAcceptsCallUpdate({ callId: "call-1" }, "call-1"), true);
    assert.equal(leadAcceptsCallUpdate({ callId: "newer-call" }, "old-call"), false);
    assert.equal(leadAcceptsCallUpdate({}, ""), false);

    console.log("recordingAccess.check.js: all checks passed");
}

run().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});