-- =============================================================================
-- Migration:  20260518001000_fix01_v_lessons_panel_media_fields.sql
-- Classificação: Fix-01 — Correção de view canônica
-- Data:       2026-05-18
-- Autor:      institutional-fix-2026-05-18
-- Revisão:    AGUARDANDO EXECUÇÃO — não executar sem aprovação institucional
-- =============================================================================
--
-- PROBLEMA
-- --------
-- A view public.v_lessons_panel (schema remoto ln 13251) não expõe as colunas
-- video_url e pdf_url da tabela public.aulas.
--
-- Consequência: o hook useLessonData (src/hooks/useLessonData.ts) lê
-- lessonData.video_url e lessonData.pdf_url da view. Como os campos não
-- existem na view, ambos chegam como undefined no JavaScript. A coerção
-- `?? null` em useLessonData.ts:49–50 transforma undefined em null.
-- Resultado: a tela app/(stack)/lesson/[id].tsx sempre exibe o placeholder
-- "Conteúdo Institucional" mesmo quando aulas.video_url ou aulas.pdf_url
-- contém uma URL válida.
--
-- Adicionalmente, ModuleLessonsScreen.tsx (src/screens/ModuleLessonsScreen.tsx)
-- usa o seguinte select explícito:
--   .select('id:lesson_id, titulo:title, ordem:lesson_order, video_url, pdf_url')
-- Como video_url e pdf_url não existem na view, PostgREST retorna erro e
-- setAulas([]) é chamado — as aulas nunca são exibidas nesta tela.
--
-- ESTADO ATUAL (dump remoto ln 13251–13264)
-- -----------------------------------------
-- CREATE OR REPLACE VIEW "public"."v_lessons_panel" AS
-- SELECT "a"."id"        AS "lesson_id",
--        "a"."titulo"    AS "title",
--        "a"."modulo_id" AS "module",
--        "a"."ordem"     AS "lesson_order",
--        "m"."forca"     AS "force"
-- FROM "public"."aulas" "a"
-- JOIN "public"."modulos" "m" ON ("m"."id" = "a"."modulo_id");
--
-- CORREÇÃO
-- --------
-- Adicionar a.video_url e a.pdf_url ao SELECT, mapeadas diretamente das
-- colunas canônicas de public.aulas (dump remoto ln 9082–9083).
-- Todos os campos existentes (lesson_id, title, module, lesson_order, force)
-- são preservados sem alteração de nome ou tipo.
--
-- REGRAS DE RENDERIZAÇÃO DO APP (lesson/[id].tsx:55–93)
-- -------------------------------------------------------
-- A tela usa URL = video_url ?? pdf_url e inspeciona o valor:
--   contém 'cloudflarestream' | 'customer-' | termina '.m3u8' → VideoPlayer
--   termina '.mp3' | '.aac'                                    → placeholder áudio
--   termina '.pdf'                                              → link "Abrir Externamente"
--   null / undefined                                            → "Conteúdo Institucional"
--
-- SCHEMA DE REFERÊNCIA (dump ln 9075–9084)
-- ----------------------------------------
-- CREATE TABLE public.aulas (
--     id        uuid NOT NULL,
--     modulo_id uuid NOT NULL,
--     titulo    text NOT NULL,
--     ordem     integer NOT NULL,
--     xp_valor  integer DEFAULT 0 NOT NULL,
--     created_at timestamptz,
--     video_url text,          ← coluna que será exposta
--     pdf_url   text           ← coluna que será exposta
-- );
--
-- IDEMPOTÊNCIA DA MIGRATION
-- --------------------------
-- CREATE OR REPLACE VIEW: reexecutável sem efeito colateral.
-- COMMENT ON VIEW: idempotente — sobrescreve o comentário existente.
-- GRANT: idempotente no PostgreSQL (GRANT novamente é no-op se já existe).
--
-- IMPACTO FRONTEND
-- ----------------
-- useLessonData.ts         : lessonData.video_url e lessonData.pdf_url
--                            deixam de ser undefined; passam a retornar
--                            o valor real da coluna (string | null).
--                            Nenhuma alteração de código necessária no hook.
-- ModuleLessonsScreen.tsx  : o select explícito 'video_url, pdf_url' para
--                            de gerar erro PostgREST; aulas são exibidas.
-- services/lessons.ts      : usa select('*') + eq('force', 'marinha').
--                            Adição de colunas não quebra select('*').
-- useLessonData.ts         : usa select('*'). Idem acima.
--
-- RISCO
-- -----
-- MÍNIMO — recria view sem alterar tabelas, sem remover colunas existentes.
-- CREATE OR REPLACE preserva GRANTs e OWNER automaticamente no PostgreSQL.
-- COMMENT não é preservado pelo CREATE OR REPLACE — re-aplicado explicitamente.
-- Reversão instantânea via rollback abaixo.
--
-- REFERÊNCIAS
-- -----------
-- Plano:      supabase/baseline/LESSON_CONTENT_CREATION_PLAN.md (Fix-01, seção 4)
-- Handoff:    supabase/baseline/FIX_01_02_HANDOFF.md
-- Dump ref:   supabase/remote/supabase_remote_schema.sql (ln 9075, 13251)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- PASSO 1 — Recriar v_lessons_panel com video_url e pdf_url
-- -----------------------------------------------------------------------------
-- CREATE OR REPLACE VIEW preserva:
--   - OWNER (postgres)
--   - GRANTs existentes (GRANT ALL TO service_role; GRANT SELECT TO authenticated)
-- NÃO preserva automaticamente:
--   - COMMENT (re-aplicado no PASSO 2)

