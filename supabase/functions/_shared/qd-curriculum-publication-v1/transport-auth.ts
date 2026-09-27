export const QD_CURRICULUM_INTEGRATION = "quartel_curriculum_publication:v1" as const;
export const QD_CURRICULUM_MAX_BODY_BYTES = 1024 * 1024;
export const QD_CURRICULUM_ALLOWED_CLOCK_SKEW_SECONDS = 300;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KEY_ID = /^[A-Za-z0-9._-]{1,64}$/;
const SIGNATURE = /^v1=([0-9a-f]{64})$/;
const encoder = new TextEncoder();

export type TransportAuthReason =
  | "missing_integration"
  | "unexpected_integration"
  | "missing_key_id"
  | "invalid_key_id"
  | "unknown_key_id"
  | "missing_timestamp"
  | "invalid_timestamp"
  | "timestamp_outside_window"
  | "missing_nonce"
  | "invalid_nonce"
  | "missing_signature"
  | "invalid_signature_format"
  | "invalid_signature"
  | "weak_runtime_secret";

export class TransportAuthError extends Error {
  readonly reason: TransportAuthReason;

  constructor(reason: TransportAuthReason) {
    super(reason);
    this.reason = reason;
    this.name = "TransportAuthError";
  }
}

export interface TransportAuthContext {
  integration: typeof QD_CURRICULUM_INTEGRATION;
  key_id: string;
  timestamp: number;
  nonce: string;
  body_hash: string;
}

function requireHeader(headers: Headers, name: string, reason: TransportAuthReason): string {
  const value = headers.get(name);
  if (!value) throw new TransportAuthError(reason);
  return value;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

async function sha256Hex(input: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", input);
  return bytesToHex(new Uint8Array(digest));
}

async function importHmacKey(secret: string): Promise<CryptoKey> {
  if (encoder.encode(secret).byteLength < 32) {
    throw new TransportAuthError("weak_runtime_secret");
  }
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

export async function computeTransportBodyHashV1(rawBody: Uint8Array): Promise<string> {
  return sha256Hex(rawBody);
}

export function buildTransportCanonicalMessageV1(
  timestamp: string | number,
  nonce: string,
  bodyHash: string,
): string {
  return ["v1", String(timestamp), nonce, bodyHash].join("\n");
}

export async function computeTransportSignatureV1(
  secret: string,
  timestamp: string | number,
  nonce: string,
  rawBody: Uint8Array,
): Promise<string> {
  const bodyHash = await computeTransportBodyHashV1(rawBody);
  const message = buildTransportCanonicalMessageV1(timestamp, nonce, bodyHash);
  const key = await importHmacKey(secret);
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return bytesToHex(new Uint8Array(signature));
}

export function getTransportKeyId(headers: Headers): string {
  const keyId = requireHeader(headers, "X-RP-Key-Id", "missing_key_id");
  if (!KEY_ID.test(keyId)) throw new TransportAuthError("invalid_key_id");
  return keyId;
}

export async function verifyTransportRequestV1(input: {
  headers: Headers;
  rawBody: Uint8Array;
  keyring: Readonly<Record<string, string>>;
  nowUnixSeconds?: number;
}): Promise<TransportAuthContext> {
  const integration = requireHeader(
    input.headers,
    "X-RP-Integration",
    "missing_integration",
  );
  if (integration !== QD_CURRICULUM_INTEGRATION) {
    throw new TransportAuthError("unexpected_integration");
  }

  const keyId = getTransportKeyId(input.headers);
  const secret = input.keyring[keyId];
  if (!secret) throw new TransportAuthError("unknown_key_id");

  const timestampText = requireHeader(
    input.headers,
    "X-RP-Timestamp",
    "missing_timestamp",
  );
  if (!/^\d{1,13}$/.test(timestampText)) {
    throw new TransportAuthError("invalid_timestamp");
  }

  const timestamp = Number(timestampText);
  if (!Number.isSafeInteger(timestamp) || timestamp < 0) {
    throw new TransportAuthError("invalid_timestamp");
  }

  const now = input.nowUnixSeconds ?? Math.floor(Date.now() / 1000);
  if (Math.abs(now - timestamp) > QD_CURRICULUM_ALLOWED_CLOCK_SKEW_SECONDS) {
    throw new TransportAuthError("timestamp_outside_window");
  }

  const nonce = requireHeader(input.headers, "X-RP-Nonce", "missing_nonce");
  if (!UUID.test(nonce)) throw new TransportAuthError("invalid_nonce");

  const signatureHeader = requireHeader(
    input.headers,
    "X-RP-Signature",
    "missing_signature",
  );
  const signatureMatch = SIGNATURE.exec(signatureHeader);
  if (!signatureMatch) throw new TransportAuthError("invalid_signature_format");

  const bodyHash = await computeTransportBodyHashV1(input.rawBody);
  const message = buildTransportCanonicalMessageV1(timestampText, nonce, bodyHash);
  const key = await importHmacKey(secret);
  const valid = await crypto.subtle.verify(
    "HMAC",
    key,
    hexToBytes(signatureMatch[1]),
    encoder.encode(message),
  );
  if (!valid) throw new TransportAuthError("invalid_signature");

  return {
    integration: QD_CURRICULUM_INTEGRATION,
    key_id: keyId,
    timestamp,
    nonce,
    body_hash: bodyHash,
  };
}

export function parseTransportKeyringJson(value: string | undefined): Record<string, string> {
  if (!value) return {};

  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    throw new Error("invalid_hmac_keyring_json");
  }

  if (
    parsed === null ||
    typeof parsed !== "object" ||
    Array.isArray(parsed)
  ) {
    throw new Error("invalid_hmac_keyring_json");
  }

  const entries = Object.entries(parsed as Record<string, unknown>);
  if (entries.length === 0 || entries.length > 4) {
    throw new Error("invalid_hmac_keyring_size");
  }

  const keyring: Record<string, string> = {};
  for (const [keyId, secret] of entries) {
    if (!KEY_ID.test(keyId) || typeof secret !== "string") {
      throw new Error("invalid_hmac_keyring_entry");
    }
    if (encoder.encode(secret).byteLength < 32) {
      throw new Error("weak_hmac_keyring_secret");
    }
    keyring[keyId] = secret;
  }

  return keyring;
}
