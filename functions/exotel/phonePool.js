const { createHash } = require("node:crypto");

function parsePhonePool(phoneNumbers, fallbackPhoneNumber) {
    const parseNumbers = (value) => [...new Set(
        String(value || "")
            .split(",")
            .map((phoneNumber) => phoneNumber.trim())
            .filter((phoneNumber) => /^\+?\d{8,15}$/.test(phoneNumber))
    )];
    const phonePool = parseNumbers(phoneNumbers);

    return phonePool.length > 0 ? phonePool : parseNumbers(fallbackPhoneNumber);
}

function selectPhoneNumber(phonePool, callId) {
    if (phonePool.length === 0) return "";

    const hash = createHash("sha256").update(String(callId)).digest();
    return phonePool[hash.readUInt32BE(0) % phonePool.length];
}

module.exports = { parsePhonePool, selectPhoneNumber };