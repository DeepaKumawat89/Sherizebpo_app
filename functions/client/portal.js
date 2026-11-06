/* global require, exports, Buffer */
const functions = require('firebase-functions');
const functionsV1 = require('firebase-functions/v1');
const admin = require('firebase-admin');
const { FieldValue } = require('firebase-admin/firestore');
const crypto = require('node:crypto');
const {
  DEFAULT_BILLING_CONFIG,
  calculateRecordingCharge,
  extractCallIdentity,
  firstValue,
  isPotentiallyFinalized,
  normalizeBillingConfig,
} = require('../utilities/recordingBilling');

const emulatorConfig = process.env.FIREBASE_STORAGE_EMULATOR_HOST ? JSON.parse(process.env.FIREBASE_CONFIG || '{}') : {};
if (admin.apps.length === 0) {
  admin.initializeApp({ storageBucket: emulatorConfig.storageBucket || 'sherize-bpo.firebasestorage.app' });
}
const db = admin.firestore();
const bucket = admin.storage().bucket();
const COMPANY_PROFILE_FIELDS = ['firstName', 'lastName', 'dateOfBirth', 'gender', 'nationality', 'phone', 'addressLine1', 'city', 'state', 'postalCode', 'country', 'companyLegalName', 'companyType', 'registrationNumber', 'registeredAddress'];
const INDIVIDUAL_PROFILE_FIELDS = ['firstName', 'lastName', 'dateOfBirth', 'gender', 'nationality', 'phone', 'email', 'addressLine1', 'city', 'state', 'postalCode', 'country'];
const COMPANY_DOCUMENT_TYPES = ['identity', 'address', 'company'];
const INDIVIDUAL_DOCUMENT_TYPES = ['identity', 'address'];
const REVIEW_ROLES = ['super_admin', 'admin', 'kyc_admin'];
const RECORDING_SETTINGS_PATH = 'billing_settings/recordings';
const RECORDING_BILLING_COLLECTION = 'recording_billing';
const EXOTEL_SECRETS = ['EXOTEL_API_KEY', 'EXOTEL_API_TOKEN', 'EXOTEL_SID', 'EXOTEL_SUBDOMAIN'];
const RETRYABLE_BILLING_STATUSES = [
  'pending_verification',
  'retry_provider',
  'retry_ownership',
  'pending_insufficient_balance',
  'configuration_error',
];

function billingDocumentId(callId) {
  return crypto.createHash('sha256').update(String(callId)).digest('hex');
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  const text = String(value).trim();
  const exotelLocalTime = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(text)
    ? `${text.replace(' ', 'T')}+05:30`
    : text;
  const millis = new Date(exotelLocalTime).getTime();
  return Number.isFinite(millis) ? millis : null;
}

function configSnapshot(source = {}) {
  const normalized = normalizeBillingConfig(source);
  return {
    ...normalized,
    version: Math.max(0, Number(source.version || 0)),
    effectiveAt: source.effectiveAt || null,
  };
}

async function resolveApplicableBillingConfiguration(finalizedAtMillis, settings) {
  const current = configSnapshot(settings);
  const currentEffectiveAt = timestampMillis(current.effectiveAt);
  if (!finalizedAtMillis || !currentEffectiveAt || finalizedAtMillis >= currentEffectiveAt) return current;

  const history = await db.collection(`${RECORDING_SETTINGS_PATH}/history`)
    .where('effectiveAt', '<=', admin.firestore.Timestamp.fromMillis(finalizedAtMillis))
    .orderBy('effectiveAt', 'desc')
    .limit(1)
    .get();
  if (history.empty) return { ...DEFAULT_BILLING_CONFIG, version: 0, effectiveAt: null };
  const historical = history.docs[0].data();
  return configSnapshot({
    ...(historical.newRate || historical.configuration || {}),
    version: historical.version,
    effectiveAt: historical.effectiveAt,
  });
}

