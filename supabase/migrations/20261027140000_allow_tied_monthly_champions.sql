-- Approved domain rule: ties in rank() are legitimate co-champions.
-- Keep the materialized-view definition and its rows unchanged; only remove
-- the conflicting uniqueness requirement for a force/month pair.
BEGIN;

DROP INDEX IF EXISTS public.idx_mv_campeao_mensal;

CREATE INDEX idx_mv_campeao_mensal
  ON public.mv_campeao_mensal (forca, mes_referencia);

COMMIT;
