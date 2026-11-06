const { callStartMatchesResources } = require("../recordings/recordingAccess");

async function claimCallStart(
    db,
    callRef,
    assignmentData,
    leadData,
    requestData,
    provider,
    exotelPhoneNumber
) {
    return db.runTransaction(async (txn) => {
        const callDoc = await txn.get(callRef);
        if (!callDoc.exists || !callStartMatchesResources(
            callDoc.data(), assignmentData, leadData, requestData
        )) {
            return false;
        }

        // ponytail: Do not auto-expire this claim; without provider idempotency,
        // retrying an uncertain request could create a second paid call.
        const claimData = { provider, status: "starting" };
        if (exotelPhoneNumber) claimData.exotelPhoneNumber = exotelPhoneNumber;
        txn.update(callRef, claimData);
        return true;
    });
}

module.exports = { claimCallStart };