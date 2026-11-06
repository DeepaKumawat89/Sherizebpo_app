const MIN_REQUEUE_DELAY_MS = 60 * 1000;
const MAX_REQUEUE_DELAY_MS = 365 * 24 * 60 * 60 * 1000;

function parseRequeueAt(value, now = Date.now()) {
    const requeueAt = Number(value);
    if (!Number.isFinite(requeueAt) || requeueAt < now + MIN_REQUEUE_DELAY_MS) {
        throw new Error("The requeue time must be at least 1 minute in the future.");
    }
    if (requeueAt > now + MAX_REQUEUE_DELAY_MS) {
        throw new Error("The requeue time cannot be more than 365 days away.");
    }
    return requeueAt;
}

module.exports = { parseRequeueAt, MIN_REQUEUE_DELAY_MS, MAX_REQUEUE_DELAY_MS };