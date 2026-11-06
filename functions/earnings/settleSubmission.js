/**
 * settleSubmission.js
 *
 * Shared settlement logic that credits a worker's wallet for an approved task
 * submission, debits the client wallet, records platform commission, and marks
 * the submission + lead approved. Extracted so it can be triggered from BOTH:
 *   - reviewSubmissionQA (QA accept → pay immediately), and
 *   - approveTaskSubmission (legacy pending_payment items).
 *
 * The money math and transaction ordering are identical to the original
 * approveTaskSubmission implementation.
 */
const functions = require("firebase-functions/v1");
const {
    runTransaction,
    serverTimestamp,
    increment,
} = require("../utils/firestoreTransaction");

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {Object} opts
 * @param {string} opts.submissionId
 * @param {string} opts.adminId              - UID recorded as approvedBy
 * @param {string[]} opts.allowedStatuses    - submission statuses valid to settle from
 * @param {Object} [opts.extraSubmissionFields] - extra fields merged onto the submission update (e.g. QA metadata)
 * @returns {Promise<{ payout: number }>}
 */
async function settleSubmissionPayout(db, { submissionId, adminId, allowedStatuses, extraSubmissionFields = {}, rating = null }) {
    // A reviewer's star rating (1–5). When present it is stored on the submission
    // and rolled into the worker's consolidated profile rating below.
    const hasRating = typeof rating === "number" && isFinite(rating) && rating > 0;
    const submissionRef = db.collection("task_submissions").doc(submissionId);
    const submissionSnap = await submissionRef.get();
    if (!submissionSnap.exists) {
        throw new functions.https.HttpsError("not-found", `Submission ${submissionId} not found.`);
    }
    const submission = submissionSnap.data();
    if (!allowedStatuses.includes(submission.status)) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            `Submission is currently "${submission.status}". Cannot settle payout.`
        );
    }

    const userId = submission.userId || null;
    const taskId = submission.taskId || null;

    if (!userId) throw new functions.https.HttpsError("invalid-argument", "Missing userId in submission document.");
    if (!taskId) throw new functions.https.HttpsError("invalid-argument", "Missing taskId in submission document.");

    const taskSnap = await db.collection("tasks").doc(taskId).get();
    if (!taskSnap.exists) {
        throw new functions.https.HttpsError("not-found", `Related task document ${taskId} not found.`);
    }
    const taskData = taskSnap.data();
    const payout = Number(taskData.payout || 0);
    if (isNaN(payout) || payout <= 0) {
        throw new functions.https.HttpsError("failed-precondition", "The task payout must be a positive number.");
    }
    const campaignId = taskData.campaignId || null;
    if (!campaignId) {
        throw new functions.https.HttpsError("not-found", `Task ${taskId} has no associated campaignId.`);
    }

    // Duplicate-credit guard (queries not allowed inside a transaction).
    const duplicateTxSnap = await db.collection("transactions")
        .where("referenceId", "==", submissionId)
        .where("userId", "==", userId)
        .where("type", "==", "credit")
        .limit(1)
        .get();
    const hasDuplicateTx = !duplicateTxSnap.empty;

    let campaignExhausted = false;
    await runTransaction(db, `Settle submission ${submissionId}`, async (transaction) => {
        // ── READS FIRST ──
        const freshSnap = await transaction.get(submissionRef);
        if (!freshSnap.exists) {
            throw new functions.https.HttpsError("not-found", "Submission document disappeared.");
        }
        const freshData = freshSnap.data();
        if (!allowedStatuses.includes(freshData.status)) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                `Submission already handled (status: "${freshData.status}"). Cannot settle again.`
            );
        }

        const assignmentSnap = freshData.assignmentId
            ? await transaction.get(db.collection("task_assignments").doc(freshData.assignmentId)) : null;
        const assignment = assignmentSnap?.data();
        if (assignment && (assignment.taskId !== taskId || assignment.userId !== userId)) {
            throw new functions.https.HttpsError("failed-precondition", "Submission assignment does not match its worker and task.");
        }
        const expiredPartial = assignment && ["active", "in_progress"].includes(assignment.status) &&
            assignment.tatDeadline?.toMillis() <= Date.now() &&
            (!Number(assignment.totalLeads) || Number(assignment.leadsProcessed || 0) < Number(assignment.totalLeads));
        const seized = assignment?.payoutRecipient === "super_admin" ||
            ["revoked", "out_of_tat", "out_of_tat_processing"].includes(assignment?.status) || expiredPartial;

        const campaignRef = db.collection("campaigns").doc(campaignId);
        const campaignSnap = await transaction.get(campaignRef);
        if (!campaignSnap.exists) {
            throw new functions.https.HttpsError("not-found", `Campaign ${campaignId} not found.`);
        }
        const campaignData = campaignSnap.data() || {};
        const clientId = campaignData.clientId || null;
        if (!clientId) {
            throw new functions.https.HttpsError("failed-precondition", "Campaign has no clientId associated.");
        }

        const clientWalletRef = db.collection("client_wallets").doc(clientId);
        const clientWalletSnap = await transaction.get(clientWalletRef);

        const workerWalletRef = db.collection("worker_wallets").doc(userId);
        const workerWalletSnap = await transaction.get(workerWalletRef);

        let leadSnap = null;
        const leadId = freshData.leadId || null;
        if (leadId) {
            const leadRef = db.collection("campaign_leads").doc(leadId);
            leadSnap = await transaction.get(leadRef);
        }

        const userRef = db.collection("users").doc(userId);
        const userSnap = await transaction.get(userRef);

        const platformRef = db.collection("platform_earnings").doc("global");
        await transaction.get(platformRef);

        const superAdminWalletRef = db.collection("super_admin_wallet").doc("main");
        const superAdminWalletSnap = await transaction.get(superAdminWalletRef);

        // ── DATA VALIDATION ──
        const workerPayout = Number(freshData.payout || 0);
        const clientDeduction = Number(
            campaignData.clientPricePerLead || campaignData.payout || workerPayout
        );
        if (workerPayout <= 0 || clientDeduction <= 0) {
            throw new functions.https.HttpsError("invalid-argument", "Invalid payout amounts: must be greater than 0");
        }

        let clientBalance = 0;
        if (clientWalletSnap.exists) {
            clientBalance = Number(clientWalletSnap.data().balance || 0);
        }
        if (isNaN(clientBalance) || clientBalance < clientDeduction) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                `Client has insufficient balance. Available: ₹${isNaN(clientBalance) ? "unknown" : clientBalance}, Required: ₹${clientDeduction}.`
            );
        }

        const campaignReserved = Number(campaignData.reserved || 0);
        const campaignSpentBefore = Number(campaignData.spentAmount || 0);
        if (campaignReserved > 0 && (campaignSpentBefore + clientDeduction) > campaignReserved + 0.01) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                `Campaign budget exhausted. Reserved: ₹${campaignReserved}, Spent: ₹${campaignSpentBefore}, Required: ₹${clientDeduction}.`
            );
        }
        const willExhaust = campaignReserved > 0 && (campaignSpentBefore + clientDeduction) >= campaignReserved - 0.01;
        campaignExhausted = willExhaust;

        const currentReserved = clientWalletSnap.exists ? Number(clientWalletSnap.data().reservedBalance || 0) : 0;
        const releaseAmount = campaignReserved > 0 ? clientDeduction : 0;
        const newReservedBalance = Math.max(0, currentReserved - releaseAmount);

        let currentWorkerBalance = 0;
        let currentWorkerEarned = 0;
        if (!workerWalletSnap.exists && !seized) {
            transaction.set(workerWalletRef, {
                balance: 0,
                totalEarned: 0,
                totalWithdrawn: 0,
                createdAt: serverTimestamp()
            });
        } else if (workerWalletSnap.exists) {
            currentWorkerBalance = Number(workerWalletSnap.data()?.balance || 0);
            currentWorkerEarned = Number(workerWalletSnap.data()?.totalEarned || 0);
        }

        const workerEarns = seized ? 0 : workerPayout;
        const seizedPayout = seized ? workerPayout : 0;
        const commission = Number((clientDeduction - workerPayout).toFixed(2));
        const platformEarns = Number((clientDeduction - workerEarns).toFixed(2));
        const newWorkerBalance = currentWorkerBalance + workerEarns;
        const newWorkerEarned = currentWorkerEarned + workerEarns;

        // ── WRITES ──
        transaction.update(submissionRef, {
            status: "approved",
            payoutRecipient: seized ? "super_admin" : userId,
            seizedPayout,
            approvedBy: adminId,
            // `reviewedBy` is the canonical reviewer field (reject paths already
            // set it). Writing it here too means "Review History" can attribute
            // every reviewed submission — approved or rejected — to one admin.
            reviewedBy: adminId,
            reviewedAt: serverTimestamp(),
            ...(hasRating ? { rating } : {}),
            ...extraSubmissionFields,
        });

        if (clientWalletSnap.exists) {
            transaction.update(clientWalletRef, {
                balance: clientBalance - clientDeduction,
                reservedBalance: newReservedBalance,
                totalSpent: increment(clientDeduction),
                updatedAt: serverTimestamp()
            });
        } else {
            transaction.set(clientWalletRef, {
                balance: -clientDeduction,
                totalSpent: clientDeduction,
                totalDeposited: 0,
                updatedAt: serverTimestamp()
            });
        }

        if (!seized) transaction.update(workerWalletRef, {
            balance: newWorkerBalance,
            totalEarned: newWorkerEarned,
            updatedAt: serverTimestamp()
        });

        transaction.set(platformRef, {
            totalRevenue: increment(clientDeduction),
            totalPayout: increment(workerEarns),
            netProfit: increment(platformEarns),
            updatedAt: serverTimestamp()
        }, { merge: true });

        if (platformEarns > 0) {
            if (superAdminWalletSnap.exists) {
                transaction.update(superAdminWalletRef, {
                    balance: increment(platformEarns),
                    totalCommission: increment(commission),
                    totalSeizedPayout: increment(seizedPayout),
                    updatedAt: serverTimestamp(),
                });
            } else {
                transaction.set(superAdminWalletRef, {
                    balance: platformEarns,
                    totalCommission: commission,
                    totalSeizedPayout: seizedPayout,
                    totalWithdrawn: 0,
                    createdAt: serverTimestamp(),
                    updatedAt: serverTimestamp(),
                });
            }
        }

        if (!hasDuplicateTx) {
            const txWorkerRef = db.collection("transactions").doc();
            transaction.set(txWorkerRef, {
                userId: seized ? "super_admin" : userId,
                role: seized ? "super_admin" : "worker",
                type: "credit",
                amount: workerPayout,
                source: seized ? "seized_payout" : "task",
                referenceId: submissionId,
                status: "success",
                description: seized ? "Approved partial-assignment payout" : "Task approved earning",
                createdAt: serverTimestamp()
            });

            const txClientRef = db.collection("transactions").doc();
            transaction.set(txClientRef, {
                userId: clientId,
                role: "client",
                type: "debit",
                amount: clientDeduction,
                source: "task",
                referenceId: submissionId,
                status: "success",
                description: "Campaign task payout",
                createdAt: serverTimestamp()
            });

            if (commission > 0) {
                const txCommissionRef = db.collection("transactions").doc();
                transaction.set(txCommissionRef, {
                    userId: "super_admin",
                    role: "super_admin",
                    type: "credit",
                    amount: commission,
                    source: "commission",
                    referenceId: submissionId,
                    status: "success",
                    description: "Platform commission",
                    createdAt: serverTimestamp()
                });
            }
        }

        if (seized) transaction.set(db.collection("earnings").doc(`seized_${submissionId}`), {
            userId: "super_admin", workerId: userId, taskId, assignmentId: freshData.assignmentId,
            submissionId, amount: workerPayout, type: "seized_payout", status: "completed",
            createdAt: serverTimestamp(),
        });

        let currentUsersWallet = 0;
        let currentUsersEarnings = 0;
        if (userSnap.exists) {
            currentUsersWallet = Number(userSnap.data().walletBalance || 0);
            currentUsersEarnings = Number(userSnap.data().earnings || 0);
        }

        // Consolidate the reviewer's rating into the worker's profile: a running
        // average kept alongside its sample count. Also count the completed task.
        const ratingUpdate = {};
        if (hasRating) {
            const prevRating = Number(userSnap.exists ? (userSnap.data().rating || 0) : 0);
            const prevCount = Number(userSnap.exists ? (userSnap.data().ratingCount || 0) : 0);
            const newCount = prevCount + 1;
            const newAvg = ((prevRating * prevCount) + rating) / newCount;
            ratingUpdate.rating = Math.round(newAvg * 100) / 100; // 2 dp
            ratingUpdate.ratingCount = newCount;
        }

        transaction.set(userRef, {
            ...(!seized ? { walletBalance: currentUsersWallet + workerEarns,
                earnings: currentUsersEarnings + workerEarns } : {}),
            totalTasksCompleted: increment(1),
            ...ratingUpdate,
        }, { merge: true });

        transaction.update(campaignRef, willExhaust
            ? { spentAmount: increment(clientDeduction), status: "completed" }
            : { spentAmount: increment(clientDeduction) });

        if (leadSnap && leadSnap.exists) {
            transaction.update(leadSnap.ref, {
                status: "approved",
                approvedAt: serverTimestamp(),
                approvedBy: adminId,
            });
        }
    });

    // Close open tasks for an exhausted campaign so workers can't claim unpayable work.
    if (campaignExhausted && campaignId) {
        try {
            const openTasks = await db.collection("tasks")
                .where("campaignId", "==", campaignId)
                .where("status", "==", "active")
                .get();
            if (!openTasks.empty) {
                const closeBatch = db.batch();
                openTasks.forEach((t) => closeBatch.update(t.ref, { status: "completed" }));
                await closeBatch.commit();
            }
        } catch (closeErr) {
            console.warn(`[settleSubmission] Failed to close tasks for exhausted campaign:`, closeErr.message);
        }
    }

    return { payout };
}

module.exports = { settleSubmissionPayout };
