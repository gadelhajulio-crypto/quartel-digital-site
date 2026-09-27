-- Gate 5C — transport anti-replay foundation for the QD curriculum shadow receiver.
--
-- Repository-only migration. Do not apply remotely in Gate 5C.
-- This table contains transport metadata only: no learner/person/commercial data.
-- It intentionally depends on qd_curriculum_reject_mutation() from Gate 5A.

BEGIN;

CREATE TABLE IF NOT EXISTS public.qd_curriculum_transport_nonces (
  key_id text NOT NULL
    CHECK (key_id ~ '^[A-Za-z0-9._-]{1,64}$'),
  nonce uuid NOT NULL,
  request_id uuid NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (key_id, nonce),
  CONSTRAINT qd_curriculum_transport_nonces_request_uq UNIQUE (request_id),
  CONSTRAINT qd_curriculum_transport_nonces_expiry_ck
    CHECK (expires_at > accepted_at)
);

COMMENT ON TABLE public.qd_curriculum_transport_nonces IS
  'Gate 5C transport anti-replay ledger for authenticated QD curriculum receiver requests. No learner/person data.';

ALTER TABLE public.qd_curriculum_transport_nonces ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.qd_curriculum_transport_nonces
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.qd_curriculum_transport_nonces
  TO service_role;

CREATE TRIGGER qd_curriculum_transport_nonces_append_only
BEFORE UPDATE OR DELETE ON public.qd_curriculum_transport_nonces
FOR EACH ROW EXECUTE FUNCTION public.qd_curriculum_reject_mutation();

CREATE OR REPLACE FUNCTION public.qd_curriculum_reserve_transport_nonce(
  p_key_id text,
  p_nonce uuid,
  p_request_id uuid,
  p_retention_seconds integer DEFAULT 600
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_rows integer;
BEGIN
  IF p_key_id IS NULL OR p_key_id !~ '^[A-Za-z0-9._-]{1,64}$' THEN
    RAISE EXCEPTION 'invalid key id'
      USING ERRCODE = '22023';
  END IF;

  IF p_retention_seconds IS NULL
     OR p_retention_seconds < 600
     OR p_retention_seconds > 86400 THEN
    RAISE EXCEPTION 'retention must be between 600 and 86400 seconds'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.qd_curriculum_transport_nonces (
    key_id,
    nonce,
    request_id,
    expires_at
  )
  VALUES (
    p_key_id,
    p_nonce,
    p_request_id,
    now() + make_interval(secs => p_retention_seconds)
  )
  ON CONFLICT (key_id, nonce) DO NOTHING;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows = 1;
END;
$$;

REVOKE ALL ON FUNCTION public.qd_curriculum_reserve_transport_nonce(
  text, uuid, uuid, integer
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.qd_curriculum_reserve_transport_nonce(
  text, uuid, uuid, integer
) FROM anon;
REVOKE ALL ON FUNCTION public.qd_curriculum_reserve_transport_nonce(
  text, uuid, uuid, integer
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.qd_curriculum_reserve_transport_nonce(
  text, uuid, uuid, integer
) TO service_role;

COMMENT ON FUNCTION public.qd_curriculum_reserve_transport_nonce(
  text, uuid, uuid, integer
) IS
  'Atomically reserves an authenticated transport nonce. Returns false on replay. Gate 5C shadow receiver only.';

COMMIT;
