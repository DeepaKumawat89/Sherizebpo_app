const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const crypto = require("node:crypto");
const db = admin.firestore();

const fail = (code, message) => { throw new functions.https.HttpsError(code, message); };
const currentDayKey = (date = new Date()) => date.toISOString().slice(0, 10);
const requestedDay = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : currentDayKey();

async function requireShift(uid, date) {
  const ref = db.collection("work_sessions").doc(`${uid}_${date}`);
  const snap = await ref.get();
  if (!snap.exists || !["active", "on_break"].includes(snap.get("status"))) {
    fail("failed-precondition", "Location is available only during an active work session.");
  }
  return ref;
}

const setLocationConsent = functions.https.onCall(async (data, context) => {
  if (!context.auth) fail("unauthenticated", "Sign in to manage location sharing.");
  const uid = context.auth.uid;
  const date = requestedDay(data && data.date);
  const enabled = data && data.enabled === true;
  const token = enabled ? crypto.randomUUID() : null;
  const sessionRef = enabled ? await requireShift(uid, date) : null;
  const consentRef = db.collection("location_tracking_consents").doc(uid);
  await db.runTransaction(async (tx) => {
    if (sessionRef) {
      const session = await tx.get(sessionRef);
      if (!session.exists || !["active", "on_break"].includes(session.get("status"))) {
        fail("failed-precondition", "The work session has ended.");
      }
    }
    tx.set(consentRef, {
      userId: uid,
      date,
      enabled,
      token,
      changedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (enabled) {
      tx.set(db.collection("employee_locations").doc(uid), {
        userId: uid,
        date,
        tracking: true,
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        latitude: admin.firestore.FieldValue.delete(),
        longitude: admin.firestore.FieldValue.delete(),
        accuracy: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.delete(),
      }, { merge: true });
    } else {
      tx.set(db.collection("employee_locations").doc(uid), {
        tracking: false,
        date,
        stoppedAt: admin.firestore.FieldValue.serverTimestamp(),
        latitude: admin.firestore.FieldValue.delete(),
        longitude: admin.firestore.FieldValue.delete(),
        accuracy: admin.firestore.FieldValue.delete(),
      }, { merge: true });
    }
  });
  return { enabled, token };
});

const renewLocationConsent = functions.https.onCall(async (data, context) => {
  if (!context.auth) fail("unauthenticated", "Sign in to renew location sharing.");
  const uid = context.auth.uid;
  const date = requestedDay(data && data.date);
  const token = data && data.token;
  if (typeof token !== "string" || token.length < 20) fail("invalid-argument", "Invalid consent token.");
  const sessionRef = db.collection("work_sessions").doc(`${uid}_${date}`);
  const consentRef = db.collection("location_tracking_consents").doc(uid);
  await db.runTransaction(async (tx) => {
    const [session, consent] = await Promise.all([tx.get(sessionRef), tx.get(consentRef)]);
    if (!session.exists || !["active", "on_break"].includes(session.get("status")) ||
        !consent.exists || consent.get("enabled") !== true || consent.get("date") !== date ||
        consent.get("token") !== token) {
      fail("permission-denied", "Location sharing is no longer enabled for this shift.");
    }
    tx.update(consentRef, { changedAt: admin.firestore.FieldValue.serverTimestamp() });
  });
  return { renewed: true };
});

const purgeOldLocationHistory = functions.pubsub.schedule("every 24 hours").onRun(async () => {
  // Daily cadence plus a 29-day threshold guarantees no point exceeds 30 days.
  const cutoff = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 29 * 24 * 60 * 60 * 1000));
  while (true) {
    const oldPoints = await db.collectionGroup("points").where("recordedAt", "<", cutoff).limit(400).get();
    if (oldPoints.empty) break;
    const batch = db.batch();
    oldPoints.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
  return null;
});

const stopLocationOnCheckout = functions.firestore
  .document("work_sessions/{sessionId}")
  .onUpdate(async (change, context) => {
    if (change.after.get("status") !== "ended" || change.before.get("status") === "ended") return null;
    const uid = change.after.get("userId");
    if (!uid) return null;
    const batch = db.batch();
    batch.set(db.collection("location_tracking_consents").doc(uid), {
      enabled: false,
      token: null,
      changedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    batch.set(db.collection("employee_locations").doc(uid), {
      tracking: false,
      stoppedAt: admin.firestore.FieldValue.serverTimestamp(),
      latitude: admin.firestore.FieldValue.delete(),
      longitude: admin.firestore.FieldValue.delete(),
      accuracy: admin.firestore.FieldValue.delete(),
    }, { merge: true });
    await batch.commit();
    return null;
  });

const recordEmployeeLocation = functions.https.onCall(async (data, context) => {
  if (!context.auth) fail("unauthenticated", "Sign in to share location.");
  const uid = context.auth.uid;
  const lat = Number(data && data.latitude);
  const lng = Number(data && data.longitude);
  const accuracy = Number(data && data.accuracy);
  const date = requestedDay(data && data.date);
  const token = data && data.token;
  if (!Number.isFinite(lat) || lat < -90 || lat > 90 || !Number.isFinite(lng) || lng < -180 || lng > 180 || !Number.isFinite(accuracy) || accuracy < 0 || accuracy > 100) {
    fail("invalid-argument", "A valid location with accuracy within 100 meters is required.");
  }
  const sessionRef = await requireShift(uid, date);
  const consentRef = db.collection("location_tracking_consents").doc(uid);
  const latestRef = db.collection("employee_locations").doc(uid);
  const now = admin.firestore.Timestamp.now();
  await db.runTransaction(async (tx) => {
    const [session, consent, latest] = await Promise.all([tx.get(sessionRef), tx.get(consentRef), tx.get(latestRef)]);
    if (!session.exists || !["active", "on_break"].includes(session.get("status")) ||
        !consent.exists || consent.get("enabled") !== true || consent.get("date") !== date ||
        consent.get("token") !== token ||
        !consent.get("changedAt") || now.toMillis() - consent.get("changedAt").toMillis() > 120000) {
      fail("permission-denied", "Location sharing is not enabled for an active shift.");
    }
    const previous = latest.exists ? latest.data() : {};
    const previousTime = previous.lastAcceptedAt && previous.lastAcceptedAt.toMillis();
    if (previousTime && now.toMillis() - previousTime < 30000) {
      fail("resource-exhausted", "Location updates must be at least 30 seconds apart.");
    }
    const point = { latitude: lat, longitude: lng, accuracy, recordedAt: now, userId: uid, date };
    tx.set(latestRef, { ...point, tracking: true, updatedAt: now, lastAcceptedAt: now }, { merge: true });
    tx.set(consentRef, { changedAt: now }, { merge: true });
    const historyRef = db.collection("employee_location_history").doc(`${uid}_${date}`).collection("points").doc();
    tx.set(historyRef, point);
  });
  return { accepted: true };
});

exports.setLocationConsent = setLocationConsent;
exports.renewLocationConsent = renewLocationConsent;
exports.recordEmployeeLocation = recordEmployeeLocation;
exports.purgeOldLocationHistory = purgeOldLocationHistory;
exports.stopLocationOnCheckout = stopLocationOnCheckout;
