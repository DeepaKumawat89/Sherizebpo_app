/**
 * syncCampaignLeadCounts.js
 *
 * Callable Cloud Function: syncCampaignLeadCounts({ campaignId })
 *
 * Recomputes a campaign's true lead count from the campaign_leads collection
 * and pushes it onto both the campaign document and its worker-facing task, so
 * the marketplace's "per worker" quota and the campaign completion % always
 * reflect reality.
 *
 * WHY THIS EXISTS: leads can be added through several paths (the sheet-ingest
 * Cloud Function, the client portal's direct batch write, and the super admin
 * portal). Only the sheet-ingest path used to sync task.totalLeads, so leads
 * added by the other paths left the task's count stale. This callable is the
 * single server-side source of truth that every upload path calls once when it
 * finishes — the server recomputes the count itself, so a client cannot inflate
 * it.
 *
 * It reconciles counts and availability on tasks that already exist. Dividing a campaign
 * into tasks (choosing slots / leads-per-worker) is owned exclusively by the
 * super admin — this function never creates a task.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { reconcileTaskAvailability } = require("../tasks/syncTaskLeadCounts");

const db = admin.firestore();

const syncCampaignLeadCounts = functions
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "You must be logged in.");
        }

        const campaignId = data && typeof data.campaignId === "string" ? data.campaignId.trim() : "";
        if (!campaignId) {
            throw new functions.https.HttpsError("invalid-argument", "campaignId is required.");
        }

        const campaignRef = db.collection("campaigns").doc(campaignId);
        const campaignSnap = await campaignRef.get();
        if (!campaignSnap.exists) {
            throw new functions.https.HttpsError("not-found", "Campaign not found.");
        }
        const campaign = campaignSnap.data();
        const claimedRoles = [context.auth.token.role, ...(Array.isArray(context.auth.token.roles)
            ? context.auth.token.roles : [])].filter(Boolean);
        const trustedRoles = ["admin", "super_admin", "developer", "task_review_admin", "team_leader"];
        const trustedCaller = claimedRoles.some((role) => trustedRoles.includes(role));
        if (campaign.clientId !== context.auth.uid && !trustedCaller) {
            throw new functions.https.HttpsError("permission-denied", "You cannot synchronize this campaign.");
        }
        if (campaign.clientId === context.auth.uid && !trustedCaller) {
            const clientSnapshot = await db.collection("clients").doc(context.auth.uid).get();
            if (!clientSnapshot.exists
                || clientSnapshot.data().kycStatus !== "approved"
                || clientSnapshot.data().accountActive !== true) {
                throw new functions.https.HttpsError("permission-denied", "Your client account must be approved and active.");
            }
        }

        // Server recomputes the count — never trust a client-supplied number.
        const countSnap = await db
            .collection("campaign_leads")
            .where("campaignId", "==", campaignId)
            .count()
            .get();
        const totalLeadsCount = countSnap.data().count;

        // Campaign keeps the ABSOLUTE total (all statuses) — drives completion %.
        await campaignRef.update({
            totalLeads: totalLeadsCount,
            lastLeadSyncAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // The worker-facing task count must reflect only AVAILABLE (pending)
        // leads — that's what the marketplace shows ("X per worker") and what the
        // Accept flow hands out. At first upload all leads are pending (so this
        // equals the total), but on a later repair call it keeps a
        // partially-worked campaign's marketplace count correct, matching the
        // syncTaskLeadCounts trigger's invariant.
        const pendingSnap = await db
            .collection("campaign_leads")
            .where("campaignId", "==", campaignId)
            .where("status", "==", "pending")
            .count()
            .get();
        const pendingLeadsCount = pendingSnap.data().count;

        // Keep the worker-facing task's count in sync IF one already exists.
        // Task creation / dividing a campaign into tasks is owned exclusively by
        // the super admin — we never auto-create a task here.
        const existingTaskSnap = await db.collection("tasks")
            .where("campaignId", "==", campaignId)
            .get();

        if (!existingTaskSnap.empty) {
            for (const taskDoc of existingTaskSnap.docs) {
                await reconcileTaskAvailability(db, taskDoc.id);
            }
        }

        return { totalLeads: totalLeadsCount, pendingLeads: pendingLeadsCount };
    });

module.exports = { syncCampaignLeadCounts };
