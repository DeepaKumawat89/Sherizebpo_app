const { URL } = require("node:url");

async function clientOwnsLeadRecording(db, uid, leadId, callId) {
    if (!uid || !leadId || !callId) return false;

    const leadSnap = await db.collection("campaign_leads").doc(leadId).get();
    if (!leadSnap.exists) return false;

    const leadData = leadSnap.data();
    if (!leadData.campaignId || leadData.callId !== callId) return false;

    const campaignSnap = await db.collection("campaigns").doc(leadData.campaignId).get();
    return campaignSnap.exists && campaignSnap.data().clientId === uid;
}

function isAllowedRecordingUrl(recordingUrl, provider, exotelSubdomain) {
    try {
        const parsedUrl = new URL(recordingUrl);
        if (parsedUrl.protocol !== "https:") return false;

        if (provider === "twilio") return parsedUrl.hostname === "api.twilio.com";

        const isExotelHost = parsedUrl.hostname === exotelSubdomain
            || parsedUrl.hostname.endsWith(".exotel.com");
        const isS3Host = /(^|\.)s3([.-][a-z0-9-]+)?\.amazonaws\.com$/.test(parsedUrl.hostname)
            || /\.s3([.-][a-z0-9-]+)?\.amazonaws\.com$/.test(parsedUrl.hostname);
        return isExotelHost || isS3Host;
    } catch {
        return false;
    }
}

function callStartMatchesResources(callData, assignmentData, leadData, requestData) {
    return callData.userId === requestData.userId
        && callData.taskId === requestData.taskId
        && callData.assignmentId === requestData.assignmentId
        && callData.leadId === requestData.leadId
        && callData.customerPhone === requestData.customerPhone
        && callData.status === "initiated"
        && !callData.exotelCallSid
        && assignmentData.userId === requestData.userId
        && assignmentData.taskId === requestData.taskId
        && ["active", "in_progress"].includes(assignmentData.status)
        && leadData.assignedTo === requestData.userId
        && leadData.taskId === requestData.taskId
        && leadData.status === "in_progress"
        && leadData.phone === requestData.customerPhone;
}

function twilioCallbackMatchesCall(callData, callbackData) {
    return callData.exotelCallSid === callbackData.callSid
        && callData.provider === "twilio"
        && callData.leadId === callbackData.leadId
        && callData.assignmentId === callbackData.assignmentId
        && callData.taskId === callbackData.taskId;
}

function leadAcceptsCallUpdate(leadData, callId) {
    return Boolean(callId) && (!leadData.callId || leadData.callId === callId);
}

module.exports = {
    clientOwnsLeadRecording,
    isAllowedRecordingUrl,
    callStartMatchesResources,
    twilioCallbackMatchesCall,
    leadAcceptsCallUpdate,
};