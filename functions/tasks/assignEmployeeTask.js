const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { validateActiveManager } = require("../utils/teamLeaderAccess");

const MAX_EMPLOYEES_PER_TASK = 50;

function assignmentPlan(task, employeeCount) {
    const totalLeads = Number(task.totalLeads ?? 0);
    if (task.status !== "pending_team_leader") {
        throw new functions.https.HttpsError("failed-precondition", "This task has already been distributed.");
    }
    return {
        taskUpdate: {
            status: "active",
            distributionMode: "individual",
            totalSlots: employeeCount,
            remainingSlots: 0,
            acceptedCount: employeeCount,
        },
        quota: Math.ceil(totalLeads / employeeCount),
    };
}

exports.assignEmployeeTask = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }

    const rawEmployeeUids = Array.isArray(data?.employeeUids) ? data.employeeUids : [data?.employeeUid];
    const employeeUids = [...new Set(rawEmployeeUids.map((uid) => String(uid || "").trim()).filter(Boolean))];
    const taskId = String(data?.taskId || "").trim();
    if (!taskId || employeeUids.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "At least one employee and a task are required.");
    }
    if (employeeUids.length > MAX_EMPLOYEES_PER_TASK) {
        throw new functions.https.HttpsError("invalid-argument", `Select at most ${MAX_EMPLOYEES_PER_TASK} employees.`);
    }

    const db = admin.firestore();
    const { user: manager } = await validateActiveManager(db, context.auth.uid);
    const taskRef = db.collection("tasks").doc(taskId);
    const employeeRefs = employeeUids.map((uid) => db.collection("users").doc(uid));
    const assignmentRefs = employeeUids.map((uid) => db.collection("task_assignments").doc(`${uid}_${taskId}`));
    const retryAssignmentRefs = employeeUids.map(() => db.collection("task_assignments").doc());

    const assignmentIds = await db.runTransaction(async (transaction) => {
        const [taskSnap, employeeSnaps, assignmentSnaps] = await Promise.all([
            transaction.get(taskRef),
            Promise.all(employeeRefs.map((ref) => transaction.get(ref))),
            Promise.all(assignmentRefs.map((ref) => transaction.get(ref))),
        ]);

        if (!taskSnap.exists) {
            throw new functions.https.HttpsError("not-found", "Task not found.");
        }
        if (assignmentSnaps.some((snapshot) => snapshot.exists &&
            !["completed", "out_of_tat", "revoked", "cancelled", "rejected"].includes(snapshot.data().status))) {
            throw new functions.https.HttpsError("already-exists", "This task is already assigned to one of the selected employees.");
        }
        const activeAssignments = await transaction.get(db.collection("task_assignments")
            .where("taskId", "==", taskId)
            .where("status", "in", ["active", "in_progress", "out_of_tat_processing"])
            .limit(1));
        if (!activeAssignments.empty) {
            throw new functions.https.HttpsError("failed-precondition", "This task still has an active assignment.");
        }
        const nextAssignmentRefs = assignmentRefs.map((ref, index) =>
            assignmentSnaps[index].exists ? retryAssignmentRefs[index] : ref);

        const employees = employeeSnaps.map((snapshot) => {
            if (!snapshot.exists || snapshot.data().role !== "worker") {
                throw new functions.https.HttpsError("not-found", "Employee not found.");
            }
            const employee = snapshot.data();
            if (employee.isActive === false) {
                throw new functions.https.HttpsError("failed-precondition", "A selected employee account is inactive.");
            }
            if (!["approved", "verified"].includes(String(employee.kycStatus || employee.kyc_status || "").toLowerCase())) {
                throw new functions.https.HttpsError("failed-precondition", "All selected employees must have approved KYC.");
            }
            return employee;
        });

        const task = taskSnap.data();
        let totalLeads = Number(task.totalLeads || 0);
        if (task.campaignId) {
            const campaignSnap = await transaction.get(db.collection("campaigns").doc(task.campaignId));
            if (!campaignSnap.exists || campaignSnap.data().status !== "active") {
                throw new functions.https.HttpsError("failed-precondition", "Activate the campaign before assigning this task.");
            }
            const pendingLeads = await transaction.get(db.collection("campaign_leads")
                .where("taskId", "==", taskId)
                .where("status", "==", "pending")
                .count());
            totalLeads = pendingLeads.data().count;
            if (!totalLeads) {
                throw new functions.https.HttpsError("failed-precondition", "This task has no pending leads to assign.");
            }
        }
        if (totalLeads < employeeUids.length) {
            throw new functions.https.HttpsError("failed-precondition", "Select no more employees than pending leads.");
        }
        const plan = assignmentPlan({ ...task, totalLeads }, employeeUids.length);

        const assignedAt = admin.firestore.Timestamp.now();
        const tatHours = Number(task.tatHours ?? 3);
        const tatDeadline = admin.firestore.Timestamp.fromMillis(
            assignedAt.toMillis() + Math.max(tatHours, 0.25) * 60 * 60 * 1000
        );
        transaction.update(taskRef, {
            ...plan.taskUpdate,
            totalLeads,
            distributedByTeamLeaderId: context.auth.uid,
            distributedAt: assignedAt,
        });
        nextAssignmentRefs.forEach((assignmentRef, index) => transaction.set(assignmentRef, {
            taskId,
            userId: employeeUids[index],
            workerId: employeeUids[index],
            employeeId: employees[index].employeeId || employees[index].workerId || "",
            status: "active",
            acceptedAt: assignedAt,
            assignedAt,
            assignedBy: context.auth.uid,
            assignedByAdminId: manager.adminId || "",
            assignedByName: manager.fullName || manager.name || "",
            tatDeadline,
            title: task.title || "",
            payout: task.payout || 0,
            clientName: task.clientName || "",
            campaignId: task.campaignId || "",
            totalLeads: Math.floor(totalLeads / employeeUids.length) + (index < totalLeads % employeeUids.length ? 1 : 0),
            leadsProcessed: 0,
            processedLeadIds: [],
        }));
        return nextAssignmentRefs.map((ref) => ref.id);
    });

    return { assignmentIds, success: true };
});

