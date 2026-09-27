import {
  QD_CURRICULUM_MAX_BODY_BYTES,
  TransportAuthError,
  verifyTransportRequestV1,
} from "../_shared/qd-curriculum-publication-v1/transport-auth.ts";
import type {
  ShadowArtifactStageResult,
  ShadowReleaseStageResult,
} from "../_shared/qd-curriculum-publication-v1/receiver-core.ts";

export interface ShadowReceiverDependencies {
  enabled: boolean;
  keyring: Readonly<Record<string, string>>;
  reserveNonce(input: {
    key_id: string;
    nonce: string;
    request_id: string;
    retention_seconds: number;
  }): Promise<boolean>;
  stageArtifact(input: unknown): Promise<ShadowArtifactStageResult>;
  stageRelease(input: unknown): Promise<ShadowReleaseStageResult>;
  nowUnixSeconds?: () => number;
  requestId?: () => string;
  log?: (event: string, fields: Record<string, unknown>) => void;
}

class RequestFailure extends Error {
  readonly status: number;
  readonly reason: string;

  constructor(status: number, reason: string) {
    super(reason);
    this.status = status;
    this.reason = reason;
  }
}

function json(
  status: number,
  body: Record<string, unknown>,
  headers?: Record<string, string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...headers,
    },
  });
}

async function readBodyLimited(
  request: Request,
  maxBytes = QD_CURRICULUM_MAX_BODY_BYTES,
): Promise<Uint8Array> {
  const declaredLength = request.headers.get("content-length");
  if (declaredLength !== null) {
    const parsed = Number(declaredLength);
    if (!Number.isFinite(parsed) || parsed < 0) {
      throw new RequestFailure(400, "invalid_content_length");
    }
    if (parsed > maxBytes) {
      throw new RequestFailure(413, "request_too_large");
    }
  }

  if (!request.body) return new Uint8Array();

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value) continue;

    total += value.byteLength;
    if (total > maxBytes) {
      try {
        await reader.cancel();
      } catch {
        // Best-effort cancellation only.
      }
      throw new RequestFailure(413, "request_too_large");
    }
    chunks.push(value);
  }

  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}

function objectShape(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new RequestFailure(422, "invalid_contract");
  }
  return value as Record<string, unknown>;
}

function classifyPayload(value: unknown): "artifact" | "release" {
  const body = objectShape(value);
  const artifact =
    Object.prototype.hasOwnProperty.call(body, "publication_id") &&
    Object.prototype.hasOwnProperty.call(body, "artifact");
  const release =
    Object.prototype.hasOwnProperty.call(body, "manifest_hash") &&
    Object.prototype.hasOwnProperty.call(body, "artifacts");

  if (artifact === release) {
    throw new RequestFailure(422, "invalid_contract");
  }
  return artifact ? "artifact" : "release";
}

function stageResponse(
  result: ShadowArtifactStageResult | ShadowReleaseStageResult,
  requestId: string,
): Response {
  if (result.status === "STAGED") {
    return json(202, {
      ok: true,
      status: result.status,
      request_id: requestId,
    });
  }

  if (result.status === "CONFLICT") {
    return json(409, {
      ok: false,
      status: result.status,
      request_id: requestId,
    });
  }

  return json(200, {
    ok: true,
    status: result.status,
    request_id: requestId,
  });
}

export async function handleShadowReceiver(
  request: Request,
  deps: ShadowReceiverDependencies,
): Promise<Response> {
  const requestId = deps.requestId?.() ?? crypto.randomUUID();
  const log = deps.log ?? (() => undefined);

  if (!deps.enabled) {
    log("receiver_disabled", { request_id: requestId });
    return json(503, {
      ok: false,
      reason: "receiver_disabled",
      request_id: requestId,
    });
  }

  if (request.method !== "POST") {
    log("method_rejected", { request_id: requestId, method: request.method });
    return json(
      405,
      { ok: false, reason: "method_not_allowed", request_id: requestId },
      { allow: "POST" },
    );
  }

  const contentType = request.headers.get("content-type") ?? "";
  if (!/^application\/json(?:\s*;|$)/i.test(contentType)) {
    log("content_type_rejected", { request_id: requestId });
    return json(415, {
      ok: false,
      reason: "unsupported_content_type",
      request_id: requestId,
    });
  }

  let rawBody: Uint8Array;
  try {
    rawBody = await readBodyLimited(request);
  } catch (error) {
    if (error instanceof RequestFailure) {
      log("request_rejected", {
        request_id: requestId,
        reason: error.reason,
      });
      return json(error.status, {
        ok: false,
        reason: error.reason,
        request_id: requestId,
      });
    }
    throw error;
  }

  let auth;
  try {
    auth = await verifyTransportRequestV1({
      headers: request.headers,
      rawBody,
      keyring: deps.keyring,
      nowUnixSeconds: deps.nowUnixSeconds?.(),
    });
  } catch (error) {
    if (error instanceof TransportAuthError) {
      log("transport_auth_rejected", {
        request_id: requestId,
        reason: error.reason,
      });
      return json(401, {
        ok: false,
        reason: "transport_auth_failed",
        request_id: requestId,
      });
    }
    throw error;
  }

  let reserved: boolean;
  try {
    reserved = await deps.reserveNonce({
      key_id: auth.key_id,
      nonce: auth.nonce,
      request_id: requestId,
      retention_seconds: 600,
    });
  } catch {
    log("nonce_reservation_failed", {
      request_id: requestId,
      key_id: auth.key_id,
    });
    return json(500, {
      ok: false,
      reason: "internal_error",
      request_id: requestId,
    });
  }

  if (!reserved) {
    log("transport_replay_rejected", {
      request_id: requestId,
      key_id: auth.key_id,
    });
    return json(409, {
      ok: false,
      reason: "transport_replay",
      request_id: requestId,
    });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(rawBody));
  } catch {
    log("contract_rejected", {
      request_id: requestId,
      key_id: auth.key_id,
      reason: "invalid_json",
    });
    return json(422, {
      ok: false,
      reason: "invalid_contract",
      request_id: requestId,
    });
  }

  try {
    const kind = classifyPayload(parsed);
    const result = kind === "artifact"
      ? await deps.stageArtifact(parsed)
      : await deps.stageRelease(parsed);

    const response = stageResponse(result, requestId);
    log("shadow_stage_result", {
      request_id: requestId,
      key_id: auth.key_id,
      kind,
      status: result.status,
      http_status: response.status,
    });
    return response;
  } catch (error) {
    if (error instanceof TypeError || error instanceof RequestFailure) {
      log("contract_rejected", {
        request_id: requestId,
        key_id: auth.key_id,
        reason: "invalid_contract",
      });
      return json(422, {
        ok: false,
        reason: "invalid_contract",
        request_id: requestId,
      });
    }

    log("shadow_stage_failed", {
      request_id: requestId,
      key_id: auth.key_id,
    });
    return json(500, {
      ok: false,
      reason: "internal_error",
      request_id: requestId,
    });
  }
}
