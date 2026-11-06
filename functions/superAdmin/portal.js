'use strict';
/* global require, exports */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getApps, initializeApp } = require('firebase-admin/app');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

if (getApps().length === 0) initializeApp();
const db = getFirestore();
const emulatorConfig = process.env.FIREBASE_STORAGE_EMULATOR_HOST ? JSON.parse(process.env.FIREBASE_CONFIG || '{}') : {};
const STORAGE_BUCKET = emulatorConfig.storageBucket || 'sherize-bpo.firebasestorage.app';
const bucket = () => getStorage().bucket(STORAGE_BUCKET);

async function requireSuperAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in is required.');
  const user = await db.doc(`users/${request.auth.uid}`).get();
  if (!user.exists || user.get('role') !== 'super_admin') throw new HttpsError('permission-denied', 'Super Admin access is required.');
  return { uid: request.auth.uid, email: request.auth.token.email || null };
}

const clean = (value, max) => typeof value === 'string' ? value.trim().slice(0, max) : '';
const audit = (action, clientId, actor, details = {}) => ({ action, targetType: 'client_kyc', targetId: clientId, actor, details, createdAt: FieldValue.serverTimestamp() });
const COMPANY_DOCUMENTS = ['identity', 'address', 'company'];
const INDIVIDUAL_DOCUMENTS = ['identity', 'address'];
const ALLOWED_CONTENT_TYPES = ['application/pdf', 'image/jpeg', 'image/png'];
const COMPANY_PROFILE_FIELDS = ['firstName', 'lastName', 'dateOfBirth', 'gender', 'nationality', 'phone', 'addressLine1', 'city', 'state', 'postalCode', 'country', 'companyLegalName', 'companyType', 'registrationNumber', 'registeredAddress'];
const INDIVIDUAL_PROFILE_FIELDS = ['firstName', 'lastName', 'dateOfBirth', 'gender', 'nationality', 'phone', 'email', 'addressLine1', 'city', 'state', 'postalCode', 'country'];
const normalizeAccountType = value => String(value || '').trim().toLowerCase() === 'individual' ? 'individual' : 'company';

function getProfileValue(snapshot, profile, field, accountType) {
  const directValue = profile?.[field];
  if (typeof directValue === 'string' && directValue.trim()) return directValue.trim();
  const legacyName = String(profile?.legalName || '').trim().split(/\s+/).filter(Boolean);
  if (field === 'firstName') return clean(snapshot.get('firstName') || legacyName[0], 120);
  if (field === 'lastName') return clean(snapshot.get('lastName') || legacyName.slice(1).join(' '), 120);
  if (field === 'dateOfBirth' || field === 'gender') return clean(snapshot.get(field), 120);
  if (field === 'companyLegalName' && accountType === 'company') return clean(snapshot.get('companyName'), 200);
  return '';
}

async function verifySubmissionDocuments(clientId, submissionId, documents, requiredDocuments) {
  for (const type of requiredDocuments) {
    const document = documents?.[type];
    const prefix = `client-kyc/${clientId}/${submissionId}/${type}-`;
    if (!document?.path?.startsWith(prefix) || !document.name || !ALLOWED_CONTENT_TYPES.includes(document.contentType)) {
      throw new HttpsError('failed-precondition', `The ${type} document is missing or invalid.`);
    }
    let metadata;
    try { [metadata] = await bucket().file(document.path).getMetadata(); } catch (error) {
      if (error.code === 404) throw new HttpsError('failed-precondition', `The ${type} document is missing from secure storage.`);
      console.error('KYC document validation failed', { clientId, submissionId, type, code: error.code, message: error.message });
      throw new HttpsError('unavailable', 'Secure document validation is temporarily unavailable. Please try again.');
    }
    if (metadata.metadata?.ownerId !== clientId || metadata.metadata?.documentType !== type || !ALLOWED_CONTENT_TYPES.includes(metadata.contentType) || Number(metadata.size) > 10 * 1024 * 1024) {
      throw new HttpsError('failed-precondition', `The ${type} document failed secure validation.`);
    }
  }
}

