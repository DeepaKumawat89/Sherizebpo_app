const DEFAULT_BILLING_CONFIG = Object.freeze({
  creditsToDeduct: 1,
  recordingDurationMinutes: 1,
});
const MAX_RECORDING_DURATION_SECONDS = 24 * 60 * 60;

function asPositiveInteger(value) {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : null;
}

function configurationError(message) {
  const error = new Error(message);
  error.code = 'billing/configuration';
  return error;
}

function normalizeBillingConfig(input = {}) {
  const creditsToDeduct = asPositiveInteger(
    input.creditsToDeduct ?? input.creditsPerMinute ?? DEFAULT_BILLING_CONFIG.creditsToDeduct,
  );
  const recordingDurationMinutes = asPositiveInteger(
    input.recordingDurationMinutes ?? DEFAULT_BILLING_CONFIG.recordingDurationMinutes,
  );
  if (!creditsToDeduct || creditsToDeduct > 1000) {
    throw configurationError('Credits to deduct must be a whole number between 1 and 1,000.');
  }
  if (!recordingDurationMinutes || recordingDurationMinutes > 1440) {
    throw configurationError('Recording duration must be a whole number between 1 and 1,440 minutes.');
  }
  return { creditsToDeduct, recordingDurationMinutes };
}

function calculateRecordingCharge(durationSeconds, configuration = DEFAULT_BILLING_CONFIG) {
  const duration = Number(durationSeconds);
  if (!Number.isFinite(duration) || duration <= 0 || duration > MAX_RECORDING_DURATION_SECONDS) {
    const error = new Error('Recording duration is invalid.');
    error.code = 'billing/invalid-duration';
    throw error;
  }
  const verifiedDurationSeconds = Math.ceil(duration);
  const rate = normalizeBillingConfig(configuration);
  const intervalSeconds = rate.recordingDurationMinutes * 60;
  const billableIntervals = Math.ceil(verifiedDurationSeconds / intervalSeconds);
  return {
    verifiedDurationSeconds,
    billableIntervals,
    creditsToDeduct: rate.creditsToDeduct,
    recordingDurationMinutes: rate.recordingDurationMinutes,
    creditsDue: billableIntervals * rate.creditsToDeduct,
  };
}

function firstValue(source, keys) {
  for (const key of keys) {
    const value = source?.[key];
    if (value !== undefined && value !== null && value !== '') return value;
  }
  return null;
}

function extractCallIdentity(data, documentId) {
  return String(firstValue(data, [
    'providerCallId', 'callSid', 'CallSid', 'callId', 'sid', 'Sid', 'exotelCallSid',
  ]) || documentId || '').trim();
}

function isPotentiallyFinalized(data) {
  const status = String(firstValue(data, ['providerStatus', 'callStatus', 'status', 'Status']) || '').toLowerCase();
  const recording = firstValue(data, ['recordingUrl', 'RecordingUrl', 'recordingURL', 'recording_url']);
  return status === 'completed' || Boolean(recording);
}

module.exports = {
  DEFAULT_BILLING_CONFIG,
  MAX_RECORDING_DURATION_SECONDS,
  calculateRecordingCharge,
  extractCallIdentity,
  firstValue,
  isPotentiallyFinalized,
  normalizeBillingConfig,
};
