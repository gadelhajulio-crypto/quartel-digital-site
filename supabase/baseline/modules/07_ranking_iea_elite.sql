-- =============================================================================
-- MÓDULO 07: Ranking, IEA e Elite
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Domínio: IEA scores, ciclos formativos, elite, materialized views, ranking RCC
-- Linhas relevantes: 8318-8364 (ciclos/iea), 10772-10807 (MVs), migrations 20260503009000
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABELAS — Ciclos Formativos e IEA (migration 20260503009000)
-- -----------------------------------------------------------------------------

-- ciclos_formativos — Períodos de avaliação formativa
-- Linhas dump: 8318-8334
CREATE TABLE IF NOT EXISTS "public"."ciclos_formativos" (
    -- DDL completo: ver dump linhas 8318-8334
    -- Colunas: id, nome, inicio, fim, ativo, created_at
    -- NOTA: c7_ciclos pode ser alias ou tabela paralela (verificar)
);

-- iea_snapshots — Snapshots de IEA por ciclo (processados externamente)
-- Linhas dump: 8335-8349
CREATE TABLE IF NOT EXISTS "public"."iea_snapshots" (
    -- DDL completo: ver dump linhas 8335-8349
    -- Colunas: id, recruta_id, ciclo_id, score, concept, snapshot_at, created_at
);

-- recruta_ciclo_status — Status do recruta por ciclo (classificação)
-- Migration local: 20260503009000
CREATE TABLE IF NOT EXISTS "public"."recruta_ciclo_status" (
    -- DDL completo: ver migrations
    -- Colunas: id, recruta_id, ciclo_id, status, classificacao, updated_at
);

-- recruta_iea — IEA calculada por ciclo (UNIQUE: recruta_id, ciclo_id)
-- Migration local: 20260503009000
CREATE TABLE IF NOT EXISTS "public"."recruta_iea" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "ciclo_id" "uuid" NOT NULL,
    "score" numeric(5,2),
    "concept" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "recruta_iea_unique" UNIQUE ("recruta_id", "ciclo_id")
);

-- ciclo_classificacao — Classificação final por ciclo (preenchido externamente)
-- Migration local: 20260503009000
CREATE TABLE IF NOT EXISTS "public"."ciclo_classificacao" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "ciclo_id" "uuid" NOT NULL,
    "classificacao" "text",
    "score_final" numeric(5,2),
    "elegivel_elite" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ciclo_classificacao_unique" UNIQUE ("recruta_id", "ciclo_id")
);

-- campeoes_mensais — Histórico de campeões mensais (append-only)
-- Linhas dump: 9949-9967
CREATE TABLE IF NOT EXISTS "public"."campeoes_mensais" (
    -- DDL completo: ver dump linhas 9949-9967
    -- Colunas: id, recruta_id, forca, mes_referencia, xp_total, created_at
    -- UNIQUE: (recruta_id, forca, mes_referencia)
);

-- -----------------------------------------------------------------------------
-- MATERIALIZED VIEWS — Ranking
-- Fonte: 01_core_tables.sql (definição completa lá)
-- NOTA CRÍTICA: Sem REFRESH agendado → dados sempre desatualizados
-- Correção planejada: Migration 07 (pg_cron ou Edge Function cron)
-- -----------------------------------------------------------------------------

-- mv_xp_mensal_recruta — XP por recruta por mês
-- Colunas: recruta_id, forca, mes_referencia (date), xp_total (sum)
-- Requer REFRESH periódico
-- NOTA MEMORY.md: month_ref e xp_mensal (divergência — nomes reais: mes_referencia, xp_total)

-- mv_ranking_mensal — Ranking por força por mês
-- Colunas: recruta_id, forca, mes_referencia, xp_total, posicao (rank())
-- NOTA MEMORY.md: rank_position (divergência — nome real: posicao)

-- mv_campeao_mensal — Campeões mensais (posicao=1)
-- Colunas: recruta_id, forca, mes_referencia

-- -----------------------------------------------------------------------------
-- VIEWS CANÔNICAS — Ranking RCC (sem migration local)
-- security_invoker=true em todas
-- Linhas dump: presentes no remoto
-- -----------------------------------------------------------------------------

-- v_ranking_mensal_rcc — Ranking mensal formatado para o frontend
-- security_invoker=true
-- Colunas: posicao, recruta_id, nome_guerra, forca, xp_total, mes_referencia
CREATE OR REPLACE VIEW "public"."v_ranking_mensal_rcc" WITH ("security_invoker"='true') AS
    SELECT NULL::integer AS "posicao" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_ranking_mensal_rcc" IS 'CANONICAL RANKING VIEW. security_invoker=true. Ranking mensal por força. DDL no dump remoto.';

-- v_posicao_recruta_mes_rcc — Posição específica do recruta atual
-- security_invoker=true
-- Colunas: posicao, xp_total, forca, mes_referencia, total_recrutas
CREATE OR REPLACE VIEW "public"."v_posicao_recruta_mes_rcc" WITH ("security_invoker"='true') AS
    SELECT NULL::integer AS "posicao" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_posicao_recruta_mes_rcc" IS 'CANONICAL RANKING VIEW. security_invoker=true. Posição do recruta autenticado no ranking mensal.';

-- v_campeoes_mensais_rcc — Histórico de campeões mensais
-- security_invoker=true
-- Colunas: recruta_id, nome_guerra, forca, mes_referencia, xp_total
CREATE OR REPLACE VIEW "public"."v_campeoes_mensais_rcc" WITH ("security_invoker"='true') AS
    SELECT NULL::uuid AS "recruta_id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_campeoes_mensais_rcc" IS 'CANONICAL RANKING VIEW. security_invoker=true. Histórico de campeões mensais.';

