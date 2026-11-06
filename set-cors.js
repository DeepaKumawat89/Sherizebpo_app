const admin = require("firebase-admin");

// Initialize from existing service account or default creds
// if the functions folder already has a serviceAccountKey, we could use that.
// Or we can just use application default credentials if gcloud is logged in.
// But wait, do we have admin SDK configured locally?
