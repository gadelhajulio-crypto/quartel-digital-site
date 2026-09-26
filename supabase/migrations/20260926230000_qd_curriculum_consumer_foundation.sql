-- Gate 5A — QD curriculum publication consumer mapping/staging foundation.
--
-- IMPORTANT:
--   * Migration file only in Gate 5A. Do not apply remotely in this gate.
--   * No receiver, transport, automatic sync, activation or learner-state mutation.
--   * All tables are server-side staging/control structures and intentionally have
--     no foreign keys to learner/runtime curriculum tables.
--   * Existing Quartel Digital UUIDs are preserved through explicit source mapping;
--     identity must never be inferred from title/name heuristics.

BEGIN;

CREATE OR REPLACE FUNCTION public.qd_curriculum_reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION '% is append-only; % is not allowed', TG_TABLE_NAME, TG_OP
    USING ERRCODE = '55000';
END;
$$;

REVOKE ALL ON FUNCTION public.qd_curriculum_reject_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.qd_curriculum_reject_mutation() FROM anon;
REVOKE ALL ON FUNCTION public.qd_curriculum_reject_mutation() FROM authenticated;

CREATE TABLE IF NOT EXISTS public.qd_curriculum_source_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  artifact_type text NOT NULL CHECK (artifact_type IN ('module', 'lesson', 'quiz', 'review', 'asset')),
  stable_source_id uuid NOT NULL,
  local_uuid uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT qd_curriculum_source_mappings_source_uq UNIQUE (artifact_type, stable_source_id),
  CONSTRAINT qd_curriculum_source_mappings_local_uq UNIQUE (artifact_type, local_uuid)
);

COMMENT ON TABLE public.qd_curriculum_source_mappings IS
  'Immutable explicit RP OS stable_source_id -> existing QD local UUID mapping. Never infer identity by title/name.';

CREATE TABLE IF NOT EXISTS public.qd_curriculum_artifact_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_schema_version integer NOT NULL CHECK (contract_schema_version = 1),
  publication_id uuid NOT NULL,
  artifact_type text NOT NULL CHECK (artifact_type IN ('module', 'lesson', 'quiz', 'review', 'asset')),
  stable_source_id uuid NOT NULL,
  stable_code text,
  source_version_major integer NOT NULL CHECK (source_version_major >= 0),
  source_version_minor integer NOT NULL CHECK (source_version_minor >= 0),
  artifact_version_id uuid NOT NULL,
  content_hash text NOT NULL CHECK (content_hash ~ '^sha256:[0-9a-f]{64}$'),
  release_id uuid NOT NULL,
  release_code text NOT NULL CHECK (length(release_code) > 0),
  release_sequence bigint NOT NULL CHECK (release_sequence > 0),
  approved_at timestamptz NOT NULL,
  approved_by_ref text NOT NULL CHECK (length(approved_by_ref) > 0),
  published_at timestamptz NOT NULL,
  effective_at timestamptz,
  supersedes_artifact_version_id uuid,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) > 0),
  provenance jsonb NOT NULL,
  payload jsonb NOT NULL,
  envelope jsonb NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT qd_curriculum_artifact_versions_publication_uq UNIQUE (publication_id),
  CONSTRAINT qd_curriculum_artifact_versions_version_id_uq UNIQUE (artifact_version_id),
  CONSTRAINT qd_curriculum_artifact_versions_idempotency_uq UNIQUE (idempotency_key),
  CONSTRAINT qd_curriculum_artifact_versions_source_version_uq
    UNIQUE (artifact_type, stable_source_id, source_version_major, source_version_minor)
);

COMMENT ON TABLE public.qd_curriculum_artifact_versions IS
  'Append-only validated quartel_curriculum_publication:v1 artifact envelopes. Server-side staging only; not learner-visible.';

CREATE INDEX IF NOT EXISTS qd_curriculum_artifact_versions_source_lookup_idx
  ON public.qd_curriculum_artifact_versions (artifact_type, stable_source_id, source_version_major DESC, source_version_minor DESC);
CREATE INDEX IF NOT EXISTS qd_curriculum_artifact_versions_release_idx
  ON public.qd_curriculum_artifact_versions (release_id);

