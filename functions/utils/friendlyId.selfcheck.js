/**
 * friendlyId.selfcheck.js
 *
 * Minimal assert-based check for the pure code generator (no Firestore needed).
 * Run: node utils/friendlyId.selfcheck.js
 */
const assert = require("assert");
const { generateFriendlyId } = require("./friendlyId");

// Default width = 4 digits: PREFIX-1234
for (let i = 0; i < 1000; i++) {
    assert.match(generateFriendlyId("TSK"), /^TSK-\d{4}$/, "default width must be 4 digits");
}

// Explicit width = 6 digits: PREFIX-123456
for (let i = 0; i < 1000; i++) {
    assert.match(generateFriendlyId("PAY", 6), /^PAY-\d{6}$/, "width=6 must be 6 digits");
}

// Prefix is respected.
assert.ok(generateFriendlyId("ADM").startsWith("ADM-"), "prefix must be preserved");

console.log("friendlyId self-check passed");
