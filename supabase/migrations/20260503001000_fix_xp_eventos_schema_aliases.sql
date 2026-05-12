-- ==============================================================================
-- FIX: xp_eventos — Aliases de Colunas para Compatibilidade C4
-- ==============================================================================
-- Motivo: Migration C4 (20260202113000) criou v_ranking_global usando xe.recruta_id
--         e xe.xp, mas a tabela original (20240114220000) usa user_id e amount.
--         Este script adiciona as colunas canônicas se ainda não existirem,
--         sincroniza dados históricos e instala trigger de manutenção.
-- Data: 03/05/2026
-- Idempotente: SIM (IF NOT EXISTS + ON CONFLICT DO NOTHING)
-- ==============================================================================

-- 1. ADICIONAR COLUNA recruta_id (alias de user_id)
ALTER TABLE public.xp_eventos
    ADD COLUMN IF NOT EXISTS recruta_id UUID REFERENCES auth.users(id);

-- 2. ADICIONAR COLUNA xp (alias de amount)
ALTER TABLE public.xp_eventos
    ADD COLUMN IF NOT EXISTS xp INTEGER;

-- 3. SINCRONIZAR DADOS HISTÓRICOS (backfill idempotente)
UPDATE public.xp_eventos
SET
    recruta_id = user_id,
    xp        = amount
WHERE recruta_id IS NULL OR xp IS NULL;

-- 4. ÍNDICES DE PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_xp_eventos_recruta_id
    ON public.xp_eventos (recruta_id);

-- 5. TRIGGER: manter recruta_id e xp sempre em sincronia com user_id e amount
CREATE OR REPLACE FUNCTION public.fn_sync_xp_evento_aliases()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.recruta_id := NEW.user_id;
    NEW.xp        := NEW.amount;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_xp_evento_aliases ON public.xp_eventos;
CREATE TRIGGER trg_sync_xp_evento_aliases
    BEFORE INSERT OR UPDATE OF user_id, amount
    ON public.xp_eventos
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_sync_xp_evento_aliases();

-- 6. RECRIA v_ranking_global e v_ranking_force apontando para colunas canônicas
CREATE OR REPLACE VIEW public.v_ranking_global AS
SELECT
    ROW_NUMBER() OVER (
        ORDER BY COALESCE(SUM(xe.xp), 0) DESC, xe.recruta_id ASC
    ) AS position,
    xe.recruta_id,
    r.nome,
    COALESCE(SUM(xe.xp), 0) AS xp_total
FROM public.xp_eventos xe
JOIN public.recrutas r ON r.id = xe.recruta_id
GROUP BY xe.recruta_id, r.nome;

CREATE OR REPLACE VIEW public.v_ranking_force AS
SELECT
    ROW_NUMBER() OVER (
        PARTITION BY r.forca
        ORDER BY COALESCE(SUM(xe.xp), 0) DESC, xe.recruta_id ASC
    ) AS position,
    xe.recruta_id,
    r.nome,
    COALESCE(SUM(xe.xp), 0) AS xp_total,
    r.forca
FROM public.xp_eventos xe
JOIN public.recrutas r ON r.id = xe.recruta_id
WHERE r.forca IS NOT NULL
GROUP BY xe.recruta_id, r.nome, r.forca;

-- 7. RECRIA mv_xp_mensal_recruta apontando para recruta_id e xp
-- Materialized views precisam ser dropadas e recriadas.
DROP MATERIALIZED VIEW IF EXISTS public.mv_campeao_mensal CASCADE;
DROP MATERIALIZED VIEW IF EXISTS public.mv_ranking_mensal  CASCADE;
DROP MATERIALIZED VIEW IF EXISTS public.mv_xp_mensal_recruta CASCADE;

CREATE MATERIALIZED VIEW public.mv_xp_mensal_recruta AS
SELECT
    xe.recruta_id,
    r.forca,
    date_trunc('month', xe.created_at)::date AS month_ref,
    SUM(xe.xp) AS xp_mensal
FROM public.xp_eventos xe
JOIN public.recrutas r ON r.id = xe.recruta_id
GROUP BY xe.recruta_id, r.forca, date_trunc('month', xe.created_at);

CREATE UNIQUE INDEX idx_mv_xp_mensal_recruta
    ON public.mv_xp_mensal_recruta (recruta_id, forca, month_ref);

CREATE MATERIALIZED VIEW public.mv_ranking_mensal AS
SELECT
    recruta_id,
    forca,
    month_ref,
    xp_mensal,
    rank() OVER (PARTITION BY forca, month_ref ORDER BY xp_mensal DESC) AS rank_position
FROM public.mv_xp_mensal_recruta;

CREATE UNIQUE INDEX idx_mv_ranking_mensal
    ON public.mv_ranking_mensal (recruta_id, forca, month_ref);

CREATE MATERIALIZED VIEW public.mv_campeao_mensal AS
SELECT recruta_id, forca, month_ref
FROM public.mv_ranking_mensal
WHERE rank_position = 1;

CREATE UNIQUE INDEX idx_mv_campeao_mensal
    ON public.mv_campeao_mensal (forca, month_ref);

-- ==============================================================================
-- NOTA SOBRE recrutas.xp vs recrutas.xp_total
-- ==============================================================================
-- recrutas.xp       → atualizado por complete_lesson (RPC C2) — XP de aulas
-- recrutas.xp_total → atualizado por registrar_xp (RPC original) — XP de eventos
-- xp_eventos.xp     → ledger de eventos (colunas amount/xp são sinônimas)
-- Decisão: v_identidade_recruta expõe recrutas.xp (complete_lesson é canônico)
-- O ranking agrega xp_eventos.xp (ledger completo).
-- A normalização de recrutas.xp + xp_total requer decisão institucional — BLOQUEADO.

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP TRIGGER IF EXISTS trg_sync_xp_evento_aliases ON public.xp_eventos;
-- DROP FUNCTION IF EXISTS public.fn_sync_xp_evento_aliases();
-- ALTER TABLE public.xp_eventos DROP COLUMN IF EXISTS recruta_id;
-- ALTER TABLE public.xp_eventos DROP COLUMN IF EXISTS xp;
-- (recria mv_* a partir das migrations originais)

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT recruta_id, xp FROM public.xp_eventos LIMIT 5;
-- SELECT * FROM public.v_ranking_global LIMIT 5;
-- SELECT * FROM public.mv_xp_mensal_recruta LIMIT 5;