-- v_ranking_global — V1 legada (verificar se substituída)
-- Colunas: posicao, recruta_id, nome_guerra, forca, xp_total
CREATE OR REPLACE VIEW "public"."v_ranking_global" AS
    SELECT NULL::integer AS "posicao" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_ranking_global" IS 'LEGACY. Ver v_ranking_mensal_rcc. NOTA: recruta_id visível aqui pode ser usado por SEC-01 para exploit de complete_lesson.';

-- v_ranking_force — Ranking por força (V1)
CREATE OR REPLACE VIEW "public"."v_ranking_force" AS
    SELECT NULL::integer AS "posicao" WHERE false; -- placeholder

-- -----------------------------------------------------------------------------
-- VIEWS CANÔNICAS — IEA e Elite (sem migration local)
-- -----------------------------------------------------------------------------

-- v_iea_atual — Score IEA mais recente do recruta (V1)
-- Colunas: score, concept, updated_at (filtra por auth.uid())
CREATE OR REPLACE VIEW "public"."v_iea_atual" AS
    SELECT NULL::numeric AS "score" WHERE false; -- placeholder

-- v_iea_atual_v2 — CANÔNICA (V1 legada)
-- Linhas dump: presentes no remoto, sem migration local
CREATE OR REPLACE VIEW "public"."v_iea_atual_v2" AS
    SELECT NULL::numeric AS "score" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_iea_atual_v2" IS 'CANONICAL IEA VIEW. v1 legada. DDL no dump remoto. Sem migration local.';

-- v_elegibilidade_elite — Status de elegibilidade para elite (V1)
-- Colunas: recruta_id, elegivel_elite, regularidade_percentual, motivos_negacao
CREATE OR REPLACE VIEW "public"."v_elegibilidade_elite" AS
    SELECT NULL::uuid AS "recruta_id" WHERE false; -- placeholder

-- v_elegibilidade_elite_v2 — CANÔNICA
-- Linhas dump: presentes no remoto, sem migration local
CREATE OR REPLACE VIEW "public"."v_elegibilidade_elite_v2" AS
    SELECT NULL::uuid AS "recruta_id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_elegibilidade_elite_v2" IS 'CANONICAL ELITE VIEW. Sem migration local. DDL no dump remoto.';

-- v_classificacao_final_ciclo — Classificação final por ciclo (V1)
CREATE OR REPLACE VIEW "public"."v_classificacao_final_ciclo" AS
    SELECT NULL::uuid AS "recruta_id" WHERE false; -- placeholder

-- v_classificacao_final_ciclo_v2 — CANÔNICA
-- Linhas dump: presentes no remoto, sem migration local
CREATE OR REPLACE VIEW "public"."v_classificacao_final_ciclo_v2" AS
    SELECT NULL::uuid AS "recruta_id" WHERE false; -- placeholder
COMMENT ON VIEW "public"."v_classificacao_final_ciclo_v2" IS 'CANONICAL CLASSIFICATION VIEW. Sem migration local. DDL no dump remoto.';

-- -----------------------------------------------------------------------------
-- RPCs — IEA e Elite
-- PROTEÇÃO: Todas SECURITY DEFINER
-- -----------------------------------------------------------------------------

-- c6_get_iea_score(p_recruta_id uuid) → numeric
-- GRANT: authenticated
-- Função: calcula ou retorna score IEA atual do recruta

-- c6_get_simulado_final_score(p_recruta_id uuid, p_ciclo_id uuid) → numeric
-- GRANT: authenticated
-- Função: score do simulado final para o ciclo

-- verificar_elegibilidade_grau6(p_recruta_id uuid) → jsonb
-- GRANT: authenticated
-- Função: verifica todos os critérios de elegibilidade para elite (grau 6)

-- garantir_recruta_ciclo_status_me() → void
-- GRANT: authenticated (ou service_role — verificar)
-- Função: upsert de status do recruta no ciclo atual

-- -----------------------------------------------------------------------------
-- RLS POLICIES — Ranking/IEA
-- Linhas dump: ~17750-17900
-- -----------------------------------------------------------------------------

ALTER TABLE "public"."recruta_iea" ENABLE ROW LEVEL SECURITY;
-- Policy: SELECT — recruta vê apenas própria IEA
-- Policy: INSERT/UPDATE — service_role apenas (IEA calculada externamente)

ALTER TABLE "public"."ciclo_classificacao" ENABLE ROW LEVEL SECURITY;
-- Policy: SELECT — recruta vê apenas própria classificação
-- Policy: INSERT/UPDATE — service_role apenas

ALTER TABLE "public"."campeoes_mensais" ENABLE ROW LEVEL SECURITY;
-- Policy: SELECT — público (todos podem ver campeões)

-- =============================================================================
-- NOTAS CRÍTICAS
-- =============================================================================
-- 1. Materialized views sem REFRESH → ranking congelado indefinidamente
--    Correção: Migration 07 via pg_cron (verificar disponibilidade da extensão)
-- 2. v_ranking_global expõe recruta_id — vetor para SEC-01 (complete_lesson bypass)
-- 3. IEA e classificação são preenchidos por processo EXTERNO (não pelo frontend)
--    Fórmulas não são reproduzíveis apenas pelo código do app
-- 4. v_iea_atual_v2, v_elegibilidade_elite_v2, v_classificacao_final_ciclo_v2
--    existem no remoto mas sem migration local — capturas urgentes necessárias
-- 5. mes_referencia (dump) ≠ month_ref (MEMORY.md anterior) — MEMORY.md corrigida
-- 6. posicao (dump) ≠ rank_position (MEMORY.md anterior) — MEMORY.md corrigida
-- =============================================================================
