/**
 * processLeadSheet — Storage-triggered Cloud Function
 *
 * Fires when a file is uploaded to: lead_sheets/{campaignId}/{fileName}
 * 
 * Flow:
 *   1. Download file from Storage
 *   2. Detect format (CSV / XLSX)
 *   3. Parse rows with streaming (CSV) or read-excel-file (Excel)
 *   4. Validate: Name + Phone required, phone normalization
 *   5. Deduplicate: within-file + against existing Firestore leads
 *   6. Batch write to campaign_leads (500 per batch)
 *   7. Track job status in lead_uploads/{uploadId}
 *
 * Filename convention: {uploadId}_{originalName}.csv
 * The uploadId maps to the lead_uploads doc for status tracking.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const readXlsxFile = require("read-excel-file/node");
const os = require("os");
const path = require("path");
const fs = require("fs");
const csvParser = require("csv-parser");

// Ensure admin is initialized (safe to call multiple times)
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

// ─── Phone Validation & Normalization (Indian) ───────────────────
function normalizePhone(raw) {
    if (!raw) return null;

    // Convert to string, strip whitespace, dashes, dots, parens
    let phone = String(raw).replace(/[\s\-\.\(\)]/g, "");

    // Remove leading + if present
    if (phone.startsWith("+")) {
        phone = phone.substring(1);
    }

    // Handle 91XXXXXXXXXX (12 digits with country code)
    if (phone.startsWith("91") && phone.length === 12) {
        phone = phone.substring(2);
    }

    // Handle 0XXXXXXXXXX (11 digits with leading zero)
    if (phone.startsWith("0") && phone.length === 11) {
        phone = phone.substring(1);
    }

    // Must be exactly 10 digits
    if (!/^\d{10}$/.test(phone)) {
        return null;
    }

    // Must start with valid Indian mobile prefix (6-9)
    if (!/^[6-9]/.test(phone)) {
        return null;
    }

    return phone;
}

// ─── Flexible Column Mapping ─────────────────────────────────────
function extractFields(row) {
    // Build a case-insensitive lookup
    const lower = {};
    for (const key of Object.keys(row)) {
        lower[key.toLowerCase().trim()] = row[key];
    }

    const name = (
        lower["name"] || lower["full name"] || lower["fullname"] ||
        lower["customer name"] || lower["lead name"] || lower["contact name"] || ""
    ).toString().trim();

    const phoneRaw = (
        lower["phone"] || lower["phone number"] || lower["phonenumber"] ||
        lower["mobile"] || lower["mobile number"] || lower["contact"] ||
        lower["cell"] || lower["telephone"] || ""
    ).toString().trim();

    const email = (
        lower["email"] || lower["email address"] || lower["emailaddress"] || ""
    ).toString().trim();

    const city = (
        lower["city"] || lower["location"] || lower["area"] || ""
    ).toString().trim();

    return { name, phoneRaw, email, city };
}

// ─── Parse CSV using line-by-line processing ─────────────────────
function parseCSV(buffer) {
    const content = buffer.toString("utf-8");
    const lines = content.split(/\r?\n/).filter(line => line.trim() !== "");

    if (lines.length < 2) return []; // Need at least header + 1 row

    // Parse header
    const headers = parseCSVLine(lines[0]);
    const rows = [];

    for (let i = 1; i < lines.length; i++) {
        const values = parseCSVLine(lines[i]);
        if (values.length === 0) continue;

        const row = {};
        for (let j = 0; j < headers.length; j++) {
            row[headers[j]] = values[j] || "";
        }
        rows.push(row);
    }

    return rows;
}

// ─── Parse a single CSV line (handles quoted fields) ─────────────
function parseCSVLine(line) {
    const result = [];
    let current = "";
    let inQuotes = false;

    for (let i = 0; i < line.length; i++) {
        const char = line[i];

        if (inQuotes) {
            if (char === '"') {
                if (i + 1 < line.length && line[i + 1] === '"') {
                    current += '"';
                    i++; // Skip escaped quote
                } else {
                    inQuotes = false;
                }
            } else {
                current += char;
            }
        } else {
            if (char === '"') {
                inQuotes = true;
            } else if (char === ',') {
                result.push(current.trim());
                current = "";
            } else {
                current += char;
            }
        }
    }

    result.push(current.trim());
    return result;
}

// ─── Parse Excel ─────────────────────────────────────────────────
async function parseExcel(buffer) {
    const [headers = [], ...dataRows] = await readXlsxFile(buffer);
    return dataRows
        .filter((values) => values.some((value) => value !== null && value !== ""))
        .map((values) => Object.fromEntries(
            headers.map((header, index) => [String(header ?? "").trim(), values[index] ?? ""])
        ));
}

// ─── Fetch Existing Phones for Campaign ──────────────────────────
async function getExistingPhones(campaignId) {
    const phones = new Set();
    const snapshot = await db
        .collection("campaign_leads")
        .where("campaignId", "==", campaignId)
        .select("phone")
        .get();

    snapshot.forEach(doc => {
        const phone = doc.data().phone;
        if (phone) phones.add(phone);
    });

    return phones;
}

// ─── Update Job Status ──────────────────────────────────────────
async function updateJobStatus(uploadId, data) {
    try {
        await db.collection("lead_uploads").doc(uploadId).set(data, { merge: true });
    } catch (err) {
        console.error(`Failed to update job status for ${uploadId}:`, err.message);
    }
}

// ═══════════════════════════════════════════════════════════════════
// MAIN: Storage-triggered Cloud Function
// ═══════════════════════════════════════════════════════════════════

exports.processLeadSheet = functions
    .runWith({
        timeoutSeconds: 540,
        memory: "1GB",
    })
    .storage.object()
    .onFinalize(async (object) => {
        const filePath = object.name; // e.g. lead_sheets/campaignId/uploadId_file.csv
        const contentType = object.contentType;

        // Only process files in lead_sheets/
        if (!filePath || !filePath.startsWith("lead_sheets/")) {
            console.log(`Ignoring file outside lead_sheets/: ${filePath}`);
            return null;
        }

        // Extract campaignId and fileName from path
        const pathParts = filePath.split("/");
        if (pathParts.length < 3) {
            console.error(`Invalid path structure: ${filePath}`);
            return null;
        }

        const campaignId = pathParts[1];
        const fileName = pathParts.slice(2).join("/");

        // Extract uploadId from fileName (format: uploadId_originalname.ext)
        const underscoreIndex = fileName.indexOf("_");
        if (underscoreIndex === -1) {
            console.error(`Filename missing uploadId prefix: ${fileName}`);
            return null;
        }

        const uploadId = fileName.substring(0, underscoreIndex);
        const originalName = fileName.substring(underscoreIndex + 1);
        const extension = originalName.split(".").pop().toLowerCase();

        console.log(`Processing lead sheet: campaign=${campaignId}, upload=${uploadId}, file=${originalName}`);

        // Validate file extension
        if (!["csv", "xlsx"].includes(extension)) {
            await updateJobStatus(uploadId, {
                status: "failed",
            error: `Unsupported file format: .${extension}. Use CSV or XLSX.`,
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return null;
        }

        // ── Idempotency Guard ─────────────────────────────────────────
        // onFinalize fires on BOTH file creation AND metadata updates,
        // which causes duplicate processing (e.g. 4 leads → 8 leads).
        // Skip if metageneration > 1 (metadata-only event, not a new upload).
        const metageneration = parseInt(object.metageneration || "1", 10);
        if (metageneration > 1) {
            console.log(`Skipping metadata-only event (metageneration=${metageneration}) for ${uploadId}`);
            return null;
        }

        // Also check Firestore: if this uploadId is already processing/completed, skip.
        const existingJob = await db.collection("lead_uploads").doc(uploadId).get();
        if (existingJob.exists) {
            const existingStatus = existingJob.data().status;
            if (existingStatus === "processing" || existingStatus === "completed") {
                console.log(`Skipping duplicate trigger for uploadId=${uploadId} (status: ${existingStatus})`);
                return null;
            }
        }

        // Initialize job status
        await updateJobStatus(uploadId, {
            status: "processing",
            campaignId,
            fileName: originalName,
            progress: 5,
            startedAt: admin.firestore.FieldValue.serverTimestamp(),
            totalRows: 0,
            validLeads: 0,
            duplicatesSkipped: 0,
            errorsSkipped: 0,
        });

        try {
            // ── Step 1: Download file from Storage ───────────────
            await updateJobStatus(uploadId, { progress: 10, progressLabel: "Downloading file..." });

            const bucket = admin.storage().bucket(object.bucket);
            const tempFilePath = path.join(os.tmpdir(), `lead_${uploadId}.${extension}`);
            await bucket.file(filePath).download({ destination: tempFilePath });

            // ── Step 2: Parse file ───────────────────────────────
            await updateJobStatus(uploadId, { progress: 20, progressLabel: "Parsing file..." });

            let rows = [];
            if (extension === "csv") {
                await new Promise((resolve, reject) => {
                    fs.createReadStream(tempFilePath)
                        .pipe(csvParser())
                        .on('data', (data) => rows.push(data))
                        .on('end', () => resolve())
                        .on('error', (error) => reject(error));
                });
            } else {
                const fileBuffer = fs.readFileSync(tempFilePath);
                rows = await parseExcel(fileBuffer);
            }

            const totalRows = rows.length;
            console.log(`Parsed ${totalRows} rows from ${originalName}`);

            if (totalRows === 0) {
                // Clean up temp file
                fs.unlinkSync(tempFilePath);
                await updateJobStatus(uploadId, {
                    status: "failed",
                    error: "The uploaded file is empty or has no data rows.",
                    progress: 100,
                    totalRows: 0,
                    completedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                return null;
            }

            await updateJobStatus(uploadId, { totalRows, progress: 30, progressLabel: "Validating data..." });

            // ── Step 3: Validate & Normalize ─────────────────────
            const validLeads = [];
            const seenPhones = new Set();
            let errorsSkipped = 0;
            let withinFileDuplicates = 0;

            for (const row of rows) {
                const { name, phoneRaw, email, city } = extractFields(row);

                // Validate required fields
                if (!name) {
                    errorsSkipped++;
                    continue;
                }

                const phone = normalizePhone(phoneRaw);
                if (!phone) {
                    errorsSkipped++;
                    continue;
                }

                // Within-file dedup
                if (seenPhones.has(phone)) {
                    withinFileDuplicates++;
                    continue;
                }

                seenPhones.add(phone);
                validLeads.push({ name, phone, email, city });
            }

            console.log(`Validation: ${validLeads.length} valid, ${errorsSkipped} errors, ${withinFileDuplicates} in-file duplicates`);

            await updateJobStatus(uploadId, {
                progress: 50,
                progressLabel: "Checking for existing duplicates...",
                errorsSkipped,
            });

            // ── Step 4: Cross-Firestore Deduplication ────────────
            const existingPhones = await getExistingPhones(campaignId);
            let crossDuplicates = 0;

            const newLeads = validLeads.filter(lead => {
                if (existingPhones.has(lead.phone)) {
                    crossDuplicates++;
                    return false;
                }
                return true;
            });

            const totalDuplicatesSkipped = withinFileDuplicates + crossDuplicates;

            console.log(`Dedup: ${crossDuplicates} cross-Firestore duplicates. ${newLeads.length} new leads to store.`);

            await updateJobStatus(uploadId, {
                progress: 60,
                progressLabel: `Storing ${newLeads.length} leads...`,
                validLeads: newLeads.length,
                duplicatesSkipped: totalDuplicatesSkipped,
            });

            // ── Step 5: Batch Write to Firestore ─────────────────
            if (newLeads.length > 0) {
                const batchSize = 500;
                let totalStored = 0;

                // Get clientId from the campaign document
                let clientId = null;
                try {
                    const campaignDoc = await db.collection("campaigns").doc(campaignId).get();
                    if (campaignDoc.exists) {
                        clientId = campaignDoc.data().clientId || null;
                    }
                } catch (err) {
                    console.warn("Could not fetch campaign clientId:", err.message);
                }

                for (let i = 0; i < newLeads.length; i += batchSize) {
                    const batch = db.batch();
                    const chunk = newLeads.slice(i, i + batchSize);

                    for (const lead of chunk) {
                        const leadRef = db.collection("campaign_leads").doc();
                        batch.set(leadRef, {
                            ...lead,
                            campaignId,
                            clientId,
                            taskId: null,
                            status: "pending",
                            uploadId,
                            createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                    }

                    await batch.commit();
                    totalStored += chunk.length;

                    // Update progress (60-90% range for storing)
                    const storeProgress = 60 + Math.round((totalStored / newLeads.length) * 30);
                    await updateJobStatus(uploadId, {
                        progress: storeProgress,
                        progressLabel: `Stored ${totalStored} / ${newLeads.length} leads...`,
                    });
                }

                console.log(`Stored ${totalStored} leads for campaign ${campaignId}`);

                // ── Step 6: Update Campaign Totals ────────────────
                try {
                    const currentLeadsSnapshot = await db
                        .collection("campaign_leads")
                        .where("campaignId", "==", campaignId)
                        .count()
                        .get();

                    const totalLeadsCount = currentLeadsSnapshot.data().count;

                    await db.collection("campaigns").doc(campaignId).update({
                        totalLeads: totalLeadsCount,
                        lastUploadAt: admin.firestore.FieldValue.serverTimestamp(),
                    });

                } catch (err) {
                    console.warn("Could not update campaign totals:", err.message);
                }
            }

            // ── Step 7: Mark Complete ────────────────────────────
            // Clean up temp file
            try { fs.unlinkSync(tempFilePath); } catch (e) { console.warn("Temp cleanup failed:", e); }

            await updateJobStatus(uploadId, {
                status: "completed",
                progress: 100,
                progressLabel: "Complete!",
                validLeads: newLeads.length,
                duplicatesSkipped: totalDuplicatesSkipped,
                errorsSkipped,
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`✅ Lead processing complete for upload ${uploadId}: ${newLeads.length} new, ${totalDuplicatesSkipped} dupes, ${errorsSkipped} errors`);
            return null;

        } catch (error) {
            console.error(`❌ Lead processing failed for ${uploadId}:`, error);

            await updateJobStatus(uploadId, {
                status: "failed",
                progress: 100,
                error: error.message || "An unexpected error occurred during processing.",
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            return null;
        }
    });
