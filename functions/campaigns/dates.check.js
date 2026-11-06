const assert = require("node:assert/strict");
const Module = require("node:module");
const documents = new Map();
let nextId = 0;
const db = {
    collection: (name) => ({
        where: () => ({ limit: () => ({ get: async () => ({ empty: true }) }) }),
        doc: (id = `campaign-${++nextId}`) => ({
            id,
            path: `${name}/${id}`,
            get: async () => ({ exists: documents.has(`${name}/${id}`), data: () => documents.get(`${name}/${id}`) }),
            set: async (data) => documents.set(`${name}/${id}`, data),
        }),
    }),
    runTransaction: async (handler) => {
        const writes = [];
        const result = await handler({
            get: (ref) => ref.get(),
            set: (ref, data) => writes.push(() => documents.set(ref.path, data)),
            update: (ref, data) => writes.push(() => documents.set(ref.path, { ...documents.get(ref.path), ...data })),
        });
        writes.forEach((write) => write());
        return result;
    },
};
const firestore = () => db;
firestore.FieldValue = { serverTimestamp: () => "server-time" };
const originalLoad = Module._load;
let createCampaign;
try {
    Module._load = function (name, ...args) {
        if (name === "firebase-admin") return { firestore };
        return originalLoad.call(this, name, ...args);
    };
    ({ createCampaign } = require("./createCampaign"));
} finally {
    Module._load = originalLoad;
}

async function main() {
    const context = { auth: { uid: "client-test", token: {} } };
    const base = { title: "Date check", payout: 10, budget: 100 };
    for (const paymentsVisible of [false, true]) {
        documents.clear();
        documents.set("platform_settings/main", { clientPaymentsVisible: paymentsVisible });
        documents.set("client_wallets/client-test", { balance: 10000, reservedBalance: 0 });
        for (const dates of [
            {},
            { startDate: "2028-02-29", endDate: "2028-02-29" },
            { startDate: "2026-09-21", endDate: "2026-10-01" },
            { startDate: "2026-09-21" },
            { endDate: "2026-10-01" },
        ]) {
            const result = await createCampaign.run({ ...base, ...dates }, context);
            const saved = documents.get(`campaigns/${result.campaignId}`);
            assert.equal(saved.startDate, dates.startDate || "");
            assert.equal(saved.endDate, dates.endDate || "");
        }
        for (const dates of [
            { startDate: "2026-09-22", endDate: "2026-09-21" },
            { startDate: "2026-02-29" },
            { endDate: "2026-04-31" },
            { startDate: "2026-09-21T00:00:00Z" },
            { endDate: {} },
            { startDate: 123 },
        ]) {
            const before = JSON.stringify([...documents]);
            await assert.rejects(createCampaign.run({ ...base, ...dates }, context), { code: "invalid-argument" });
            assert.equal(JSON.stringify([...documents]), before, "Invalid dates must not reserve funds or write campaigns");
        }
    }
    console.log("PASS: campaign dates persist in priced/unpriced modes; optional, same-day and leap dates accepted; invalid ranges/dates rejected without writes");
}
main().catch((error) => { console.error(error); process.exitCode = 1; });