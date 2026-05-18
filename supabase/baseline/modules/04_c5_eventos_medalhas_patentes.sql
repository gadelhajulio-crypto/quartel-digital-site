-- =============================================================================
-- MÓDULO 04: Gamificação C5 — Eventos, Medalhas, Patentes
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Domínio: eventos_institucionais, c5_*, medalhas, patentes, c7_ciclos
-- Linhas relevantes: 9332-9821 (tabelas C5/C7), migrations 20260202*
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABELAS — Eventos Institucionais C5
-- -----------------------------------------------------------------------------

-- eventos_institucionais — Ledger de eventos gamificados (append-only)
-- Linhas dump: 9407-9486
-- RLS: SELECT authenticated (apenas próprios com idempotency_key NOT NULL)
--      INSERT: BLOQUEADO para authenticated — apenas service_role
CREATE TABLE IF NOT EXISTS "public"."eventos_institucionais" (
    -- DDL completo: ver dump linhas 9407-9486
    -- Colunas: id, recruta_id, tipo_evento, payload, idempotency_key,
    --          processado, created_at, metadata
    -- UNIQUE PARCIAL: (recruta_id, idempotency_key) WHERE idempotency_key IS NOT NULL
);

-- c5_alertas_operacionais — Alertas do sistema C5 (ops)
-- Linhas dump: 9332-9388
CREATE TABLE IF NOT EXISTS "public"."c5_alertas_operacionais" (
    -- DDL completo: ver dump linhas 9332-9388
    -- Colunas: id, tipo, severidade, mensagem, resolvido, created_at, resolved_at
);

-- c5_audit_eventos_institucionais — Auditoria de eventos C5 (append-only)
-- Linhas dump: 9389-9406
-- RLS: service_role apenas
CREATE TABLE IF NOT EXISTS "public"."c5_audit_eventos_institucionais" (
    -- DDL completo: ver dump linhas 9389-9406
    -- Colunas: id, evento_id, acao, executado_por, executado_em, detalhes
);

-- c5_fatos_analytics — Fatos desnormalizados para analytics
-- Linhas dump: 9487-9542
CREATE TABLE IF NOT EXISTS "public"."c5_fatos_analytics" (
    -- DDL completo: ver dump linhas 9487-9542
    -- Colunas: id, recruta_id, forca, fato_tipo, valor, referencia_id, created_at
);

-- c5_jobs_execucao_log — Log de execuções de jobs agendados C5
-- Linhas dump: 9543-9597
CREATE TABLE IF NOT EXISTS "public"."c5_jobs_execucao_log" (
    -- DDL completo: ver dump linhas 9543-9597
    -- Colunas: id, job_nome, status, iniciado_em, concluido_em, erro, resultado
);

-- c5_metricas_diarias — Métricas agregadas diárias
-- Linhas dump: 9598-9631
CREATE TABLE IF NOT EXISTS "public"."c5_metricas_diarias" (
    -- DDL completo: ver dump linhas 9598-9631
    -- Colunas: id, data_ref, metrica, valor, forca, created_at
    -- UNIQUE: (data_ref, metrica, forca)
);

-- c5_metricas_recruta — Métricas por recruta
-- Linhas dump: 9632-9670
CREATE TABLE IF NOT EXISTS "public"."c5_metricas_recruta" (
    -- DDL completo: ver dump linhas 9632-9670
    -- Colunas: id, recruta_id, metrica, valor, updated_at
    -- UNIQUE: (recruta_id, metrica)
);

-- c5_regras_alerta — Regras de disparo de alertas
-- Linhas dump: 9671-9720
CREATE TABLE IF NOT EXISTS "public"."c5_regras_alerta" (
    -- DDL completo: ver dump linhas 9671-9720
    -- Colunas: id, metrica, operador, threshold, severidade, ativo, created_at
);

-- c5_taxonomia_eventos — Catálogo de tipos de eventos C5
-- Linhas dump: 9721-9764
CREATE TABLE IF NOT EXISTS "public"."c5_taxonomia_eventos" (
    -- DDL completo: ver dump linhas 9721-9764
    -- Colunas: codigo, descricao, categoria, xp_base, requer_idempotencia, ativo
);

-- c6_contract_registry — Registro de contratos institucionais C6
-- Linhas dump: 9765-9780
CREATE TABLE IF NOT EXISTS "public"."c6_contract_registry" (
    -- DDL completo: ver dump linhas 9765-9780
    -- Colunas: id, contrato_nome, versao, schema_hash, ativo, created_at
);

-- c7_ciclos — Ciclos formativos (períodos de avaliação)
-- Linhas dump: 9781-9796
CREATE TABLE IF NOT EXISTS "public"."c7_ciclos" (
    -- DDL completo: ver dump linhas 9781-9796
    -- Colunas: id, nome, inicio, fim, ativo, created_at
);

