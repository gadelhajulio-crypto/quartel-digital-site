-- =============================================================================
-- MÓDULO 05: Aprendizagem — Módulos, Aulas, Progresso
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Domínio: modulos, aulas, recruta_modulos, recruta_progresso, c9_*
--          vw_rdm_lessons_v2, vw_recruta_module_progress_v2, complete_lesson
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABELAS — Aprendizagem Canônica
-- -----------------------------------------------------------------------------

-- modulos (ver também módulo 01_core_tables.sql)
-- Linhas dump: 10607-10622

-- aulas (tabela canônica — coluna modulo_id, não module_id)
-- Linhas dump: 9075-9088

-- recruta_modulos — Progresso por módulo (RPC: rpc_start_module, rpc_complete_module)
-- Linhas dump: 11064-11079
CREATE TABLE IF NOT EXISTS "public"."recruta_modulos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "modulo_id" "uuid" NOT NULL,
    "liberado" boolean DEFAULT false NOT NULL,
    "liberado_em" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "first_access_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "degustacao_notificada" boolean DEFAULT false,
    "updated_at" timestamp with time zone DEFAULT "now"()
);
ALTER TABLE "public"."recruta_modulos" OWNER TO "postgres";

-- recruta_progresso — Progresso por aula (TABELA CANÔNICA)
-- Linhas dump: 11094-11108
-- NOTA: status tem CHECK constraint: APENAS 'completed' é aceito
-- NOTA: Única constraint: UNIQUE(recruta_id, lesson_id) — idempotência via ON CONFLICT
-- NOTA: lesson_id referencia aulas.id (uuid)
CREATE TABLE IF NOT EXISTS "public"."recruta_progresso" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "lesson_id" "uuid" NOT NULL,
    "status" "text" NOT NULL,
    "completed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "xp_granted" integer DEFAULT 0 NOT NULL,
    "source" "text" DEFAULT 'lesson_completion'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "recruta_progresso_status_check" CHECK (("status" = 'completed'::"text"))
);
ALTER TABLE "public"."recruta_progresso" OWNER TO "postgres";

-- recruta_progressos_modulos — (Possivelmente legado — verificar uso)
-- Linhas dump: 11110-11123
CREATE TABLE IF NOT EXISTS "public"."recruta_progressos_modulos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recruta_id" "uuid" NOT NULL,
    "modulo_id" "uuid" NOT NULL,
    "aulas_concluidas" integer DEFAULT 0,
    "total_aulas" integer NOT NULL,
    "revisoes_concluidas" integer DEFAULT 0,
    "total_revisoes" integer NOT NULL,
    "concluido" boolean DEFAULT false,
    "atualizado_em" timestamp with time zone DEFAULT "now"()
);
ALTER TABLE "public"."recruta_progressos_modulos" OWNER TO "postgres";

-- -----------------------------------------------------------------------------
-- TABELAS — Didática C9
-- Linhas dump: 9839-9950
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS "public"."c9_aula_conteudos" (
    -- DDL completo: ver dump linhas 9839-9865
    -- Colunas: id, aula_id, tipo, conteudo, versao, ativo, deleted_at, created_at, updated_at
    -- INDEX: c9_aula_conteudos_um_ativo_por_tipo (UNIQUE parcial: ativo=true AND deleted_at IS NULL)
);

CREATE TABLE IF NOT EXISTS "public"."c9_aula_flashcards" (
    -- DDL completo: ver dump linhas 9861-9885
    -- Colunas: id, aula_id, frente, verso, ordem, ativo, deleted_at, created_at
);

CREATE TABLE IF NOT EXISTS "public"."c9_aula_quizzes" (
    -- DDL completo: ver dump linhas 9931-9950
    -- Colunas: id, aula_id, titulo, descricao, tipo, ativo, deleted_at, created_at, updated_at
);

CREATE TABLE IF NOT EXISTS "public"."c9_aula_quiz_perguntas" (
    -- DDL completo: ver dump linhas 9897-9915
    -- Colunas: id, quiz_id, texto, ordem, deleted_at, created_at
);

CREATE TABLE IF NOT EXISTS "public"."c9_aula_quiz_alternativas" (
    -- DDL completo: ver dump linhas 9880-9900
    -- Colunas: id, pergunta_id, texto, correta, ordem, deleted_at, created_at
    -- UNIQUE PARCIAL: c9_aula_quiz_alternativas_uma_correta (correta=true AND deleted_at IS NULL)
);

CREATE TABLE IF NOT EXISTS "public"."c9_aula_quiz_tentativas" (
    -- DDL completo: ver dump linhas 9914-9935
    -- Colunas: id, quiz_id, recruta_id, respostas, score, created_at
);

-- -----------------------------------------------------------------------------
-- TABELAS LEGADAS (não usar em código novo)
-- -----------------------------------------------------------------------------