exports.manageClientKyc = onCall({ invoker: 'public' }, async request => {
  const actor = await requireSuperAdmin(request);
  const clientId = clean(request.data?.clientId, 128);
  const submissionId = clean(request.data?.submissionId, 128);
  const expectedStatus = clean(request.data?.expectedStatus, 32);
  const action = request.data?.action;
  if (!clientId || !submissionId) throw new HttpsError('invalid-argument', 'A client and submission ID are required.');

  const clientRef = db.doc(`clients/${clientId}`);
  const auditRef = db.collection('admin_audit_logs').doc();
  if (action === 'decide' && request.data?.decision === 'approved') {
    const preflight = await clientRef.get();
    if (!preflight.exists || preflight.get('kycSubmissionId') !== submissionId) throw new HttpsError('aborted', 'This KYC submission has changed. Refresh before continuing.');
    const accountType = normalizeAccountType(preflight.get('accountType'));
    const requiredProfileFields = accountType === 'individual' ? INDIVIDUAL_PROFILE_FIELDS : COMPANY_PROFILE_FIELDS;
    const requiredDocuments = accountType === 'individual' ? INDIVIDUAL_DOCUMENTS : COMPANY_DOCUMENTS;
    const profile = preflight.get('kycData') || {};
    if (!requiredProfileFields.every(field => getProfileValue(preflight, profile, field, accountType))) throw new HttpsError('failed-precondition', 'Required KYC information is incomplete.');
    await verifySubmissionDocuments(clientId, submissionId, preflight.get('kycDocuments'), requiredDocuments);
  }
  return db.runTransaction(async transaction => {
    const snapshot = await transaction.get(clientRef);
    if (!snapshot.exists) throw new HttpsError('not-found', 'The KYC application no longer exists.');
    const client = snapshot.data();
    if (!client.kycSubmissionId || !client.kycSubmittedAt) throw new HttpsError('failed-precondition', 'This client has not submitted KYC.');
    if (client.kycSubmissionId !== submissionId) throw new HttpsError('aborted', 'This KYC submission has changed. Refresh before continuing.');
    if (client.kycStatus !== expectedStatus) throw new HttpsError('aborted', `This application changed to ${client.kycStatus}. Refresh before continuing.`);

    if (action === 'startReview') {
      if (client.kycStatus !== 'pending') throw new HttpsError('failed-precondition', 'Only pending applications can enter review.');
      transaction.update(clientRef, { kycStatus: 'under_review', kycReviewStartedAt: FieldValue.serverTimestamp(), kycReviewStartedBy: actor.uid, updatedAt: FieldValue.serverTimestamp() });
      transaction.create(auditRef, audit('client.kyc.review_started', clientId, actor, { submissionId: client.kycSubmissionId, from: 'pending', to: 'under_review' }));
      return { status: 'under_review' };
    }

    if (action === 'decide') {
      const decision = request.data?.decision;
      const reason = clean(request.data?.reason, 1000);
      if (!['approved', 'rejected'].includes(decision)) throw new HttpsError('invalid-argument', 'The review decision is invalid.');
      if (!['pending', 'under_review'].includes(client.kycStatus)) throw new HttpsError('failed-precondition', 'Only pending applications or applications under review can receive a decision.');
      if (decision === 'rejected' && !reason) throw new HttpsError('invalid-argument', 'A rejection reason is required.');
      const update = {
        kycStatus: decision,
        kycReviewedAt: FieldValue.serverTimestamp(),
        kycReviewedBy: actor.uid,
        accountActive: decision === 'approved',
        activatedAt: decision === 'approved' ? FieldValue.serverTimestamp() : FieldValue.delete(),
        activatedBy: decision === 'approved' ? actor.uid : FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (client.kycStatus === 'pending') {
        update.kycReviewStartedAt = FieldValue.serverTimestamp();
        update.kycReviewStartedBy = actor.uid;
      }
      update.kycRejectionReason = decision === 'rejected' ? reason : FieldValue.delete();
      transaction.update(clientRef, update);
      transaction.create(auditRef, audit(`client.kyc.${decision}`, clientId, actor, { submissionId: client.kycSubmissionId, from: client.kycStatus, to: decision, ...(reason ? { reason } : {}) }));
      return { status: decision };
    }
    throw new HttpsError('invalid-argument', 'Unsupported KYC action.');
  });
});

exports.getClientKycDocumentUrl = onCall({ invoker: 'public' }, async request => {
  const actor = await requireSuperAdmin(request);
  const clientId = clean(request.data?.clientId, 128);
  const submissionId = clean(request.data?.submissionId, 128);
  const path = clean(request.data?.path, 1024);
  const mode = request.data?.mode === 'download' ? 'download' : 'preview';
  if (!clientId || !submissionId || !path || path.includes('..') || path.startsWith('http')) throw new HttpsError('invalid-argument', 'Invalid KYC document request.');

  const snapshot = await db.doc(`clients/${clientId}`).get();
  if (!snapshot.exists) throw new HttpsError('not-found', 'The client no longer exists.');
  const client = snapshot.data();
  if (client.kycSubmissionId !== submissionId) throw new HttpsError('aborted', 'This KYC submission has been replaced. Refresh before continuing.');
  const document = Object.values(client.kycDocuments || {}).find(item => item?.path === path);
  const prefix = `client-kyc/${clientId}/${submissionId}/`;
  if (!document || !path.startsWith(prefix)) throw new HttpsError('permission-denied', 'This document does not belong to the selected application.');

  const file = bucket().file(path);
  let metadata;
  try { [metadata] = await file.getMetadata(); } catch (error) {
    if (error.code === 404) throw new HttpsError('not-found', 'The uploaded document is missing from secure storage.');
    console.error('KYC document access failed', { clientId, submissionId, path, code: error.code, message: error.message });
    throw new HttpsError('unavailable', 'Secure document access is temporarily unavailable. Please try again.');
  }
  if (metadata.metadata?.ownerId !== clientId || !ALLOWED_CONTENT_TYPES.includes(metadata.contentType)) throw new HttpsError('permission-denied', 'The stored document failed ownership or file-type validation.');

  const filename = clean(document.name, 180).replace(/["\\\r\n]/g, '_') || path.split('/').pop();
  let url;
  try {
    [url] = await file.getSignedUrl({ action: 'read', expires: Date.now() + 5 * 60 * 1000, responseType: metadata.contentType, responseDisposition: `${mode === 'download' ? 'attachment' : 'inline'}; filename="${filename}"` });
  } catch (error) {
    console.error('KYC signed URL creation failed', { clientId, submissionId, path, code: error.code, message: error.message });
    throw new HttpsError('unavailable', 'A secure document link could not be created. Please try again.');
  }
  await db.collection('admin_audit_logs').add(audit(`client.kyc.document_${mode}ed`, clientId, actor, { submissionId, path }));
  return { url, contentType: metadata.contentType, name: filename, expiresInSeconds: 300 };
});

// Keep openings closed after their calendar expiration even when the admin portal is not open.
exports.expireJobOpenings = onSchedule('every 60 minutes', async () => {
  const now = new Date();
  const offset = now.getTimezoneOffset() * 60000;
  const today = new Date(now.getTime() - offset).toISOString().slice(0, 10);
  const snapshot = await db.collection('job_postings').where('status', '==', 'open').get();
  const batch = db.batch();
  let expired = 0;
  snapshot.docs.forEach(job => {
    if (job.get('lastDate') && job.get('lastDate') < today) {
      batch.update(job.ref, { status: 'closed', expiredAt: FieldValue.serverTimestamp() });
      expired += 1;
    }
  });
  if (expired) await batch.commit();
  return { expired };
});
