-- ==============================================================================
-- RPCs INSTITUCIONAIS PARA SUBSTITUIR ESCRITAS DIRETAS DO FRONTEND
-- ==============================================================================
-- Motivo: Frontend (progressService, onboardingService, profileService) fazem
--         escritas diretas em tabelas sem passar por RPCs. Isso viola banco-first.
-- Cria:
--   - rpc_complete_onboarding       (onboardingService)
--   - rpc_set_instructor_profile    (profileService)
--   - rpc_start_module              (progressService.startModule)
--   - rpc_complete_module           (progressService.completeModule)
-- Data: 03/05/2026
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. rpc_complete_onboarding
-- Substitui: onboardingService.ts → recrutas.update({forca, nome_guerra, onboarding_concluido})
-- Idempotente: UPDATE é naturalmente idempotente (sobrescreve mesmo valor)
-- Auditoria: campo onboarding_concluido registra estado permanentemente
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_complete_onboarding(
    p_forca       TEXT,
    p_nome_guerra TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_forca_normalizada TEXT;
BEGIN
    -- Normaliza forca: aceita tanto inglês quanto português
    v_forca_normalizada := CASE p_forca
        WHEN 'navy'       THEN 'marinha'
        WHEN 'army'       THEN 'exercito'
        WHEN 'airforce'   THEN 'aeronautica'
        ELSE p_forca
    END;

    IF v_forca_normalizada NOT IN ('marinha','exercito','aeronautica') THEN
        RAISE EXCEPTION 'INVALID_FORCA: %', p_forca;
    END IF;

    IF p_nome_guerra IS NULL OR trim(p_nome_guerra) = '' THEN
        RAISE EXCEPTION 'NOME_GUERRA_OBRIGATORIO';
    END IF;

    UPDATE public.recrutas
    SET
        forca                = v_forca_normalizada,
        nome_guerra          = trim(p_nome_guerra),
        onboarding_concluido = true
    WHERE id = auth.uid();
END;
$$;

-- ------------------------------------------------------------------------------
-- 2. rpc_set_instructor_profile
-- Substitui: profileService.ts → profiles.update({instructor_profile_id})
-- Idempotente: UPDATE é idempotente (mesmo valor = sem efeito)
-- Auditoria: campo no profiles com constraint CHECK
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_set_instructor_profile(
    p_instructor_id TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_instructor_id NOT IN ('objetivo','estrategico','didatico') THEN
        RAISE EXCEPTION 'INVALID_INSTRUCTOR_PROFILE: %', p_instructor_id;
    END IF;

    UPDATE public.profiles
    SET instructor_profile_id = p_instructor_id
    WHERE id = auth.uid();
END;
$$;

-- ------------------------------------------------------------------------------
-- 3. rpc_start_module
-- Substitui: progressService.startModule → recruta_modulos.upsert(...)
-- Idempotente: ON CONFLICT DO NOTHING (não sobrescreve first_access_at)
-- Auditoria: recruta_modulos registra first_access_at
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_start_module(
    p_modulo_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_modulo_id IS NULL THEN RETURN; END IF;

    INSERT INTO public.recruta_modulos (
        recruta_id, modulo_id, first_access_at, status
    )
    VALUES (
        auth.uid(), p_modulo_id, now(), 'in_progress'
    )
    ON CONFLICT (recruta_id, modulo_id) DO NOTHING;
    -- Não sobrescreve first_access_at se o módulo já foi iniciado
END;
$$;

-- ------------------------------------------------------------------------------
-- 4. rpc_complete_module
-- Substitui: progressService.completeModule → recruta_modulos.update(...)
-- Idempotente: WHERE status != 'completed' evita sobrescrever completed_at
-- Auditoria: completed_at registra data de conclusão
-- NOTA: O bônus de XP de módulo (500 XP via registrar_xp) continua sendo
--       responsabilidade do cliente por ora — sem lógica nova aqui.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_complete_module(
    p_modulo_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_modulo_id IS NULL THEN RETURN; END IF;

    UPDATE public.recruta_modulos
    SET
        completed_at = now(),
        status       = 'completed'
    WHERE recruta_id = auth.uid()
      AND modulo_id  = p_modulo_id
      AND status    != 'completed';  -- Idempotência: não re-completa
END;
$$;

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT public.rpc_complete_onboarding('marinha', 'TIGRE');
-- SELECT public.rpc_set_instructor_profile('objetivo');
-- SELECT public.rpc_start_module('<uuid>');
-- SELECT public.rpc_complete_module('<uuid>');

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP FUNCTION IF EXISTS public.rpc_complete_module(UUID);
-- DROP FUNCTION IF EXISTS public.rpc_start_module(UUID);
-- DROP FUNCTION IF EXISTS public.rpc_set_instructor_profile(TEXT);
-- DROP FUNCTION IF EXISTS public.rpc_complete_onboarding(TEXT, TEXT);
