-- ==============================================================================
-- AUDITORIA C4 - INFRAESTRUTURA DE RANKING (CORREÇÃO DE SCHEMA)
-- ==============================================================================
-- Motivo: Ajuste rigoroso ao schema real do banco (recruta_id, xp).
--         Correção de nomes de colunas incorretos (user_id, amount).
-- Data: 02/02/2026
-- ==============================================================================

-- 1. VIEW: RANKING GLOBAL
-- Soma de XP por recruta (todas as forças), ordenação decrescente.
-- Tabela xp_eventos: recruta_id, xp
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

-- 2. VIEW: RANKING POR FORÇA (GENÉRICO)
-- Ranking particionado por força.
-- Tabela recrutas: id, nome, forca
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

-- Validação implícita:
-- SELECT * FROM public.v_ranking_global LIMIT 1;
-- SELECT * FROM public.v_ranking_force LIMIT 1;
