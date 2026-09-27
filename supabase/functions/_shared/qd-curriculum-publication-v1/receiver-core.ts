import {
  classifyIncomingPublication,
  parseContentReleaseManifestV1,
  parsePublicationEnvelopeV1,
  type ArtifactType,
  type ContentPublicationEnvelopeV1,
  type ContentReleaseManifestV1,
  type SourceVersion,
} from "./contract.ts";

export interface StagedArtifactVersion {
  id?: string;
  artifact_type: ArtifactType;
  stable_source_id: string;
  source_version_major: number;
  source_version_minor: number;
  artifact_version_id: string;
  content_hash: string;
}

export interface StagedRelease {
  release_id: string;
  release_code: string;
  release_sequence: number;
  manifest_hash: string;
}

export interface ShadowStagingStore {
  findArtifactVersion(input: {
    artifact_type: ArtifactType;
    stable_source_id: string;
    source_version_major: number;
    source_version_minor: number;
  }): Promise<StagedArtifactVersion | null>;
  findLatestArtifactVersion(input: {
    artifact_type: ArtifactType;
    stable_source_id: string;
  }): Promise<StagedArtifactVersion | null>;
  insertArtifactVersion(row: Record<string, unknown>): Promise<void>;
  findRelease(release_id: string): Promise<StagedRelease | null>;
  insertReleaseBundle(release: Record<string, unknown>, artifacts: Record<string, unknown>[]): Promise<void>;
}

export type ShadowArtifactStageResult =
  | { status: "STAGED"; inserted: true; relation: "FIRST" | "NEWER" }
  | { status: "REPLAY" | "CONFLICT" | "STALE"; inserted: false };

export type ShadowReleaseStageResult =
  | { status: "STAGED"; inserted: true; artifact_count: number }
  | { status: "REPLAY" | "CONFLICT"; inserted: false };

