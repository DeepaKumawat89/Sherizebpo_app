const { claimCallStart } = require("./claimCallStart");

describe("claimCallStart", () => {
    test("claims a call once and stores its ExoPhone before dialing", async () => {
        const requestData = {
            userId: "worker-1",
            taskId: "task-1",
            assignmentId: "assignment-1",
            leadId: "lead-1",
            customerPhone: "09876543210",
        };
        const assignmentData = {
            userId: "worker-1",
            taskId: "task-1",
            status: "active",
        };
        const leadData = {
            assignedTo: "worker-1",
            taskId: "task-1",
            status: "in_progress",
            phone: "09876543210",
        };
        const callData = {
            ...requestData,
            status: "initiated",
            exotelCallSid: null,
        };
        const callRef = { id: "call-1" };
        const txn = {
            get: jest.fn(async () => ({
                exists: true,
                data: () => ({ ...callData }),
            })),
            update: jest.fn((ref, updateData) => Object.assign(callData, updateData)),
        };
        const db = {
            runTransaction: jest.fn((operation) => operation(txn)),
        };

        await expect(claimCallStart(
            db,
            callRef,
            assignmentData,
            leadData,
            requestData,
            "exotel",
            "04048956322"
        )).resolves.toBe(true);
        expect(txn.update).toHaveBeenCalledWith(callRef, {
            provider: "exotel",
            status: "starting",
            exotelPhoneNumber: "04048956322",
        });

        await expect(claimCallStart(
            db,
            callRef,
            assignmentData,
            leadData,
            requestData,
            "exotel",
            "04048956322"
        )).resolves.toBe(false);
        expect(txn.update).toHaveBeenCalledTimes(1);
    });
});