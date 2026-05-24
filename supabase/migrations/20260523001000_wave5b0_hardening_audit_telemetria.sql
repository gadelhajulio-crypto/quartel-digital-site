-- Wave 5b-0 — Hardening da telemetria de auditoria do chat institucional
--
-- CAUSA RAIZ (3 bugs em cadeia):
--   Bug 1: fn_insert_audit_evento_smart fazia lookup em profiles.id
--           mas recruta_id canônico é recrutas.id — identidades diferentes.
--           profiles.id = auth.uid(); recrutas.id = UUID próprio.
--           Resultado: v_forca sempre NULL → force = 'unknown'.
--
--   Bug 2: access_mode traduzido como 'full'/'free' mas o sistema
--           usa 'full_access'/'restricted' (contrato de instrutor-send).
--
--   Bug 3: chat-central não insere em v_audit_eventos. O trigger nunca
--           é invocado. Corrigido estruturalmente aqui; inserção será
--           habilitada em Wave 5b-1 via instrutor-send.
--
-- INVARIANTES:
--   - Nenhuma coluna existente é removida ou alterada destrutivamente
--   - Nenhum dado histórico é perdido
--   - force/access_mode passam a ser nullable para evitar 'unknown' forçado
--   - instrutor_slug adicionado (nullable) para suportar Wave 5b-1
--   - Trigger ativo após esta migration usa recrutas como fonte canônica
--
-- IDEMPOTÊNCIA (patch para banco divergente):
--   - force/access_mode: ADD COLUMN se ausentes; DROP NOT NULL se presentes
--     como NOT NULL — handle qualquer estado remoto via DO $$ block
--   - instrutor_slug/latency_ms: verificação de existência no DO $$ block
--   - Índices: CREATE INDEX IF NOT EXISTS
--   - Trigger e função: DROP IF EXISTS / CREATE OR REPLACE
--
-- IMPACTO EM PRODUÇÃO: nenhum — fluxo atual não insere em v_audit_eventos.
--   A correção prepara o pipeline sem alterar qualquer comportamento ativo.

-- ── 1. Preparar colunas de chat_audit_log (idempotente) ───────────────────────
--
-- Estratégia por coluna:
--   force       — se NÃO existir: ADD COLUMN TEXT (nullable)
--               — se existir e NOT NULL: DROP NOT NULL
--               — se existir e nullable: no-op
--   access_mode — mesma lógica
--   instrutor_slug — adicionar se não existir
--   latency_ms     — adicionar se não existir

DO $$
BEGIN

  -- ── force ──────────────────────────────────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'chat_audit_log'
       AND column_name  = 'force'
  ) THEN
    -- Coluna ausente no banco remoto: adicionar como nullable
    ALTER TABLE public.chat_audit_log ADD COLUMN force TEXT;

  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'chat_audit_log'
       AND column_name  = 'force'
       AND is_nullable  = 'NO'
  ) THEN
    -- Coluna existe mas é NOT NULL: relaxar
    ALTER TABLE public.chat_audit_log ALTER COLUMN force DROP NOT NULL;
  END IF;
  -- else: coluna existe e já é nullable — no-op

  -- ── access_mode ────────────────────────────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'chat_audit_log'
       AND column_name  = 'access_mode'
  ) THEN
    ALTER TABLE public.chat_audit_log ADD COLUMN access_mode TEXT;

  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'chat_audit_log'
       AND column_name  = 'access_mode'
       AND is_nullable  = 'NO'
  ) THEN
    ALTER TABLE public.chat_audit_log ALTER COLUMN access_mode DROP NOT NULL;
  END IF;

  -- ── instrutor_slug (nova — Wave 5b-1) ──────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'chat_audit_log'
       AND column_name  = 'instrutor_slug'
  ) THEN
    ALTER TABLE public.chat_audit_log ADD COLUMN instrutor_slug TEXT;
  END IF;

  -- ── latency_ms (nova — Wave 5b-1) ──────────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'chat_audit_log'
       AND column_name  = 'latency_ms'
  ) THEN
    ALTER TABLE public.chat_audit_log ADD COLUMN latency_ms INTEGER;
  END IF;

