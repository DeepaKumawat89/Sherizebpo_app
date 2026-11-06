const assert = require("node:assert/strict");
const admin = require("firebase-admin");

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("This check requires the local Firestore emulator.");
const projectId = "demo-retry-recovery";
admin.initializeApp({ projectId });
const db = admin.firestore();
const { acceptMarketplaceTask } = require("./acceptMarketplaceTask");
const { reconcileTaskAvailability } = require("./syncTaskLeadCounts");
const { submitTaskWork, getTaskAssignmentProgress } = require("./submitTaskWork");
const { assignEmployeeTask, getTaskAssignmentEmployees, getTeamLeaderEmployees } = require("./assignEmployeeTask");
const { revokeTaskAssignment } = require("./revokeTaskAssignment");
const { enforceTatAndRecreate } = require("./enforceTatAndRecreate");
const { reviewSubmissionQA } = require("../earnings/reviewSubmissionQA");
const { manageTeamCampaign } = require("../campaigns/manageTeamCampaign");
const portalRequire = require("node:module").createRequire(require("node:path").resolve(__dirname, "../../../super_admin_portal/package.json"));
const { initializeApp, deleteApp } = portalRequire("firebase/app");
const { getFirestore, connectFirestoreEmulator, doc, getDoc, getDocs, collection, query, where, updateDoc, setDoc, terminate } = portalRequire("firebase/firestore");

