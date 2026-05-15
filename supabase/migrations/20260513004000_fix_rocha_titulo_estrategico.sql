-- RCC-0.5 — Corrige título do Rocha para INSTRUTOR ESTRATÉGICO
--
-- Motivo: migration 20260513003000 pode ter sido aplicada com valor incorreto
-- ('INSTRUTOR TÁTICO'). Esta migration sobrescreve explicitamente.
--
-- Idempotente: pode ser aplicada múltiplas vezes sem efeito colateral.

UPDATE public.instrutores
SET titulo = 'INSTRUTOR ESTRATÉGICO'
WHERE slug = 'rocha';

-- Validação:
-- SELECT slug, titulo FROM public.instrutores WHERE slug = 'rocha';
-- Expected: rocha | INSTRUTOR ESTRATÉGICO