END $$;

-- ── Comments (após DO block garantir que colunas existem) ─────────────────────

COMMENT ON COLUMN public.chat_audit_log.force IS
  'Força institucional do recruta (marinha/exercito/aeronautica). '
  'Nullable após Wave 5b-0: preferir COALESCE defensivo ao invés de NOT NULL com unknown.';

COMMENT ON COLUMN public.chat_audit_log.access_mode IS
  'Modo de acesso canônico: full_access | restricted. '
  'Alinhado com contrato de instrutor-send (antes: full/free — divergente).';

COMMENT ON COLUMN public.chat_audit_log.instrutor_slug IS
  'Slug canônico do instrutor: objetivo | estrategico | didatico. '
  'Populado em Wave 5b-1 quando instrutor-send passar a inserir auditoria.';

COMMENT ON COLUMN public.chat_audit_log.latency_ms IS
  'Latência total do request instrutor-send em milissegundos. '
  'Populado em Wave 5b-1.';

CREATE INDEX IF NOT EXISTS idx_chat_audit_instrutor_slug
  ON public.chat_audit_log (instrutor_slug, timestamp_utc DESC)
  WHERE instrutor_slug IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chat_audit_force
  ON public.chat_audit_log (force, timestamp_utc DESC)
  WHERE force IS NOT NULL;

-- ── 2. Recriar v_audit_eventos expondo instrutor_slug ─────────────────────────
-- Additive: adicionar instrutor_slug e latency_ms na view de escrita.
-- chat-central pode passar esses campos quando implementar inserção.

CREATE OR REPLACE VIEW public.v_audit_eventos AS
SELECT
  audit_id,
  session_id,
  timestamp_utc,
  recruta_id,
  source,
  response_category AS categoria,
  -- Campos adicionados Wave 5b-0 (nullable — sem breaking change para inserções antigas)
  instrutor_slug,
  latency_ms
FROM public.chat_audit_log;

COMMENT ON VIEW public.v_audit_eventos IS
  'View de escrita para auditoria de chat. '
  'INSTEAD OF INSERT trigger resolve identidade canônica via recrutas (não profiles). '
  'Wave 5b-0: instrutor_slug e latency_ms expostos para inserção futura.';

-- ── 3. Corrigir fn_insert_audit_evento_smart — lookup canônico via recrutas ───
--
-- ANTES (bug):
--   SELECT forca, tipo_acesso FROM public.profiles WHERE id = NEW.recruta_id
--   profiles.id = auth.uid() ≠ recrutas.id (UUID canônico)
--   → sempre retornava NULL → force = 'unknown'
--
-- DEPOIS (correto):
--   SELECT forca, tipo_acesso FROM public.recrutas WHERE id = NEW.recruta_id
--   recrutas.id = UUID canônico — mesmo UUID passado por instrutor-send
--   → retorna dados reais
--
-- access_mode: alinhado com contrato canônico full_access/restricted.

CREATE OR REPLACE FUNCTION public.fn_insert_audit_evento_smart()
RETURNS TRIGGER AS $$
DECLARE
  v_forca       TEXT;
  v_tipo_acesso TEXT;
  v_access_mode TEXT;
