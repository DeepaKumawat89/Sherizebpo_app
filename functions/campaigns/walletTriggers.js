const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

// ─── Setup Nodemailer Transporter ─────────────────────────────
// Gmail App Passwords display with spaces ("abcd efgh ijkl mnop") that are not
// part of the secret; keeping them triggers 535 BadCredentials. Strip all
// whitespace so the pasted app password authenticates.
const SMTP_EMAIL = (functions.config().smtp?.email || process.env.SMTP_EMAIL || "").trim();
const SMTP_PASSWORD = (functions.config().smtp?.password || process.env.SMTP_PASSWORD || "").replace(/\s+/g, "");

const mailTransport = nodemailer.createTransport({
    service: "gmail",
    auth: {
        user: SMTP_EMAIL,
        pass: SMTP_PASSWORD,
    },
});

exports.onClientWalletUpdated = functions.firestore
    .document("client_wallets/{clientId}")
    .onUpdate(async (change, context) => {
        const clientId = context.params.clientId;
        const beforeData = change.before.data();
        const afterData = change.after.data();

        const beforeBalance = Number(beforeData.balance || 0);
        const afterBalance = Number(afterData.balance || 0);

        const db = admin.firestore();

        // Configurable low-balance pause threshold (platform_settings/main),
        // falling back to ₹50 when unset.
        let threshold = 50;
        try {
            const cfgSnap = await db.collection("platform_settings").doc("main").get();
            if (cfgSnap.exists && cfgSnap.data().lowBalanceThreshold != null) {
                threshold = Number(cfgSnap.data().lowBalanceThreshold) || 50;
            }
        } catch (cfgErr) {
            console.warn("[Wallet] Could not read lowBalanceThreshold; using ₹50.", cfgErr.message);
        }

        // ──────────────────────────────────────────────────────────────
        // SCENARIO 1: Balance drops below threshold (PAUSE CAMPAIGNS)
        // ──────────────────────────────────────────────────────────────
        if (beforeBalance >= threshold && afterBalance < threshold) {
            console.log(`[Wallet] Client ${clientId} balance dropped below ₹${threshold} (Currently: ₹${afterBalance}). Pausing campaigns...`);

            const batch = db.batch();
            const emailMessages = [];

            // 1. Find all active campaigns for this client
            const campaignsQuery = await db.collection("campaigns")
                .where("clientId", "==", clientId)
                .where("status", "==", "active")
                .get();

            let hasCampaignsToPause = campaignsQuery.docs.length > 0;
            
            for (const doc of campaignsQuery.docs) {
                const campaignRef = doc.ref;
                batch.update(campaignRef, { 
                    status: "paused_low_balance",
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });

                const data = doc.data();
                const totalLeads = Number(data.totalLeads || 0);
                const completedLeads = Number(data.completedLeads || 0);
                const percentage = totalLeads > 0 
                    ? Math.round((completedLeads / totalLeads) * 100) 
                    : 0;

                emailMessages.push(
                    `<li><strong>${data.name || "Campaign"}</strong>: ${percentage}% completed (${completedLeads}/${totalLeads} leads).</li>`
                );

                // 2. Find and pause related tasks for this campaign
                const tasksQuery = await db.collection("tasks")
                    .where("campaignId", "==", doc.id)
                    .where("status", "==", "active")
                    .get();

                for (const taskDoc of tasksQuery.docs) {
                    batch.update(taskDoc.ref, { 
                        status: "paused_low_balance",
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                }
            }

            if (hasCampaignsToPause) {
                await batch.commit();
                console.log(`[Wallet] Successfully paused campaigns and tasks for ${clientId}`);

                // 3. Send Email Notification
                await sendLowBalanceEmail(clientId, afterBalance, emailMessages.join(""), db);
            }
        } 
        
        // ─────────────────────────────────────────────────────────────────
        // SCENARIO 2: Balance recharges to 50 or above (RESUME CAMPAIGNS)
        // ─────────────────────────────────────────────────────────────────
        else if (beforeBalance < threshold && afterBalance >= threshold) {
            console.log(`[Wallet] Client ${clientId} wallet recharged to ₹${afterBalance}. Resuming paused campaigns...`);

            const batch = db.batch();

            // 1. Find all 'paused_low_balance' campaigns for this client
            const campaignsQuery = await db.collection("campaigns")
                .where("clientId", "==", clientId)
                .where("status", "==", "paused_low_balance")
                .get();

            let hasCampaignsToResume = campaignsQuery.docs.length > 0;

            for (const doc of campaignsQuery.docs) {
                batch.update(doc.ref, { 
                    status: "active",
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });

                // 2. Find and resume related 'paused_low_balance' tasks
                const tasksQuery = await db.collection("tasks")
                    .where("campaignId", "==", doc.id)
                    .where("status", "==", "paused_low_balance")
                    .get();

                for (const taskDoc of tasksQuery.docs) {
                    batch.update(taskDoc.ref, { 
                        status: "active",
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                }
            }

            if (hasCampaignsToResume) {
                await batch.commit();
                console.log(`[Wallet] Successfully resumed campaigns and tasks for ${clientId}`);
                // Sending a resume confirmation email is nice but optional. 
                // sendRechargedEmail(clientId, afterBalance, db);
            }
        }
    });

/**
 * Helper: Sends the Low Balance warning email to the client using Nodemailer
 */
async function sendLowBalanceEmail(clientId, currentBalance, campaignListHtml, db) {
    try {
        const userDoc = await db.collection("users").doc(clientId).get();
        if (!userDoc.exists) return;

        const email = userDoc.data().email;
        const name = userDoc.data().name || "Client";

        if (!email) {
            console.warn(`[Wallet] Cannot send email to ${clientId}: No email address on file.`);
            return;
        }

        const mailOptions = {
            from: `"Human BPO / Sherize" <${SMTP_EMAIL}>`,
            to: email,
            subject: "Action Required: Campaigns Paused due to Low Wallet Balance",
            html: `
                <div style="font-family: Arial, sans-serif; padding: 20px; color: #333; max-width: 600px; line-height: 1.6;">
                    <h2 style="color: #DC2626;">Wallet Balance Critically Low</h2>
                    <p>Hello ${name},</p>
                    <p>Your wallet balance has dropped to <strong>₹${currentBalance.toFixed(2)}</strong>, which is below the minimum required balance of ₹50.</p>
                    <p>To prevent any interruptions to our workers answering and completing your tasks, <strong>all of your active continuous campaigns have been paused automatically</strong>.</p>
                    
                    ${campaignListHtml ? `
                    <div style="background-color: #F9FAFB; padding: 15px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #F59E0B;">
                        <h4 style="margin-top: 0;">Campaign Summary:</h4>
                        <ul style="padding-left: 20px; margin-bottom: 0;">
                            ${campaignListHtml}
                        </ul>
                    </div>
                    ` : ""}

                    <p><strong>Please log into your client portal and load more funds into your wallet to resume your campaigns automatically.</strong></p>
                    
                    <p>Thank you,<br/>The Sherize Team</p>
                </div>
            `,
        };

        await mailTransport.sendMail(mailOptions);
        console.log(`[Wallet] Sent low balance email to ${email}`);
    } catch (err) {
        console.error(`[Wallet] Error sending low balance email to client ${clientId}:`, err);
    }
}
