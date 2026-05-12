-- ==============================================================================
-- v_app_bootstrap_institucional
-- ==============================================================================
-- Frontend: bootstrapService.ts → .from('v_app_bootstrap_institucional').select('*').limit(1)
-- Propósito: Validação de sanidade do ambiente institucional no cold start.
--            Se a view retornar sem erro, o banco está acessível e configurado.
-- Data: 03/05/2026
-- ==============================================================================

CREATE OR REPLACE VIEW public.v_app_bootstrap_institucional AS
SELECT
    -- Verificações de sanidade do ambiente
    (SELECT value FROM public.auth_app_config WHERE key = 'auth_contract_version')
                                        AS auth_contract_version,
    (SELECT COUNT(*) FROM public.modulos WHERE forca IS NOT NULL)
                                        AS total_modulos,
    (SELECT COUNT(*) FROM public.aulas)
                                        AS total_aulas,
    (SELECT COUNT(*) FROM public.medalhas WHERE ativo = true)
                                        AS total_medalhas_ativas,
    (SELECT COUNT(*) FROM public.patentes_catalogo WHERE ativo = true)
                                        AS total_patentes_ativas,
    now()                               AS timestamp_verificacao;

-- Sem RLS: a view é de leitura de metadados, sem dados de usuário.
-- O próprio Supabase exige JWT válido (authenticated) para chamar a view
-- via cliente com anon key.

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.v_app_bootstrap_institucional;

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_app_bootstrap_institucional;