BEGIN

  -- ── Diagnóstico: início do lookup ────────────────────────────────────────
  RAISE LOG '[AUDIT_C5] audit_lookup_started recruta_id=% source=%',
    NEW.recruta_id, COALESCE(NEW.source, 'unknown');

  -- ── Lookup canônico: recrutas.id (não profiles.id = auth.uid()) ──────────
  -- instrutor-send resolve recruta_id via v_identidade_recruta → recrutas.id.
  -- profiles.id = auth.uid() — identidade diferente, nunca usar aqui.
  SELECT forca, tipo_acesso
    INTO v_forca, v_tipo_acesso
    FROM public.recrutas
   WHERE id = NEW.recruta_id;

  -- ── Diagnóstico: resultado do lookup ────────────────────────────────────
  IF v_forca IS NULL THEN
    RAISE LOG '[AUDIT_C5] force_unknown_detected recruta_id=% source=% hint=recruta_nao_encontrada',
      NEW.recruta_id, COALESCE(NEW.source, 'unknown');
  END IF;

  IF v_tipo_acesso IS NULL THEN
    RAISE LOG '[AUDIT_C5] access_mode_unknown_detected recruta_id=% source=%',
      NEW.recruta_id, COALESCE(NEW.source, 'unknown');
  END IF;

  -- ── Tradução canônica de access_mode ────────────────────────────────────
  -- Contrato de instrutor-send: 'full_access' | 'restricted'
  -- Antes deste fix: 'full' | 'free' — divergente do sistema
  v_access_mode := CASE
    WHEN v_tipo_acesso = 'completo' THEN 'full_access'
    WHEN v_tipo_acesso IS NOT NULL  THEN 'restricted'
    ELSE NULL  -- NULL explícito: sem dado é melhor que 'unknown' enganoso
  END;

  -- ── Inserção na tabela canônica ──────────────────────────────────────────
  INSERT INTO public.chat_audit_log (
    session_id,
    timestamp_utc,
    user_id,
    recruta_id,
    source,
    response_category,
    force,
    access_mode,
    instrutor_slug,
    latency_ms
  ) VALUES (
    NEW.session_id,
    COALESCE(NEW.timestamp_utc, now()),
    NEW.recruta_id,   -- user_id = recruta_id (contrato legado: mesmo UUID)
    NEW.recruta_id,
    NEW.source,
    NEW.categoria,
    v_forca,          -- NULL quando recruta não encontrado (não 'unknown')
    v_access_mode,    -- NULL quando recruta não encontrado (não 'unknown')
    NEW.instrutor_slug,
    NEW.latency_ms
  );

  -- ── Diagnóstico: lookup resolvido ────────────────────────────────────────
  RAISE LOG '[AUDIT_C5] audit_lookup_resolved recruta_id=% force=% access_mode=%',
    NEW.recruta_id,
    COALESCE(v_forca, 'NULL'),
    COALESCE(v_access_mode, 'NULL');

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  -- Falha silenciosa: auditoria não deve bloquear o fluxo principal
  RAISE LOG '[AUDIT_C5] audit_lookup_failed recruta_id=% error=%',
    NEW.recruta_id, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

COMMENT ON FUNCTION public.fn_insert_audit_evento_smart() IS
  'Wave 5b-0: lookup corrigido de profiles.id → recrutas.id. '
  'access_mode alinhado: full_access/restricted (antes: full/free). '
  'force/access_mode nullable: NULL explícito ao invés de ''unknown'' enganoso.';

-- ── 4. Recriar trigger (garante que a nova função está ativa) ─────────────────
DROP TRIGGER IF EXISTS trg_insert_audit ON public.v_audit_eventos;

CREATE TRIGGER trg_insert_audit
  INSTEAD OF INSERT ON public.v_audit_eventos
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_insert_audit_evento_smart();

-- ── 5. Remover função legada fn_insert_audit_evento (force hardcoded 'unknown') ─
-- A função original fn_insert_audit_evento hardcodava force='unknown'.
-- Não está em uso (trigger aponta para _smart). Drop seguro.
DROP FUNCTION IF EXISTS public.fn_insert_audit_evento();

-- ── 6. Grant para service_role na view ────────────────────────────────────────
-- instrutor-send rodará como service_role ao inserir em Wave 5b-1.
GRANT INSERT, SELECT ON public.v_audit_eventos TO service_role;