-- aulas_concluidas — LEGADO (substituída por recruta_progresso)
-- Linhas dump: 9090-9098
CREATE TABLE IF NOT EXISTS "public"."aulas_concluidas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "aula_id" "uuid" NOT NULL,
    "data_conclusao" timestamp with time zone DEFAULT "now"()
);

-- lessons, lesson_media, lesson_progress — LEGADO (pré-RCC)
-- lesson_progress: Linhas dump 3291-3435 (inclui colunas user_id, lesson_id, completed_at)
-- lessons: Linhas dump 10328-10342 (inclui force, module text, lesson_order)
-- NOTA: lessons.module é TEXT (não UUID!) — tabela diferente do modelo canônico

-- -----------------------------------------------------------------------------
-- VIEWS CANÔNICAS — Aprendizagem
-- Linhas dump: 14111-14340
-- -----------------------------------------------------------------------------

-- vw_rdm_lessons — V1 LEGADA (substituída por v2)
-- Linhas dump: 14111-14135
-- NOTA: Usa auth.uid() internamente para filtrar por recruta

-- vw_rdm_lessons_v2 — CANÔNICA (usada pelo frontend)
-- Linhas dump: 14177-14200
CREATE OR REPLACE VIEW "public"."vw_rdm_lessons_v2" AS
    -- DDL completo: ver dump linhas 14177-14200
    -- Colunas: lesson_id, lesson_order, lesson_title, module (UUID), status, module_title
    -- Filtra por recruta via auth.uid()
    SELECT NULL::uuid AS "lesson_id" WHERE false; -- placeholder
ALTER VIEW "public"."vw_rdm_lessons_v2" OWNER TO "postgres";
COMMENT ON VIEW "public"."vw_rdm_lessons_v2" IS 'CANONICAL RCC FRONTEND VIEW. Lesson list for recruta. DDL completo em dump linha 14177.';

-- vw_recruta_module_progress — V1 LEGADA
-- Linhas dump: 14239-14260

-- vw_recruta_module_progress_v2 — CANÔNICA
-- Linhas dump: 14314-14340
CREATE OR REPLACE VIEW "public"."vw_recruta_module_progress_v2" AS
    -- DDL completo: ver dump linhas 14314-14340
    -- Colunas: module_id, module_title, total_lessons, completed_lessons, progress_percentage
    -- Usa auth.uid() internamente
    SELECT NULL::uuid AS "module_id" WHERE false; -- placeholder
ALTER VIEW "public"."vw_recruta_module_progress_v2" OWNER TO "postgres";
COMMENT ON VIEW "public"."vw_recruta_module_progress_v2" IS 'CANONICAL RCC FRONTEND VIEW. Module progress for recruta. DDL completo em dump linha 14314.';

-- vw_recruta_module_status_rcc — security_invoker=true
-- Linhas dump: 14374-14420
CREATE OR REPLACE VIEW "public"."vw_recruta_module_status_rcc" WITH ("security_invoker"='true') AS
    -- DDL completo: ver dump linhas 14374-14420
    SELECT NULL::uuid AS "modulo_id" WHERE false; -- placeholder

-- v_lessons_panel — Panel view (admin/instrutores)
-- Linhas dump: 13251-13270
CREATE OR REPLACE VIEW "public"."v_lessons_panel" AS
    -- DDL completo: ver dump linhas 13251-13270
    -- Colunas: lesson_id, title, module (UUID), lesson_order, force, video_url, pdf_url
    SELECT NULL::uuid AS "lesson_id" WHERE false; -- placeholder

-- v_lesson_progress_panel — Progresso (panel)
-- Linhas dump: 13188-13199
CREATE OR REPLACE VIEW "public"."v_lesson_progress_panel" AS
 SELECT "user_id",
    "lesson_id",
    "completed_at"
   FROM "public"."lesson_progress" "lp";
ALTER VIEW "public"."v_lesson_progress_panel" OWNER TO "postgres";
COMMENT ON VIEW "public"."v_lesson_progress_panel" IS 'CANONICAL RCC FRONTEND VIEW. Lesson progress projection. Frontend may SELECT through authenticated role.';

-- v_modulos_catalogo — Catálogo de módulos por recruta (com is_degustacao)
-- Linhas dump: 13436-13455

-- v_c9_aula_execucao — security_invoker=true
-- Linhas dump: 12349-12375

-- v_c9_quiz_execucao — security_invoker=true (dois DDLs: 12371 e 16504)
-- v_c9_quiz_resultado — security_invoker=true
-- Linhas dump: 12385-12440

