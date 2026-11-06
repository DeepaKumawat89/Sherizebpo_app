// One-off: apply CORS to the Storage bucket so the Flutter WEB admin app
// (CanvasKit renderer) can load support screenshots / KYC docs. CanvasKit draws
// network images onto a WebGL canvas, which requires the host to return CORS
// headers — Firebase Storage does not by default, so cross-origin image loads
// fail with "Could not load attachment" until this runs.
//
// Usage (from human_bpo/functions):  node set-cors.js
// ponytail: reads the origins from ../../cors.json — edit that file to add the
// production admin domain, then re-run.

const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const serviceAccount = require("./serviceAccountKey.json");
const cors = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "..", "cors.json"), "utf8")
);

const BUCKET = "sherize-bpo.firebasestorage.app";

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: BUCKET,
});

(async () => {
  const bucket = admin.storage().bucket();
  await bucket.setCorsConfiguration(cors);
  const [meta] = await bucket.getMetadata();
  console.log(`CORS applied to gs://${BUCKET}:`);
  console.log(JSON.stringify(meta.cors, null, 2));
  process.exit(0);
})().catch((err) => {
  console.error("Failed to set CORS:", err);
  process.exit(1);
});
