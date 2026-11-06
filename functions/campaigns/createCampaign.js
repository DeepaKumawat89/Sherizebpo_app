/**
 * createCampaign.js
 *
 * Callable Cloud Function: createCampaign
 *
 * Atomically RESERVES the campaign budget from the client's wallet at creation
 * time. This prevents a client from over-committing the same funds across many
 * campaigns and guarantees that workers can be paid for work done within the
 * reserved budget.
 *
 * Wallet accounting model:
 *   balance          = total money deposited and not yet spent
 *   reservedBalance  = portion of balance committed to active campaigns
 *   available        = balance - reservedBalance   (spendable for new campaigns)
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const db = admin.firestore();

function requireApprovedClient(snapshot) {
    if (!snapshot.exists
        || snapshot.data().kycStatus !== "approved"
        || snapshot.data().accountActive !== true) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Your client account must be approved and active before creating campaigns."
        );
    }
}

// Generate a short, human-friendly campaign code (CMP-XXXX) that is NOT the
// raw Firestore document ID, so internal IDs are never exposed to users.
// Uniqueness is verified against existing campaigns with bounded retries.
async function generateUniqueCampaignCode() {
    for (let i = 0; i < 8; i++) {
        const code = `CMP-${Math.floor(1000 + Math.random() * 9000)}`;
        const dup = await db.collection("campaigns").where("campaignCode", "==", code).limit(1).get();
        if (dup.empty) return code;
    }
    // ponytail: the 4-digit space (9000 codes) is nearly exhausted or we hit an
    // unlucky streak; widen to 6 digits to stay unique. Upgrade path: bump the
    // default width once campaign volume approaches a few thousand.
    return `CMP-${Math.floor(100000 + Math.random() * 900000)}`;
}

const createCampaign = functions
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "You must be logged in.");
        }
        const clientId = context.auth.uid;

        const title = data && typeof data.title === "string" ? data.title.trim() : "";
        const description = data && typeof data.description === "string" ? data.description.trim() : "";
        const payout = Number(data && data.payout);
        const budget = Number(data && data.budget);
        const startDate = data?.startDate ?? "";
        const endDate = data?.endDate ?? "";

        for (const [label, value] of [["Start date", startDate], ["End date", endDate]]) {
            if (value === "") continue;
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

        // ── Model A pricing (client markup) ────────────────────────
        // The super admin sets the platform commission % in
        // platform_settings/main. We SNAPSHOT it onto the campaign at creation
        // so the client's reserved budget always matches the price they agreed
        // to. Changing the % later affects only NEW campaigns.
        //   workerPayout       = payout (rate the worker earns — unchanged)
        //   clientPricePerLead = payout × (1 + commission%)  (what client pays)
        //   platform earns     = clientPrice − workerPayout   (the markup)
        // We also read clientPaymentsVisible: when the super admin has hidden
        // money from clients (closed-platform mode), campaigns are created with
        // NO price/budget and take no wallet reservation.
        let commissionRate = 10;
        let paymentsVisible = true;
        try {
            const cfgSnap = await db.collection("platform_settings").doc("main").get();
            if (cfgSnap.exists) {
                const cfg = cfgSnap.data();
                if (cfg.platformCommission != null) commissionRate = Number(cfg.platformCommission);
                if (cfg.clientPaymentsVisible === false) paymentsVisible = false;
            }
        } catch (cfgErr) {
            console.warn("[createCampaign] Could not read platform_settings; using defaults.", cfgErr.message);
        }
        if (!isFinite(commissionRate) || commissionRate < 0) commissionRate = 0;

        // ── Closed-platform mode ───────────────────────────────────
        // Client is billed offline (fixed per-agent), so the campaign carries no
        // price or budget and reserves nothing from the wallet. The super admin
        // can add pricing later via editCampaign. This lets clients keep creating
        // campaigns + uploading leads during the closed testing phase.
        if (!paymentsVisible) {
            const campaignRef = db.collection("campaigns").doc();
            const campaignCode = await generateUniqueCampaignCode();
            await db.runTransaction(async (txn) => {
                const clientSnapshot = await txn.get(db.collection("clients").doc(clientId));
                requireApprovedClient(clientSnapshot);
                txn.set(campaignRef, {
                    title,
                    name: title,
                    description,
                    clientId,
                    campaignCode,
                    startDate,
                    endDate,
                    payout: 0,
                    commissionRate,
                    clientPricePerLead: 0,
                    budget: 0,
                    reserved: 0,
                    spentAmount: 0,
                    leadCount: 0,
                    totalLeads: 0,
                    unpriced: true, // created without a price/budget (closed mode)
                    status: "active",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            });
            return { success: true, campaignId: campaignRef.id, campaignCode };
        }

        // ── Priced mode (payments visible) ─────────────────────────
        if (!isFinite(payout) || payout <= 0) {
            throw new functions.https.HttpsError("invalid-argument", "payout must be a positive number.");
        }
        if (!isFinite(budget) || budget <= 0) {
            throw new functions.https.HttpsError("invalid-argument", "budget must be a positive number.");
        }

        const clientPricePerLead = Number((payout * (1 + commissionRate / 100)).toFixed(2));

        if (clientPricePerLead > budget) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                `Client price per lead (₹${clientPricePerLead}, incl. ${commissionRate}% platform fee) cannot exceed the total budget (₹${budget}).`
            );
        }

        const campaignRef = db.collection("campaigns").doc();
        const campaignCode = await generateUniqueCampaignCode();

        await db.runTransaction(async (txn) => {
            const walletRef = db.collection("client_wallets").doc(clientId);
            const clientRef = db.collection("clients").doc(clientId);
            const [clientSnapshot, walletSnap] = await Promise.all([
                txn.get(clientRef),
                txn.get(walletRef),
            ]);
            requireApprovedClient(clientSnapshot);

            const balance = walletSnap.exists ? Number(walletSnap.data().balance || 0) : 0;
            const reserved = walletSnap.exists ? Number(walletSnap.data().reservedBalance || 0) : 0;
            const available = balance - reserved;

            if (available < budget) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    `Insufficient available balance. Available: ₹${available}, Required: ₹${budget}. Please top up your wallet.`
                );
            }

            // Reserve the budget (wallet must exist here since available >= budget > 0).
            txn.update(walletRef, {
                reservedBalance: reserved + budget,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            txn.set(campaignRef, {
                title,
                name: title,
                description,
                clientId,
                campaignCode,
                startDate,
                endDate,
                payout,
                commissionRate,
                clientPricePerLead,
                budget,
                reserved: budget, // funds held in the wallet for this campaign
                spentAmount: 0,
                leadCount: 0,
                totalLeads: 0,
                status: "active",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });

        return { success: true, campaignId: campaignRef.id, campaignCode };
    });

module.exports = { createCampaign };