function asRecord(value: unknown, path: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${path}: expected object`);
  }
  return value as Record<string, unknown>;
}

function asString(value: unknown, path: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`${path}: expected non-empty string`);
  }
  return value;
}

function asInteger(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new TypeError(`${path}: expected integer`);
  }
  return value;
}

function sourceVersion(value: unknown, path = "artifact.source_version"): SourceVersion {
  const version = asRecord(value, path);
  return {
    major: asInteger(version.major, path + ".major"),
    minor: asInteger(version.minor, path + ".minor"),
  };
}

function artifactIdentity(envelope: ContentPublicationEnvelopeV1) {
  const artifact = asRecord(envelope.artifact, "artifact");
  const artifact_type = asString(artifact.type, "artifact.type") as ArtifactType;
  const stable_source_id = asString(artifact.stable_source_id, "artifact.stable_source_id");
  const source_version = sourceVersion(artifact.source_version);
  const artifact_version_id = asString(artifact.artifact_version_id, "artifact.artifact_version_id");
  const content_hash = asString(artifact.content_hash, "artifact.content_hash");
  return {
    artifact,
    artifact_type,
    stable_source_id,
    source_version,
    artifact_version_id,
    content_hash,
  };
}

function relationInput(row: StagedArtifactVersion) {
  return {
    stable_source_id: row.stable_source_id,
    source_version: {
      major: row.source_version_major,
      minor: row.source_version_minor,
    },
    content_hash: row.content_hash,
  };
}

export async function stagePublicationEnvelopeV1(
  store: ShadowStagingStore,
  input: unknown,
): Promise<ShadowArtifactStageResult> {
  const envelope = await parsePublicationEnvelopeV1(input);
  const identity = artifactIdentity(envelope);

  const exact = await store.findArtifactVersion({
    artifact_type: identity.artifact_type,
    stable_source_id: identity.stable_source_id,
    source_version_major: identity.source_version.major,
    source_version_minor: identity.source_version.minor,
  });

  const incoming = {
    stable_source_id: identity.stable_source_id,
    source_version: identity.source_version,
    content_hash: identity.content_hash,
  };

  if (exact) {
    const relation = classifyIncomingPublication(relationInput(exact), incoming);
    if (relation === "REPLAY") return { status: "REPLAY", inserted: false };
    return { status: "CONFLICT", inserted: false };
  }

  const latest = await store.findLatestArtifactVersion({
    artifact_type: identity.artifact_type,
    stable_source_id: identity.stable_source_id,
  });

  if (latest) {
    const relation = classifyIncomingPublication(relationInput(latest), incoming);
    if (relation === "STALE") return { status: "STALE", inserted: false };
    if (relation === "CONFLICT" || relation === "REPLAY") {
      return { status: relation, inserted: false };
    }
    if (relation !== "NEWER") {
      throw new Error(`unexpected publication relation: ${relation}`);
    }
  }

  const approval = asRecord(envelope.approval, "approval");
  const provenance = asRecord(envelope.provenance, "provenance");
  const release = asRecord(envelope.release, "release");
  const timing = asRecord(envelope.timing, "timing");
  const supersession = asRecord(envelope.supersession, "supersession");
  const idempotency = asRecord(envelope.idempotency, "idempotency");
  const payloadContainer = asRecord(envelope.payload, "payload");

  await store.insertArtifactVersion({
    contract_schema_version: envelope.contract_schema_version,
    publication_id: envelope.publication_id,
    artifact_type: identity.artifact_type,
    stable_source_id: identity.stable_source_id,
    stable_code: identity.artifact.stable_code ?? null,
    source_version_major: identity.source_version.major,
    source_version_minor: identity.source_version.minor,
    artifact_version_id: identity.artifact_version_id,
    content_hash: identity.content_hash,
    release_id: release.release_id,
    release_code: release.release_code,
    release_sequence: release.release_sequence,
    approved_at: approval.approved_at,
    approved_by_ref: approval.approved_by_ref,
    published_at: timing.published_at,
    effective_at: timing.effective_at,
    supersedes_artifact_version_id: supersession.supersedes_artifact_version_id,
    idempotency_key: idempotency.key,
    provenance,
    payload: payloadContainer[identity.artifact_type],
    envelope,
  });

  return {
    status: "STAGED",
    inserted: true,
    relation: latest ? "NEWER" : "FIRST",
  };
}

export async function stageReleaseManifestV1(
  store: ShadowStagingStore,
  input: unknown,
): Promise<ShadowReleaseStageResult> {
  const manifest = await parseContentReleaseManifestV1(input);
  const release_id = asString(manifest.release_id, "release_id");
  const manifest_hash = asString(manifest.manifest_hash, "manifest_hash");
  const existing = await store.findRelease(release_id);

  if (existing) {
    return existing.manifest_hash === manifest_hash
      ? { status: "REPLAY", inserted: false }
      : { status: "CONFLICT", inserted: false };
  }

  const artifacts = Array.isArray(manifest.artifacts) ? manifest.artifacts : [];
  const releaseRow = {
    release_id,
    contract_schema_version: manifest.contract_schema_version,
    release_code: manifest.release_code,
    release_sequence: manifest.release_sequence,
    manifest_hash,
    published_at: manifest.published_at,
    manifest,
  };

  const membershipRows = artifacts.map((value, index) => {
    const artifact = asRecord(value, `artifacts[${index}]`);
    const version = sourceVersion(
      artifact.source_version,
      `artifacts[${index}].source_version`,
    );
    return {
      release_id,
      artifact_type: artifact.artifact_type,
      stable_source_id: artifact.stable_source_id,
      source_version_major: version.major,
      source_version_minor: version.minor,
      artifact_version_id: artifact.artifact_version_id,
      content_hash: artifact.content_hash,
    };
  });

  await store.insertReleaseBundle(releaseRow, membershipRows);

  return {
    status: "STAGED",
    inserted: true,
    artifact_count: artifacts.length,
  };
}