(async () => {
    const prefix = `retry-check-${Date.now()}`;
    const userId = `${prefix}-worker`;
    const otherUserId = `${prefix}-other`;
    const campaignId = `${prefix}-campaign`;
    const taskId = `${prefix}-task`;
    await db.collection("users").doc(userId).set({ role: "worker", kycStatus: "approved", isActive: true });
    await db.collection("users").doc(otherUserId).set({ role: "worker", kycStatus: "approved", isActive: true });
    await db.collection("campaigns").doc(campaignId).set({ status: "active" });
    const task = db.collection("tasks").doc(taskId);
    await task.set({ campaignId, status: "active", distributionMode: "marketplace", totalSlots: 2, acceptedCount: 0 });
    await db.collection("campaign_leads").doc(`${prefix}-lead`).set({ taskId, campaignId, status: "pending" });

    const sameWorker = await Promise.allSettled([
        acceptMarketplaceTask.run({ taskId }, { auth: { uid: userId } }),
        acceptMarketplaceTask.run({ taskId }, { auth: { uid: userId } }),
    ]);
    assert.equal(sameWorker.filter((result) => result.status === "fulfilled").length, 1);
    assert.equal(sameWorker.find((result) => result.status === "rejected").reason.code, "already-exists");
    const initialAssignments = await db.collection("task_assignments").where("taskId", "==", taskId).get();
    assert.equal(initialAssignments.size, 1);
    await initialAssignments.docs[0].ref.update({ status: "completed" });
    await task.update({ acceptedCount: 20, totalSlots: 1 });
    await reconcileTaskAvailability(db, taskId);
    assert.equal((await task.get()).data().acceptedCount, 0);

    const lastSlot = await Promise.allSettled([
        acceptMarketplaceTask.run({ taskId }, { auth: { uid: userId } }),
        acceptMarketplaceTask.run({ taskId }, { auth: { uid: otherUserId } }),
    ]);
    assert.equal(lastSlot.filter((result) => result.status === "fulfilled").length, 1);
    assert.equal(lastSlot.find((result) => result.status === "rejected").reason.code, "resource-exhausted");
    await reconcileTaskAvailability(db, taskId);
    assert.equal((await task.get()).data().acceptedCount, 1);
    assert.equal((await initialAssignments.docs[0].ref.get()).data().status, "completed");

    const progressTaskId = `${prefix}-progress`;
    const progressAssignmentId = `${prefix}-attempt`;
    const progressAssignment = db.collection("task_assignments").doc(progressAssignmentId);
    const context = { auth: { uid: userId } };
    const acceptedAt = admin.firestore.Timestamp.fromMillis(Date.now() - 60000);
    await db.collection("tasks").doc(progressTaskId).set({ campaignId, status: "active", payout: 10 });
    await progressAssignment.set({ taskId: progressTaskId, userId, status: "in_progress", totalLeads: 5,
        acceptedAt, tatDeadline: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000) });
    const outcomeIds = ["wrong_number", "interested", "not_interested", "callback", "no_answer"]
        .map((outcome, index) => `${prefix}-${index}-${outcome}`);
    for (const [index, leadId] of outcomeIds.entries()) {
        await db.collection("campaign_leads").doc(leadId).set({ taskId: progressTaskId, campaignId,
            status: index === 0 ? "wrong_number" : index === 1 ? "completed" : "pending", assignedTo: null });
    }
    await db.collection("wrong_numbers").doc(outcomeIds[0]).set({ taskId: progressTaskId,
        leadId: outcomeIds[0], reportedBy: userId, reportedAt: admin.firestore.Timestamp.now() });
    await db.collection("task_submissions").doc(`${prefix}-legacy`).set({ taskId: progressTaskId,
        assignmentId: progressAssignmentId, userId, leadId: outcomeIds[1], outcome: "interested" });
    const resume = () => getTaskAssignmentProgress.run({ assignmentId: progressAssignmentId, claimLead: true }, context);
    const resumed = await resume();
    assert.equal(resumed.leadsProcessed, 2, "Recover legacy wrong-number and payable outcomes");
    assert.equal(resumed.totalLeads, 5);
    assert.equal(resumed.lead.id, outcomeIds[2]);
    assert.equal((await resume()).lead.id, outcomeIds[2], "Reopening recovers the same locked lead");
    await assert.rejects(getTaskAssignmentProgress.run({ assignmentId: progressAssignmentId },
        { auth: { uid: otherUserId } }), (error) => error.code === "permission-denied");
    for (const [offset, outcome] of ["not_interested", "callback", "no_answer"].entries()) {
        const data = { taskId: progressTaskId, assignmentId: progressAssignmentId, leadId: outcomeIds[offset + 2],
            outcome, requeueAt: Date.now() + 120000, callDuration: 12, notes: "LOCAL EMULATOR ONLY" };
        const submitted = await submitTaskWork.run(data, context);
        assert.equal(submitted.leadsProcessed, offset + 3);
        await assert.rejects(submitTaskWork.run(data, context));
        const progress = await resume();
        assert.equal(progress.leadsProcessed, offset + 3, "Retries must not double count");
        assert.equal(progress.lead?.id ?? null, outcomeIds[offset + 3] ?? null);
    }
    assert.equal((await progressAssignment.get()).data().status, "completed");
    await progressAssignment.update({ status: "revoked" });
    assert.equal((await resume()).lead, null);
    await progressAssignment.update({ status: "in_progress", tatDeadline: acceptedAt });
    assert.equal((await resume()).lead, null);
    await assert.rejects(submitTaskWork.run({ taskId: progressTaskId, assignmentId: progressAssignmentId,
        leadId: outcomeIds[4], outcome: "interested" }, context), (error) => error.code === "failed-precondition");
    console.log("assignment progress checks passed: legacy 2/5 resume, stable lock, all outcome counts, duplicate and expiry guards");

    const managerId = `${prefix}-manager`;
    const leaderId = `${prefix}-leader`;
    const clientId = `${prefix}-client`;
    const partialTaskId = `${prefix}-partial`;
    const managerContext = { auth: { uid: managerId } };
    await db.collection("users").doc(managerId).set({ role: "super_admin", isActive: true });
    await db.collection("users").doc(leaderId).set({ role: "team_leader", isActive: true });
    await db.collection("campaigns").doc(campaignId).update({ clientId, payout: 10, clientPricePerLead: 15,
        reserved: 100, spentAmount: 0 });
    await db.collection("client_wallets").doc(clientId).set({ balance: 100, reservedBalance: 100 });
    const partialTask = db.collection("tasks").doc(partialTaskId);
    await partialTask.set({ campaignId, status: "pending_team_leader", payout: 10, totalLeads: 99, tatHours: 1 });
    for (let index = 0; index < 5; index++) {
        await db.collection("campaign_leads").doc(`${prefix}-partial-${index}`).set({
            taskId: partialTaskId, campaignId, status: "pending", assignedTo: null });
    }
    const assigned = await assignEmployeeTask.run({ taskId: partialTaskId, employeeUid: userId }, managerContext);
    const oldAttemptId = assigned.assignmentIds[0];
    const partialResume = (assignmentId) => getTaskAssignmentProgress.run({ assignmentId, claimLead: true }, context);
    let payableSubmission;
    for (const outcome of ["wrong_number", "interested"]) {
        const progress = await partialResume(oldAttemptId);
        const result = await submitTaskWork.run({ taskId: partialTaskId, assignmentId: oldAttemptId,
            leadId: progress.lead.id, outcome, callDuration: 12, notes: "LOCAL EMULATOR ONLY" }, context);
        if (result.submissionId) payableSubmission = result.submissionId;
    }
    assert.equal((await partialResume(oldAttemptId)).leadsProcessed, 2);
    await revokeTaskAssignment.run({ taskId: partialTaskId, employeeUid: userId, assignmentId: oldAttemptId },
        { auth: { uid: leaderId } });
    assert.equal((await db.collection("task_assignments").doc(oldAttemptId).get()).data().revokedBy, leaderId);
    const revokedTask = (await partialTask.get()).data();
    assert.equal(revokedTask.status, "pending_team_leader");
    assert.equal(revokedTask.totalLeads, 3);
    assert.equal((await partialResume(oldAttemptId)).lead, null);
    await assert.rejects(submitTaskWork.run({ taskId: partialTaskId, assignmentId: oldAttemptId,
        leadId: `${prefix}-partial-2`, outcome: "interested", callDuration: 12 }, context),
    (error) => error.code === "permission-denied" || error.code === "failed-precondition");
    assert.equal((await db.collection("task_submissions").doc(payableSubmission).get()).data().status, "pending_admin_review");
    assert.equal((await db.collection("earnings").doc(`seized_${payableSubmission}`).get()).exists, false);
    await partialTask.update({ totalLeads: 500 });
    const reassigned = await assignEmployeeTask.run({ taskId: partialTaskId, employeeUid: userId }, managerContext);
    const newAttemptId = reassigned.assignmentIds[0];
    assert.notEqual(newAttemptId, oldAttemptId);
    const newProgress = await partialResume(newAttemptId);
    assert.equal(newProgress.leadsProcessed, 0);
    assert.equal(newProgress.totalLeads, 3);
    assert.equal(newProgress.taskId, partialTaskId);
    await assert.rejects(revokeTaskAssignment.run({ taskId: partialTaskId, employeeUid: userId, assignmentId: oldAttemptId },
        { auth: { uid: leaderId } }), (error) => error.code === "failed-precondition");
    assert.equal((await db.collection("task_assignments").doc(newAttemptId).get()).data().status, "in_progress");
    assert.equal((await db.collection("task_assignments").doc(oldAttemptId).get()).data().status, "revoked");
    const adminWalletRef = db.collection("super_admin_wallet").doc("main");
    const adminBalance = Number((await adminWalletRef.get()).data()?.balance || 0);
    const reviews = await Promise.allSettled([
        reviewSubmissionQA.run({ submissionId: payableSubmission, pass: true, rating: 4 }, managerContext),
        reviewSubmissionQA.run({ submissionId: payableSubmission, pass: true, rating: 4 }, managerContext),
    ]);
    assert.equal(reviews.filter((result) => result.status === "fulfilled").length, 1);
    assert.equal((await adminWalletRef.get()).data().balance, adminBalance + 15);
    assert.equal((await db.collection("worker_wallets").doc(userId).get()).exists, false);
    assert.equal((await db.collection("task_submissions").doc(payableSubmission).get()).data().payoutRecipient, "super_admin");
    const payoutTransactions = await db.collection("transactions").where("referenceId", "==", payableSubmission).get();
    assert.equal(payoutTransactions.docs.filter((doc) => doc.data().source === "seized_payout").length, 1);
    const nextSubmission = await submitTaskWork.run({ taskId: partialTaskId, assignmentId: newAttemptId,
        leadId: newProgress.lead.id, outcome: "not_interested", callDuration: 12 }, context);
    await partialResume(newAttemptId);
    await db.collection("task_assignments").doc(newAttemptId).update({ tatDeadline: acceptedAt });
    await enforceTatAndRecreate.run({});
    assert.equal((await db.collection("task_assignments").doc(newAttemptId).get()).data().status, "out_of_tat");
    assert.equal((await partialTask.get()).data().totalLeads, 2);
    assert.equal((await partialTask.get()).data().status, "pending_team_leader");
    assert.equal((await adminWalletRef.get()).data().balance, adminBalance + 15, "Expiry itself moves no money");
    assert.equal((await db.collection("task_submissions").doc(nextSubmission.submissionId).get()).data().status, "pending_admin_review");
    const partialLeads = await db.collection("campaign_leads").where("taskId", "==", partialTaskId).get();
    assert.equal(partialLeads.size, 5);
    assert.equal(partialLeads.docs.filter((doc) => doc.data().status === "pending").length, 2);
    assert.equal(partialLeads.docs.filter((doc) => doc.data().status === "wrong_number").length, 1);
    assert.equal(partialLeads.docs.filter((doc) => doc.data().status === "approved").length, 1);
    assert.equal(partialLeads.docs.filter((doc) => doc.data().status === "completed").length, 1);
    console.log("partial lifecycle checks passed: 2/5 revoke, pending-only fresh attempt, stable task ID, QA-only single admin payout, TAT recovery");

    const clientApp = initializeApp({ projectId, apiKey: "demo-only", appId: "demo-app" });
    const clientDb = getFirestore(clientApp);
    const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(":");
    connectFirestoreEmulator(clientDb, host, Number(port), { mockUserToken: { sub: userId, user_id: userId } });
    try {
        await assert.rejects(getDocs(query(collection(clientDb, "task_assignments"),
            where("status", "in", ["active", "in_progress", "out_of_tat_processing"]))),
        (error) => error.code === "permission-denied");
        await assert.rejects(updateDoc(doc(clientDb, "tasks", taskId), { acceptedCount: 2 }),
            (error) => error.code === "permission-denied");
        await assert.rejects(setDoc(doc(clientDb, "task_assignments", `${prefix}-bypass`), {
            taskId, userId, status: "active",
        }), (error) => error.code === "permission-denied");
        await assert.rejects(updateDoc(doc(clientDb, "task_assignments", newAttemptId), { status: "completed" }),
            (error) => error.code === "permission-denied");
        await assert.rejects(updateDoc(doc(clientDb, "campaign_leads", `${prefix}-partial-4`), {
            status: "in_progress", assignedTo: userId,
        }), (error) => error.code === "permission-denied");
    } finally {
        await terminate(clientDb);
        await deleteApp(clientApp);
    }
    const leaderApp = initializeApp({ projectId, apiKey: "demo-only", appId: "demo-leader" }, "leader-rules-check");
    const leaderDb = getFirestore(leaderApp);
    connectFirestoreEmulator(leaderDb, host, Number(port), {
        mockUserToken: { sub: leaderId, user_id: leaderId },
    });
    try {
        const liveQuery = query(collection(leaderDb, "task_assignments"),
            where("status", "in", ["active", "in_progress", "out_of_tat_processing"]));
        const live = await getDocs(liveQuery);
        assert.ok(live.size > 0, "Leader can list marketplace work without assignedBy");
        await db.collection("task_assignments").doc(`${prefix}-leader-history`).set({
            userId, taskId, status: "completed", assignedBy: leaderId,
        });
        const liveWorkerId = live.docs[0].data().userId;
        await db.collection("users").doc(liveWorkerId).update({
            name: "Fixture Worker", employeeId: "SHR-7001", phone: "PRIVATE", kycDocument: "PRIVATE",
        });
        const employeeLabels = await getTaskAssignmentEmployees.run({
            assignmentIds: [live.docs[0].id, "missing-assignment"],
        }, { auth: { uid: leaderId } });
        assert.deepStrictEqual(employeeLabels, { employees: [{
            assignmentId: live.docs[0].id, employeeName: "Fixture Worker", employeeId: "SHR-7001",
        }] });
        assert.equal((await getTaskAssignmentEmployees.run({ assignmentIds: [`${prefix}-leader-history`] },
            { auth: { uid: leaderId } })).employees.length, 1);
        await assert.rejects(getTaskAssignmentEmployees.run({ assignmentIds: [live.docs[0].id] }, context),
            (error) => error.code === "permission-denied");
        assert.equal((await getDocs(query(collection(leaderDb, "task_assignments"),
            where("assignedBy", "==", leaderId)))).size, 1);
        assert.equal((await getDoc(doc(leaderDb, "task_assignments", oldAttemptId))).exists(), true);
        assert.ok((await getDocs(query(collection(leaderDb, "task_assignments"),
            where("status", "in", ["completed", "revoked", "cancelled", "rejected", "out_of_tat"])))).size > 0);
        await assert.rejects(getDoc(doc(leaderDb, "users", otherUserId)),
            (error) => error.code === "permission-denied");
        await db.collection("users").doc(otherUserId).update({
            teamLeaderId: managerId, createdBy: managerId, bankAccount: "PRIVATE", kycDocument: "PRIVATE",
        });
        await db.collection("users").doc(managerId).update({ adminId: "ADM-2002", fullName: "Creator Leader" });
        await db.collection("users").doc(leaderId).update({ adminId: "ADM-1001", fullName: "Assigning Leader" });
        const roster = await getTeamLeaderEmployees.run({}, { auth: { uid: leaderId } });
        const sharedEmployee = roster.employees.find((employee) => employee.id === otherUserId);
        assert.equal(sharedEmployee.creatorAdminId, "ADM-2002");
        assert.equal(sharedEmployee.creatorName, "Creator Leader");
        assert.equal(sharedEmployee.bankAccount, undefined);
        assert.equal(sharedEmployee.kycDocument, undefined);
        const sharedTaskId = `${prefix}-shared-task`;
        await db.collection("tasks").doc(sharedTaskId).set({ status: "pending_team_leader", totalLeads: 1 });
        const sharedResult = await assignEmployeeTask.run({ taskId: sharedTaskId, employeeUids: [otherUserId] }, { auth: { uid: leaderId } });
        const sharedAssignment = (await db.collection("task_assignments").doc(sharedResult.assignmentIds[0]).get()).data();
        assert.equal(sharedAssignment.assignedBy, leaderId);
        assert.equal(sharedAssignment.assignedByAdminId, "ADM-1001");
        await assert.rejects(updateDoc(doc(leaderDb, "task_assignments", live.docs[0].id), { status: "revoked" }),
            (error) => error.code === "permission-denied");
        const teamContext = { auth: { uid: leaderId } };
        const teamCampaign = await manageTeamCampaign.run({ action: "createCampaign", campaign: {
            title: "Emulator campaign", clientName: "Test client", payout: 10,
            status: "paused", startDate: "2026-10-01", endDate: "2026-10-31",
        } }, teamContext);
        const uploadRequest = { action: "importTaskLeads", campaignId: teamCampaign.campaignId,
            requestId: `${prefix}-chunk`, taskRequestId: `${prefix}-upload-task`,
            leads: [{ name: "Emulator lead", phone: "9876543210", email: "", notes: "Synthetic" }],
        };
        const uploadedTask = await manageTeamCampaign.run(uploadRequest, teamContext);
        assert.deepStrictEqual(await manageTeamCampaign.run(uploadRequest, teamContext), uploadedTask);
        await manageTeamCampaign.run({ ...uploadRequest, requestId: `${prefix}-chunk-2` }, teamContext);
        assert.equal((await db.collection("tasks").doc(uploadedTask.taskId).get()).data().totalLeads, 2);
        await manageTeamCampaign.run({ action: "importLeads", campaignId: teamCampaign.campaignId,
            requestId: `${prefix}-legacy-upload`, leads: uploadRequest.leads }, teamContext);
        const splitRequest = { action: "createSubtasks", campaignId: teamCampaign.campaignId,
            subtasksCount: 1, tatHours: 48, requestId: `${prefix}-split` };
        const splitResult = await manageTeamCampaign.run(splitRequest, teamContext);
        assert.deepStrictEqual(await manageTeamCampaign.run(splitRequest, teamContext), splitResult);
        assert.equal(splitResult.allocated, 1);
        assert.equal(splitResult.created, 1);
        assert.ok((await getDocs(collection(leaderDb, "campaigns"))).size > 0);
        const visibleLeads = await getDocs(query(collection(leaderDb, "campaign_leads"),
            where("campaignId", "==", teamCampaign.campaignId)));
        assert.equal(visibleLeads.size, 3);
        await assert.rejects(updateDoc(doc(leaderDb, "campaigns", teamCampaign.campaignId), { status: "active" }),
            (error) => error.code === "permission-denied");
        await assert.rejects(updateDoc(doc(leaderDb, "campaign_leads", visibleLeads.docs[0].id), { status: "approved" }),
            (error) => error.code === "permission-denied");
        await assert.rejects(manageTeamCampaign.run(splitRequest, context),
            (error) => error.code === "permission-denied");
        console.log("team campaigns passed: real transactional upload/append/retry, exact split, campaign/lead reads and direct-write denial");
        await db.collection("users").doc(leaderId).update({ isActive: false });
        await assert.rejects(getDocs(liveQuery), (error) => error.code === "permission-denied");
        await assert.rejects(getTaskAssignmentEmployees.run({ assignmentIds: [live.docs[0].id] },
            { auth: { uid: leaderId } }), (error) => error.code === "permission-denied");
        await assert.rejects(getTeamLeaderEmployees.run({}, { auth: { uid: leaderId } }),
            (error) => error.code === "permission-denied");
        await assert.rejects(getTeamLeaderEmployees.run({}, context),
            (error) => error.code === "permission-denied");
    } finally {
        await terminate(leaderDb);
        await deleteApp(leaderApp);
    }
    console.log("leader checks passed: cross-team assignment/revoke, shared history, private-profile/direct-write denial");
    console.log("shared roster passed: real field projection, creator/assigner ADM IDs, claimless leader access, worker/inactive denials");
    console.log("emulator recovery checks passed: atomic uniqueness, last-slot contention, history and legacy write denial");
})().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => admin.app().delete());