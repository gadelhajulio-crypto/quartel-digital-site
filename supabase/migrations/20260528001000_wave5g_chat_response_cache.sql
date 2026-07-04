-- Wave 5g — Cache institucional de respostas do chat
-- Armazena respostas do instrutor para perguntas elegíveis.
-- Elegibilidade: question_norm < 300 chars, output_tokens < 200, sem pronomes pessoais.
-- cache_key = instrutor_slug:forca:access_mode:scope_type:model:prompt_version:question_hash
-- TTL: 30 dias. Hit/miss/write via telemetria [INSTRUTOR_SEND_CACHE] nos logs do Edge.
--
-- INVARIANTES:
--   - Nunca armazenar PII — question_norm é normalizada (lower + trim + sem pontuação)
--   - question_hash = SHA-256 da question_norm (64 chars hex)
--   - hit_count incrementado em background — sem contention na leitura
--   - answer_text: TEXT ilimitado (nunca truncar resposta cacheada)
--   - Invalidado automaticamente por expires_at (TTL 30 dias)
--
-- IDEMPOTÊNCIA: CREATE IF NOT EXISTS em todos os objetos

CREATE TABLE IF NOT EXISTS public.chat_response_cache (
  cache_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cache_key      TEXT        NOT NULL,
  question_hash  TEXT        NOT NULL,
  question_norm  TEXT        NOT NULL,
  answer_text    TEXT        NOT NULL,
  instrutor_slug TEXT        NOT NULL,
  forca          TEXT        NOT NULL,
  access_mode    TEXT        NOT NULL,
  scope_type     TEXT        NOT NULL,    -- 'full' | 'degustacao'
  model          TEXT        NOT NULL,    -- 'gpt-4o' etc
  prompt_version TEXT        NOT NULL DEFAULT 'v1',
  input_tokens   INTEGER,
  output_tokens  INTEGER,
  hit_count      INTEGER     NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_hit_at    TIMESTAMPTZ,
  expires_at     TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '30 days'
);

COMMENT ON TABLE public.chat_response_cache IS
  'Wave 5g — Cache institucional de respostas do chat. '
  'Perguntas elegíveis (<300 chars, <200 tokens, sem pronomes pessoais) são cacheadas por 30 dias. '
  'cache_key: instrutor_slug:forca:access_mode:scope_type:model:prompt_version:question_hash.';

COMMENT ON COLUMN public.chat_response_cache.question_norm IS
  'Pergunta normalizada: lowercase + trim + collapse whitespace + sem pontuação. '
  'Base para o hash e para exibição em auditoria (sem PII).';

COMMENT ON COLUMN public.chat_response_cache.scope_type IS
  'Escopo de acesso: ''full'' (plano completo) ou ''degustacao'' (restrito). '
  'Determina qual material foi usado na resposta — chave de invalidação por plano.';

-- ── Índices ───────────────────────────────────────────────────────────────────

CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_response_cache_key
  ON public.chat_response_cache (cache_key);

CREATE INDEX IF NOT EXISTS idx_chat_response_cache_expires
  ON public.chat_response_cache (expires_at);

CREATE INDEX IF NOT EXISTS idx_chat_response_cache_hash
  ON public.chat_response_cache (question_hash, instrutor_slug);

CREATE INDEX IF NOT EXISTS idx_chat_response_cache_slug_forca
  ON public.chat_response_cache (instrutor_slug, forca, access_mode);

-- ── RLS: somente service_role acessa (Edge Functions rodam como service_role) ─

ALTER TABLE public.chat_response_cache ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename  = 'chat_response_cache'
       AND policyname = 'service_role_full_access'
  ) THEN
    EXECUTE $p$
      CREATE POLICY service_role_full_access
        ON public.chat_response_cache
        FOR ALL
        TO service_role
        USING (true)
        WITH CHECK (true)
    $p$;
  END IF;
END $$;

-- Grant explícito para garantir acesso mesmo com RLS habilitado
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_response_cache TO service_role;