function getExotelConfiguration() {
  const apiKey = process.env.EXOTEL_API_KEY;
  const apiToken = process.env.EXOTEL_API_TOKEN;
  const sid = process.env.EXOTEL_SID;
  const host = String(process.env.EXOTEL_SUBDOMAIN || 'api.in.exotel.com')
    .replace(/^https?:\/\//, '').replace(/\/$/, '');
  if (!apiKey || !apiToken || !sid) return null;
  return { apiKey, apiToken, sid, host };
}

async function getVerifiedExotelRecording(callId) {
  const config = getExotelConfiguration();
  if (!config) {
    const error = new Error('Exotel server credentials are not configured for the billing function.');
    error.code = 'billing/configuration';
    throw error;
  }
  const url = `https://${config.host}/v1/Accounts/${encodeURIComponent(config.sid)}/Calls/${encodeURIComponent(callId)}.json?details=true&RecordingUrlValidity=5`;
  const authorization = Buffer.from(`${config.apiKey}:${config.apiToken}`).toString('base64');
  const response = await fetch(url, { headers: { Authorization: `Basic ${authorization}`, Accept: 'application/json' } });
  if (!response.ok) {
    const error = new Error(`Exotel call verification returned HTTP ${response.status}.`);
    error.code = response.status === 404 ? 'billing/not-found' : 'billing/provider-unavailable';
    throw error;
  }
  const payload = await response.json();
  const call = payload?.Call || payload?.TwilioResponse?.Call || payload;
  const returnedSid = String(call?.Sid || '');
  if (!returnedSid || returnedSid !== String(callId)) throw new Error('Exotel returned a mismatched call identifier.');
  const status = String(call?.Status || '').toLowerCase();
  const recordingUrl = call?.PreSignedRecordingUrl || call?.RecordingUrl || '';
  const durationSeconds = Number(call?.Details?.ConversationDuration ?? call?.ConversationDuration ?? call?.Duration);
  return {
    callId: returnedSid,
    status,
    recordingUrl: String(recordingUrl || ''),
    durationSeconds,
    durationSource: call?.Details?.ConversationDuration !== undefined
      ? 'exotel.call_details.conversation_duration'
      : 'exotel.call_details.duration',
    finalizedAt: call?.EndTime || call?.DateUpdated || null,
  };
}

async function resolveClientOwnership(billing) {
  if (billing.clientId) return { clientId: billing.clientId, campaignId: billing.campaignId || null, leadId: billing.leadId || null };
  const source = billing.sourcePath ? await db.doc(billing.sourcePath).get() : null;
  const data = source?.exists ? source.data() : {};
  let clientId = String(firstValue(data, ['clientId', 'customerId', 'accountId']) || billing.clientIdHint || '');
  let campaignId = String(firstValue(data, ['campaignId']) || billing.campaignId || billing.campaignIdHint || '');
  const leadId = String(firstValue(data, ['leadId', 'campaignLeadId']) || billing.leadId || billing.leadIdHint || '');

  if (leadId && (!clientId || !campaignId)) {
    const lead = await db.doc(`campaign_leads/${leadId}`).get();
    if (lead.exists) {
      clientId ||= String(lead.get('clientId') || '');
      campaignId ||= String(lead.get('campaignId') || '');
    }
  }
  if (campaignId && !clientId) {
    const campaign = await db.doc(`campaigns/${campaignId}`).get();
    if (campaign.exists) clientId = String(campaign.get('clientId') || '');
  }
  return { clientId, campaignId: campaignId || null, leadId: leadId || null };
}

async function applyRecordingDebit(billingRef, billing, verified, ownership, configuration) {
  const snapshottedConfiguration = normalizeBillingConfig({
    creditsToDeduct: billing.creditsToDeduct ?? billing.appliedRate ?? configuration.creditsToDeduct,
    recordingDurationMinutes: billing.recordingDurationMinutes ?? configuration.recordingDurationMinutes,
  });
  const charge = billing.creditsDue && billing.verifiedDurationSeconds
    ? {
        verifiedDurationSeconds: billing.verifiedDurationSeconds,
        billableIntervals: billing.billableIntervals ?? billing.billableMinutes,
        ...snapshottedConfiguration,
        creditsDue: billing.creditsDue,
      }
    : calculateRecordingCharge(verified.durationSeconds, snapshottedConfiguration);
  const walletRef = db.doc(`client_credit_wallets/${ownership.clientId}`);
  const transactionRef = walletRef.collection('transactions').doc(`recording_${billingRef.id}`);

  return db.runTransaction(async transaction => {
    const [currentBilling, walletSnapshot] = await Promise.all([
      transaction.get(billingRef), transaction.get(walletRef),
    ]);
    const latest = currentBilling.exists ? currentBilling.data() : {};
    if (latest.status === 'billed') return { status: 'billed', duplicate: true };

    const wallet = walletSnapshot.exists ? walletSnapshot.data() : {};
    const balanceBefore = Math.max(0, Number(wallet.availableCredits || 0));
    const commonBilling = {
      clientId: ownership.clientId,
      campaignId: ownership.campaignId,
      leadId: ownership.leadId,
      provider: 'exotel',
      providerCallId: verified.callId,
      recordingUrlVerified: true,
      verifiedDurationSeconds: charge.verifiedDurationSeconds,
      durationSource: verified.durationSource || latest.durationSource,
      billableIntervals: charge.billableIntervals,
      creditsToDeduct: charge.creditsToDeduct,
      recordingDurationMinutes: charge.recordingDurationMinutes,
      billingConfigVersion: billing.billingConfigVersion ?? configuration.version ?? 0,
      billingConfigEffectiveAt: billing.billingConfigEffectiveAt || configuration.effectiveAt || null,
      creditsDue: charge.creditsDue,
      balanceBefore,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (balanceBefore < charge.creditsDue) {
      transaction.set(billingRef, {
        ...commonBilling,
        status: 'pending_insufficient_balance',
        creditsDeducted: 0,
        balanceAfter: balanceBefore,
        failureReason: 'insufficient_balance',
      }, { merge: true });
      transaction.set(walletRef, {
        availableCredits: balanceBefore,
        serviceBlocked: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return { status: 'pending_insufficient_balance' };
    }

    const balanceAfter = balanceBefore - charge.creditsDue;
    transaction.set(walletRef, {
      availableCredits: balanceAfter,
      usedCredits: Number(wallet.usedCredits || 0) + charge.creditsDue,
      totalAdded: Number(wallet.totalAdded || 0),
      serviceBlocked: balanceAfter <= 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(transactionRef, {
      type: 'usage',
      source: 'recording',
      clientId: ownership.clientId,
      recordingBillingId: billingRef.id,
      callId: verified.callId,
      campaignId: ownership.campaignId,
      leadId: ownership.leadId,
      durationSeconds: charge.verifiedDurationSeconds,
      billableIntervals: charge.billableIntervals,
      creditsToDeduct: charge.creditsToDeduct,
      recordingDurationMinutes: charge.recordingDurationMinutes,
      billingConfigVersion: billing.billingConfigVersion ?? configuration.version ?? 0,
      credits: charge.creditsDue,
      balanceBefore,
      balanceAfter,
      status: 'success',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.set(billingRef, {
      ...commonBilling,
      status: 'billed',
      creditsDeducted: charge.creditsDue,
      balanceAfter,
      billedAt: admin.firestore.FieldValue.serverTimestamp(),
      failureReason: admin.firestore.FieldValue.delete(),
    }, { merge: true });
    return { status: 'billed', duplicate: false };
  });
}

async function processRecordingBilling(billingId) {
  const billingRef = db.collection(RECORDING_BILLING_COLLECTION).doc(billingId);
  const [billingSnapshot, settingsSnapshot] = await Promise.all([
    billingRef.get(), db.doc(RECORDING_SETTINGS_PATH).get(),
  ]);
  if (!billingSnapshot.exists) return null;
  const billing = billingSnapshot.data();
  if (billing.status === 'billed' || String(billing.status || '').startsWith('unbillable_') || billing.status === 'excluded_before_cutover') return billing.status;
  const settings = { enabled: false, ...DEFAULT_BILLING_CONFIG, ...(settingsSnapshot.exists ? settingsSnapshot.data() : {}) };
  if (settings.enabled !== true) {
    if (billing.status !== 'billing_disabled') {
      await billingRef.set({ status: 'billing_disabled', updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    }
    return 'billing_disabled';
  }

  try {
    const ownership = await resolveClientOwnership(billing);
    if (!ownership.clientId) {
      await billingRef.set({
        status: 'retry_ownership', failureReason: 'client_ownership_not_resolved',
        attempts: admin.firestore.FieldValue.increment(1), updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return 'retry_ownership';
    }
    if (!billing.clientId) {
      await billingRef.set({
        clientId: ownership.clientId,
        campaignId: ownership.campaignId,
        leadId: ownership.leadId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    if (billing.status === 'pending_insufficient_balance' && billing.verifiedDurationSeconds && billing.creditsDue) {
      const snapshottedConfiguration = configSnapshot({
        creditsToDeduct: billing.creditsToDeduct ?? billing.appliedRate,
        recordingDurationMinutes: billing.recordingDurationMinutes ?? 1,
        version: billing.billingConfigVersion,
        effectiveAt: billing.billingConfigEffectiveAt,
      });
      return (await applyRecordingDebit(billingRef, billing, {
        callId: billing.providerCallId || billing.callId,
        durationSeconds: billing.verifiedDurationSeconds,
        durationSource: billing.durationSource,
      }, ownership, snapshottedConfiguration)).status;
    }

    const verified = await getVerifiedExotelRecording(billing.callId);
    if (verified.status !== 'completed') {
      const terminalFailure = ['failed', 'busy', 'no-answer', 'canceled', 'cancelled'].includes(verified.status);
      await billingRef.set({
        status: terminalFailure ? 'unbillable_failed_call' : 'retry_provider',
        providerStatus: verified.status || 'unknown',
        failureReason: terminalFailure ? `provider_status_${verified.status}` : 'provider_not_finalized',
        attempts: admin.firestore.FieldValue.increment(1), updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return terminalFailure ? 'unbillable_failed_call' : 'retry_provider';
    }
    if (!verified.recordingUrl) {
      const attempts = Number(billing.attempts || 0) + 1;
      await billingRef.set({
        status: attempts >= 12 ? 'unbillable_missing_recording' : 'retry_provider',
        providerStatus: verified.status, failureReason: 'recording_not_available', attempts,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return attempts >= 12 ? 'unbillable_missing_recording' : 'retry_provider';
    }
    if (!Number.isFinite(verified.durationSeconds) || verified.durationSeconds <= 0) {
      await billingRef.set({
        status: 'unbillable_invalid_duration',
        providerStatus: verified.status, failureReason: 'recording_duration_invalid',
        attempts: admin.firestore.FieldValue.increment(1), updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return 'unbillable_invalid_duration';
    }

    const settingsForRecording = await resolveApplicableBillingConfiguration(timestampMillis(verified.finalizedAt), settings);
    const result = await applyRecordingDebit(billingRef, billing, verified, ownership, settingsForRecording);
    return result.status;
  } catch (error) {
    const status = error.code === 'billing/configuration' ? 'configuration_error' : 'retry_provider';
    console.error('Recording billing attempt failed', { billingId, code: error.code, message: error.message });
    await billingRef.set({
      status,
      failureReason: String(error.message || 'provider_verification_failed').slice(0, 500),
      attempts: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return status;
  }
}

async function enqueueRecordingBilling(change, context, sourceCollection) {
  const snapshot = change.after?.exists ? change.after : change;
  if (!snapshot?.exists) return null;
  const data = snapshot.data() || {};
  if (!isPotentiallyFinalized(data)) return null;
  const sourceId = context.params.callId || context.params.callLogId || snapshot.id;
  const callId = extractCallIdentity(data, sourceId);
  if (!callId) return null;
  const billingId = billingDocumentId(callId);
  const ref = db.collection(RECORDING_BILLING_COLLECTION).doc(billingId);
  await db.runTransaction(async transaction => {
    const existing = await transaction.get(ref);
    const update = {
      callId,
      provider: String(data.provider || data.callProvider || 'exotel').toLowerCase(),
      sourcePath: `${sourceCollection}/${snapshot.id}`,
      sourcePaths: admin.firestore.FieldValue.arrayUnion(`${sourceCollection}/${snapshot.id}`),
      clientIdHint: firstValue(data, ['clientId', 'customerId', 'accountId']) || null,
      campaignIdHint: firstValue(data, ['campaignId']) || null,
      leadIdHint: firstValue(data, ['leadId', 'campaignLeadId']) || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!existing.exists) {
      update.status = 'pending_verification';
      update.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }
    transaction.set(ref, update, { merge: true });
  });
  return processRecordingBilling(billingId);
}

function requireAuth(request) {
  if (!request.auth?.uid) throw new functions.https.HttpsError('unauthenticated', 'Sign in is required.');
  return request.auth.uid;
}
async function requireReviewer(request) {
  const uid = requireAuth(request);
  const user = await db.doc(`users/${uid}`).get();
  if (!REVIEW_ROLES.includes(user.data()?.role)) throw new functions.https.HttpsError('permission-denied', 'KYC reviewer access is required.');
  return uid;
}
async function requireBillingSuperAdmin(request) {
  const uid = requireAuth(request);
  const user = await db.doc(`users/${uid}`).get();
  if (!['super_admin', 'admin'].includes(user.data()?.role)) {
    throw new functions.https.HttpsError('permission-denied', 'Super Admin access is required.');
  }
  return uid;
}
function normalizeAccountType(value) {
  return String(value || '').trim().toLowerCase() === 'individual' ? 'individual' : 'company';
}
function cleanProfile(input, fields) {
  if (!input || typeof input !== 'object') throw new functions.https.HttpsError('invalid-argument', 'KYC profile is required.');
  const result = {};
  for (const key of fields) {
    const value = typeof input[key] === 'string' ? input[key].trim() : '';
    if (!value) throw new functions.https.HttpsError('invalid-argument', `${key} is required.`);
    if (value.length > 250) throw new functions.https.HttpsError('invalid-argument', `${key} is too long.`);
    result[key] = value;
  }
  const parsedBirthDate = new Date(`${result.dateOfBirth}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(result.dateOfBirth) || Number.isNaN(parsedBirthDate.getTime()) || parsedBirthDate.toISOString().slice(0, 10) !== result.dateOfBirth || result.dateOfBirth > new Date().toISOString().slice(0, 10)) {
    throw new functions.https.HttpsError('invalid-argument', 'A valid date of birth is required.');
  }
  if (!['Female', 'Male', 'Non-binary', 'Prefer not to say'].includes(result.gender)) throw new functions.https.HttpsError('invalid-argument', 'A valid gender selection is required.');
  if (!/^[+0-9][0-9 ()-]{6,24}$/.test(result.phone)) throw new functions.https.HttpsError('invalid-argument', 'A valid mobile number is required.');
  if (result.email) result.email = result.email.toLowerCase();
  result.legalName = `${result.firstName} ${result.lastName}`.trim();
  return result;
}


////-----------------------------------------------------------------Submit Kyc-------------------------------------------------------
exports.submitClientKyc = functions.https.onCall(async (request) => {
  const uid = requireAuth(request);
  const data = request.data;
  const submissionId = typeof data?.submissionId === 'string' ? data.submissionId : '';
  if (!data?.consent || !/^[a-zA-Z0-9-]{20,100}$/.test(submissionId)) throw new functions.https.HttpsError('invalid-argument', 'Valid consent and submission ID are required.');
  const clientRef = db.doc(`clients/${uid}`);
  const initialSnapshot = await clientRef.get();
  if (!initialSnapshot.exists) throw new functions.https.HttpsError('failed-precondition', 'Client profile not found.');
  const initialClient = initialSnapshot.data();
  if (!['not_submitted', 'rejected'].includes(initialClient.kycStatus || 'not_submitted')) throw new functions.https.HttpsError('failed-precondition', 'This KYC application cannot be resubmitted.');
  const accountType = normalizeAccountType(initialClient.accountType);
  const profileFields = accountType === 'individual' ? INDIVIDUAL_PROFILE_FIELDS : COMPANY_PROFILE_FIELDS;
  const documentTypes = accountType === 'individual' ? INDIVIDUAL_DOCUMENT_TYPES : COMPANY_DOCUMENT_TYPES;
  const profile = cleanProfile(data?.profile, profileFields);
  if (accountType === 'individual') {
    const registeredEmail = String(initialClient.email || request.auth?.token?.email || '').trim().toLowerCase();
    if (!registeredEmail || profile.email !== registeredEmail) throw new functions.https.HttpsError('invalid-argument', 'KYC email must match the registered account email.');
  }
  const suppliedDocumentTypes = Object.keys(data?.documents || {});
  if (suppliedDocumentTypes.length !== documentTypes.length || !suppliedDocumentTypes.every(type => documentTypes.includes(type))) {
    throw new functions.https.HttpsError('invalid-argument', 'The submitted document set does not match this account type.');
  }
  const documents = {};
  for (const type of documentTypes) {
    const document = data?.documents?.[type];
    const expectedPrefix = `client-kyc/${uid}/${submissionId}/${type}-`;
    if (!document?.path?.startsWith(expectedPrefix)) throw new functions.https.HttpsError('invalid-argument', `Invalid ${type} document.`);
    const [metadata] = await bucket.file(document.path).getMetadata();
    if (metadata.metadata?.ownerId !== uid || metadata.metadata?.documentType !== type || Number(metadata.size) > 10 * 1024 * 1024 || !['application/pdf', 'image/jpeg', 'image/png'].includes(metadata.contentType)) throw new functions.https.HttpsError('permission-denied', `The ${type} document failed validation.`);
    documents[type] = { path: document.path, name: String(document.name || '').slice(0, 180), contentType: metadata.contentType, size: Number(metadata.size) };
  }
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(clientRef);
    if (!snap.exists) throw new functions.https.HttpsError('failed-precondition', 'Client profile not found.');
    if (!['not_submitted', 'rejected'].includes(snap.data().kycStatus || 'not_submitted')) throw new functions.https.HttpsError('failed-precondition', 'This KYC application cannot be resubmitted.');
    if (normalizeAccountType(snap.data().accountType) !== accountType) throw new functions.https.HttpsError('aborted', 'The account type changed. Please reload and try again.');
    const clientUpdate = { accountType, firstName: profile.firstName, lastName: profile.lastName, dateOfBirth: profile.dateOfBirth, gender: profile.gender, kycData: profile, kycDocuments: documents, kycSubmissionId: submissionId, kycStatus: 'pending', kycSubmittedAt: FieldValue.serverTimestamp(), kycRejectionReason: FieldValue.delete(), accountActive: false, updatedAt: FieldValue.serverTimestamp() };
    if (accountType === 'company') clientUpdate.companyName = profile.companyLegalName;
    transaction.update(clientRef, clientUpdate);
  });
  return { status: 'pending' };
});


///-------------------------------------------------- Review KYC--------------------------------------
exports.reviewClientKyc = functions.https.onCall(async (request) => {
  const reviewerId = await requireReviewer(request);
  const data = request.data;
  const clientId = typeof data?.clientId === 'string' ? data.clientId : '';
  const status = data?.status;
  if (!clientId || !['under_review', 'approved', 'rejected'].includes(status)) throw new functions.https.HttpsError('invalid-argument', 'Valid client and review status are required.');
  const reason = typeof data?.reason === 'string' ? data.reason.trim().slice(0, 1000) : '';
  if (status === 'rejected' && !reason) throw new functions.https.HttpsError('invalid-argument', 'A rejection reason is required.');
  await db.doc(`clients/${clientId}`).update({ kycStatus: status, kycRejectionReason: status === 'rejected' ? reason : admin.firestore.FieldValue.delete(), kycReviewedAt: admin.firestore.FieldValue.serverTimestamp(), kycReviewedBy: reviewerId, accountActive: false, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  return { status };
});

exports.setClientAccountActivation = functions.https.onCall(async (request) => {
  const reviewerId = await requireReviewer(request);
  const data = request.data;
  const clientId = typeof data?.clientId === 'string' ? data.clientId : '';
  if (!clientId || typeof data?.active !== 'boolean') throw new functions.https.HttpsError('invalid-argument', 'Valid client and activation state are required.');
  const ref = db.doc(`clients/${clientId}`);
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists || (data.active && snap.data().kycStatus !== 'approved')) throw new functions.https.HttpsError('failed-precondition', 'KYC must be approved before activation.');
    transaction.update(ref, { accountActive: data.active, activatedAt: data.active ? admin.firestore.FieldValue.serverTimestamp() : admin.firestore.FieldValue.delete(), activatedBy: data.active ? reviewerId : admin.firestore.FieldValue.delete(), updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  });
  return { active: data.active };
});

// Adds the activation check at the backend boundary to the existing recording service.
exports.clientRecording = functions.https.onRequest(async (request, response) => {
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  response.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (request.method === 'OPTIONS') return response.status(204).send('');
  if (request.method !== 'GET') return response.status(405).json({ error: 'Method not allowed.' });
  const match = String(request.headers.authorization || '').match(/^Bearer\s+(.+)$/i);
  if (!match) return response.status(401).json({ error: 'Authentication required.' });
  try {
    const decoded = await admin.auth().verifyIdToken(match[1]);
    const client = await db.doc(`clients/${decoded.uid}`).get();
    if (!client.exists || client.data().kycStatus !== 'approved' || client.data().accountActive !== true) return response.status(403).json({ error: 'KYC approval and account activation are required.' });
    const callId = typeof request.query.callId === 'string' ? request.query.callId : '';
    if (!callId) return response.status(400).json({ error: 'callId is required.' });
    const upstream = await fetch('https://us-central1-sherize-bpo.cloudfunctions.net/api/recording?callId=' + encodeURIComponent(callId), { headers: { Authorization: 'Bearer ' + match[1] } });
    if (!upstream.ok) return response.status(upstream.status).json(await upstream.json().catch(() => ({ error: 'Recording could not be loaded.' })));
    response.set('Content-Type', upstream.headers.get('content-type') || 'audio/mpeg');
    response.set('Cache-Control', 'private, no-store');
    return response.status(200).send(Buffer.from(await upstream.arrayBuffer()));
  } catch (error) {
    console.error('clientRecording failed', error);
    return response.status(401).json({ error: 'Invalid or expired authentication.' });
  }
});

// Recording billing is deliberately isolated from the call API. Firestore only
// supplies the provider call identifier and ownership hints; status, recording
// availability, and duration are re-read from Exotel with server credentials.
exports.onCallRecordingFinalized = functionsV1.runWith({ timeoutSeconds: 120, memory: '256MB', secrets: EXOTEL_SECRETS })
  .firestore.document('calls/{callId}')
  .onWrite((change, context) => enqueueRecordingBilling(change, context, 'calls'));

exports.onCallLogRecordingFinalized = functionsV1.runWith({ timeoutSeconds: 120, memory: '256MB', secrets: EXOTEL_SECRETS })
  .firestore.document('call_logs/{callLogId}')
  .onWrite((change, context) => enqueueRecordingBilling(change, context, 'call_logs'));

exports.retryPendingRecordingBilling = functionsV1.runWith({ timeoutSeconds: 300, memory: '256MB', secrets: EXOTEL_SECRETS })
  .pubsub.schedule('every 5 minutes')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const settings = await db.doc(RECORDING_SETTINGS_PATH).get();
    const statuses = settings.exists && settings.get('enabled') === true
      ? [...RETRYABLE_BILLING_STATUSES, 'billing_disabled']
      : RETRYABLE_BILLING_STATUSES;
    const pending = await db.collection(RECORDING_BILLING_COLLECTION)
      .where('status', 'in', statuses)
      .orderBy('createdAt', 'asc')
      .limit(100)
      .get();
    for (const document of pending.docs) await processRecordingBilling(document.id);
    return null;
  });

exports.updateRecordingBillingSettings = functions.https.onCall(async request => {
  const adminUid = await requireBillingSuperAdmin(request);
  let requestedRate;
  try {
    requestedRate = normalizeBillingConfig(request.data || {});
  } catch (error) {
    throw new functions.https.HttpsError('invalid-argument', error.message);
  }
  if (typeof request.data?.enabled !== 'boolean' || typeof request.data?.demoTopUpsEnabled !== 'boolean') {
    throw new functions.https.HttpsError('invalid-argument', 'Billing status and demo top-up status are required.');
  }
  const settingsRef = db.doc(RECORDING_SETTINGS_PATH);
  const historyRef = settingsRef.collection('history').doc();
  const result = await db.runTransaction(async transaction => {
    const snapshot = await transaction.get(settingsRef);
    const current = { enabled: false, demoTopUpsEnabled: true, ...DEFAULT_BILLING_CONFIG, ...(snapshot.exists ? snapshot.data() : {}) };
    const previousRate = normalizeBillingConfig(current);
    if (snapshot.exists
      && previousRate.creditsToDeduct === requestedRate.creditsToDeduct
      && previousRate.recordingDurationMinutes === requestedRate.recordingDurationMinutes
      && current.enabled === request.data.enabled
      && (current.demoTopUpsEnabled !== false) === request.data.demoTopUpsEnabled) {
      throw new functions.https.HttpsError('failed-precondition', 'The billing configuration has not changed.');
    }
    const now = admin.firestore.Timestamp.now();
    const version = Math.max(0, Number(current.version || 0)) + 1;
    const billingStartedAt = request.data.enabled && current.enabled !== true
      ? now
      : current.billingStartedAt || current.effectiveAt || (request.data.enabled ? now : null);
    if (Number(current.version || 0) === 0 && (current.effectiveAt || current.billingStartedAt)) {
      transaction.create(settingsRef.collection('history').doc(), {
        adminUid, changeType: 'baseline_migration', version: 0, previousRate, newRate: previousRate,
        previousEnabled: current.enabled === true, newEnabled: current.enabled === true,
        effectiveAt: current.billingStartedAt || current.effectiveAt, changedAt: now,
      });
    }
    transaction.set(settingsRef, {
      enabled: request.data.enabled, demoTopUpsEnabled: request.data.demoTopUpsEnabled, ...requestedRate,
      creditsPerMinute: admin.firestore.FieldValue.delete(), version, effectiveAt: now, billingStartedAt,
      updatedAt: now, updatedBy: adminUid,
    }, { merge: true });
    transaction.create(historyRef, {
      adminUid, changeType: 'configuration_update', version, previousRate, newRate: requestedRate,
      previousEnabled: current.enabled === true, newEnabled: request.data.enabled,
      previousDemoTopUpsEnabled: current.demoTopUpsEnabled !== false,
      newDemoTopUpsEnabled: request.data.demoTopUpsEnabled, effectiveAt: now, changedAt: now,
    });
    return { ...requestedRate, enabled: request.data.enabled, version };
  });
  return result;
});

///------------------------------------------------------  Demo Credits ----------------------------------------------------------------
exports.addDemoRecordingCredits = functions.https.onCall(async request => {
  const uid = requireAuth(request);
  const amount = Number(request.data?.amount);
  if (!Number.isInteger(amount) || amount < 1 || amount > 100000) {
    throw new functions.https.HttpsError('invalid-argument', 'Credits must be a whole number between 1 and 100,000.');
  }
  const [client, settings] = await Promise.all([
    db.doc(`clients/${uid}`).get(), db.doc(RECORDING_SETTINGS_PATH).get(),
  ]);
  if (!client.exists || client.get('kycStatus') !== 'approved' || client.get('accountActive') !== true) {
    throw new functions.https.HttpsError('permission-denied', 'An active client account is required.');
  }
  if (settings.exists && settings.get('demoTopUpsEnabled') === false) {
    throw new functions.https.HttpsError('failed-precondition', 'Demo credit top-ups are disabled.');
  }

  const walletRef = db.doc(`client_credit_wallets/${uid}`);
  const ledgerRef = walletRef.collection('transactions').doc();
  const result = await db.runTransaction(async transaction => {
    const walletSnapshot = await transaction.get(walletRef);
    const wallet = walletSnapshot.exists ? walletSnapshot.data() : {};
    const balanceBefore = Math.max(0, Number(wallet.availableCredits || 0));
    const balanceAfter = balanceBefore + amount;
    transaction.set(walletRef, {
      availableCredits: balanceAfter,
      usedCredits: Number(wallet.usedCredits || 0),
      totalAdded: Number(wallet.totalAdded || 0) + amount,
      serviceBlocked: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(ledgerRef, {
      type: 'top_up', source: 'demo-server', clientId: uid, credits: amount,
      balanceBefore, balanceAfter, status: 'success',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { balanceAfter };
  });

  return result;
});
