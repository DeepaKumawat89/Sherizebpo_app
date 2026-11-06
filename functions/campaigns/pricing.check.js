/**
 * Runnable check for isUnpricedCampaign.
 *   node campaigns/pricing.check.js
 */
const assert = require("assert");
const { isUnpricedCampaign } = require("./pricing");

// Priced campaigns are never exempt.
assert.strictEqual(isUnpricedCampaign({ payout: 50 }), false);
assert.strictEqual(isUnpricedCampaign({ payout: "50" }), false);

// Closed / unpriced campaigns (payout 0, missing, or non-numeric) are exempt.
assert.strictEqual(isUnpricedCampaign({ payout: 0, unpriced: true }), true);
assert.strictEqual(isUnpricedCampaign({}), true);
assert.strictEqual(isUnpricedCampaign(null), true);
assert.strictEqual(isUnpricedCampaign({ payout: "0" }), true);
assert.strictEqual(isUnpricedCampaign({ payout: -5 }), true);

console.log("pricing.check.js OK");
