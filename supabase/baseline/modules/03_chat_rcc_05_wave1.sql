-- =============================================================================
-- MÓDULO 03: Chat RCC-0.5 Wave 1
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Domínio: chat_conversas, chat_mensagens, locks, reads, audit, views, RPCs
-- Linhas relevantes: 9968-10160 (tabelas), ~12000-12350 (views), ~3000-4500 (RPCs)
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABELAS — Chat (sem DDL local — existem apenas no remoto)
-- RISCO: Sem migration local → impossível recriar schema do zero
-- -----------------------------------------------------------------------------

-- chat_audit_log — Auditoria de interações (serviço C7 interno)
-- Linhas dump: 9968-9987
-- Migration local: 20260120170000
CREATE TABLE IF NOT EXISTS "public"."chat_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "text",
    "timestamp_utc" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    "recruta_id" "uuid",
    "source" "text",
    "response_category" "text",
    "force" "text",
    "access_mode" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."chat_audit_log" OWNER TO "postgres";

-- chat_conversas — Conversas entre recruta e instrutor
-- Linhas dump: 9988-10010
-- NOTA: Sem migration local — DDL deve ser capturado via pg_dump urgente
CREATE TABLE IF NOT EXISTS "public"."chat_conversas" (
    -- DDL completo: ver dump linhas 9988-10010
    -- Colunas prováveis: id, recruta_id, instrutor_slug, thread_id (OpenAI),
    --                    created_at, updated_at, status
    -- UNIQUE: (recruta_id, instrutor_slug) — uma conversa por instrutor
);

-- chat_events — Eventos de ciclo de vida de conversa
-- Linhas dump: 10011-10028
CREATE TABLE IF NOT EXISTS "public"."chat_events" (
    -- DDL completo: ver dump linhas 10011-10028
    -- Colunas: id, conversa_id, tipo, payload, created_at
);

-- chat_logs — Log raw de interações (append-only)
-- Linhas dump: 10029-10058
CREATE TABLE IF NOT EXISTS "public"."chat_logs" (
    -- DDL completo: ver dump linhas 10029-10058
    -- Colunas: id, conversa_id, role (user/assistant), content, tokens_input,
    --          tokens_output, created_at
);

-- chat_mensagens — Mensagens individuais (canonical read source)
-- Linhas dump: 10059-10097
-- NOTA: Sem migration local — RISCO ALTO (histórico irrecuperável sem backup)
CREATE TABLE IF NOT EXISTS "public"."chat_mensagens" (
    -- DDL completo: ver dump linhas 10059-10097
    -- Colunas: id, conversa_id, recruta_id, role (user/assistant/system),
    --          content, created_at, metadata
);

-- chat_reads — Ledger de leituras por mensagem
-- Linhas dump: 10098-10112
CREATE TABLE IF NOT EXISTS "public"."chat_reads" (
    -- DDL completo: ver dump linhas 10098-10112
    -- Colunas: id, mensagem_id, recruta_id, read_at
    -- UNIQUE: (mensagem_id, recruta_id)
);

-- chat_summaries — Sumários gerados por IA por conversa
-- Linhas dump: 10113-10125
CREATE TABLE IF NOT EXISTS "public"."chat_summaries" (
    -- DDL completo: ver dump linhas 10113-10125
    -- Colunas: id, conversa_id, content, tokens_used, created_at, updated_at
);

-- chat_threads — Threads OpenAI por recruta (mapping thread_id → recruta)
-- Linhas dump: 10126-10138
CREATE TABLE IF NOT EXISTS "public"."chat_threads" (
    -- DDL completo: ver dump linhas 10126-10138
    -- Colunas: id, recruta_id, thread_id, instrutor_slug, created_at
    -- UNIQUE: (recruta_id, instrutor_slug)
);

-- conversation_locks — Mutex distribuído para processamento de mensagem
-- Linhas dump: 10139-10159
-- NOTA: fn_acquire_conversation_lock / fn_release_conversation_lock operam aqui
CREATE TABLE IF NOT EXISTS "public"."conversation_locks" (
    -- DDL completo: ver dump linhas 10139-10159
    -- Colunas: id, conversa_id, locked_by, locked_at, expires_at
    -- UNIQUE: (conversa_id) quando ativo
);

-- -----------------------------------------------------------------------------
-- VIEWS CANÔNICAS — Chat (security_invoker=true em todas)
-- Linhas dump: ~12000-12350
-- NOTA: security_invoker=true garante que RLS do usuário é aplicado
-- -----------------------------------------------------------------------------

-- v_chat_conversas_recruta — Lista de conversas do recruta atual
-- security_invoker=true
-- Colunas: conversa_id, instrutor_slug, instrutor_nome, ultima_mensagem,
--          unread_count, updated_at
CREATE OR REPLACE VIEW "public"."v_chat_conversas_recruta" WITH ("security_invoker"='true') AS
    SELECT NULL::uuid AS "conversa_id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_chat_conversas_recruta" IS 'CANONICAL CHAT VIEW. security_invoker=true. Conversas do recruta autenticado.';

-- v_chat_mensagens_recruta — Mensagens de uma conversa (com paginação)
-- security_invoker=true
-- Colunas: mensagem_id, role, content, created_at, is_read
CREATE OR REPLACE VIEW "public"."v_chat_mensagens_recruta" WITH ("security_invoker"='true') AS
    SELECT NULL::uuid AS "mensagem_id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_chat_mensagens_recruta" IS 'CANONICAL CHAT VIEW. security_invoker=true. Mensagens da conversa ativa.';

