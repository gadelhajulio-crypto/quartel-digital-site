-- ==============================================================================
-- IEA, CLASSIFICAÇÃO DE CICLO E ELEGIBILIDADE ELITE
-- ==============================================================================
-- Cria:
--   - recruta_iea               (scores IEA por ciclo)
--   - ciclo_classificacao       (classificação final por ciclo)
--   - v_iea_atual               (ieaService — IEA mais recente do recruta)
--   - v_iea_audit               (ieaService — verificação de existência)
--   - v_classificacao_final_ciclo (eliteService — classificação do ciclo)
--   - v_elegibilidade_elite      (eliteService — elegibilidade elite)
-- Data: 03/05/2026
-- BLOQUEADO PARA: fórmulas de IEA/score_final/elegibilidade.
--   As views expõem apenas dados existentes no banco. A lógica de cálculo
--   deve ser executada por processo externo (Edge Function, CRON, admin).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. TABELA: recruta_iea (Índice de Eficiência Acadêmica por ciclo)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.recruta_iea (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    recruta_id  UUID        NOT NULL REFERENCES public.recrutas(id) ON DELETE CASCADE,
    ciclo_id    TEXT        NOT NULL,
    score       NUMERIC(5,2) NOT NULL DEFAULT 0,
    concept     TEXT        NOT NULL DEFAULT 'Regular'
                CHECK (concept IN ('Regular','Alta Performance','Excelência')),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (recruta_id, ciclo_id)
);

CREATE INDEX IF NOT EXISTS idx_recruta_iea_recruta ON public.recruta_iea (recruta_id);

ALTER TABLE public.recruta_iea ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User read own iea" ON public.recruta_iea;
CREATE POLICY "User read own iea"
    ON public.recruta_iea FOR SELECT TO authenticated
    USING (recruta_id = auth.uid());

DROP POLICY IF EXISTS "Service role full iea" ON public.recruta_iea;
CREATE POLICY "Service role full iea"
    ON public.recruta_iea FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- VIEW: v_iea_atual
-- ieaService: .from('v_iea_atual').select('score, concept, updated_at').eq('recruta_id', id).single()
CREATE OR REPLACE VIEW public.v_iea_atual AS
SELECT DISTINCT ON (ri.recruta_id)
    ri.recruta_id,
    ri.score,
    ri.concept,
    ri.updated_at
FROM public.recruta_iea ri
ORDER BY ri.recruta_id, ri.updated_at DESC;

-- VIEW: v_iea_audit (verificação de existência — HEAD request pelo ieaService)
CREATE OR REPLACE VIEW public.v_iea_audit AS
SELECT
    ri.id,
    ri.recruta_id,
    ri.ciclo_id,
    ri.score,
    ri.concept,
    ri.updated_at
FROM public.recruta_iea ri
WHERE ri.recruta_id = auth.uid();

-- ------------------------------------------------------------------------------
-- 2. TABELA: ciclo_classificacao (Classificação final por ciclo por recruta)
-- Preenchida por processo externo (não pelo frontend).
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ciclo_classificacao (
    id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    recruta_id             UUID        NOT NULL REFERENCES public.recrutas(id) ON DELETE CASCADE,
    ciclo_id               TEXT        NOT NULL,
    iea_score              NUMERIC(5,2),
    xp_normalizado         NUMERIC(5,2),
    score_final            NUMERIC(5,2),
    status_regularidade    TEXT,
                           -- 'regular' | 'irregular' | 'em_apuracao'
    regularidade_percentual INTEGER,
    hierarquia_atual       TEXT,       -- 'recruta', 'soldado', 'cabo', etc.
    elegivel_elite         BOOLEAN     NOT NULL DEFAULT false,
    motivos_negacao        TEXT[]      DEFAULT '{}',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (recruta_id, ciclo_id)
);

CREATE INDEX IF NOT EXISTS idx_ciclo_class_recruta
    ON public.ciclo_classificacao (recruta_id, ciclo_id DESC);

ALTER TABLE public.ciclo_classificacao ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User read own classification" ON public.ciclo_classificacao;
CREATE POLICY "User read own classification"
    ON public.ciclo_classificacao FOR SELECT TO authenticated
    USING (recruta_id = auth.uid());

DROP POLICY IF EXISTS "Service role full classification" ON public.ciclo_classificacao;
CREATE POLICY "Service role full classification"
    ON public.ciclo_classificacao FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- VIEW: v_classificacao_final_ciclo
-- eliteService: campos recruta_id, ciclo_id, iea_score, xp_normalizado,
--               score_final, status_regularidade, regularidade_percentual, hierarquia_atual
CREATE OR REPLACE VIEW public.v_classificacao_final_ciclo AS
SELECT
    cc.recruta_id,
    cc.ciclo_id,
    cc.iea_score,
    cc.xp_normalizado,
    cc.score_final,
    cc.status_regularidade,
    cc.regularidade_percentual,
    cc.hierarquia_atual
FROM public.ciclo_classificacao cc
WHERE cc.recruta_id = auth.uid()
ORDER BY cc.ciclo_id DESC;

-- VIEW: v_elegibilidade_elite
-- eliteService: campos recruta_id, elegivel_elite, regularidade_percentual, motivos_negacao
CREATE OR REPLACE VIEW public.v_elegibilidade_elite AS
SELECT DISTINCT ON (cc.recruta_id)
    cc.recruta_id,
    cc.elegivel_elite,
    cc.regularidade_percentual,
    cc.motivos_negacao
FROM public.ciclo_classificacao cc
WHERE cc.recruta_id = auth.uid()
ORDER BY cc.recruta_id, cc.ciclo_id DESC;

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.v_iea_atual;
-- SELECT * FROM public.v_iea_audit LIMIT 1;
-- SELECT * FROM public.v_classificacao_final_ciclo LIMIT 1;
-- SELECT * FROM public.v_elegibilidade_elite LIMIT 1;

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_elegibilidade_elite;
-- DROP VIEW IF EXISTS public.v_classificacao_final_ciclo;
-- DROP VIEW IF EXISTS public.v_iea_audit;
-- DROP VIEW IF EXISTS public.v_iea_atual;
-- DROP TABLE IF EXISTS public.ciclo_classificacao;
-- DROP TABLE IF EXISTS public.recruta_iea;
