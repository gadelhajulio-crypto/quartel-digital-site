-- =============================================================================
-- MÓDULO 02: Auth, Identidade e Onboarding
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Domínio: Sessões de dispositivo, identidade do recruta, onboarding, config
-- Linhas relevantes: 9101-9195 (tabelas), 11553-11637 (views), 5983-6100 (RPCs)
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABELAS — Auth Client Sessions
-- Migration local: 20260503003000
-- -----------------------------------------------------------------------------

-- auth_client_revocations — Revogações de sessão por dispositivo
-- Linhas dump: 9101-9133
CREATE TABLE IF NOT EXISTS "public"."auth_client_revocations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_instance_id" "text" NOT NULL,
    "revoked_by" "uuid",
    "reason" "text",
    "revoked_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

-- auth_client_singleton — Estado singleton do cliente (heartbeat)
-- Linhas dump: 9134-9147
CREATE TABLE IF NOT EXISTS "public"."auth_client_singleton" (
    "client_instance_id" "text" NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "recruta_id" "uuid",
    "metadata" "jsonb" DEFAULT '{}'
);

-- auth_session_revocations — Revogações de sessão (nível de sessão Supabase)
-- Linhas dump: 9148-9180
CREATE TABLE IF NOT EXISTS "public"."auth_session_revocations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "uuid" NOT NULL,
    "revoked_by" "uuid",
    "reason" "text",
    "revoked_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

-- auth_session_singleton — Estado singleton da sessão
-- Linhas dump: 9181-9194
CREATE TABLE IF NOT EXISTS "public"."auth_session_singleton" (
    "session_id" "uuid" NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'
);

-- auth_client_sessions — Sessões por dispositivo (auth_client_instance_id)
-- Migration local: 20260503003000
-- Linhas dump: ~9101+ (ver migration)
CREATE TABLE IF NOT EXISTS "public"."auth_client_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "client_instance_id" "text" NOT NULL,
    "session_state" "text" DEFAULT 'active'::text NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_at" timestamp with time zone,
    "metadata" "jsonb" DEFAULT '{}'
);

