-- ==============================================================================
-- Wave 5a-2 — Infraestrutura de Push Tokens Institucionais
-- ==============================================================================
-- Tabela:  recruta_push_tokens
-- RPC:     rpc_register_push_token(p_token TEXT, p_platform TEXT)
--
-- Contrato de identidade: recruta resolvido via WHERE auth_id = auth.uid()
-- (nunca WHERE id = auth.uid() — id é UUID próprio, auth_id é o vínculo com auth)
--
-- Invariantes:
--   - frontend NUNCA escreve diretamente na tabela
--   - registro via RPC SECURITY DEFINER (upsert idempotente)
--   - platform restrita a: ios | android
--   - token vazio rejeitado na RPC (não apenas no CHECK)
--   - is_active=true no upsert — reativa token previamente desativado
--   - service_role lê a tabela (necessário para Edge Function chat-notify, Wave 5a-3)
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. DROP PREVENTIVO
-- ─────────────────────────────────────────────────────────────────────────────

DROP TRIGGER   IF EXISTS trg_push_tokens_updated_at ON public.recruta_push_tokens;
DROP FUNCTION  IF EXISTS public.fn_push_tokens_updated_at() CASCADE;
DROP FUNCTION  IF EXISTS public.rpc_register_push_token(TEXT, TEXT) CASCADE;
DROP TABLE     IF EXISTS public.recruta_push_tokens CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TABELA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE public.recruta_push_tokens (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  recruta_id  UUID        NOT NULL REFERENCES public.recrutas(id) ON DELETE CASCADE,
  token       TEXT        NOT NULL,
  platform    TEXT        NOT NULL CHECK (platform IN ('ios', 'android')),
  is_active   BOOLEAN     NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_push_tokens_recruta_token UNIQUE (recruta_id, token)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. ÍNDICES
-- ─────────────────────────────────────────────────────────────────────────────

-- Busca de todos os tokens do recruta (ex: limpeza de tokens antigos)
CREATE INDEX idx_push_tokens_recruta
  ON public.recruta_push_tokens(recruta_id);

-- Busca de tokens ativos por recruta (caminho quente: Edge Function chat-notify)
CREATE INDEX idx_push_tokens_recruta_active
  ON public.recruta_push_tokens(recruta_id)
  WHERE is_active = true;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. TRIGGER: updated_at automático
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_push_tokens_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER trg_push_tokens_updated_at
  BEFORE UPDATE ON public.recruta_push_tokens
  FOR EACH ROW EXECUTE FUNCTION public.fn_push_tokens_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RLS
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.recruta_push_tokens ENABLE ROW LEVEL SECURITY;

-- Recruta lê apenas os próprios tokens (para debug/validação futura)
-- Escrita: bloqueada por ausência de policy INSERT/UPDATE/DELETE para authenticated.
-- Toda escrita é feita via rpc_register_push_token (SECURITY DEFINER).
DROP POLICY IF EXISTS "recruta_select_own_push_tokens" ON public.recruta_push_tokens;
CREATE POLICY "recruta_select_own_push_tokens" ON public.recruta_push_tokens
  FOR SELECT TO authenticated
  USING (
    recruta_id = (SELECT id FROM public.recrutas WHERE auth_id = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RPC: rpc_register_push_token
-- ─────────────────────────────────────────────────────────────────────────────
-- Registra ou reativa um push token para o recruta autenticado.
-- Idempotente via ON CONFLICT (recruta_id, token).
-- Validação de platform na RPC (além do CHECK da tabela) para retornar
-- mensagem de erro clara ao frontend.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.rpc_register_push_token(
  p_token    TEXT,
  p_platform TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recruta_id UUID;
BEGIN
  -- Resolver recruta canonicamente (nunca auth.uid() direto como recruta_id)
  SELECT id INTO v_recruta_id
  FROM public.recrutas
  WHERE auth_id = auth.uid();

  -- Sem recruta → não é um recruta autenticado; retorna silenciosamente
  IF v_recruta_id IS NULL THEN RETURN; END IF;

  -- Validar token
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RAISE EXCEPTION 'rpc_register_push_token: token não pode ser vazio'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Validar platform (além do CHECK da tabela — erro mais legível no frontend)
  IF p_platform NOT IN ('ios', 'android') THEN
    RAISE EXCEPTION 'rpc_register_push_token: platform inválido "%". Valores aceitos: ios, android', p_platform
      USING ERRCODE = 'check_violation';
  END IF;

  -- Upsert idempotente: registra novo token ou reativa existente
  INSERT INTO public.recruta_push_tokens (recruta_id, token, platform, is_active)
  VALUES (v_recruta_id, p_token, p_platform, true)
  ON CONFLICT (recruta_id, token) DO UPDATE SET
    platform   = EXCLUDED.platform,
    is_active  = true,
    updated_at = NOW();
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. GRANTS
-- ─────────────────────────────────────────────────────────────────────────────

-- authenticated: executar a RPC (único caminho de escrita)
GRANT EXECUTE ON FUNCTION public.rpc_register_push_token(TEXT, TEXT) TO authenticated;

-- service_role: leitura direta da tabela (Edge Function chat-notify, Wave 5a-3)
GRANT SELECT ON public.recruta_push_tokens TO service_role;
