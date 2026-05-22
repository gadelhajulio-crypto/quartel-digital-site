// Minimal assert polyfill for React Native bundle.
// Replaces the Node.js `assert` module (pulled in by @ide/backoff via expo-notifications).
// Only implements the API surface actually used: assert(condition, message).
'use strict';

function assert(value, message) {
  if (!value) {
    var err = new Error(message != null ? String(message) : 'Assertion failed');
    err.name = 'AssertionError';
    throw err;
  }
}

assert.ok = assert;
assert.strictEqual = function strictEqual(actual, expected, message) {
  if (actual !== expected) {
    throw new Error(message != null ? String(message) : actual + ' !== ' + expected);
  }
};
assert.deepStrictEqual = assert.strictEqual;

module.exports = assert;
