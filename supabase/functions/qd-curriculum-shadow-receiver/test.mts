import assert from "node:assert/strict";
import { buildIdempotencyKey, computeContentHash } from "../_shared/qd-curriculum-publication-v1/contract.ts";
import { computeTransportSignatureV1, QD_CURRICULUM_INTEGRATION } from "../_shared/qd-curriculum-publication-v1/transport-auth.ts";
import { handleShadowReceiver } from "./handler.ts";

const secret = "test-secret-0123456789abcdef-0123456789";
const keyId = "qd-2026-09-a";
const now = 1790467200;
const nonce = "11111111-1111-4111-8111-111111111111";

async function artifact() {
  const payload = { title: "Módulo", force: "marinha", sequence_order: 1, active: true };
  const stable_source_id = "11111111-1111-4111-8111-111111111112";
  const source_version = { major: 1, minor: 0 };
  return {
    contract_schema_version: 1,
    publication_id: "33333333-3333-4333-8333-333333333330",
    producer: { system: "rp_os", capability: "quartel_curriculum_publication" },
    artifact: {
      type: "module",
      stable_source_id,
      stable_code: "QD.MOD.001",
      source_version,
      artifact_version_id: "22222222-2222-4222-8222-222222222220",
      content_hash: await computeContentHash(payload),
      state: "published",
    },
    approval: { state: "approved", approved_at: "2026-09-20T10:00:00.000Z", approved_by_ref: "editorial-board" },
    provenance: { source_reference: "manual", authority_body: "RP OS", curriculum_version: "2026.09" },
    release: { release_id: "55555555-5555-4555-8555-555555555555", release_code: "QD-MAR-2026.001", release_sequence: 1 },
    timing: { published_at: "2026-09-20T11:00:00.000Z", effective_at: null },
    supersession: { supersedes_artifact_version_id: null },
    idempotency: {
      key: await buildIdempotencyKey({ artifact_type: "module", stable_source_id, source_version }),
    },
    payload: { module: payload },
  };
}

async function signed(body: string, signedBody = body) {
  const sig = await computeTransportSignatureV1(secret, now, nonce, new TextEncoder().encode(signedBody));
  return new Request("https://example.invalid/qd-curriculum-shadow-receiver", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-RP-Integration": QD_CURRICULUM_INTEGRATION,
      "X-RP-Key-Id": keyId,
      "X-RP-Timestamp": String(now),
      "X-RP-Nonce": nonce,
      "X-RP-Signature": `v1=${sig}`,
    },
    body,
  });
}

function make(overrides: Record<string, unknown> = {}) {
  const calls = { reserve: 0, stage: 0 };
  return {
    calls,
    deps: {
      enabled: true,
      keyring: { [keyId]: secret },
      nowUnixSeconds: () => now,
      requestId: () => "99999999-9999-4999-8999-999999999999",
      async reserveNonce() { calls.reserve++; return true; },
      async stageArtifact() { calls.stage++; return { status: "STAGED", inserted: true, relation: "FIRST" } as const; },
      async stageRelease() { return { status: "STAGED", inserted: true, artifact_count: 1 } as const; },
      ...overrides,
    },
  };
}

const body = JSON.stringify(await artifact());

{
  const { deps, calls } = make({ enabled: false });
  const response = await handleShadowReceiver(await signed(body), deps);
  assert.equal(response.status, 503);
  assert.deepEqual(calls, { reserve: 0, stage: 0 });
}

{
  const { deps, calls } = make();
  const response = await handleShadowReceiver(await signed(body), deps);
  assert.equal(response.status, 202);
  assert.deepEqual(calls, { reserve: 1, stage: 1 });
}

{
  const { deps, calls } = make();
  const response = await handleShadowReceiver(await signed(body, body + "tamper"), deps);
  assert.equal(response.status, 401);
  assert.deepEqual(calls, { reserve: 0, stage: 0 });
}

{
  const { calls, deps } = make({
    async reserveNonce() { calls.reserve++; return false; },
  });
  const response = await handleShadowReceiver(await signed(body), deps);
  assert.equal(response.status, 409);
  assert.deepEqual(calls, { reserve: 1, stage: 0 });
}

{
  const { deps, calls } = make();
  const response = await handleShadowReceiver(await signed("{invalid-json"), deps);
  assert.equal(response.status, 422);
  assert.deepEqual(calls, { reserve: 1, stage: 0 });
}

console.log("✅ Gate 5C shadow receiver handler PASS");
