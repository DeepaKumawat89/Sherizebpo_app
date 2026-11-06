
const admin = require("firebase-admin");
const fs = require("fs");
admin.initializeApp({
    projectId: "human-cold-bpo"
});
const db = admin.firestore();

// Attempt to use emulator if available, otherwise prod (will likely fail in shell without auth)
if (process.env.FIRESTORE_EMULATOR_HOST) {
    db.settings({ host: process.env.FIRESTORE_EMULATOR_HOST, ssl: false });
}

async function exportSubmissions() {
    console.log("Fetching pending submissions...");
    try {
        const snap = await db.collection("task_submissions")
            .where("status", "==", "pending_admin_review")
            .limit(10)
            .get();
        
        const data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        fs.writeFileSync("submissions_dump.json", JSON.stringify(data, null, 2));
        console.log(`Exported ${data.length} submissions to submissions_dump.json`);
    } catch (err) {
        console.error("Export failed:", err.message);
    }
}

exportSubmissions().then(() => process.exit(0));
