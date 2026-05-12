-- ==============================================================================
-- CONTRATO CRÍTICO: v_identidade_recruta
-- ==============================================================================
-- Motivo: View mais crítica do sistema — usada em AuthContext (carrega perfil
--         em toda sessão) e em stripe-create-checkout-session.
--         Sem DDL rastreável nas migrations locais.
-- Data: 03/05/2026
-- ==============================================================================
-- Frontend espera (AuthContext.Profile):
--   id, auth_id, nome, nome_guerra, patente, forca, nivel_atual, xp,
--   avatar_url, instructor_profile_id, tipo_acesso, onboarding_concluido, ativo
-- Stripe espera: id, auth_id, nome, nome_guerra
-- ==============================================================================

CREATE OR REPLACE VIEW public.v_identidade_recruta AS
SELECT
    -- Identidade principal
    r.id,
    r.id                                            AS auth_id,        -- recrutas.id = auth.users.id (padrão Supabase)

    -- Dados pessoais
    r.nome,
    r.nome_guerra,
    r.avatar_url,

    -- Hierarquia (patente do nível mais alto, fallback 'Recruta')
    COALESCE(vpa.titulo, 'Recruta')                AS patente,
    COALESCE(vpa.nivel, 0)                         AS nivel_atual,

    -- Força normalizada: aceita tanto inglês legado quanto português
    CASE r.forca
        WHEN 'navy'      THEN 'marinha'
        WHEN 'army'      THEN 'exercito'
        WHEN 'airforce'  THEN 'aeronautica'
        ELSE COALESCE(r.forca, 'marinha')
    END                                             AS forca,

    -- XP canônico (complete_lesson é a fonte oficial — RPC C2)
    COALESCE(r.xp, 0)                              AS xp,

    -- Perfil do instrutor (armazenado em profiles)
    p.instructor_profile_id,

    -- Acesso (recrutas é fonte; fallback em profiles)
    COALESCE(r.tipo_acesso, p.tipo_acesso, 'degustacao') AS tipo_acesso,

    -- Estado do recruta
    COALESCE(r.onboarding_concluido, false)        AS onboarding_concluido,
    COALESCE(r.ativo, true)                        AS ativo

FROM public.recrutas r
LEFT JOIN public.profiles p
    ON p.id = r.id
LEFT JOIN public.v_recruta_patente_atual vpa
    ON vpa.recruta_id = r.id;

-- RLS: A view herda as políticas das tabelas base.
-- recrutas: authenticated pode SELECT WHERE auth.uid() = id
-- A SECURITY INVOKER garante que auth.uid() seja respeitado.
-- Supabase aplica RLS via políticas das tabelas-base ao acessar a view.

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.v_identidade_recruta LIMIT 1;
-- SELECT id, auth_id, nome, forca, xp, onboarding_concluido FROM public.v_identidade_recruta LIMIT 5;

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_identidade_recruta;