-- v_chat_unread_status — Contagem de não lidas por conversa
-- security_invoker=true
-- Colunas: conversa_id, unread_count
CREATE OR REPLACE VIEW "public"."v_chat_unread_status" WITH ("security_invoker"='true') AS
    SELECT NULL::uuid AS "conversa_id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_chat_unread_status" IS 'CANONICAL CHAT VIEW. security_invoker=true. Unread counts for recruta.';

-- v_audit_eventos — View writable com INSTEAD OF INSERT trigger
-- NOTA CRÍTICA: NÃO é read-only. Trigger fn_insert_audit_evento_smart faz INSERT em chat_audit_log.
-- NOTA CRÍTICA: fn_insert_audit_evento_smart é INVOKER, não DEFINER — falha silenciosa se
--               usuário authenticated não tem acesso a chat_audit_log.
-- Linhas dump: ~12300-12350
CREATE OR REPLACE VIEW "public"."v_audit_eventos" AS
    SELECT NULL::text AS "source" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_audit_eventos" IS 'WRITABLE VIEW (INSTEAD OF INSERT trigger). fn_insert_audit_evento_smart deve ser SECURITY DEFINER para funcionar. Ver SECURITY_DEFINER_AUDIT.md.';

-- -----------------------------------------------------------------------------
-- RPCs CANÔNICAS — Chat
-- PROTEÇÃO: Todas SECURITY DEFINER, authenticated
-- Sem migration local — RISCO ALTO
-- -----------------------------------------------------------------------------

-- rpc_chat_open_conversation(p_instrutor_slug text) → uuid (conversa_id)
-- GRANT: authenticated
-- Função: abre ou recupera conversa existente com instrutor. Idempotente.

-- rpc_chat_send_message(p_conversa_id uuid, p_content text) → uuid (mensagem_id)
-- GRANT: authenticated
-- Função: envia mensagem e agenda processamento pela IA. NÃO é idempotente.

-- rpc_chat_mark_read(p_conversa_id uuid) → void
-- GRANT: authenticated
-- Função: marca todas as mensagens da conversa como lidas. Idempotente via upsert.

-- rpc_chat_summary_upsert(p_conversa_id uuid, p_content text, p_tokens_used int)
-- GRANT: authenticated, service_role
-- Função: salva ou atualiza sumário de conversa gerado pela IA.

-- -----------------------------------------------------------------------------
-- FUNÇÕES INTERNAS — Chat
-- Sem migration local
-- -----------------------------------------------------------------------------

-- fn_acquire_conversation_lock(p_conversa_id uuid) → boolean
-- SECURITY DEFINER, search_path=—(não confirmado)
-- GRANT: authenticated, service_role
-- Função: adquire lock distribuído para processamento atômico de mensagem

-- fn_release_conversation_lock(p_conversa_id uuid) → void
-- SECURITY DEFINER
-- GRANT: authenticated, service_role
-- Função: libera lock após processamento

-- fn_insert_audit_evento_smart() → TRIGGER
-- SECURITY INVOKER (BUG — deve ser DEFINER)
-- Trigger em v_audit_eventos INSTEAD OF INSERT
-- RISCO: falha silenciosa pois authenticated não acessa chat_audit_log
-- Correção planejada: Migration 03 (20260516003000)

-- -----------------------------------------------------------------------------
-- RLS POLICIES — Chat
-- NOTA: chat_conversas, chat_mensagens, chat_reads com security_invoker nas views
-- -----------------------------------------------------------------------------

ALTER TABLE "public"."chat_audit_log" ENABLE ROW LEVEL SECURITY;
-- Policy: service_role apenas para INSERT/SELECT
-- Policy: authenticated — sem acesso direto (acesso via v_audit_eventos)

ALTER TABLE "public"."chat_conversas" ENABLE ROW LEVEL SECURITY;
-- Policy: SELECT — recruta vê apenas suas conversas (WHERE recruta_id = auth.uid())
-- Policy: INSERT/UPDATE — apenas via RPC (DEFINER bypassa RLS)

ALTER TABLE "public"."chat_mensagens" ENABLE ROW LEVEL SECURITY;
-- Policy: SELECT — recruta vê apenas suas mensagens
-- Policy: INSERT — apenas via RPC

ALTER TABLE "public"."conversation_locks" ENABLE ROW LEVEL SECURITY;
-- Policy: service_role e authenticated via fn_acquire/fn_release (DEFINER)

-- =============================================================================
-- NOTAS CRÍTICAS
-- =============================================================================
-- 1. chat_conversas, chat_mensagens, chat_reads NÃO têm migration local
--    → Impossível recriar do zero. Capture urgente via pg_dump.
-- 2. fn_insert_audit_evento_smart é INVOKER — auditoria de chat INOPERANTE
--    → Correção: Migration 03 (SECURITY DEFINER)
-- 3. conversation_locks são criados com TTL — verificar limpeza automática
-- 4. chat_threads usa thread_id do OpenAI Assistants API
-- 5. v_chat_mensagens_recruta provavelmente requer parâmetro de conversa_id
--    (pode ser filtrada por sessão via auth.uid() + conversa ativa)
-- =============================================================================
