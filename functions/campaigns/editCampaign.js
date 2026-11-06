/**
 * editCampaign.js
 *
 * Callable Cloud Function: editCampaign
 *
 * Lets a campaign owner (or an admin) edit a campaign. The sensitive part is the
 * BUDGET: the difference between the old and new budget is atomically
 * re-reserved from — or released back to — the client's wallet so the campaign's
 * `reserved` (the settlement cap) and the wallet's `reservedBalance` never
 * drift. It also recomputes `clientPricePerLead` from the edited payout using
 * the campaign's snapshotted commission rate, so the upload budget-guard and
 * settlement always agree on the price.
 *
 * Reservation math (holds regardless of how much is already spent):
 *   wallet reservedBalance currently holds (oldReserved − spent) for this
 *   campaign. We want it to hold (newBudget − spent). The change is therefore
 *   simply (newBudget − oldReserved) = delta.  reservedBalance += delta.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const db = admin.firestore();

const editCampaign = functions
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "You must be logged in.");
        }
        const uid = context.auth.uid;
        const isAdmin = ["admin", "super_admin"].includes(context.auth.token.role);

        const campaignId = data && typeof data.campaignId === "string" ? data.campaignId.trim() : "";
        if (!campaignId) {
            throw new functions.https.HttpsError("invalid-argument", "campaignId is required.");
        }

        const title = data && typeof data.title === "string" ? data.title.trim() : "";
        const description = data && typeof data.description === "string" ? data.description.trim() : "";
        const payoutInput = data && data.payout;
        const budgetInput = data && data.budget;
        const payout = Number(payoutInput);
        const budget = Number(budgetInput);
        const startDate = data && data.startDate != null ? data.startDate : null;
        const endDate = data && data.endDate != null ? data.endDate : null;

        for (const [label, value] of [["Start date", startDate], ["End date", endDate]]) {
            if (value == null || value === "") continue;
            const parsed = typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)
                ? new Date(`${value}T00:00:00Z`) : new Date(NaN);
            if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
                throw new functions.https.HttpsError("invalid-argument", `${label} must be a valid date (YYYY-MM-DD).`);
            }
        }
        if (startDate && endDate && endDate < startDate) {
            throw new functions.https.HttpsError("invalid-argument", "End date cannot be before start date.");
        }

        if (!title) {
            throw new functions.https.HttpsError("invalid-argument", "Campaign title is required.");
        }
        if (title.length > 120 || description.length > 2000) {
            throw new functions.https.HttpsError("invalid-argument", "Campaign title or description is too long.");
        }
        const result = await db.runTransaction(async (txn) => {
            const campaignRef = db.collection("campaigns").doc(campaignId);
            const campaignSnap = await txn.get(campaignRef);
            if (!campaignSnap.exists) {
                throw new functions.https.HttpsError("not-found", "Campaign not found.");
            }
            const campaign = campaignSnap.data();

            // Only the owning client (or an admin) may edit.
            if (campaign.clientId !== uid && !isAdmin) {
                throw new functions.https.HttpsError("permission-denied", "You can only edit your own campaigns.");
            }
            if (!campaign.clientId) {
                throw new functions.https.HttpsError("failed-precondition", "Campaign has no owning client.");
            }
            if (!isAdmin) {
                const clientSnapshot = await txn.get(db.collection("clients").doc(uid));
                if (!clientSnapshot.exists
                    || clientSnapshot.data().kycStatus !== "approved"
                    || clientSnapshot.data().accountActive !== true) {
                    throw new functions.https.HttpsError(
                        "permission-denied",
                        "Your client account must be approved and active before editing campaigns."
                    );
                }
            }

            const existingUnpriced = campaign.unpriced === true
                || (Number(campaign.payout || 0) <= 0 && Number(campaign.budget || 0) <= 0);
            const pricingProvided = payoutInput != null && payoutInput !== ""
                && budgetInput != null && budgetInput !== "";
            if (!pricingProvided && existingUnpriced) {
                txn.update(campaignRef, {
                    title,
                    name: title,
                    description,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    ...(startDate != null ? { startDate } : {}),
                    ...(endDate != null ? { endDate } : {}),
                });
                return { clientPricePerLead: 0, reserved: 0, budget: 0, delta: 0 };
            }
            if (!isFinite(payout) || payout <= 0) {
                throw new functions.https.HttpsError("invalid-argument", "payout must be a positive number.");
            }
            if (!isFinite(budget) || budget <= 0) {
                throw new functions.https.HttpsError("invalid-argument", "budget must be a positive number.");
            }

            // Commission-inclusive price so the budget guard + settlement match
            // the edited payout. Reuse the campaign's snapshotted rate.
            let commissionRate = Number(campaign.commissionRate);
            if (!isFinite(commissionRate) || commissionRate < 0) commissionRate = 10;
            const clientPricePerLead = Number((payout * (1 + commissionRate / 100)).toFixed(2));

            if (clientPricePerLead > budget) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    `Client price per lead (₹${clientPricePerLead}, incl. ${commissionRate}% fee) cannot exceed the budget (₹${budget}).`
                );
            }

            const oldReserved = Number(campaign.reserved != null ? campaign.reserved : (campaign.budget || 0));
            const spent = Number(campaign.spentAmount || 0);

            // Can't set the budget below what's already been spent on approved leads.
            if (budget < spent - 0.01) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    `Budget (₹${budget}) cannot be lower than the amount already spent (₹${spent}).`
                );
            }

            const walletRef = db.collection("client_wallets").doc(campaign.clientId);
            const walletSnap = await txn.get(walletRef);
            const balance = walletSnap.exists ? Number(walletSnap.data().balance || 0) : 0;
            const reservedBalance = walletSnap.exists ? Number(walletSnap.data().reservedBalance || 0) : 0;
            const available = balance - reservedBalance;

            const delta = budget - oldReserved; // > 0 reserve more, < 0 release

            if (delta > 0.01) {
                if (!walletSnap.exists || available < delta) {
                    throw new functions.https.HttpsError(
                        "failed-precondition",
                        `Insufficient wallet balance to raise the budget. Available: ₹${available.toFixed(2)}, additional required: ₹${delta.toFixed(2)}. Please top up your wallet.`
                    );
                }
            }

            // ── WRITES ──
            if (walletSnap.exists && Math.abs(delta) > 0.001) {
                txn.update(walletRef, {
                    // Guard against dropping below zero on drifted data.
                    reservedBalance: Math.max(0, reservedBalance + delta),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            const update = {
                title,
                name: title,
                description,
                payout,
                budget,
                reserved: budget,
                clientPricePerLead,
                commissionRate,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (startDate != null) update.startDate = startDate;
            if (endDate != null) update.endDate = endDate;

            txn.update(campaignRef, update);

            return { clientPricePerLead, reserved: budget, budget, delta };
        });

        console.log(`[editCampaign] ${campaignId} edited by ${uid}: budget=₹${result.budget}, price=₹${result.clientPricePerLead}, reservationDelta=₹${result.delta}`);

        return { success: true, ...result };
    });

module.exports = { editCampaign };
