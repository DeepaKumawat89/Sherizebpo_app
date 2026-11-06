/**
 * submitTaskWork.js
 *
 * Callable Cloud Function: submitTaskWork
 *
 * Server-authoritative worker submission. Replaces the previous client-side
 * write to `task_submissions`, and enforces integrity that a client cannot:
 *   1. Verifies the task is active and belongs to a funded, active campaign
 *      (pause re-check).
 *   2. Re-checks the campaign's reserved budget can still cover this payout
 *      (funds re-check).
 *   3. Uses the AUTHORITATIVE payout from the task (never trusts the client).
 *   4. Verifies the lead belongs to this exact task, the worker holds it, and
 *      it hasn't already been submitted (atomic, inside a transaction).
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { isUnpricedCampaign } = require("../campaigns/pricing");
const { parseRequeueAt } = require("./requeueSchedule");

const db = admin.firestore();

// Outcomes that release the lead for another worker to retry later.
const REQUEUE_OUTCOMES = ["no_answer", "callback"];
const ALLOWED_OUTCOMES = [...REQUEUE_OUTCOMES, "interested", "not_interested", "wrong_number"];

const RECORDING_API_BASE = "https://us-central1-sherize-bpo.cloudfunctions.net/api";

async function readProcessedLeadIds(transaction, assignmentRef, assignment) {
    if (Array.isArray(assignment.processedLeadIds)) return new Set(assignment.processedLeadIds);
    const [submissions, wrongNumbers, leads, attempts] = await Promise.all([
        transaction.get(db.collection("task_submissions").where("assignmentId", "==", assignmentRef.id)),
        transaction.get(db.collection("wrong_numbers").where("taskId", "==", assignment.taskId)),
        transaction.get(db.collection("campaign_leads").where("taskId", "==", assignment.taskId)),
        transaction.get(db.collection("task_assignments").where("taskId", "==", assignment.taskId)),
    ]);
    const processed = new Set(submissions.docs.map((doc) => doc.data().leadId).filter(Boolean));
    const startedAt = (assignment.acceptedAt || assignment.assignedAt)?.toMillis();
    const workerAttempts = attempts.docs.filter((doc) => doc.data().userId === assignment.userId);
    const nextStart = Math.min(...workerAttempts.map((doc) =>
        (doc.data().acceptedAt || doc.data().assignedAt)?.toMillis()).filter((time) => time > startedAt));
    for (const doc of wrongNumbers.docs) {
        const report = doc.data();
        const reportedAt = report.reportedAt?.toMillis();
        if (report.reportedBy === assignment.userId && report.leadId &&
            (report.assignmentId === assignmentRef.id || (!report.assignmentId &&
                startedAt != null && reportedAt >= startedAt && reportedAt < nextStart))) {
            processed.add(report.leadId);
        }
    }
    for (const doc of leads.docs) {
        const lead = doc.data();
        if (lead.lastAssignmentId === assignmentRef.id ||
            (!lead.lastAssignmentId && workerAttempts.length === 1 && lead.lastCalledBy === assignment.userId &&
                REQUEUE_OUTCOMES.includes(lead.lastOutcome))) processed.add(doc.id);
    }
    return processed;
}

const getTaskAssignmentProgress = functions.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    const assignmentId = typeof data?.assignmentId === "string" ? data.assignmentId.trim() : "";
    if (!assignmentId || assignmentId.includes("/")) {
        throw new functions.https.HttpsError("invalid-argument", "A valid assignment ID is required.");
    }
    const assignmentRef = db.collection("task_assignments").doc(assignmentId);
    return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(assignmentRef);
        if (!snapshot.exists || snapshot.data().userId !== context.auth.uid) {
            throw new functions.https.HttpsError("permission-denied", "This assignment does not belong to you.");
        }
        const assignment = snapshot.data();
        const processed = await readProcessedLeadIds(transaction, assignmentRef, assignment);
        let lead = null;
        if (data.claimLead === true && ["active", "in_progress"].includes(assignment.status) &&
            (!assignment.tatDeadline || assignment.tatDeadline.toMillis() > Date.now()) &&
            (!Number(assignment.totalLeads) || processed.size < Number(assignment.totalLeads))) {
            const [taskSnap, workerSnap, locked, pending] = await Promise.all([
                transaction.get(db.collection("tasks").doc(assignment.taskId)),
                transaction.get(db.collection("users").doc(context.auth.uid)),
                transaction.get(db.collection("campaign_leads").where("taskId", "==", assignment.taskId)
                    .where("assignedTo", "==", context.auth.uid).where("status", "==", "in_progress")),
                transaction.get(db.collection("campaign_leads").where("taskId", "==", assignment.taskId)
                    .where("status", "==", "pending")),
            ]);
            const worker = workerSnap.data() || {};
            if (!taskSnap.exists || taskSnap.data().status !== "active" || worker.isActive === false ||
                !["approved", "verified"].includes(String(worker.kycStatus || worker.kyc_status || "").toLowerCase())) {
                throw new functions.https.HttpsError("failed-precondition", "This task is not available for work.");
            }
            const campaign = await transaction.get(db.collection("campaigns").doc(taskSnap.data().campaignId));
            if (!campaign.exists || campaign.data().status !== "active") {
                throw new functions.https.HttpsError("failed-precondition", "This campaign is not active.");
            }
            const candidate = [...locked.docs, ...pending.docs].find((doc) => !processed.has(doc.id));
            if (candidate) {
                const update = { status: "in_progress", assignedTo: context.auth.uid, activeAssignmentId: assignmentId };
                transaction.update(candidate.ref, { ...update,
                    ...(candidate.data().status === "pending"
                        ? { lockedAt: admin.firestore.FieldValue.serverTimestamp() } : {}) });
                lead = { ...candidate.data(), ...update, id: candidate.id };
            }
        }
        if (!Array.isArray(assignment.processedLeadIds) || (lead && assignment.status !== "in_progress")) {
            transaction.update(assignmentRef, { processedLeadIds: [...processed], leadsProcessed: processed.size,
                ...(lead ? { status: "in_progress",
                    ...(assignment.status === "active" && !assignment.startedAt
                        ? { startedAt: admin.firestore.FieldValue.serverTimestamp() } : {}) } : {}) });
        }
        return { taskId: assignment.taskId, status: assignment.status,
            lead,
            processedLeadIds: [...processed], leadsProcessed: processed.size,
            totalLeads: Number(assignment.totalLeads || 0), tatDeadline: assignment.tatDeadline?.toMillis() ?? null };
    });
});

// Builds the completed-lead update, back-linking the recording so the client
// portal can play it immediately instead of waiting for (or missing) the async
// provider status webhook. Only links a recording the worker actually made for
// THIS lead and that has a provider SID the /recording proxy can resolve.
function buildLeadCompletionUpdate({ userId, callId, callData, leadId, taskId, assignmentId }) {
    const update = { status: "completed", calledBy: userId };
    if (callId && callData
        && callData.userId === userId
        && callData.leadId === leadId
        && callData.taskId === taskId
        && callData.assignmentId === assignmentId
        && callData.exotelCallSid) {
        update.callId = callId;
        update.recordingUrl = `${RECORDING_API_BASE}/recording?callId=${encodeURIComponent(callId)}`;
    }
    return update;
}

const submitTaskWork = functions
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "You must be logged in.");
        }
        const userId = context.auth.uid;

        // ── KYC gate: only verified workers may submit work (start/earn) ──
        const submitterSnap = await db.collection("users").doc(userId).get();
        const submitterKyc = String(
            (submitterSnap.exists && (submitterSnap.data().kycStatus || submitterSnap.data().kyc_status)) || ""
        ).toLowerCase();
        if (submitterKyc !== "approved" && submitterKyc !== "verified") {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "KYC verification must be approved before you can start and submit work."
            );
        }

        // Friendly worker code (SHR######) denormalized onto the submission so
        // reviewers can display it without reading the users collection (which
        // is restricted to super admins by the privacy rules).
        const submitterData = submitterSnap.exists ? submitterSnap.data() : {};
        const workerCode = String(submitterData.systemWorkerId || submitterData.workerId || "");

        const taskId = data && typeof data.taskId === "string" ? data.taskId.trim() : "";
        const assignmentId = data && typeof data.assignmentId === "string" ? data.assignmentId.trim() : "";
        const leadId = data && typeof data.leadId === "string" ? data.leadId.trim() : "";
        const outcome = data && typeof data.outcome === "string" ? data.outcome : null;
        const notes = data && typeof data.notes === "string" ? data.notes.trim() : "";
        const callDuration = Number(data && data.callDuration) || 0;
        const callSid = (data && data.callSid) || null;
        const callId = data && typeof data.callId === "string" ? data.callId.trim() : "";
        const workerName = data && typeof data.workerName === "string" ? data.workerName : "Unknown Worker";

        if (!taskId || !assignmentId || !leadId || !ALLOWED_OUTCOMES.includes(outcome)) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "A valid taskId, assignmentId, leadId and outcome are required."
            );
        }

        // ── Task: authoritative payout + active status (pause re-check) ──
        const taskSnap = await db.collection("tasks").doc(taskId).get();
        if (!taskSnap.exists) {
            throw new functions.https.HttpsError("not-found", "Task not found.");
        }
        const taskData = taskSnap.data();
        if (taskData.status !== "active") {
            throw new functions.https.HttpsError("failed-precondition", "This task is no longer active.");
        }
        const campaignId = taskData.campaignId;
        const payout = Number(taskData.payout || 0);
        if (!campaignId) {
            throw new functions.https.HttpsError("failed-precondition", "Task has no associated campaign.");
        }

        // ── Campaign: pause + funds re-check ──
        const campaignSnap = await db.collection("campaigns").doc(campaignId).get();
        if (!campaignSnap.exists) {
            throw new functions.https.HttpsError("not-found", "Campaign not found.");
        }
        const campaignData = campaignSnap.data();
        if (campaignData.status !== "active") {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "This campaign is paused or closed — work cannot be submitted right now."
            );
        }

        // Closed-platform (unpriced) campaigns carry no payout — money is hidden
        // from clients AND workers — so a zero payout is expected here. A PRICED
        // campaign with a zero/invalid payout is still a misconfig and is rejected.
        const unpriced = isUnpricedCampaign(campaignData);
        if (payout <= 0 && !unpriced) {
            throw new functions.https.HttpsError("failed-precondition", "Task has an invalid payout.");
        }

        const reserved = Number(campaignData.reserved || 0);
        const spent = Number(campaignData.spentAmount || 0);
        if (reserved > 0 && (reserved - spent) < payout - 0.01) {
            throw new functions.https.HttpsError("failed-precondition", "The campaign budget is exhausted.");
        }

        const shouldRequeue = REQUEUE_OUTCOMES.includes(outcome);
        const isWrongNumber = outcome === "wrong_number";
        let requeueAt = null;
        if (shouldRequeue) {
            try {
                requeueAt = parseRequeueAt(data && data.requeueAt);
            } catch (error) {
                throw new functions.https.HttpsError("invalid-argument", error.message);
            }
        }
        // interested / not_interested (contact made) are payable and go to QA
        // review. callback/no_answer re-queue (keep badge); wrong_number is
        // surfaced to super admins. Neither of the latter two is payable.
        const createsSubmission = !shouldRequeue && !isWrongNumber;

        const submissionRef = db.collection("task_submissions").doc();
        const leadRef = db.collection("campaign_leads").doc(leadId);
        const assignmentRef = db.collection("task_assignments").doc(assignmentId);
        const callRef = callId ? db.collection("calls").doc(callId) : null;

        // ── Atomic: verify lead ownership + not double-submitted, then write ──
        const leadsProcessed = await db.runTransaction(async (txn) => {
            const [leadSnap, assignmentSnap, callSnap] = await Promise.all([
                txn.get(leadRef),
                txn.get(assignmentRef),
                callRef ? txn.get(callRef) : Promise.resolve(null),
            ]);
            if (!leadSnap.exists) {
                throw new functions.https.HttpsError("not-found", "Lead not found.");
            }
            if (!assignmentSnap.exists) {
                throw new functions.https.HttpsError("permission-denied", "Task assignment not found.");
            }
            const lead = leadSnap.data();
            const assignment = assignmentSnap.data();

            if (assignment.userId !== userId || assignment.taskId !== taskId) {
                throw new functions.https.HttpsError("permission-denied", "This task is not assigned to you.");
            }
            if (!["active", "in_progress"].includes(assignment.status)) {
                throw new functions.https.HttpsError("failed-precondition", "This task assignment is not active.");
            }
            if (assignment.tatDeadline && assignment.tatDeadline.toMillis() <= Date.now()) {
                throw new functions.https.HttpsError("failed-precondition", "This assignment has exceeded its TAT.");
            }
            if (lead.taskId !== taskId) {
                throw new functions.https.HttpsError("permission-denied", "Lead does not belong to this task.");
            }
            if (lead.campaignId !== campaignId) {
                throw new functions.https.HttpsError("permission-denied", "Lead does not belong to this task's campaign.");
            }
            if (lead.assignedTo !== userId || lead.status !== "in_progress" ||
                (lead.activeAssignmentId && lead.activeAssignmentId !== assignmentId)) {
                throw new functions.https.HttpsError("permission-denied", "This lead is not active for this worker.");
            }

            const processed = await readProcessedLeadIds(txn, assignmentRef, assignment);
            if (processed.has(leadId) || (Number(assignment.totalLeads) > 0 && processed.size >= Number(assignment.totalLeads))) {
                throw new functions.https.HttpsError("failed-precondition", "This assignment has already processed this work.");
            }
            processed.add(leadId);
            const completed = Number(assignment.totalLeads) > 0 && processed.size >= Number(assignment.totalLeads);
            txn.update(assignmentRef, {
                processedLeadIds: [...processed],
                leadsProcessed: processed.size,
                status: completed ? "completed" : "in_progress",
                ...(completed ? { completedAt: admin.firestore.FieldValue.serverTimestamp() } : {}),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            txn.update(leadRef, {
                lastAssignmentId: assignmentId,
                lastOutcome: outcome,
                lastOutcomeAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // ── callback / no_answer: re-queue for retry, KEEP the reason badge.
            //    No payable submission is created — no contact was made. ──
            if (shouldRequeue) {
                try {
                    parseRequeueAt(requeueAt);
                } catch (error) {
                    throw new functions.https.HttpsError("invalid-argument", error.message);
                }
                txn.update(leadRef, {
                    status: "requeue_pending",
                    requeueAfter: admin.firestore.Timestamp.fromMillis(requeueAt),
                    requeueReason: outcome,
                    isRequeued: true,
                    lastCalledBy: userId,
                    lastOutcome: outcome,
                    assignedTo: null,
                    lockedAt: null,
                });
                return processed.size;
            }

            // ── wrong_number: dead lead. Surface to super admins, no payout,
            //    no re-queue. ──
            if (isWrongNumber) {
                txn.update(leadRef, {
                    status: "wrong_number",
                    lastCalledBy: userId,
                    lastOutcome: "wrong_number",
                    isRequeued: false,
                    assignedTo: null,
                    lockedAt: null,
                });
                const wrongRef = db.collection("wrong_numbers").doc(leadId);
                txn.set(wrongRef, {
                    leadId,
                    taskId,
                    assignmentId,
                    campaignId,
                    campaignName: lead.campaignName || "",
                    name: lead.name || "",
                    phone: lead.phone || "",
                    notes,
                    reportedBy: userId,
                    workerName,
                    reportedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                return processed.size;
            }

            // ── interested / not_interested: contact made → QA review (payable). ──
            const recordingUrl = callSid
                ? `https://us-central1-sherize-bpo.cloudfunctions.net/api/recording?callSid=${callSid}`
                : null;

            txn.set(submissionRef, {
                taskId,
                assignmentId,
                userId,
                workerName,
                workerId: workerCode,
                leadId,
                leadName: lead.name || "",
                leadPhone: lead.phone || "",
                customerPhone: lead.phone || "",
                callDuration,
                outcome,
                notes,
                status: "pending_admin_review",
                submittedAt: admin.firestore.FieldValue.serverTimestamp(),
                payout,
                callSid,
                recordingUrl,
            });

            txn.update(leadRef, buildLeadCompletionUpdate({
                userId,
                callId,
                callData: callSnap && callSnap.exists ? callSnap.data() : null,
                leadId,
                taskId,
                assignmentId,
            }));
            return processed.size;
        });

        return {
            success: true,
            leadsProcessed,
            submissionId: createsSubmission ? submissionRef.id : null,
            requeued: shouldRequeue,
            wrongNumber: isWrongNumber,
        };
    });

module.exports = { submitTaskWork, getTaskAssignmentProgress, buildLeadCompletionUpdate };
