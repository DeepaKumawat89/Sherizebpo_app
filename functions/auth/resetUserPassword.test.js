const mockUpdateUser = jest.fn();
const mockTargetGet = jest.fn();
const mockTargetSet = jest.fn();
const mockValidateActiveManager = jest.fn();

const mockDb = {
    collection: jest.fn(() => ({
        doc: jest.fn(() => ({
            get: mockTargetGet,
            set: mockTargetSet,
        })),
    })),
};

jest.mock("firebase-admin", () => ({
    firestore: jest.fn(() => mockDb),
    auth: jest.fn(() => ({ updateUser: mockUpdateUser })),
}));

jest.mock("firebase-functions/v1", () => ({
    https: {
        onCall: jest.fn((handler) => handler),
        HttpsError: class HttpsError extends Error {
            constructor(code, message) {
                super(message);
                this.code = code;
            }
        },
    },
}));

jest.mock("../utils/teamLeaderAccess", () => ({
    validateActiveManager: mockValidateActiveManager,
}));

const { resetUserPassword } = require("./resetUserPassword");

describe("resetUserPassword", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockTargetSet.mockResolvedValue(undefined);
        mockUpdateUser.mockResolvedValue(undefined);
    });

    test("synchronizes a worker's Auth email with their Employee ID", async () => {
        mockValidateActiveManager.mockResolvedValue({ isPlatformAdmin: false });
        mockTargetGet.mockResolvedValue({
            exists: true,
            data: () => ({
                role: "worker",
                teamLeaderId: "another-leader",
                employeeId: "SHR-4049",
                email: "legacy@example.com",
            }),
        });

        await resetUserPassword(
            { uid: "worker-uid", newPassword: "NewPassword7!" },
            { auth: { uid: "leader-uid" } },
        );

        expect(mockUpdateUser).toHaveBeenCalledWith("worker-uid", {
            password: "NewPassword7!",
            email: "shr-4049@sherize.app",
            emailVerified: true,
        });
        expect(mockTargetSet).toHaveBeenCalledWith({
            email: "shr-4049@sherize.app",
            loginEmail: "shr-4049@sherize.app",
        }, { merge: true });
    });

    test.each([
        { role: "admin" },
        { role: "team_leader" },
        { role: "client" },
        { role: "worker", roles: ["worker", "super_admin"] },
        { role: "worker", roles: ["support_admin"] },
    ])("denies team-leader resets of privileged targets: %j", async (target) => {
        mockValidateActiveManager.mockResolvedValue({ isPlatformAdmin: false });
        mockTargetGet.mockResolvedValue({ exists: true, data: () => target });
        await expect(resetUserPassword(
            { uid: "target", newPassword: "NewPassword7!" },
            { auth: { uid: "leader-uid" } },
        )).rejects.toMatchObject({ code: "permission-denied" });
        expect(mockUpdateUser).not.toHaveBeenCalled();
    });

    test("denies unauthenticated callers", async () => {
        await expect(resetUserPassword({}, {})).rejects.toMatchObject({ code: "unauthenticated" });
        expect(mockUpdateUser).not.toHaveBeenCalled();
    });

    test("preserves active-manager denial before modifying Auth", async () => {
        mockValidateActiveManager.mockRejectedValue({ code: "permission-denied" });
        await expect(resetUserPassword(
            { uid: "worker-uid", newPassword: "NewPassword7!" },
            { auth: { uid: "inactive-leader" } },
        )).rejects.toMatchObject({ code: "permission-denied" });
        expect(mockUpdateUser).not.toHaveBeenCalled();
    });

    test("keeps administrator resets password-only", async () => {
        mockValidateActiveManager.mockResolvedValue({ isPlatformAdmin: true });
        mockTargetGet.mockResolvedValue({
            exists: true,
            data: () => ({ role: "admin" }),
        });

        await resetUserPassword(
            { uid: "admin-uid", newPassword: "NewPassword7!" },
            { auth: { uid: "super-admin-uid" } },
        );

        expect(mockUpdateUser).toHaveBeenCalledWith("admin-uid", {
            password: "NewPassword7!",
        });
        expect(mockTargetSet).not.toHaveBeenCalled();
    });
});