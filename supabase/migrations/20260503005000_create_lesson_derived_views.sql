-- ==============================================================================
-- VIEWS DERIVADAS DE AULAS E MÓDULOS
-- ==============================================================================
-- Cria:
--   - vw_rdm_lessons         (useModuleLessons — lista aulas de módulo com status)
--   - vw_recruta_module_progress  (useModulesProgress — progresso por módulo)
--   - v_available_reviews    (useAvailableReviews — revisões disponíveis)
--   - v_review_content       (useReviewContent — conteúdo de revisão por ID)
-- Data: 03/05/2026
-- ==============================================================================

-- ==============================================================================
-- 1. vw_rdm_lessons
-- Hook: useModuleLessons — .from('vw_rdm_lessons').select('*').eq('module', moduleId)
-- Retorna: lesson_id, lesson_order, lesson_title, status (blocked|available|completed), module
-- Status calculado via auth.uid(): completed se está em recruta_progresso.
-- ==============================================================================
CREATE OR REPLACE VIEW public.vw_rdm_lessons AS
SELECT
    a.id                                                    AS lesson_id,
    a."order"                                               AS lesson_order,
    a.title                                                 AS lesson_title,
    a.modulo_id                                             AS module,
    CASE
        WHEN rp.lesson_id IS NOT NULL THEN 'completed'::text
        ELSE 'available'::text
    END                                                     AS status
FROM public.aulas a
LEFT JOIN public.recruta_progresso rp
    ON  rp.lesson_id  = a.id
    AND rp.recruta_id = auth.uid()
    AND rp.status     = 'completed';

-- ==============================================================================
-- 2. vw_recruta_module_progress
-- Hook: useModulesProgress — .from('vw_recruta_module_progress').select('*')
-- Retorna: module_id, module_title, total_lessons, completed_lessons, progress_percentage
-- Calculado via auth.uid().
-- ==============================================================================
CREATE OR REPLACE VIEW public.vw_recruta_module_progress AS
SELECT
    m.id                                                            AS module_id,
    m.title                                                         AS module_title,
    COUNT(a.id)                                                     AS total_lessons,
    COUNT(rp.lesson_id)                                             AS completed_lessons,
    CASE
        WHEN COUNT(a.id) = 0 THEN 0
        ELSE ROUND(
            (COUNT(rp.lesson_id)::numeric / COUNT(a.id)::numeric) * 100,
            0
        )
    END                                                             AS progress_percentage
FROM public.modulos m
LEFT JOIN public.aulas a
    ON a.modulo_id = m.id
LEFT JOIN public.recruta_progresso rp
    ON  rp.lesson_id  = a.id
    AND rp.recruta_id = auth.uid()
    AND rp.status     = 'completed'
GROUP BY m.id, m.title;

-- ==============================================================================
-- 3. TABELA: aula_midias (media complementar — revisões de vídeo/áudio)
-- Revisões são conteúdos complementares de uma aula (vídeo ou áudio resumo).
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.aula_midias (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aula_id     UUID        NOT NULL REFERENCES public.aulas(id) ON DELETE CASCADE,
    type        TEXT        NOT NULL CHECK (type IN ('video','audio','pdf')),
    url         TEXT        NOT NULL,
    is_review   BOOLEAN     NOT NULL DEFAULT false,  -- true = é uma revisão
    ativo       BOOLEAN     NOT NULL DEFAULT true,
    ordem       INTEGER     NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_aula_midias_aula ON public.aula_midias (aula_id);
CREATE INDEX IF NOT EXISTS idx_aula_midias_review ON public.aula_midias (is_review) WHERE is_review = true;

ALTER TABLE public.aula_midias ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read midias" ON public.aula_midias;
CREATE POLICY "Authenticated read midias"
    ON public.aula_midias FOR SELECT TO authenticated
    USING (ativo = true);

DROP POLICY IF EXISTS "Service role full midias" ON public.aula_midias;
CREATE POLICY "Service role full midias"
    ON public.aula_midias FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- ==============================================================================
-- 4. v_available_reviews
-- Hook: useAvailableReviews — .from('v_available_reviews').select('*').order('lesson_order')
-- Retorna: review_id, lesson_title, type ('audio'|'video'), status, lesson_order
-- Disponível se: a aula já foi concluída pelo recruta atual (auth.uid()).
-- ==============================================================================
CREATE OR REPLACE VIEW public.v_available_reviews AS
SELECT
    am.id                                           AS review_id,
    a.title                                         AS lesson_title,
    am.type::text                                   AS type,
    a."order"                                       AS lesson_order,
    CASE
        WHEN rp.lesson_id IS NOT NULL THEN 'available'::text
        ELSE 'blocked'::text
    END                                             AS status
FROM public.aula_midias am
JOIN public.aulas a ON a.id = am.aula_id
LEFT JOIN public.recruta_progresso rp
    ON  rp.lesson_id  = a.id
    AND rp.recruta_id = auth.uid()
    AND rp.status     = 'completed'
WHERE am.is_review = true
  AND am.ativo     = true
  AND am.type IN ('audio', 'video');

-- ==============================================================================
-- 5. v_review_content
-- Hook: useReviewContent — .from('v_review_content').select('*').eq('review_id', id)
-- Retorna: review_id, lesson_title, type, media_url
-- ==============================================================================
CREATE OR REPLACE VIEW public.v_review_content AS
SELECT
    am.id       AS review_id,
    a.title     AS lesson_title,
    am.type     AS type,
    am.url      AS media_url
FROM public.aula_midias am
JOIN public.aulas a ON a.id = am.aula_id
WHERE am.is_review = true
  AND am.ativo     = true;

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.vw_rdm_lessons LIMIT 10;
-- SELECT * FROM public.vw_recruta_module_progress;
-- SELECT * FROM public.v_available_reviews LIMIT 5;
-- SELECT * FROM public.v_review_content LIMIT 5;

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_review_content;
-- DROP VIEW IF EXISTS public.v_available_reviews;
-- DROP VIEW IF EXISTS public.vw_recruta_module_progress;
-- DROP VIEW IF EXISTS public.vw_rdm_lessons;
-- DROP TABLE IF EXISTS public.aula_midias;