CREATE TABLE IF NOT EXISTS public.qd_curriculum_releases (
  release_id uuid PRIMARY KEY,
  contract_schema_version integer NOT NULL CHECK (contract_schema_version = 1),
  release_code text NOT NULL CHECK (length(release_code) > 0),
  release_sequence bigint NOT NULL CHECK (release_sequence > 0),
  manifest_hash text NOT NULL CHECK (manifest_hash ~ '^sha256:[0-9a-f]{64}$'),
  published_at timestamptz NOT NULL,
  manifest jsonb NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT qd_curriculum_releases_code_uq UNIQUE (release_code),
  CONSTRAINT qd_curriculum_releases_sequence_uq UNIQUE (release_sequence)
);

COMMENT ON TABLE public.qd_curriculum_releases IS
  'Append-only validated quartel_curriculum_publication:v1 release manifests. No activation semantics in Gate 5A.';

CREATE TABLE IF NOT EXISTS public.qd_curriculum_release_artifacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  release_id uuid NOT NULL,
  artifact_type text NOT NULL CHECK (artifact_type IN ('module', 'lesson', 'quiz', 'review', 'asset')),
  stable_source_id uuid NOT NULL,
  source_version_major integer NOT NULL CHECK (source_version_major >= 0),
  source_version_minor integer NOT NULL CHECK (source_version_minor >= 0),
  artifact_version_id uuid NOT NULL,
  content_hash text NOT NULL CHECK (content_hash ~ '^sha256:[0-9a-f]{64}$'),
  staged_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT qd_curriculum_release_artifacts_exact_uq UNIQUE (release_id, artifact_version_id),
  CONSTRAINT qd_curriculum_release_artifacts_logical_uq
    UNIQUE (release_id, artifact_type, stable_source_id, source_version_major, source_version_minor)
);

COMMENT ON TABLE public.qd_curriculum_release_artifacts IS
  'Append-only release membership staging. Deliberately no FK to legacy learner/runtime tables and no activation behavior.';

CREATE INDEX IF NOT EXISTS qd_curriculum_release_artifacts_source_idx
  ON public.qd_curriculum_release_artifacts (artifact_type, stable_source_id, source_version_major, source_version_minor);

ALTER TABLE public.qd_curriculum_source_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_curriculum_artifact_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_curriculum_releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_curriculum_release_artifacts ENABLE ROW LEVEL SECURITY;

-- No anon/authenticated policies are created. The learner client cannot read staging
-- or answer-key-bearing payloads. Service role is the only granted runtime role.
REVOKE ALL ON TABLE public.qd_curriculum_source_mappings FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.qd_curriculum_artifact_versions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.qd_curriculum_releases FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.qd_curriculum_release_artifacts FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT ON TABLE public.qd_curriculum_source_mappings TO service_role;
GRANT SELECT, INSERT ON TABLE public.qd_curriculum_artifact_versions TO service_role;
GRANT SELECT, INSERT ON TABLE public.qd_curriculum_releases TO service_role;
GRANT SELECT, INSERT ON TABLE public.qd_curriculum_release_artifacts TO service_role;

CREATE TRIGGER qd_curriculum_source_mappings_append_only
BEFORE UPDATE OR DELETE ON public.qd_curriculum_source_mappings
FOR EACH ROW EXECUTE FUNCTION public.qd_curriculum_reject_mutation();

CREATE TRIGGER qd_curriculum_artifact_versions_append_only
BEFORE UPDATE OR DELETE ON public.qd_curriculum_artifact_versions
FOR EACH ROW EXECUTE FUNCTION public.qd_curriculum_reject_mutation();

CREATE TRIGGER qd_curriculum_releases_append_only
BEFORE UPDATE OR DELETE ON public.qd_curriculum_releases
FOR EACH ROW EXECUTE FUNCTION public.qd_curriculum_reject_mutation();

CREATE TRIGGER qd_curriculum_release_artifacts_append_only
BEFORE UPDATE OR DELETE ON public.qd_curriculum_release_artifacts
FOR EACH ROW EXECUTE FUNCTION public.qd_curriculum_reject_mutation();

COMMIT;
