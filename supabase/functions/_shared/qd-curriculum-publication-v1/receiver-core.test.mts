import assert from "node:assert/strict";
import {
  buildIdempotencyKey,
  computeContentHash,
  computeReleaseManifestHash,
} from "./contract.ts";
import {
  stagePublicationEnvelopeV1,
  stageReleaseManifestV1,
  type ShadowStagingStore,
  type StagedArtifactVersion,
  type StagedRelease,
} from "./receiver-core.ts";

class MemoryStore implements ShadowStagingStore {
  artifacts: Record<string, unknown>[] = [];
  releases: Record<string, unknown>[] = [];
  members: Record<string, unknown>[] = [];

  async findArtifactVersion(input: {
    artifact_type: string;
    stable_source_id: string;
    source_version_major: number;
    source_version_minor: number;
  }): Promise<StagedArtifactVersion | null> {
    return (
      (this.artifacts.find(
        (row) =>
          row.artifact_type === input.artifact_type &&
          row.stable_source_id === input.stable_source_id &&
          row.source_version_major === input.source_version_major &&
          row.source_version_minor === input.source_version_minor,
      ) as StagedArtifactVersion | undefined) ?? null
    );
  }

  async findLatestArtifactVersion(input: {
    artifact_type: string;
    stable_source_id: string;
  }): Promise<StagedArtifactVersion | null> {
    return (
      (this.artifacts
        .filter(
          (row) =>
            row.artifact_type === input.artifact_type &&
            row.stable_source_id === input.stable_source_id,
        )
        .sort(
          (left, right) =>
            Number(right.source_version_major) -
              Number(left.source_version_major) ||
            Number(right.source_version_minor) -
              Number(left.source_version_minor),
        )[0] as StagedArtifactVersion | undefined) ?? null
    );
  }

  async insertArtifactVersion(row: Record<string, unknown>): Promise<void> {
    this.artifacts.push(row);
  }

  async findRelease(release_id: string): Promise<StagedRelease | null> {
    return (
      (this.releases.find(
        (row) => row.release_id === release_id,
      ) as StagedRelease | undefined) ?? null
    );
  }

  async insertReleaseBundle(
    release: Record<string, unknown>,
    artifacts: Record<string, unknown>[],
  ): Promise<void> {
    this.releases.push(release);
    this.members.push(...artifacts);
  }
}

const ids = {
  source: "11111111-1111-4111-8111-111111111111",
  artifact0: "22222222-2222-4222-8222-222222222220",
  artifact1: "22222222-2222-4222-8222-222222222221",
  artifact2: "22222222-2222-4222-8222-222222222222",
  publication0: "33333333-3333-4333-8333-333333333330",
  publication1: "33333333-3333-4333-8333-333333333331",
  publication2: "33333333-3333-4333-8333-333333333332",
  release: "55555555-5555-4555-8555-555555555555",
};

async function publication(
  minor: 0 | 1 | 2,
  title = "Módulo",
): Promise<Record<string, unknown>> {
  const payload = {
    title,
    force: "marinha",
    sequence_order: 1,
    active: true,
  };
  const sourceVersion = { major: 1, minor };
  const artifactVersions = [ids.artifact0, ids.artifact1, ids.artifact2];
  const publicationIds = [ids.publication0, ids.publication1, ids.publication2];

  return {
    contract_schema_version: 1,
    publication_id: publicationIds[minor],
    producer: {
      system: "rp_os",
      capability: "quartel_curriculum_publication",
    },
    artifact: {
      type: "module",
      stable_source_id: ids.source,
      stable_code: "QD.MOD.001",
      source_version: sourceVersion,
      artifact_version_id: artifactVersions[minor],
      content_hash: await computeContentHash(payload),
      state: "published",
    },
    approval: {
      state: "approved",
      approved_at: "2026-09-20T10:00:00.000Z",
      approved_by_ref: "editorial-board",
    },
    provenance: {
      source_reference: "manual",
      authority_body: "RP OS",
      curriculum_version: "2026.09",
    },
    release: {
      release_id: ids.release,
      release_code: "QD-MAR-2026.001",
      release_sequence: 1,
    },
    timing: {
      published_at: "2026-09-20T11:00:00.000Z",
      effective_at: null,
    },
    supersession: {
      supersedes_artifact_version_id: null,
    },
    idempotency: {
      key: await buildIdempotencyKey({
        artifact_type: "module",
        stable_source_id: ids.source,
        source_version: sourceVersion,
      }),
    },
    payload: {
      module: payload,
    },
  };
}

