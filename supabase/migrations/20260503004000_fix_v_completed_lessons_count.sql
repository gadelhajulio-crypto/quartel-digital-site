-- ==============================================================================
-- FIX: v_completed_lessons_count — Substituir tabela legada lesson_progress
-- ==============================================================================
-- Motivo: View original aponta para tabela legada 'lesson_progress' (coluna user_id).
--         Tabela canônica é 'recruta_progresso' (coluna recruta_id).
--         Resultado: contagem sempre retorna 0 para usuários novos.
-- Data: 03/05/2026
-- ==============================================================================

-- DROP antiga (aponta para lesson_progress legada)
DROP VIEW IF EXISTS public.v_completed_lessons_count;

-- RECRIA apontando para recruta_progresso (canônica)
CREATE OR REPLACE VIEW public.v_completed_lessons_count AS
SELECT
    rp.recruta_id         AS user_id,        -- alias mantido para compatibilidade com frontend
    COUNT(*)              AS completed_count
FROM public.recruta_progresso rp
WHERE rp.status = 'completed'
GROUP BY rp.recruta_id;

-- RLS: recruta_progresso já tem RLS (auth.uid() = recruta_id).
-- A view herda as políticas da tabela base.

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.v_completed_lessons_count LIMIT 5;
-- SELECT completed_count FROM public.v_completed_lessons_count WHERE user_id = auth.uid();

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_completed_lessons_count;
-- (Recriar apontando para lesson_progress conforme migration original 20260119233000)
