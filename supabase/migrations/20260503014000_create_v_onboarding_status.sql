-- ==============================================================================
-- CONTRATO RCC: v_onboarding_status
-- ==============================================================================
-- Propósito: Retorna o status de onboarding do recruta autenticado.
--            Usado pelo BootstrapGate quando v_identidade_recruta não retorna row
--            (recruta autenticado mas sem identidade criada — pré-onboarding).
-- Frontend: bootstrapService / BootstrapGate → getOnboardingStatus()
--           .from('v_onboarding_status').select('*').maybeSingle()
-- Retorno: recruta_id, onboarding_concluido, forca_definida, nome_guerra_definido
-- Filtro: WHERE r.id = auth.uid() — retorna no máximo 1 row
-- Data: 03/05/2026
-- ==============================================================================

CREATE OR REPLACE VIEW public.v_onboarding_status AS
SELECT
    r.id                                                  AS recruta_id,
    COALESCE(r.onboarding_concluido, false)               AS onboarding_concluido,
    (r.forca IS NOT NULL AND r.forca <> '')               AS forca_definida,
    (r.nome_guerra IS NOT NULL AND r.nome_guerra <> '')   AS nome_guerra_definido
FROM public.recrutas r
WHERE r.id = auth.uid();

-- RLS: view filtrada por auth.uid() — retorna apenas dados do usuário atual.
-- Sem política adicional necessária; a cláusula WHERE garante isolamento.

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.v_onboarding_status;

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_onboarding_status;
