const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const db = admin.firestore();
const TIME_ZONE = "Asia/Kolkata";
const PAGE_SIZE = 100;
const MAX_CAMPAIGNS_PER_RUN = 1000;

function dateInTimeZone(date, timeZone) {
    const parts = new Intl.DateTimeFormat("en-CA", {
        timeZone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).formatToParts(date);
    const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
    return `${values.year}-${values.month}-${values.day}`;
}

function isValidDateOnly(value) {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const parsed = new Date(`${value}T00:00:00Z`);
    return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

async function requestDeletionIfExpired(campaignRef, today) {
    return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(campaignRef);
        if (!snapshot.exists) return false;

        const endDate = snapshot.get("endDate");
        // Equality is deliberately excluded: the campaign remains available
        // throughout its complete end date in the configured business zone.
        if (!isValidDateOnly(endDate) || endDate >= today) return false;

        transaction.set(db.collection("campaign_deletion_jobs").doc(campaignRef.id), {
            campaignId: campaignRef.id,
            source: "expired_schedule",
            endDate,
            timeZone: TIME_ZONE,
            deletionRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        transaction.delete(campaignRef);
        return true;
    });
}

const deleteExpiredCampaigns = functions
    .runWith({ timeoutSeconds: 540, memory: "256MB", failurePolicy: true })
    .pubsub.schedule("15 * * * *")
    .timeZone(TIME_ZONE)
    .onRun(async () => {
        const today = dateInTimeZone(new Date(), TIME_ZONE);
        let cursor = null;
        let examined = 0;
        let deleted = 0;
        const failures = [];

        while (examined < MAX_CAMPAIGNS_PER_RUN) {
            let expiredQuery = db.collection("campaigns")
                .where("endDate", ">=", "0001-01-01")
                .where("endDate", "<", today)
                .orderBy("endDate")
                .limit(Math.min(PAGE_SIZE, MAX_CAMPAIGNS_PER_RUN - examined));
            if (cursor) expiredQuery = expiredQuery.startAfter(cursor);

            const page = await expiredQuery.get();
            if (page.empty) break;
            examined += page.size;
            cursor = page.docs[page.docs.length - 1];

            const results = await Promise.allSettled(page.docs.map((campaign) =>
                requestDeletionIfExpired(campaign.ref, today)
            ));
            results.forEach((result, index) => {
                if (result.status === "fulfilled" && result.value) deleted += 1;
                if (result.status === "rejected") {
                    failures.push({ campaignId: page.docs[index].id, message: result.reason?.message || String(result.reason) });
                }
            });
            if (page.size < PAGE_SIZE) break;
        }

        console.log("Expired campaign cleanup completed.", { today, timeZone: TIME_ZONE, examined, deleted, failed: failures.length });
        if (failures.length) {
            console.error("Some expired campaigns could not be deleted and will be retried by a later schedule.", failures);
            throw new Error(`Failed to delete ${failures.length} expired campaign(s).`);
        }
        return { today, examined, deleted };
    });

module.exports = { deleteExpiredCampaigns };
