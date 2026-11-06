const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const db = admin.firestore();

function deletionFingerprint(campaignId, data) {
    const createdAt = data.createdAt;
    const createdKey = createdAt?.seconds != null
        ? `${createdAt.seconds}.${createdAt.nanoseconds || 0}`
        : "legacy";
    return [campaignId, createdKey, data.clientId || "", Number(data.reserved || 0), Number(data.spentAmount || 0)].join(":");
}

async function releaseReservationOnce(campaignId, data, fingerprint) {
    const markerRef = db.collection("campaign_deletion_jobs").doc(campaignId);
    const clientId = data.clientId;
    const remaining = Math.max(0, Number(data.reserved || 0) - Number(data.spentAmount || 0));

    await db.runTransaction(async (transaction) => {
        const marker = await transaction.get(markerRef);
        if (marker.get("reservationReleasedFor") === fingerprint) return;

        let walletRef = null;
        let wallet = null;
        if (clientId && remaining > 0) {
            walletRef = db.collection("client_wallets").doc(clientId);
            wallet = await transaction.get(walletRef);
        }
        if (wallet?.exists) {
            const currentReserved = Number(wallet.get("reservedBalance") || 0);
            transaction.update(walletRef, {
                reservedBalance: Math.max(0, currentReserved - remaining),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        transaction.set(markerRef, {
            campaignId,
            source: marker.get("source") || "manual_admin_deletion",
            reservationReleasedFor: fingerprint,
            reservationReleasedAmount: remaining,
            reservationReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}

async function deleteQueryInPages(query) {
    let total = 0;
    while (true) {
        const snapshot = await query.limit(400).get();
        if (snapshot.empty) break;
        const batch = db.batch();
        snapshot.docs.forEach((document) => batch.delete(document.ref));
        await batch.commit();
        total += snapshot.size;
        if (snapshot.size < 400) break;
    }
    return total;
}

exports.onCampaignDeleted = functions
    .runWith({ timeoutSeconds: 540, memory: "256MB", failurePolicy: true })
    .firestore
    .document("campaigns/{campaignId}")
    .onDelete(async (snapshot, context) => {
        const campaignId = context.params.campaignId;
        const data = snapshot.data() || {};
        const fingerprint = deletionFingerprint(campaignId, data);

        // The transaction-backed marker makes retries safe: a retried trigger
        // cannot release the same wallet reservation twice.
        await releaseReservationOnce(campaignId, data, fingerprint);

        const [tasksDeleted, leadsDeleted, assignmentsDeleted, uploadsDeleted] = await Promise.all([
            deleteQueryInPages(db.collection("tasks").where("campaignId", "==", campaignId)),
            deleteQueryInPages(db.collection("campaign_leads").where("campaignId", "==", campaignId)),
            deleteQueryInPages(db.collection("task_assignments").where("campaignId", "==", campaignId)),
            deleteQueryInPages(db.collection("lead_uploads").where("campaignId", "==", campaignId)),
        ]);

        // Uploaded lead sheets are campaign-specific source files. Recordings,
        // earnings, wallet history, and client records are intentionally kept.
        await admin.storage().bucket().deleteFiles({ prefix: `lead_sheets/${campaignId}/`, force: true });

        await db.collection("campaign_deletion_jobs").doc(campaignId).set({
            cleanupCompletedFor: fingerprint,
            cleanupCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
            deletedCounts: { tasks: tasksDeleted, leads: leadsDeleted, assignments: assignmentsDeleted, uploads: uploadsDeleted },
        }, { merge: true });

        console.log("Campaign cleanup completed.", {
            campaignId,
            tasksDeleted,
            leadsDeleted,
            assignmentsDeleted,
            uploadsDeleted,
        });
    });
