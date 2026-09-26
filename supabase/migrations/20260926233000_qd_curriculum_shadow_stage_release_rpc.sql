-- Gate 5B — atomic shadow staging for a validated release bundle.
--
-- Repository-only migration in this gate. Do not apply remotely yet.
-- This function does not validate the publication contract itself; validation
-- remains in the server-side consumer core before persistence. Database
-- constraints remain the final fail-closed guard.
--
-- No learner/runtime curriculum table is read or mutated.

BEGIN;

CREATE OR REPLACE FUNCTION public.qd_curriculum_stage_release_bundle(
  p_release jsonb,
  p_artifacts jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_release_id uuid;
BEGIN
  IF p_release IS NULL OR jsonb_typeof(p_release) <> 'object' THEN
    RAISE EXCEPTION 'p_release must be a JSON object'
      USING ERRCODE = '22023';
  END IF;

  IF p_artifacts IS NULL OR jsonb_typeof(p_artifacts) <> 'array' THEN
    RAISE EXCEPTION 'p_artifacts must be a JSON array'
      USING ERRCODE = '22023';
  END IF;

  IF jsonb_array_length(p_artifacts) = 0 THEN
    RAISE EXCEPTION 'p_artifacts must contain at least one artifact'
      USING ERRCODE = '23514';
  END IF;

  v_release_id := (p_release ->> 'release_id')::uuid;

  INSERT INTO public.qd_curriculum_releases (
    release_id,
    contract_schema_version,
    release_code,
    release_sequence,
    manifest_hash,
    published_at,
    manifest
  )
  VALUES (
    v_release_id,
    (p_release ->> 'contract_schema_version')::integer,
    p_release ->> 'release_code',
    (p_release ->> 'release_sequence')::bigint,
    p_release ->> 'manifest_hash',
    (p_release ->> 'published_at')::timestamptz,
    p_release -> 'manifest'
  );

  INSERT INTO public.qd_curriculum_release_artifacts (
    release_id,
    artifact_type,
    stable_source_id,
    source_version_major,
    source_version_minor,
    artifact_version_id,
    content_hash
  )
  SELECT
    v_release_id,
    artifact ->> 'artifact_type',
    (artifact ->> 'stable_source_id')::uuid,
    (artifact ->> 'source_version_major')::integer,
    (artifact ->> 'source_version_minor')::integer,
    (artifact ->> 'artifact_version_id')::uuid,
    artifact ->> 'content_hash'
  FROM jsonb_array_elements(p_artifacts) AS artifact;
END;
$$;

REVOKE ALL ON FUNCTION public.qd_curriculum_stage_release_bundle(jsonb, jsonb)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.qd_curriculum_stage_release_bundle(jsonb, jsonb)
  FROM anon;
REVOKE ALL ON FUNCTION public.qd_curriculum_stage_release_bundle(jsonb, jsonb)
  FROM authenticated;
GRANT EXECUTE ON FUNCTION public.qd_curriculum_stage_release_bundle(jsonb, jsonb)
  TO service_role;

COMMENT ON FUNCTION public.qd_curriculum_stage_release_bundle(jsonb, jsonb) IS
  'Gate 5B shadow-staging primitive. Atomically appends one validated release and its membership rows. No activation or learner-state mutation.';

COMMIT;
