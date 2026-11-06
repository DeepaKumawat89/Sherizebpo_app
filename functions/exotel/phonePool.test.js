const { parsePhonePool, selectPhoneNumber } = require("./phonePool");

describe("Exotel phone pool", () => {
    test("uses the legacy single number when no pool is configured", () => {
        expect(parsePhonePool("", "04048956322")).toEqual(["04048956322"]);
        expect(parsePhonePool("   ", "04048956322")).toEqual(["04048956322"]);
    });

    test("parses and deduplicates comma-separated numbers", () => {
        expect(parsePhonePool(
            "04048956322, 04048956323,04048956322",
            "04000000000"
        )).toEqual(["04048956322", "04048956323"]);
    });

    test("ignores malformed pool entries and retains a valid fallback", () => {
        expect(parsePhonePool(
            "04048956322,not-a-phone,your_second_exophone",
            "04000000000"
        )).toEqual(["04048956322"]);
        expect(parsePhonePool("not-a-phone", "04000000000"))
            .toEqual(["04000000000"]);
    });

    test("selects a stable configured number for each call", () => {
        const pool = ["04048956322", "04048956323", "04048956324"];
        const selected = selectPhoneNumber(pool, "call-123");

        expect(pool).toContain(selected);
        expect(selectPhoneNumber(pool, "call-123")).toBe(selected);
    });

    test("returns an empty number when Exotel is not configured", () => {
        expect(selectPhoneNumber([], "call-123")).toBe("");
    });
});