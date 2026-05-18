-- =============================================================================
-- Migration:  20260517001000_p1_m1_create_rpc_complete_lesson.sql
-- Classificação: P1-M1 — Sprint 2 / Fase 1
-- Data:       2026-05-17
-- Autor:      institutional-audit-2026-05-17
-- Revisão:    AGUARDANDO APROVAÇÃO — não executar sem aprovação institucional
-- =============================================================================
--
-- OBJETIVO
-- --------
-- Criar public.rpc_complete_lesson(p_lesson_id uuid), nova RPC 100%
-- server-authoritative que substitui progressivamente complete_lesson(..., p_xp).
--
-- A nova RPC:
--   - usa auth.uid() como única fonte de recruta_id (sem parâmetro externo)
--   - busca aulas.xp_valor como única fonte de XP (sem parâmetro externo)
--   - bloqueia unauthenticated, aula inexistente e xp_valor < 0
--   - preserva idempotência via ON CONFLICT + ux_xp_eventos_lesson_unique
--   - coexiste com complete_lesson durante o período de transição
--
-- PREDECESSOR
-- -----------
-- P0-M6 — 20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql
--   (auth guard aplicado em complete_lesson — esta migration é o próximo passo)
--
-- O QUE NÃO MUDA
-- ---------------
-- - complete_lesson NÃO é removida — coexistência durante Sprint 2
-- - Frontend NÃO é alterado por esta migration
-- - Tabelas recruta_progresso e xp_eventos não têm DDL alterado
-- - Views de ranking, histórico e medalhas: sem mudança
--
-- CONSTRAINTS CRÍTICAS CONFIRMADAS NO DUMP (justificam decisões no corpo)
-- ------------------------------------------------------------------------
-- xp_eventos (dump ln 10756–10766):
--   CONSTRAINT "xp_eventos_quantidade_check" CHECK (quantidade > 0)
--   CONSTRAINT "xp_eventos_forca_check" CHECK (forca = ANY (...))
-- recruta_progresso (dump ln 11094–11104):
--   CONSTRAINT "recruta_progresso_status_check" CHECK (status = 'completed')
--   UNIQUE (recruta_id, lesson_id) — ln 15512
-- Unique index idempotência (dump ln 16464):
--   ux_xp_eventos_lesson_unique ON (recruta_id, referencia_id)
--   WHERE origem = 'lesson_complete'
-- recrutas (dump ln 8365–8385):
--   id = auth.uid() por convenção institucional (MEMORY.md)
--   forca CHECK (marinha/exercito/aeronautica) — NOT NULL
--
-- IDEMPOTÊNCIA DA MIGRATION
-- --------------------------
-- CREATE OR REPLACE FUNCTION: reexecução é no-op seguro
-- INSERT ON CONFLICT (contract_name) DO NOTHING: idem
-- REVOKE/GRANT: idempotentes por natureza no PostgreSQL
--
-- RISCO
-- -----
-- BAIXO — cria função nova sem alterar objetos existentes.
-- Reversão: DROP FUNCTION + DELETE do registry.
--
-- REFERÊNCIAS
-- -----------
-- Spec arquitetural:    supabase/baseline/P1_M1_COMPLETE_LESSON_XP_REFACTOR.md
-- Plano de transição:   supabase/baseline/P1_M1_TRANSITION_PLAN.md
-- Auditoria xp_valor:   supabase/baseline/P1_M1_XP_VALOR_AUDIT.md
-- Handoff desta migration: supabase/baseline/P1_M1_HANDOFF.md
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PASSO 1 — Criar rpc_complete_lesson
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_complete_lesson(
    p_lesson_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_recruta_id   uuid;
    v_forca        text;
    v_xp_valor     integer;
    v_ja_concluida boolean;
BEGIN

    -- ── GUARDA 1 — autenticação obrigatória ──────────────────────────────────
    -- auth.uid() retorna NULL quando chamada sem JWT (service_role sem contexto).
    -- Diferente de complete_lesson (que permite NULL para service_role), esta
    -- função é estritamente para callers autenticados. Qualquer chamada sem JWT
    -- é bloqueada com 42501 (insufficient_privilege).
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION
            'Authentication required: rpc_complete_lesson requires a valid JWT session'
            USING ERRCODE = '42501';
    END IF;

    -- ── Derivar recruta_id do JWT ─────────────────────────────────────────────
    -- Por convenção institucional: recrutas.id = auth.uid().
    -- Não há parâmetro externo de recruta — a identidade é derivada do JWT.
    v_recruta_id := auth.uid();

    -- ── GUARDA 2 — recruta deve existir e ter forca definida ─────────────────
    -- Busca forca: necessária para xp_eventos.forca (CHECK constraint).
    -- Se recruta não existe: onboarding não concluído ou conta inválida.
    -- Se forca IS NULL: onboarding incompleto (forca não foi definida).
    SELECT r.forca
    INTO   v_forca
    FROM   public.recrutas r
    WHERE  r.id = v_recruta_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Recruta profile not found for authenticated user. Complete registration first.'
            USING ERRCODE = '22023';
    END IF;

    IF v_forca IS NULL THEN
        RAISE EXCEPTION
            'Recruta forca is not defined. Complete onboarding (rpc_complete_onboarding) first.'
            USING ERRCODE = '22023';
    END IF;

    -- ── GUARDA 3 — aula deve existir ─────────────────────────────────────────
    -- Busca xp_valor: única fonte de XP na nova arquitetura.
    -- Se a aula não existe: UUID inválido ou aula foi deletada.
    SELECT a.xp_valor
    INTO   v_xp_valor
    FROM   public.aulas a
    WHERE  a.id = p_lesson_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Lesson not found: %. Verify the lesson UUID is correct.',
            p_lesson_id
            USING ERRCODE = '22023';
    END IF;

    -- ── GUARDA 4 — xp_valor não pode ser negativo ────────────────────────────
    -- xp_eventos.quantidade CHECK (quantidade > 0) proíbe inserção com xp = 0.
    -- Valor negativo indica dado corrompido e deve ser bloqueado explicitamente
    -- antes de tentar qualquer DML — protege contra violação de constraint.
    -- xp_valor = 0 é válido (aula informacional sem XP) — tratado abaixo.
    IF v_xp_valor < 0 THEN
        RAISE EXCEPTION
            'Invalid xp_valor for lesson %: value is negative (%). Contact admin to fix aulas.xp_valor.',
            p_lesson_id, v_xp_valor
            USING ERRCODE = '22023';
    END IF;

    -- ── Verificação de idempotência ──────────────────────────────────────────
    -- Chamar a função duas vezes com o mesmo (recruta_id, lesson_id) deve
    -- ser seguro: retorna sucesso sem duplicar progresso ou XP.
    SELECT EXISTS (
        SELECT 1
        FROM   public.recruta_progresso rp
        WHERE  rp.recruta_id   = v_recruta_id
          AND  rp.lesson_id    = p_lesson_id
          AND  rp.completed_at IS NOT NULL
    ) INTO v_ja_concluida;

    IF v_ja_concluida THEN
        RETURN json_build_object(
            'status',     'ok',
            'xp_granted', false,
            'xp_added',   0,
            'message',    'Aula já concluída anteriormente'
        );
    END IF;

    -- ── PASSO A — Registrar conclusão em recruta_progresso ───────────────────
    -- ON CONFLICT (recruta_id, lesson_id) DO NOTHING:
    --   Protege contra race condition entre a verificação acima e este INSERT.
    --   Se outra request concorrente inseriu no intervalo, este INSERT é no-op.
    -- source = 'rpc_complete_lesson': identifica registros da nova RPC
    --   (diferente de 'lesson_complete' = complete_lesson, 'lesson_completion' = default).
    INSERT INTO public.recruta_progresso (
        recruta_id,
        lesson_id,
        status,
        completed_at,
        xp_granted,
        source
    )
    VALUES (
        v_recruta_id,
        p_lesson_id,
        'completed',           -- CHECK constraint: único valor aceito
        now(),
        v_xp_valor,            -- valor institucional de aulas.xp_valor (pode ser 0)
        'rpc_complete_lesson'  -- identifica a nova RPC como origem
    )
    ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

    -- ── PASSO B — Conceder XP canônico em xp_eventos ─────────────────────────
    -- Executado APENAS quando xp_valor > 0.
    --
    -- Razão: xp_eventos.quantidade CHECK (quantidade > 0) — inserir 0 violaria
    -- a constraint e causaria erro. Aulas com xp_valor = 0 são válidas (informacionais)
    -- mas não geram entrada em xp_eventos, pois não há XP a registrar.
    --
    -- ON CONFLICT DO NOTHING reutiliza o índice de idempotência:
    --   ux_xp_eventos_lesson_unique ON (recruta_id, referencia_id)
    --   WHERE origem = 'lesson_complete'
    -- Garante que reexecução não duplica XP mesmo sem a verificação acima.
    IF v_xp_valor > 0 THEN
        INSERT INTO public.xp_eventos (
            recruta_id,
            forca,
            quantidade,
            origem,
            referencia_id
        )
        VALUES (
            v_recruta_id,
            v_forca,        -- lido de recrutas.forca (válido por CHECK constraint)
            v_xp_valor,     -- lido de aulas.xp_valor (> 0 confirmado pela condição)
            'lesson_complete',
            p_lesson_id
        )
        ON CONFLICT DO NOTHING;
    END IF;

    -- ── Retorno ──────────────────────────────────────────────────────────────
    -- xp_granted: true  → XP foi concedido (v_xp_valor > 0, primeira conclusão)
    -- xp_granted: false → Aula informacional (v_xp_valor = 0, ainda primeira conclusão)
    -- xp_added:   valor real de aulas.xp_valor (0 ou positivo)
    RETURN json_build_object(
        'status',     'ok',
        'xp_granted', (v_xp_valor > 0),
        'xp_added',   v_xp_valor
    );

END;
$$;

-- -----------------------------------------------------------------------------
-- PASSO 2 — Ajustar grants
-- -----------------------------------------------------------------------------
-- REVOKE ALL FROM PUBLIC: fecha acesso padrão herdado.
-- GRANT EXECUTE TO authenticated: frontend pode chamar via supabase.rpc().
--   Com a GUARDA 1 (auth.uid() IS NOT NULL), authenticated + JWT válido é o
--   único caminho funcional.
-- GRANT EXECUTE TO service_role: permite chamadas administrativas com JWT de
--   usuário específico (ex: scripts de seed com impersonation via Supabase Admin API).
--   Chamadas de service_role SEM JWT são bloqueadas pela GUARDA 1.

REVOKE ALL    ON FUNCTION public.rpc_complete_lesson(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_complete_lesson(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_complete_lesson(uuid) TO service_role;

-- -----------------------------------------------------------------------------
-- PASSO 3 — Registrar em c6_contract_registry
-- -----------------------------------------------------------------------------
-- Status: 'canonical' — contrato ativo e aprovado institucionalmente.
-- ON CONFLICT DO NOTHING: idempotente para reexecuções.
-- Nota: complete_lesson será marcada 'legacy' no registry em Sprint 3
--       (após migração total do frontend).

INSERT INTO public.c6_contract_registry (
    contract_name,
    contract_type,
    status,
    frontend_scope,
    notes,
    registered_at,
    updated_at
)
VALUES (
    'rpc_complete_lesson',
    'rpc',
    'canonical',
    'conclusão de aula — substitui complete_lesson (P1-M1 Sprint 2)',
    'Server-authoritative: auth.uid() como recruta_id, aulas.xp_valor como XP. '
    'GRANT EXECUTE TO authenticated. '
    'Requer onboarding concluído (forca definida). '
    'xp_valor=0: lesson registrada mas xp_eventos não inserido (CHECK quantidade>0). '
    'Depreca complete_lesson — mantida em coexistência durante Sprint 2.',
    now(),
    now()
)
ON CONFLICT (contract_name) DO NOTHING;

-- =============================================================================
-- TESTES SQL PÓS-APPLY (executar após migration — NÃO parte da migration)
-- =============================================================================
--
-- TESTE 1 — Função existe com SECURITY DEFINER e search_path correto?
--
--   SELECT p.proname, p.prosecdef, p.proconfig,
--          pg_get_function_identity_arguments(p.oid) AS assinatura
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'rpc_complete_lesson';
--   -- Esperado: prosecdef=true, proconfig={search_path=public}, assinatura='p_lesson_id uuid'
--
-- TESTE 2 — Grant para authenticated existe?
--
--   SELECT has_function_privilege(
--       'authenticated',
--       'public.rpc_complete_lesson(uuid)',
--       'EXECUTE'
--   );
--   -- Esperado: true
--
-- TESTE 3 — Grant para anon revogado?
--
--   SELECT has_function_privilege(
--       'anon',
--       'public.rpc_complete_lesson(uuid)',
--       'EXECUTE'
--   );
--   -- Esperado: false
--
-- TESTE 4 — complete_lesson ainda existe (não foi removida)?
--
--   SELECT proname FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'complete_lesson';
--   -- Esperado: 1 linha
--
-- TESTE 5 — Registry atualizado?
--
--   SELECT contract_name, contract_type, status, notes
--   FROM public.c6_contract_registry
--   WHERE contract_name = 'rpc_complete_lesson';
--   -- Esperado: 1 linha, status = 'canonical'
--
-- TESTE 6 — Corpo contém as 4 guardas críticas?
--
--   SELECT
--     pg_get_functiondef(p.oid) LIKE '%auth.uid() IS NULL%'      AS guarda_auth,
--     pg_get_functiondef(p.oid) LIKE '%NOT FOUND%'               AS guarda_not_found,
--     pg_get_functiondef(p.oid) LIKE '%v_xp_valor < 0%'          AS guarda_xp_negativo,
--     pg_get_functiondef(p.oid) LIKE '%v_xp_valor > 0%'          AS condicional_xp
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'rpc_complete_lesson';
--   -- Esperado: todas true
--
-- TESTE 7 — [STAGING] Guarda 1: sem JWT retorna 42501?
--
--   -- Executar via SQL Editor como service_role sem JWT de usuário:
--   SELECT public.rpc_complete_lesson('<qualquer_uuid>');
--   -- Esperado: ERROR 42501 — "Authentication required: ..."
--
-- TESTE 8 — [STAGING] Fluxo legítimo: autenticado conclui aula?
--
--   -- Executar como authenticated via SQL Editor (Run as User):
--   SELECT public.rpc_complete_lesson('<uuid_de_aula_com_xp_valor_positivo>');
--   -- Esperado: {"status":"ok","xp_granted":true,"xp_added":<xp_valor_da_aula>}
--
-- TESTE 9 — [STAGING] Idempotência: segunda chamada não duplica XP?
--
--   SELECT public.rpc_complete_lesson('<uuid_aula>');  -- 1ª
--   SELECT public.rpc_complete_lesson('<uuid_aula>');  -- 2ª
--   -- 2ª esperado: {"status":"ok","xp_granted":false,"xp_added":0,"message":"Aula já concluída anteriormente"}
--   SELECT COUNT(*) FROM public.xp_eventos
--   WHERE recruta_id = auth.uid() AND referencia_id = '<uuid_aula>'
--     AND origem = 'lesson_complete';
--   -- Esperado: 1 (não duplicou)
--
-- TESTE 10 — [STAGING] xp_valor = 0: lesson registrada sem inserção em xp_eventos?
--
--   -- Usar aula com xp_valor = 0 (ver Q-03 da auditoria)
--   SELECT public.rpc_complete_lesson('<uuid_aula_xp_zero>');
--   -- Esperado: {"status":"ok","xp_granted":false,"xp_added":0}
--   SELECT COUNT(*) FROM public.recruta_progresso
--   WHERE recruta_id = auth.uid() AND lesson_id = '<uuid_aula_xp_zero>'
--     AND status = 'completed';
--   -- Esperado: 1 (lesson registrada)
--   SELECT COUNT(*) FROM public.xp_eventos
--   WHERE recruta_id = auth.uid() AND referencia_id = '<uuid_aula_xp_zero>'
--     AND origem = 'lesson_complete';
--   -- Esperado: 0 (sem entrada em xp_eventos — CHECK quantidade>0 seria violado)
--
-- TESTE 11 — [STAGING] Aula inexistente retorna erro?
--
--   SELECT public.rpc_complete_lesson('00000000-0000-0000-0000-000000000000');
--   -- Esperado: ERROR 22023 — "Lesson not found: ..."
--
-- TESTE 12 — source em recruta_progresso é 'rpc_complete_lesson'?
--
--   SELECT source FROM public.recruta_progresso
--   WHERE lesson_id = '<uuid_aula_testada>'
--     AND recruta_id = auth.uid();
--   -- Esperado: 'rpc_complete_lesson' (não 'lesson_complete' nem 'lesson_completion')
--
-- =============================================================================
-- ROLLBACK (executar APENAS se a migration precisar ser revertida)
-- =============================================================================
--
-- DROP FUNCTION IF EXISTS public.rpc_complete_lesson(uuid);
--
-- DELETE FROM public.c6_contract_registry
-- WHERE contract_name = 'rpc_complete_lesson';
--
-- Verificação pós-rollback:
--   SELECT proname FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'rpc_complete_lesson';
--   -- Esperado: 0 linhas
--
--   SELECT contract_name FROM public.c6_contract_registry
--   WHERE contract_name = 'rpc_complete_lesson';
--   -- Esperado: 0 linhas
--
-- Impacto do rollback: ZERO para o usuário final — frontend ainda usa complete_lesson.
--
-- =============================================================================
-- REFERÊNCIAS
-- =============================================================================
-- Spec arquitetural:     supabase/baseline/P1_M1_COMPLETE_LESSON_XP_REFACTOR.md
-- Plano de transição:    supabase/baseline/P1_M1_TRANSITION_PLAN.md
-- Auditoria xp_valor:    supabase/baseline/P1_M1_XP_VALOR_AUDIT.md
-- Handoff:               supabase/baseline/P1_M1_HANDOFF.md
-- Predecessor P0-M6:     supabase/migrations/20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql
-- aulas DDL (ln 9075):   supabase/remote/supabase_remote_schema.sql
-- xp_eventos DDL (ln 10756): supabase/remote/supabase_remote_schema.sql
-- recruta_progresso (ln 11094): supabase/remote/supabase_remote_schema.sql
-- ux_xp_eventos_lesson_unique (ln 16464): supabase/remote/supabase_remote_schema.sql
-- =============================================================================
