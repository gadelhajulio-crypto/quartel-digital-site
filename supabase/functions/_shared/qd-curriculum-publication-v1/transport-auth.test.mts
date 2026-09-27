import assert from "node:assert/strict";
import {
  buildTransportCanonicalMessageV1,
  computeTransportBodyHashV1,
  computeTransportSignatureV1,
  parseTransportKeyringJson,
  QD_CURRICULUM_INTEGRATION,
  TransportAuthError,
  verifyTransportRequestV1,
} from "./transport-auth.ts";

const secret = "test-secret-0123456789abcdef-0123456789";
const keyId = "qd-2026-09-a";
const timestamp = 1790467200;
const nonce = "11111111-1111-4111-8111-111111111111";
const rawBody = new TextEncoder().encode(
  '{"contract_schema_version":1,"kind":"artifact"}',
);

let failed = 0;

async function check(
  name: string,
  fn: () => unknown | Promise<unknown>,
): Promise<void> {
  try {
    await fn();
    console.log(`  ✔ ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`  ✗ ${name}\n    ${(error as Error).message}`);
  }
}

function headers(signature: string): Headers {
  return new Headers({
    "X-RP-Integration": QD_CURRICULUM_INTEGRATION,
    "X-RP-Key-Id": keyId,
    "X-RP-Timestamp": String(timestamp),
    "X-RP-Nonce": nonce,
    "X-RP-Signature": `v1=${signature}`,
  });
}

console.log("Gate 5C — transport auth");

await check("known SHA-256 body vector", async () => {
  assert.equal(
    await computeTransportBodyHashV1(rawBody),
    "faa289af4f49f55ac1c25135288b6984d1527384eebfe6dc4783a39f240b909c",
  );
});

await check("known HMAC-SHA256 signature vector", async () => {
  assert.equal(
    await computeTransportSignatureV1(secret, timestamp, nonce, rawBody),
    "121ad2e4a92a6c1ed059406e791ccc02ff319a26ae3d6f29e5add27b4bcbdafa",
  );
});

await check("canonical message is stable", async () => {
  assert.equal(
    buildTransportCanonicalMessageV1(
      timestamp,
      nonce,
      "faa289af4f49f55ac1c25135288b6984d1527384eebfe6dc4783a39f240b909c",
    ),
    [
      "v1",
      String(timestamp),
      nonce,
      "faa289af4f49f55ac1c25135288b6984d1527384eebfe6dc4783a39f240b909c",
    ].join("\n"),
  );
});

await check("valid request authenticates", async () => {
  const signature = await computeTransportSignatureV1(
    secret,
    timestamp,
    nonce,
    rawBody,
  );
  const result = await verifyTransportRequestV1({
    headers: headers(signature),
    rawBody,
    keyring: { [keyId]: secret },
    nowUnixSeconds: timestamp,
  });
  assert.equal(result.key_id, keyId);
  assert.equal(result.nonce, nonce);
});

await check("tampered body fails HMAC", async () => {
  const signature = await computeTransportSignatureV1(
    secret,
    timestamp,
    nonce,
    rawBody,
  );
  const tampered = new TextEncoder().encode(
    '{"contract_schema_version":1,"kind":"release"}',
  );
  await assert.rejects(
    () =>
      verifyTransportRequestV1({
        headers: headers(signature),
        rawBody: tampered,
        keyring: { [keyId]: secret },
        nowUnixSeconds: timestamp,
      }),
    (error: unknown) =>
      error instanceof TransportAuthError &&
      error.reason === "invalid_signature",
  );
});

await check("unknown key id fails closed", async () => {
  const signature = await computeTransportSignatureV1(
    secret,
    timestamp,
    nonce,
    rawBody,
  );
  await assert.rejects(
    () =>
      verifyTransportRequestV1({
        headers: headers(signature),
        rawBody,
        keyring: {},
        nowUnixSeconds: timestamp,
      }),
    (error: unknown) =>
      error instanceof TransportAuthError &&
      error.reason === "unknown_key_id",
  );
});

await check("timestamp outside 300 seconds fails closed", async () => {
  const signature = await computeTransportSignatureV1(
    secret,
    timestamp,
    nonce,
    rawBody,
  );
  await assert.rejects(
    () =>
      verifyTransportRequestV1({
        headers: headers(signature),
        rawBody,
        keyring: { [keyId]: secret },
        nowUnixSeconds: timestamp + 301,
      }),
    (error: unknown) =>
      error instanceof TransportAuthError &&
      error.reason === "timestamp_outside_window",
  );
});

await check("malformed nonce fails closed", async () => {
  const signature = await computeTransportSignatureV1(
    secret,
    timestamp,
    nonce,
    rawBody,
  );
  const requestHeaders = headers(signature);
  requestHeaders.set("X-RP-Nonce", "not-a-uuid");
  await assert.rejects(
    () =>
      verifyTransportRequestV1({
        headers: requestHeaders,
        rawBody,
        keyring: { [keyId]: secret },
        nowUnixSeconds: timestamp,
      }),
    (error: unknown) =>
      error instanceof TransportAuthError &&
      error.reason === "invalid_nonce",
  );
});

await check("keyring enforces bounded strong secrets", () => {
  assert.deepEqual(
    parseTransportKeyringJson(JSON.stringify({ [keyId]: secret })),
    { [keyId]: secret },
  );
  assert.throws(() =>
    parseTransportKeyringJson(JSON.stringify({ [keyId]: "short" }))
  );
});

if (failed > 0) {
  console.error(`\n❌ ${failed} test(s) failed`);
  process.exit(1);
}

console.log("\n✅ Gate 5C transport auth PASS");
