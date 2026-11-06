const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const triggers = {};
const sent = [];
let settings = {};
let settingsError = null;
const functions = {
    firestore: { document: () => ({
        onCreate: (handler) => handler,
        onUpdate: (handler) => handler,
    }) },
};
const admin = {
    apps: [{}],
    firestore: () => ({ collection: (collection) => {
        assert.equal(collection, "platform_settings");
        return { doc: (id) => {
            assert.equal(id, "main");
            return { get: async () => {
                if (settingsError) throw settingsError;
                return { data: () => settings };
            } };
        } };
    } }),
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, "triggers.js"), "utf8"), {
    exports: triggers,
    require: (name) => {
        if (name === "firebase-functions/v1") return functions;
        if (name === "firebase-admin") return admin;
        if (name === "./sendUserNotification") {
            return { sendUserNotification: async (payload) => sent.push(payload) };
        }
        throw new Error(`Unexpected dependency: ${name}`);
    },
});

async function check() {
    for (const status of ["approved", "completed"]) {
        sent.length = 0;
        await triggers.onSubmissionUpdated({
            before: { data: () => ({ status: "pending_admin_review" }) },
            after: { id: "submission", data: () => ({
                status, userId: "employee", taskId: "task", unpricedApproval: true,
            }) },
        });
        assert.equal(sent.length, 1);
        assert.equal(sent[0].title, "Task Approved");
        assert.equal(sent[0].message, "Your task has been approved.");
        assert.equal(sent[0].relatedSubmissionId, "submission");
    }
    const credit = { data: () => ({ type: "credit", userId: "employee", amount: 50 }) };
    for (const enabled of [false, true, undefined]) {
        sent.length = 0;
        settings = enabled === undefined ? undefined : { earningsSystemEnabled: enabled };
        await triggers.onTransactionCreated(credit);
        assert.equal(sent.length, enabled === false ? 0 : 1);
        if (sent.length) assert.equal(sent[0].type, "payment_released");
    }
    sent.length = 0;
    await triggers.onTransactionCreated({ data: () => ({ type: "debit" }) });
    await triggers.onTransactionCreated({ data: () => ({ type: "credit", isWithdrawal: true }) });
    await triggers.onSubmissionUpdated({
        before: { data: () => ({ status: "approved" }) },
        after: { data: () => ({ status: "approved", userId: "employee" }) },
    });
    assert.equal(sent.length, 0);
    settingsError = new Error("Settings unavailable");
    await assert.rejects(triggers.onTransactionCreated(credit), /Settings unavailable/);
    assert.equal(sent.length, 0);
    console.log("Approval and payment notification checks passed.");
}

check().catch((error) => { console.error(error); process.exitCode = 1; });