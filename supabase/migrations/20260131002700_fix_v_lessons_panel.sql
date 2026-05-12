-- ==============================================================================
-- CORREÇÃO ESTRUTURAL DE VIEW: v_lessons_panel
-- ==============================================================================
-- Motivo: Corrigir falta de integridade relacional entre modulos (UUID) e legacy lessons (TEXT).
--         Adicionar colunas de mídia (video_url, pdf_url) para suportar player.
-- Ação: Recria a view apontando para as tabelas corretas (public.aulas e public.modulos).
-- Data: 31/01/2026
-- ==============================================================================

-- 1. Remove a view antiga (baseada em 'lessons')
DROP VIEW IF EXISTS public.v_lessons_panel;

-- 2. Recria a view com JOIN correto (UUID = UUID) e colunas de mídia mapeadas
CREATE VIEW public.v_lessons_panel AS
SELECT
  a.id        AS lesson_id,
  a.titulo    AS title,
  a.modulo_id AS module,      -- Retorna UUID real, permitindo filtro correto frontend
  a.ordem     AS lesson_order,
  m.forca     AS force,
  -- Mapeamento de mídia baseado no tipo para cumprir contrato do App
  CASE WHEN a.type = 'video' THEN a.url ELSE NULL END AS video_url,
  CASE WHEN a.type = 'pdf' THEN a.url ELSE NULL END AS pdf_url
FROM public.aulas a
JOIN public.modulos m
  ON m.id = a.modulo_id;

-- 3. Confirmação (apenas para log de execução, se suportado)
-- SELECT count(*) as total_aulas_conectadas FROM public.v_lessons_panel;