-- c7_execucao_diaria_log — Log de execução diária do agendador C7
-- Linhas dump: 9797-9810
CREATE TABLE IF NOT EXISTS "public"."c7_execucao_diaria_log" (
    -- DDL completo: ver dump linhas 9797-9810
    -- Colunas: id, data_execucao, status, detalhes, created_at
);

-- c7_regras_bloqueio_medalhas — Regras de bloqueio de concessão de medalhas
-- Linhas dump: 9811-9820
CREATE TABLE IF NOT EXISTS "public"."c7_regras_bloqueio_medalhas" (
    -- DDL completo: ver dump linhas 9811-9820
    -- Colunas: id, medalha_codigo, condicao_bloqueio, ativo
);

-- c7_regras_bloqueio_por_ciclo — Bloqueios por ciclo formativo
-- Linhas dump: 9821-9838
CREATE TABLE IF NOT EXISTS "public"."c7_regras_bloqueio_por_ciclo" (
    -- DDL completo: ver dump linhas 9821-9838
    -- Colunas: id, ciclo_id, tipo_bloqueio, ativo, created_at
);

-- -----------------------------------------------------------------------------
-- TABELAS — Medalhas (com DDL local — migration 20260202123000)
-- -----------------------------------------------------------------------------

-- medalhas — Catálogo de medalhas
CREATE TABLE IF NOT EXISTS "public"."medalhas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "descricao" "text",
    "nivel" integer DEFAULT 1 NOT NULL,
    "forca" "text",
    "ativo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);

-- medalha_regras — Regras dinâmicas por medalha
CREATE TABLE IF NOT EXISTS "public"."medalha_regras" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "medalha_id" "uuid" NOT NULL,
    "tipo_regra" "text" NOT NULL,
    "valor_threshold" integer,
    "ativo" boolean DEFAULT true
);

-- recruta_medalhas (medalhas_concedidas) — Ledger de concessões
-- NOTA: tabela real pode ser "medalhas_concedidas" (ver RLS_POLICY_AUDIT.md)
-- RLS: todas as operações BLOQUEADAS para authenticated (acesso via views)
CREATE TABLE IF NOT EXISTS "public"."recruta_medalhas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "medalha_id" "uuid" NOT NULL,
    "concedida_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text" DEFAULT 'sistema'::text,
    CONSTRAINT "recruta_medalhas_unique" UNIQUE ("recruta_id", "medalha_id")
);

-- -----------------------------------------------------------------------------
-- TABELAS — Patentes (com DDL local — migration 20260202183000)
-- -----------------------------------------------------------------------------

-- patentes_catalogo — Catálogo de patentes com hierarquia
CREATE TABLE IF NOT EXISTS "public"."patentes_catalogo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "nivel" integer NOT NULL,
    "xp_minimo" integer DEFAULT 0 NOT NULL,
    "forca" "text",
    "ativo" boolean DEFAULT true
);

-- patente_regras — Regras de promoção de patente
CREATE TABLE IF NOT EXISTS "public"."patente_regras" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "patente_id" "uuid" NOT NULL,
    "tipo_regra" "text" NOT NULL,
    "valor_threshold" integer,
    "ativo" boolean DEFAULT true
);

-- recruta_patentes — Histórico de promoções (append-only)
CREATE TABLE IF NOT EXISTS "public"."recruta_patentes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "patente_id" "uuid" NOT NULL,
    "motivo" "text",
    "promovido_em" timestamp with time zone DEFAULT "now"() NOT NULL,
    "promovido_por" "uuid"
);

-- c5_eventos — Eventos C5 emitidos para recruta (frontend polling)
-- Migration local: 20260503008000
-- Vide: v_eventos_pendentes
CREATE TABLE IF NOT EXISTS "public"."c5_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "payload" "jsonb" DEFAULT '{}',
    "processado" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

-- -----------------------------------------------------------------------------
-- VIEWS CANÔNICAS — Gamificação C5
-- Linhas dump: ~12450-12600
-- -----------------------------------------------------------------------------

-- v_medals_status_v3 — CANÔNICA (v1 e v2 legadas)
-- Linhas dump: presentes no remoto, sem migration local
-- Colunas: medal_id, name, description, level, achieved
-- Filtra por auth.uid()
CREATE OR REPLACE VIEW "public"."v_medals_status_v3" AS
    SELECT NULL::uuid AS "medal_id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_medals_status_v3" IS 'CANONICAL MEDALS VIEW. v1 e v2 são legadas. DDL capturado no dump remoto.';