exports.getTaskAssignmentEmployees = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }
    const ids = data?.assignmentIds;
    if (!Array.isArray(ids) || ids.length === 0 || ids.length > 50 ||
        ids.some((id) => typeof id !== "string" || !id.trim() || id.includes("/") ||
            id === "." || id === ".." || id.length > 1500)) {
        throw new functions.https.HttpsError("invalid-argument", "Provide between 1 and 50 valid assignment IDs.");
    }
    const db = admin.firestore();
    await validateActiveManager(db, context.auth.uid);
    const snapshots = await db.getAll(...[...new Set(ids)].map((id) => db.collection("task_assignments").doc(id)));
    const assignments = snapshots.filter((snapshot) => {
        if (!snapshot.exists) return false;
        const assignment = snapshot.data();
        return typeof assignment.userId === "string" && assignment.userId.length > 0 && !assignment.userId.includes("/");
    });
    if (!assignments.length) return { employees: [] };
    const userIds = [...new Set(assignments.flatMap((snapshot) => [snapshot.data().userId, snapshot.data().assignedBy])
        .filter((uid) => typeof uid === "string" && uid.length > 0 && !uid.includes("/")))];
    const employees = await db.getAll(...userIds.map((uid) => db.collection("users").doc(uid)),
        { fieldMask: ["name", "fullName", "employeeId", "workerId", "adminId"] });
    const users = new Map(employees.map((snapshot) => [snapshot.id, snapshot.data() || {}]));
    return {
        employees: assignments.map((snapshot) => {
            const assignment = snapshot.data();
            const user = users.get(assignment.userId);
            const manager = users.get(assignment.assignedBy) || {};
            const displayValue = (values) => values.find((value) => typeof value === "string" &&
                value.trim() && value.trim() !== assignment.userId)?.trim() || "";
            return {
                assignmentId: snapshot.id,
                employeeName: displayValue([user.name, user.fullName, assignment.employeeName]),
                employeeId: displayValue([user.employeeId, user.workerId, assignment.employeeId]),
                ...(assignment.assignedBy ? {
                    assignedByName: assignment.assignedByName || manager.fullName || manager.name || "",
                    assignedByAdminId: assignment.assignedByAdminId || manager.adminId || "",
                } : {}),
            };
        }),
    };
});

exports.getTeamLeaderEmployees = functions.https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
    }
    const db = admin.firestore();
    await validateActiveManager(db, context.auth.uid);
    const snapshot = await db.collection("users").where("role", "==", "worker")
        .select("name", "fullName", "employeeId", "workerId", "phone", "contactEmail", "isActive",
            "kycStatus", "kyc_status", "teamLeaderId", "createdBy", "createdAt").get();
    const creatorIds = [...new Set(snapshot.docs.map((employee) => employee.data().createdBy || employee.data().teamLeaderId)
        .filter((uid) => typeof uid === "string" && uid.length > 0 && !uid.includes("/")))];
    const creators = creatorIds.length ? await db.getAll(...creatorIds.map((uid) => db.collection("users").doc(uid)),
        { fieldMask: ["name", "fullName", "adminId"] }) : [];
    const creatorMap = new Map(creators.map((creator) => [creator.id, creator.data() || {}]));
    return { employees: snapshot.docs.map((employee) => {
        const data = employee.data();
        const creator = creatorMap.get(data.createdBy || data.teamLeaderId) || {};
        return { ...data, id: employee.id, creatorName: creator.fullName || creator.name || "",
            creatorAdminId: creator.adminId || "" };
    }) };
});

exports.assignmentPlan = assignmentPlan;