async function releaseManifest(): Promise<Record<string, unknown>> {
  const artifact = await publication(0);
  const artifactRecord = artifact.artifact as Record<string, unknown>;
  const manifestWithoutHash = {
    contract_schema_version: 1,
    release_id: ids.release,
    release_code: "QD-MAR-2026.001",
    release_sequence: 1,
    producer: { system: "rp_os" },
    artifacts: [
      {
        artifact_type: artifactRecord.type,
        stable_source_id: artifactRecord.stable_source_id,
        source_version: artifactRecord.source_version,
        artifact_version_id: artifactRecord.artifact_version_id,
        content_hash: artifactRecord.content_hash,
      },
    ],
    published_at: "2026-09-20T11:00:00.000Z",
  };

  return {
    ...manifestWithoutHash,
    manifest_hash: await computeReleaseManifestHash(manifestWithoutHash),
  };
}

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

console.log("Gate 5B — shadow ingestion core");

await check("first artifact stages once", async () => {
  const store = new MemoryStore();
  assert.deepEqual(await stagePublicationEnvelopeV1(store, await publication(0)), {
    status: "STAGED",
    inserted: true,
    relation: "FIRST",
  });
  assert.equal(store.artifacts.length, 1);
});

await check("replay is idempotent", async () => {
  const store = new MemoryStore();
  const input = await publication(0);
  await stagePublicationEnvelopeV1(store, input);
  assert.deepEqual(await stagePublicationEnvelopeV1(store, input), {
    status: "REPLAY",
    inserted: false,
  });
  assert.equal(store.artifacts.length, 1);
});

await check("same version with different hash is conflict", async () => {
  const store = new MemoryStore();
  await stagePublicationEnvelopeV1(store, await publication(0));
  assert.deepEqual(
    await stagePublicationEnvelopeV1(store, await publication(0, "Outro módulo")),
    { status: "CONFLICT", inserted: false },
  );
  assert.equal(store.artifacts.length, 1);
});

await check("stale version is rejected", async () => {
  const store = new MemoryStore();
  await stagePublicationEnvelopeV1(store, await publication(2));
  assert.deepEqual(await stagePublicationEnvelopeV1(store, await publication(1)), {
    status: "STALE",
    inserted: false,
  });
  assert.equal(store.artifacts.length, 1);
});

await check("newer version appends", async () => {
  const store = new MemoryStore();
  await stagePublicationEnvelopeV1(store, await publication(0));
  assert.deepEqual(await stagePublicationEnvelopeV1(store, await publication(1)), {
    status: "STAGED",
    inserted: true,
    relation: "NEWER",
  });
  assert.equal(store.artifacts.length, 2);
});

await check("invalid contract input performs zero writes", async () => {
  const store = new MemoryStore();
  const invalid = {
    ...(await publication(0)),
    contract_schema_version: 2,
  };
  await assert.rejects(() => stagePublicationEnvelopeV1(store, invalid));
  assert.equal(store.artifacts.length, 0);
});

await check("release stages as one logical bundle", async () => {
  const store = new MemoryStore();
  const manifest = await releaseManifest();
  assert.deepEqual(await stageReleaseManifestV1(store, manifest), {
    status: "STAGED",
    inserted: true,
    artifact_count: 1,
  });
  assert.equal(store.releases.length, 1);
  assert.equal(store.members.length, 1);
});

await check("release replay performs zero additional writes", async () => {
  const store = new MemoryStore();
  const manifest = await releaseManifest();
  await stageReleaseManifestV1(store, manifest);
  assert.deepEqual(await stageReleaseManifestV1(store, manifest), {
    status: "REPLAY",
    inserted: false,
  });
  assert.equal(store.releases.length, 1);
  assert.equal(store.members.length, 1);
});

await check("release id/hash conflict performs zero additional writes", async () => {
  const store = new MemoryStore();
  const manifest = await releaseManifest();
  await stageReleaseManifestV1(store, manifest);

  const conflictingWithoutHash = {
    ...manifest,
    release_code: "QD-MAR-2026.001-CONFLICT",
  };
  delete (conflictingWithoutHash as Record<string, unknown>).manifest_hash;
  const conflicting = {
    ...conflictingWithoutHash,
    manifest_hash: await computeReleaseManifestHash(conflictingWithoutHash),
  };

  assert.deepEqual(await stageReleaseManifestV1(store, conflicting), {
    status: "CONFLICT",
    inserted: false,
  });
  assert.equal(store.releases.length, 1);
  assert.equal(store.members.length, 1);
});

if (failed > 0) {
  console.error(`\n❌ ${failed} test(s) failed`);
  process.exit(1);
}

console.log("\n✅ Gate 5B shadow ingestion core PASS");