-- v_medals_status_v2 — Legada (frontend migrou para v3)
CREATE OR REPLACE VIEW "public"."v_medals_status_v2" AS
    SELECT NULL::uuid AS "medal_id" WHERE false; -- placeholder

-- v_eventos_pendentes — Eventos C5 não processados do recruta atual
-- Colunas: id, tipo, payload, created_at
-- Filtra por auth.uid() e processado=false
CREATE OR REPLACE VIEW "public"."v_eventos_pendentes" AS
    SELECT NULL::uuid AS "id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_eventos_pendentes" IS 'CANONICAL C5 VIEW. Eventos pendentes do recruta autenticado.';

-- c5_eventos_view — Legacy (security_invoker=true)
CREATE OR REPLACE VIEW "public"."c5_eventos_view" WITH ("security_invoker"='true') AS
    SELECT NULL::uuid AS "id" WHERE false; -- placeholder

-- -----------------------------------------------------------------------------
-- RPCs CANÔNICAS — Gamificação
-- PROTEÇÃO: Todas SECURITY DEFINER
-- -----------------------------------------------------------------------------

-- conceder_medalha_v2(p_recruta_id uuid, p_medalha_codigo text) — service_role
-- GRANT: service_role
-- Idempotente via ON CONFLICT DO NOTHING
-- NOTA: grant_medal pode ser alias ou versão anterior

-- promover_recruta(p_recruta_id uuid, p_patente_codigo text, p_motivo text)
-- GRANT: service_role
-- Idempotente: não promove se já na patente solicitada

-- consumir_evento_c5(p_evento_id uuid) — authenticated
-- GRANT: authenticated
-- Marca evento C5 como processado (idempotente)

-- emitir_evento_c5(...) — authenticated, service_role
-- GRANT: authenticated, service_role
-- RISCO: Recrutas podem emitir eventos C5 diretamente
-- Proteção: idempotency_key + constraints na tabela

-- aplicar_alteracao_medalha / aprovar_alteracao_medalha — service_role
-- Admin workflow para alterações de medalhas

-- -----------------------------------------------------------------------------
-- TRIGGERS — C5
-- Todos SECURITY DEFINER, search_path=public
-- -----------------------------------------------------------------------------

-- c5_auditar_evento_institucional() — trigger em eventos_institucionais
-- Função: audit trail de eventos C5

-- c5_guard_eventos_institucionais() — trigger em eventos_institucionais BEFORE INSERT
-- Função: valida tipo_evento contra c5_taxonomia_eventos, aplica idempotência

-- c5_normalizar_evento_institucional() — trigger em eventos_institucionais
-- Função: normaliza payload e preenche campos derivados

-- _emitir_evento_c5_iea_marco() — trigger em recruta_iea
-- Função: emite evento C5 automático quando recruta atinge marco de IEA

-- _c5_emit_auth_logout() — trigger em auth.sessions após DELETE
-- Função: emite evento C5 de logout

-- c5_recruta_id_for_auth() — helper para RLS C5
-- GRANT: authenticated, service_role
-- Retorna: recrutas.id WHERE auth_id = auth.uid()

-- -----------------------------------------------------------------------------
-- RLS POLICIES — Gamificação C5
-- Linhas dump: ~17600-17750
-- -----------------------------------------------------------------------------

ALTER TABLE "public"."eventos_institucionais" ENABLE ROW LEVEL SECURITY;
-- policies: SELECT (authenticated, próprios com idempotency_key NOT NULL)
--           INSERT (BLOQUEADO), UPDATE/DELETE (BLOQUEADOS)

ALTER TABLE "public"."c5_audit_eventos_institucionais" ENABLE ROW LEVEL SECURITY;
-- policies: SELECT/INSERT/UPDATE/DELETE → BLOQUEADOS para authenticated

ALTER TABLE "public"."c5_eventos" ENABLE ROW LEVEL SECURITY;
-- policies: SELECT (authenticated, WHERE recruta_id = c5_recruta_id_for_auth())

ALTER TABLE "public"."recruta_medalhas" ENABLE ROW LEVEL SECURITY;
-- policies: todas operações BLOQUEADAS para authenticated

-- =============================================================================
-- NOTAS
-- =============================================================================
-- 1. c5_guard_eventos_institucionais valida tipo_evento — catálogo em c5_taxonomia_eventos
-- 2. emitir_evento_c5 exposta a authenticated — verificar idempotência
-- 3. medalhas_concedidas pode ser nome alternativo de recruta_medalhas (ver dump)
-- 4. conceder_medalha_v2 substitui grant_medal (verificar se grant_medal ainda existe)
-- 5. c7_ciclos define períodos de avaliação — IEA e Elite dependem destes ciclos
-- =============================================================================
