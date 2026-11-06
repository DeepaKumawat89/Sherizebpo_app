const admin = require('firebase-admin');

// Since we deployed the rule to allow unauthenticated read, wait, admin bypasses rules anyway!
// We must initialize without arguments if it's run via firebase-functions, OR we use application default credentials.
// Let's use the default initialization.
admin.initializeApp({
    projectId: "human-cold-bpo" // Hardcoded for local fallback
});

const db = admin.firestore();

const faqs = [
    {
        question: "What is Sherize?",
        answer: "We are a trusted platform that connects skilled workers with businesses needing efficient BPO tasks. By completing assigned tasks, you earn real money directly into your wallet.",
        category: "General",
        tags: ["about", "bpo", "platform"],
        order: 1,
        isActive: true,
    },
    {
        question: "How do I accept a task?",
        answer: "Go to your main Dashboard, browse the 'Available Tasks' list, tap on a task that interests you, and press 'Accept Task'. It will immediately move to 'My Tasks' so you can begin working.",
        category: "Tasks",
        tags: ["accept", "tasks", "dashboard"],
        order: 2,
        isActive: true,
    },
    {
        question: "Why does it say 'No leads available'?",
        answer: "Every task is backed by a finite number of leads (e.g. phone numbers to call). If all leads have already been assigned to or completed by other users, you won't be able to accept the task.",
        category: "Tasks",
        tags: ["leads", "empty", "error"],
        order: 3,
        isActive: true,
    },
    {
        question: "When and how do I get paid?",
        answer: "Once you submit a completed task, your earnings go to 'Pending'. After an admin reviews and approves your submission, the funds are added to your primary Wallet. You can request a withdrawal at any time once you reach the minimum balance.",
        category: "Payments",
        tags: ["salary", "payment", "withdraw", "wallet"],
        order: 4,
        isActive: true,
    },
    {
        question: "How do I update my bank details?",
        answer: "To receive payouts, go to Settings > Edit Profile > Bank Details. Enter your secure Account Number and IFSC Code. Ensure the name matches your KYC exactly.",
        category: "Payments",
        tags: ["bank", "account", "ifsc"],
        order: 5,
        isActive: true,
    },
    {
        question: "Why do I need to complete KYC?",
        answer: "KYC (Know Your Customer) verification is required by law to process your payouts. It helps us prevent fraud and ensures an equitable environment for all workers.",
        category: "KYC",
        tags: ["kyc", "verification", "auth"],
        order: 6,
        isActive: true,
    },
    {
        question: "How long does KYC verification take?",
        answer: "Our team reviews all submitted ID documents manually. Typically, your KYC status will update within 24 to 48 hours.",
        category: "KYC",
        tags: ["time", "status", "pending"],
        order: 7,
        isActive: true,
    },
    {
        question: "Why are my profile changes not saving?",
        answer: "Please ensure you have an active internet connection. All profile updates are securely synced with our servers. If an error persists, try restarting the app or submitting a Bug Report.",
        category: "Technical",
        tags: ["bug", "profile", "save", "network"],
        order: 8,
        isActive: true,
    },
    {
        question: "Do I have to log in every time?",
        answer: "No! As long as you don't explicitly tap 'Logout' in the Settings menu, your session is securely persisted and you will remain logged in even if you close the app.",
        category: "General",
        tags: ["login", "session", "logout"],
        order: 9,
        isActive: true,
    },
    {
        question: "How do I report a missing payment?",
        answer: "If you notice an anomaly with your wallet balance after an approval, go to Settings > Help & Support > Contact Us, select 'Payment Problem' as the Issue Type, and submit your request. Our team usually responds within 24 hours.",
        category: "Payments",
        tags: ["support", "missing", "issue"],
        order: 10,
        isActive: true,
    }
];

async function seed() {
    try {
        console.log("Seeding FAQs into Firestore...");
        let batchCount = 0;
        
        for (const faq of faqs) {
            faq.createdAt = admin.firestore.FieldValue.serverTimestamp();
            faq.updatedAt = admin.firestore.FieldValue.serverTimestamp();
            
            await db.collection("faqs").add(faq);
            batchCount++;
            console.log(`Added FAQ: ${faq.question}`);
        }
        
        console.log(`Successfully added ${batchCount} FAQs.`);
        process.exit(0);
    } catch (e) {
        console.error("Error seeding FAQs: ", e);
        process.exit(1);
    }
}

seed();