-- -----------------------------------------------------------------------------
-- RPC CANÔNICA — complete_lesson
-- Linhas dump: 1182-1249
-- PROTEÇÃO: SECURITY DEFINER, SET search_path='public'
-- GRANTS: apenas service_role (linha 18633-18634 do dump)
-- RISCO: Aceita p_recruta_id como parâmetro — deveria usar auth.uid() internamente
-- -----------------------------------------------------------------------------
-- CREATE OR REPLACE FUNCTION "public"."complete_lesson"(
--     "p_recruta_id" "uuid",
--     "p_lesson_id" "uuid",
--     "p_xp" integer DEFAULT 50
-- ) RETURNS json
--     LANGUAGE "plpgsql" SECURITY DEFINER
--     SET "search_path" TO 'public'
-- DDL completo: ver dump linhas 1182-1249

-- -----------------------------------------------------------------------------
-- RLS POLICIES — Aprendizagem
-- Linhas dump: 17427-17465, 18039-18042, 18279-18330
-- -----------------------------------------------------------------------------

ALTER TABLE "public"."aulas" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aulas_read_authenticated" ON "public"."aulas"
    FOR SELECT TO "authenticated" USING (true);
CREATE POLICY "Permitir leitura de aulas para usuarios autenticados" ON "public"."aulas"
    FOR SELECT TO "authenticated" USING (true);

ALTER TABLE "public"."modulos" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "select_modulos_by_forca" ON "public"."modulos"
    FOR SELECT USING ((("forca" = ( SELECT "recrutas"."forca"
       FROM "public"."recrutas"
      WHERE ("recrutas"."id" = "auth"."uid"()))) AND ("ativo" = true)));
CREATE POLICY "Permitir leitura de modulos para usuarios autenticados" ON "public"."modulos"
    FOR SELECT TO "authenticated" USING (true);

ALTER TABLE "public"."recruta_progresso" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "recruta_progresso_select" ON "public"."recruta_progresso"
    FOR SELECT USING (("recruta_id" = ( SELECT "recrutas"."id"
       FROM "public"."recrutas"
      WHERE ("recrutas"."auth_id" = "auth"."uid"()))));
CREATE POLICY "recruta_progresso_insert" ON "public"."recruta_progresso"
    FOR INSERT WITH CHECK (("recruta_id" = ( SELECT "recrutas"."id"
       FROM "public"."recrutas"
      WHERE ("recrutas"."auth_id" = "auth"."uid"()))));
CREATE POLICY "recruta_progresso_update" ON "public"."recruta_progresso"
    FOR UPDATE USING (("recruta_id" = ( SELECT "recrutas"."id"
       FROM "public"."recrutas"
      WHERE ("recrutas"."auth_id" = "auth"."uid"()))));
CREATE POLICY "recruta_progresso_delete" ON "public"."recruta_progresso"
    FOR DELETE USING (("recruta_id" = ( SELECT "recrutas"."id"
       FROM "public"."recrutas"
      WHERE ("recrutas"."auth_id" = "auth"."uid"()))));
CREATE POLICY "recruta_progresso_service" ON "public"."recruta_progresso"
    USING (("auth"."role"() = 'service_role'::"text"))
    WITH CHECK (("auth"."role"() = 'service_role'::"text"));

-- ATENÇÃO: INSERT por authenticated em recruta_progresso é permitido via RLS
-- O contrato canônico é via complete_lesson (service_role)
-- Considerar bloquear INSERT direto em P1

ALTER TABLE "public"."aulas_concluidas" ENABLE ROW LEVEL SECURITY;
-- policies: aulas_concluidas_select/insert/update/delete/service (ver dump 17442-17458)

ALTER TABLE "public"."recruta_modulos" ENABLE ROW LEVEL SECURITY;
-- Ver dump para policies recruta_modulos_*

-- -----------------------------------------------------------------------------
-- GRANTS — Aprendizagem
-- Linhas dump: 19193-19255
-- -----------------------------------------------------------------------------
GRANT ALL ON TABLE "public"."aulas" TO "service_role";
GRANT ALL ON TABLE "public"."aulas_concluidas" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."c9_aula_conteudos" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."c9_aula_flashcards" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."c9_aula_quiz_alternativas" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."c9_aula_quiz_perguntas" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."c9_aula_quizzes" TO "service_role";

REVOKE ALL ON FUNCTION "public"."complete_lesson"("p_recruta_id" "uuid", "p_lesson_id" "uuid", "p_xp" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_lesson"("p_recruta_id" "uuid", "p_lesson_id" "uuid", "p_xp" integer) TO "service_role";

-- =============================================================================
-- NOTAS IMPORTANTES PARA ESTE MÓDULO
-- =============================================================================
-- 1. v_completed_lessons_count AUSENTE no dump — P0 CRÍTICO (ver DRIFT_REPORT.md)
-- 2. lessons (legada) e recruta_progresso (canônica) coexistem — verificar qual usar
-- 3. vw_rdm_lessons_v2 usa aulas.id como lesson_id — confirmar FK
-- 4. complete_lesson insere em recruta_progresso E em xp_eventos
-- 5. recruta_progresso tem UNIQUE(recruta_id, lesson_id) — ON CONFLICT DO NOTHING para idempotência
-- =============================================================================