CREATE OR REPLACE VIEW public.v_lessons_panel AS
SELECT
    a.id          AS lesson_id,
    a.titulo      AS title,
    a.modulo_id   AS module,
    a.ordem       AS lesson_order,
    m.forca       AS force,
    a.video_url,                   -- NOVO: expõe video_url para o player
    a.pdf_url                      -- NOVO: expõe pdf_url para o viewer
FROM public.aulas a
JOIN public.modulos m
    ON m.id = a.modulo_id;


-- -----------------------------------------------------------------------------
-- PASSO 2 — Re-aplicar COMMENT (CREATE OR REPLACE não preserva)
-- -----------------------------------------------------------------------------

COMMENT ON VIEW public.v_lessons_panel IS
    'CANONICAL RCC FRONTEND VIEW. Lessons panel projection. '
    'Frontend may SELECT through authenticated role. '
    'Fix-01 2026-05-18: added video_url, pdf_url from aulas.';


-- -----------------------------------------------------------------------------
-- PASSO 3 — Re-afirmar GRANTs (idempotente — sem mudança em relação ao dump)
-- -----------------------------------------------------------------------------
-- Dump remoto (ln 19720–19721):
--   GRANT ALL ON TABLE "public"."v_lessons_panel" TO "service_role";
--   GRANT SELECT ON TABLE "public"."v_lessons_panel" TO "authenticated";

GRANT ALL    ON TABLE public.v_lessons_panel TO service_role;
GRANT SELECT ON TABLE public.v_lessons_panel TO authenticated;


-- =============================================================================
-- TESTES SQL PÓS-APPLY
-- (executar após migration — NÃO parte da migration)
-- =============================================================================

-- TESTE T-01 — View existe com colunas corretas?
--
--   SELECT column_name, data_type
--   FROM information_schema.columns
--   WHERE table_schema = 'public'
--     AND table_name   = 'v_lessons_panel'
--   ORDER BY ordinal_position;
--   -- Esperado: 7 linhas
--   --   lesson_id    | uuid
--   --   title        | text
--   --   module       | uuid
--   --   lesson_order | integer
--   --   force        | text
--   --   video_url    | text   ← NEW
--   --   pdf_url      | text   ← NEW
--
-- TESTE T-02 — video_url e pdf_url são expostas quando preenchidas?
--
--   SELECT lesson_id, title, video_url, pdf_url
--   FROM public.v_lessons_panel
--   WHERE video_url IS NOT NULL OR pdf_url IS NOT NULL
--   LIMIT 5;
--   -- Esperado: retorna linhas com URLs reais de aulas que as têm preenchidas.
--   -- Se 0 linhas: aulas existentes têm video_url = NULL (normal — aula sem vídeo).
--
-- TESTE T-03 — Campos pré-existentes preservados?
--
--   SELECT lesson_id, title, module, lesson_order, force
--   FROM public.v_lessons_panel
--   LIMIT 1;
--   -- Esperado: mesmos valores de antes da migration.
--
-- TESTE T-04 — GRANT para authenticated existe?
--
--   SELECT has_table_privilege('authenticated', 'public.v_lessons_panel', 'SELECT');
--   -- Esperado: true
--
-- TESTE T-05 — COMMENT atualizado?
--
--   SELECT obj_description(
--       (SELECT oid FROM pg_class WHERE relname = 'v_lessons_panel' AND relnamespace = 'public'::regnamespace),
--       'pg_class'
--   );
--   -- Esperado: string contém 'Fix-01 2026-05-18'
--
-- TESTE T-06 — ModuleLessonsScreen select explícito funciona?
--
--   SELECT lesson_id, title AS titulo, lesson_order AS ordem, video_url, pdf_url
--   FROM public.v_lessons_panel
--   WHERE module = '<UUID_DE_MODULO_EXISTENTE>'
--   ORDER BY lesson_order;
--   -- Esperado: linhas retornadas sem erro.
--   -- Antes do fix: este select retornava erro PostgREST (colunas não existiam).
--
-- =============================================================================
-- ROLLBACK
-- (executar APENAS se necessário reverter Fix-01)
-- =============================================================================
--
-- Restaura o estado exato do dump remoto (ln 13251–13264):
--
-- CREATE OR REPLACE VIEW public.v_lessons_panel AS
-- SELECT
--     a.id          AS lesson_id,
--     a.titulo      AS title,
--     a.modulo_id   AS module,
--     a.ordem       AS lesson_order,
--     m.forca       AS force
-- FROM public.aulas a
-- JOIN public.modulos m
--     ON m.id = a.modulo_id;
--
-- COMMENT ON VIEW public.v_lessons_panel IS
--     'CANONICAL RCC FRONTEND VIEW. Lessons panel projection. '
--     'Frontend may SELECT through authenticated role.';
--
-- GRANT ALL    ON TABLE public.v_lessons_panel TO service_role;
-- GRANT SELECT ON TABLE public.v_lessons_panel TO authenticated;
--
-- Impacto do rollback:
--   - video_url e pdf_url voltam a ser undefined para o frontend.
--   - Tela de aula volta a exibir apenas placeholder.
--   - ModuleLessonsScreen.tsx volta a retornar erro PostgREST no select explícito.
--   - Nenhum dado é perdido (apenas view recriada).
--
-- =============================================================================
-- VEREDICTO: AGUARDANDO EXECUÇÃO
-- =============================================================================
-- Status: aprovação institucional pendente.
-- Responsável pela execução: DBA / Supabase Admin.
-- Executar no SQL Editor como service_role ou via supabase db push.
-- =============================================================================
