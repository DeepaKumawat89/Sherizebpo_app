/**
 * pricing.js — shared campaign pricing predicate.
 *
 * A "closed-platform" (unpriced) campaign is created with payout 0 (money hidden
 * from clients AND workers). A priced campaign always has payout > 0 (enforced by
 * createCampaign / editCampaign). So a zero/absent payout uniquely identifies the
 * closed, no-payout campaigns that are exempt from the worker-payout requirement.
 */
function isUnpricedCampaign(campaignData) {
    return Number((campaignData && campaignData.payout) || 0) <= 0;
}

module.exports = { isUnpricedCampaign };
