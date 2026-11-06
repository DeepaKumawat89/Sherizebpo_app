const assert = require('node:assert/strict');
const net = require('node:net');

const originalConnect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) {
  const normalized = Array.isArray(args[0]) ? args[0] : args;
  const options = normalized[0];
  const host = typeof options === 'object'
    ? options.host || options.hostname || '127.0.0.1'
    : typeof normalized[1] === 'string' ? normalized[1] : '127.0.0.1';
  if (!['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)) {
    throw new Error(`QA sandbox blocked external connection to ${host}`);
  }
  return originalConnect.apply(this, args);
};

if (process.argv.includes('--check')) {
  assert.throws(() => new net.Socket().connect(443, 'example.com'), /blocked external/);
  assert.throws(() => new net.Socket().connect({ port: 443, host: 'example.com' }), /blocked external/);
  console.log('Sandbox rejects external socket connections.');
} else {
  if (process.env.GCLOUD_PROJECT !== 'demo-sherize-workflow' ||
      !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error('QA backend requires the isolated demo project and local emulators.');
  }
  module.exports = require('./index.js');
}