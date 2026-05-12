-- ==============================================================================
-- FIX: rpc_complete_onboarding — suporte a novo recruta (Google OAuth)
-- ==============================================================================
-- Problema: A versão anterior fazia apenas UPDATE WHERE id = auth.uid().
--           Para usuários Google OAuth recém-criados, não existe row em `recrutas`,
--           então o UPDATE afeta 0 linhas. Versão remota lançava RECRUTA_NOT_FOUND.
--
-- Solução: Substituir UPDATE por UPSERT (INSERT ... ON CONFLICT DO UPDATE).
--          O INSERT provisiona o recruta com dados mínimos obtidos do auth.users.
--          O ON CONFLICT garante idempotência para recrutas já existentes.
--
-- Contrato RCC-0.5:
--   - Frontend NÃO insere direto em recrutas
--   - Esta RPC é o único ponto de criação/atualização de recruta no onboarding
--   - Idempotente: pode ser chamada mais de uma vez com segurança
--
-- Data: 09/05/2026
-- ==============================================================================

-- DROP necessário porque a versão remota pode ter tipo de retorno diferente
-- (CREATE OR REPLACE não pode alterar RETURNS type de função existente)
DROP FUNCTION IF EXISTS public.rpc_complete_onboarding(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.rpc_complete_onboarding(
    p_forca       TEXT,
    p_nome_guerra TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id         UUID := auth.uid();
    v_forca_norm      TEXT;
    v_nome            TEXT;
    v_email           TEXT;
BEGIN
    -- Sessão obrigatória
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    -- Normaliza forca: aceita inglês (legado) e português (canônico)
    v_forca_norm := CASE p_forca
        WHEN 'navy'     THEN 'marinha'
        WHEN 'army'     THEN 'exercito'
        WHEN 'airforce' THEN 'aeronautica'
        ELSE p_forca
    END;

    IF v_forca_norm NOT IN ('marinha', 'exercito', 'aeronautica') THEN
        RAISE EXCEPTION 'INVALID_FORCA: %', p_forca;
    END IF;

    IF p_nome_guerra IS NULL OR trim(p_nome_guerra) = '' THEN
        RAISE EXCEPTION 'NOME_GUERRA_OBRIGATORIO';
    END IF;

    -- Obtém nome e email do usuário a partir dos metadados do Supabase Auth.
    -- Google OAuth preenche raw_user_meta_data com 'full_name' ou 'name'.
    SELECT
        COALESCE(
            NULLIF(trim(u.raw_user_meta_data->>'full_name'), ''),
            NULLIF(trim(u.raw_user_meta_data->>'name'), ''),
            NULLIF(trim(u.email), ''),
            'Recruta'
        ),
        COALESCE(NULLIF(trim(u.email), ''), 'sem-email@quarteldigital.local')
    INTO v_nome, v_email
    FROM auth.users u
    WHERE u.id = v_user_id;

    -- UPSERT: cria recruta se não existir, atualiza se já existir.
    -- Columns not listed here use their table defaults (xp=0, xp_total=0, etc.)
    INSERT INTO public.recrutas (
        id,
        auth_id,
        email,
        nome,
        forca,
        nome_guerra,
        onboarding_concluido
    )
    VALUES (
        v_user_id,
        v_user_id,
        v_email,
        v_nome,
        v_forca_norm,
        trim(p_nome_guerra),
        true
    )
    ON CONFLICT (id) DO UPDATE SET
        forca                = EXCLUDED.forca,
        nome_guerra          = EXCLUDED.nome_guerra,
        onboarding_concluido = true;
    -- nome, auth_id e email NÃO são sobrescritos no UPDATE para preservar dados existentes
END;
$$;

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- -- Novo recruta Google (sem row em recrutas):
-- SELECT public.rpc_complete_onboarding('marinha', 'TIGRE');
-- SELECT * FROM public.recrutas WHERE id = auth.uid();
--
-- -- Idempotência (recruta já existente):
-- SELECT public.rpc_complete_onboarding('exercito', 'LOBO');
-- SELECT * FROM public.recrutas WHERE id = auth.uid();
--
-- -- Força inválida (deve lançar INVALID_FORCA):
-- SELECT public.rpc_complete_onboarding('invalid', 'TIGRE');
--
-- -- Nome de guerra vazio (deve lançar NOME_GUERRA_OBRIGATORIO):
-- SELECT public.rpc_complete_onboarding('marinha', '');

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- Restaurar versão anterior (UPDATE simples, sem criação de recruta):
-- CREATE OR REPLACE FUNCTION public.rpc_complete_onboarding(p_forca TEXT, p_nome_guerra TEXT)
-- RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
-- DECLARE v_forca_normalizada TEXT;
-- BEGIN
--     v_forca_normalizada := CASE p_forca WHEN 'navy' THEN 'marinha' WHEN 'army' THEN 'exercito' WHEN 'airforce' THEN 'aeronautica' ELSE p_forca END;
--     IF v_forca_normalizada NOT IN ('marinha','exercito','aeronautica') THEN RAISE EXCEPTION 'INVALID_FORCA: %', p_forca; END IF;
--     IF p_nome_guerra IS NULL OR trim(p_nome_guerra) = '' THEN RAISE EXCEPTION 'NOME_GUERRA_OBRIGATORIO'; END IF;
--     UPDATE public.recrutas SET forca = v_forca_normalizada, nome_guerra = trim(p_nome_guerra), onboarding_concluido = true WHERE id = auth.uid();
-- END; $$;
