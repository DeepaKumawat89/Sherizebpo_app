const { employeeIdCandidates, generateUniqueEmployeeId, idToEmail } = require("./employeeId");

describe("Employee ID helpers", () => {
    test("accepts four-digit Employee IDs with or without a hyphen", () => {
        expect(employeeIdCandidates("shr-4450")).toEqual(["SHR-4450", "SHR4450"]);
        expect(employeeIdCandidates("SHR4450")).toEqual(["SHR-4450", "SHR4450"]);
    });

    test("keeps older six-digit worker IDs login-compatible", () => {
        expect(employeeIdCandidates("SHR123456")).toEqual(["SHR123456", "SHR-123456"]);
    });

    test("rejects unrelated identifiers", () => {
        expect(employeeIdCandidates("EMP-1024")).toEqual([]);
    });

    test("maps an Employee ID to the internal Firebase login email", () => {
        expect(idToEmail("SHR-4450")).toBe("shr-4450@sherize.app");
    });

    test("retries collisions without widening beyond four digits", async () => {
        const get = jest.fn()
            .mockResolvedValue({ empty: true })
            .mockResolvedValueOnce({ empty: false });
        const db = {
            collection: jest.fn(() => ({
                where: jest.fn(() => ({
                    limit: jest.fn(() => ({ get })),
                })),
            })),
        };
        jest.spyOn(Math, "random")
            .mockReturnValueOnce(0)
            .mockReturnValueOnce(0.5);

        await expect(generateUniqueEmployeeId(db)).resolves.toBe("SHR-5500");
        expect(get).toHaveBeenCalledTimes(5);
        Math.random.mockRestore();
    });
});