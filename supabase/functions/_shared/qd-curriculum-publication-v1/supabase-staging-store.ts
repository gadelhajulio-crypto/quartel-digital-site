import type { ArtifactType } from "./contract.ts";
import type {
  ShadowStagingStore,
  StagedArtifactVersion,
  StagedRelease,
} from "./receiver-core.ts";

type SupabaseError = {
  message: string;
  code?: string | null;
};

type SupabaseClientLike = {
  from(table: string): any;
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: SupabaseError | null }>;
};

function fail(error: SupabaseError | null, operation: string): void {
  if (error) {
    throw new Error(
      `${operation}: ${error.code ? `${error.code}: ` : ""}${error.message}`,
    );
  }
}

export class SupabaseShadowStagingStore implements ShadowStagingStore {
  constructor(private readonly client: SupabaseClientLike) {}

  async findArtifactVersion(input: {
    artifact_type: ArtifactType;
    stable_source_id: string;
    source_version_major: number;
    source_version_minor: number;
  }): Promise<StagedArtifactVersion | null> {
    const { data, error } = await this.client
      .from("qd_curriculum_artifact_versions")
      .select(
        "id,artifact_type,stable_source_id,source_version_major,source_version_minor,artifact_version_id,content_hash",
      )
      .eq("artifact_type", input.artifact_type)
      .eq("stable_source_id", input.stable_source_id)
      .eq("source_version_major", input.source_version_major)
      .eq("source_version_minor", input.source_version_minor)
      .maybeSingle();

    fail(error, "findArtifactVersion");
    return data as StagedArtifactVersion | null;
  }

  async findLatestArtifactVersion(input: {
    artifact_type: ArtifactType;
    stable_source_id: string;
  }): Promise<StagedArtifactVersion | null> {
    const { data, error } = await this.client
      .from("qd_curriculum_artifact_versions")
      .select(
        "id,artifact_type,stable_source_id,source_version_major,source_version_minor,artifact_version_id,content_hash",
      )
      .eq("artifact_type", input.artifact_type)
      .eq("stable_source_id", input.stable_source_id)
      .order("source_version_major", { ascending: false })
      .order("source_version_minor", { ascending: false })
      .limit(1)
      .maybeSingle();

    fail(error, "findLatestArtifactVersion");
    return data as StagedArtifactVersion | null;
  }

  async insertArtifactVersion(row: Record<string, unknown>): Promise<void> {
    const { error } = await this.client
      .from("qd_curriculum_artifact_versions")
      .insert(row);

    fail(error, "insertArtifactVersion");
  }

  async findRelease(release_id: string): Promise<StagedRelease | null> {
    const { data, error } = await this.client
      .from("qd_curriculum_releases")
      .select("release_id,release_code,release_sequence,manifest_hash")
      .eq("release_id", release_id)
      .maybeSingle();

    fail(error, "findRelease");
    return data as StagedRelease | null;
  }

  async insertReleaseBundle(
    release: Record<string, unknown>,
    artifacts: Record<string, unknown>[],
  ): Promise<void> {
    const { error } = await this.client.rpc(
      "qd_curriculum_stage_release_bundle",
      {
        p_release: release,
        p_artifacts: artifacts,
      },
    );

    fail(error, "insertReleaseBundle");
  }
}