-- auth_app_config — Key-value config institucional
-- Migration local: 20260503003000 (seed: auth_contract_version=RCC-0.3)
CREATE TABLE IF NOT EXISTS "public"."auth_app_config" (
    "key" "text" NOT NULL,
    "value" "text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

-- automacoes_execucoes — Histórico de automações (billing/webhooks)
-- Linhas dump: 9195-9213
CREATE TABLE IF NOT EXISTS "public"."automacoes_execucoes" (
    -- DDL completo: ver dump linhas 9195-9213
    -- Colunas: id, automacao_id, status, payload, executado_em
);

-- -----------------------------------------------------------------------------
-- VIEWS CANÔNICAS — Auth/Identidade
-- NOTA: Todas usam auth.uid() internamente para segurança
-- -----------------------------------------------------------------------------

-- v_auth_app_config — Configuração institucional (auth_contract_version)
-- Linhas dump: ~11553
CREATE OR REPLACE VIEW "public"."v_auth_app_config" AS
    SELECT "key", "value"
    FROM "public"."auth_app_config";
COMMENT ON VIEW "public"."v_auth_app_config" IS 'CANONICAL READ VIEW. Auth config key-value. Frontend: auth_contract_version=RCC-0.3.';

-- v_auth_session — Estado da sessão ativa por auth.uid()
-- Linhas dump: ~11560
CREATE OR REPLACE VIEW "public"."v_auth_session" AS
    SELECT NULL::uuid AS "recruta_id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_auth_session" IS 'CANONICAL READ VIEW. Session state for current auth.uid().';

-- v_auth_active_sessions — Sessões ativas por dispositivo
-- Linhas dump: ~11570
CREATE OR REPLACE VIEW "public"."v_auth_active_sessions" AS
    SELECT NULL::uuid AS "id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_auth_active_sessions" IS 'CANONICAL READ VIEW. Active sessions per device.';

-- v_identidade_recruta — CONTRATO PRIMÁRIO DE IDENTIDADE (login)
-- Linhas dump: ~11580-11636
-- Colunas: id, auth_id, nome, nome_guerra, patente, forca, nivel_atual, xp,
--          avatar_url, instructor_profile_id, tipo_acesso, onboarding_concluido, ativo
-- JOIN: recrutas LEFT JOIN profiles ON profiles.id = recrutas.id
-- NOTA: instructor_profile_id vem de profiles (pode ser null se LEFT JOIN não encontrar)
CREATE OR REPLACE VIEW "public"."v_identidade_recruta" AS
    SELECT NULL::uuid AS "id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_identidade_recruta" IS 'CANONICAL PRIMARY IDENTITY CONTRACT. AuthContext source of truth. DDL em dump linha ~11580.';

-- v_onboarding_status — Status do onboarding por auth.uid()
-- Linhas dump: ~11637 (Migration: 20260503014000)
-- Colunas: recruta_id, onboarding_concluido, forca_definida, nome_guerra_definido
CREATE OR REPLACE VIEW "public"."v_onboarding_status" AS
    SELECT NULL::uuid AS "recruta_id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_onboarding_status" IS 'CANONICAL READ VIEW. Onboarding completion state. Filtered by auth.uid().';

-- v_app_bootstrap_institucional_rcc — Bootstrap cold-start do app
-- security_invoker=true
-- Linhas dump: ~ver SECURITY_DEFINER_AUDIT.md
-- NOTA: bootstrapService.ts usa este nome exato — ausência causa falha no cold start
CREATE OR REPLACE VIEW "public"."v_app_bootstrap_institucional_rcc" WITH ("security_invoker"='true') AS
    SELECT NULL::text AS "auth_contract_version" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_app_bootstrap_institucional_rcc" IS 'CANONICAL BOOTSTRAP VIEW. security_invoker=true. bootstrapService.ts depende deste nome exato.';

-- v_identidade_recruta_legacy_20260503 — Legacy (manter para compatibilidade)
-- Linhas dump: presente no remoto, sem migration local
CREATE OR REPLACE VIEW "public"."v_identidade_recruta_legacy_20260503" AS
    SELECT NULL::uuid AS "id" WHERE false; -- placeholder

-- -----------------------------------------------------------------------------
-- RPCs — Auth/Onboarding
-- PROTEÇÃO: Todas são SECURITY DEFINER
-- -----------------------------------------------------------------------------

-- rpc_complete_onboarding(p_forca text, p_nome_guerra text) — v2 canônica
-- Linhas dump: 6053 (com parâmetros), também existe sobrecargas sem parâmetros (5983)
-- GRANT: authenticated
-- NOTA: Duas sobrecargas existem no remoto — risco de ambiguidade de chamada

-- rpc_auth_claim_active_client_session(p_client_instance_id text)
-- GRANT: authenticated
-- Função: heartbeat de sessão por dispositivo

-- rpc_auth_resolve_session_state(p_client_instance_id text)
-- GRANT: authenticated
-- Função: retorna estado institucional completo do recruta

-- rpc_auth_revoke_client_session(p_session_id uuid)
-- GRANT: authenticated
-- Função: revoga sessão específica

-- rpc_set_recruta_forca(p_forca text) — sem migration local
-- GRANT: authenticated
-- Função: define força do recruta (alternativa a rpc_complete_onboarding)

-- rpc_mark_onboarding_complete() — sem migration local
-- GRANT: authenticated
-- Função: marca onboarding como concluído

-- rpc_select_force(p_forca text) — sem migration local
-- GRANT: authenticated
-- Função: seleção de força no onboarding

-- -----------------------------------------------------------------------------
-- TRIGGERS — Auth
-- -----------------------------------------------------------------------------

-- _auth_enforce_single_session() — SECURITY DEFINER, search_path=public,auth
-- Trigger em auth.sessions para forçar sessão única por dispositivo

-- -----------------------------------------------------------------------------
-- RLS POLICIES — Auth
-- Linhas dump: ~17527-17600
-- -----------------------------------------------------------------------------

ALTER TABLE "public"."auth_client_sessions" ENABLE ROW LEVEL SECURITY;
-- Policies: service_role acesso total, authenticated vê apenas próprias sessões

ALTER TABLE "public"."auth_app_config" ENABLE ROW LEVEL SECURITY;
-- Policy: SELECT para authenticated (config é pública leitura)
-- Policy: INSERT/UPDATE apenas service_role

-- =============================================================================
-- NOTAS
-- =============================================================================
-- 1. v_identidade_recruta usa LEFT JOIN profiles — instructor_profile_id pode ser null
-- 2. rpc_complete_onboarding tem DUAS sobrecargas no remoto — verificar chamadas
-- 3. v_app_bootstrap_institucional_rcc é crítica para cold start do app
-- 4. auth_contract_version=RCC-0.3 é o valor atual no seed
-- =============================================================================
