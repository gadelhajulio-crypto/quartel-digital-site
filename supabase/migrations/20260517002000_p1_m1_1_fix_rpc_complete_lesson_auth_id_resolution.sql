-- =============================================================================
-- Migration:  20260517002000_p1_m1_1_fix_rpc_complete_lesson_auth_id_resolution.sql
-- Classificação: P1-M1.1 — Sprint 2 / Fase 1B (hotfix de resolução de identidade)
-- Data:       2026-05-18
-- Autor:      institutional-audit-2026-05-18
-- Predecessora: 20260517001000_p1_m1_create_rpc_complete_lesson.sql
-- =============================================================================
--
-- PROBLEMA IDENTIFICADO
-- ---------------------
-- A versão P1-M1 de rpc_complete_lesson resolvia v_recruta_id com:
--
--     v_recruta_id := auth.uid();
--     SELECT r.forca INTO v_forca FROM public.recrutas r WHERE r.id = v_recruta_id;
--
-- Isso pressupõe recrutas.id = auth.users.id (convencão institucional documentada
-- em MEMORY.md). Porém o schema remoto confirma que recrutas.id é um UUID gerado
-- independentemente (DEFAULT gen_random_uuid()), e a coluna de vínculo com Auth é
-- recrutas.auth_id.
--
-- Achado durante Fase 1B (teste com GADELHA):
--   auth.users.id  = 918c08f3-8e08-4dc7-a102-da5c729a6ead
--   recrutas.id    = cc41fc7e-ce7d-405d-9178-c14b39e1a017  ← diferente
--   recrutas.auth_id = 918c08f3-8e08-4dc7-a102-da5c729a6ead  ← = auth.uid()
--
-- Consequência: a Guarda 2 retornava NOT FOUND para GADELHA e qualquer recruta
-- criado antes da convenção id=auth.uid() (usuários legados). A função era
-- inutilizável para esses usuários.
--
-- CORREÇÃO
-- --------
-- Substituir a atribuição direta e o SELECT separado por um único SELECT que
-- resolve TANTO v_recruta_id QUANTO v_forca em uma operação, usando auth_id
-- como chave de vínculo primária com fallback para r.id (defesa em profundidade):
--
--     SELECT r.id, r.forca
--     INTO   v_recruta_id, v_forca
--     FROM   public.recrutas r
--     WHERE  r.auth_id = auth.uid()
--        OR  r.id      = auth.uid()
--     ORDER BY (r.auth_id = auth.uid()) DESC  -- preferir auth_id match
--     LIMIT 1;
--
-- Justificativa do fallback (r.id = auth.uid()):
--   rpc_complete_onboarding insere id = auth.uid() E auth_id = auth.uid() para
--   novos usuários. Para eles, AMBAS as condições serão verdadeiras — a cláusula
--   ORDER BY garante que o registro correto é retornado sem LIMIT causar ambiguidade.
--   O fallback cobre o caso hipotético de um usuário onde auth_id não foi preenchido
--   mas id = auth.uid() (padrão anterior à migração do schema).
--
-- Justificativa do LIMIT 1:
--   recrutas.auth_id tem UNIQUE constraint (recrutas_auth_id_unique + recrutas_auth_unique
--   confirmadas no dump ln 15532–15537). No máximo 1 linha satisfará a condição
--   auth_id = auth.uid(). O LIMIT protege apenas contra o fallback hipotético.
--
-- O QUE NÃO MUDA
-- ---------------
-- - Assinatura: rpc_complete_lesson(p_lesson_id uuid) RETURNS json — idêntica
-- - SECURITY DEFINER: mantido
-- - SET search_path TO 'public': mantido
-- - Guarda 1 (auth.uid() IS NULL → 42501): idêntica
-- - Guarda 2 (NOT FOUND → 22023): idêntica em semântica, condensada em 1 SELECT
-- - Guarda 2b (forca IS NULL → 22023): idêntica
-- - Guarda 3 (aula não existe → 22023): idêntica
-- - Guarda 4 (xp_valor < 0 → 22023): idêntica
-- - Idempotência (SELECT EXISTS + ON CONFLICT): idêntica
-- - PASSO A (INSERT recruta_progresso): idêntico — v_recruta_id agora correto
-- - PASSO B (INSERT xp_eventos): idêntico — v_recruta_id e v_forca agora corretos
-- - Retorno JSON: idêntico
-- - Grants: idênticos (REVOKE/GRANT idempotentes)
-- - complete_lesson: NÃO removida — coexistência durante Sprint 2
-- - Frontend: NÃO alterado
-- - DDL de recruta_progresso, xp_eventos, views: sem mudança
--
-- IDEMPOTÊNCIA DA MIGRATION
-- --------------------------
-- CREATE OR REPLACE FUNCTION: reexecução é no-op seguro
-- UPDATE c6_contract_registry: idempotente (append de texto em notes)
-- REVOKE/GRANT: idempotentes por natureza no PostgreSQL
--
-- RISCO
-- -----
-- BAIXO — substitui apenas o corpo da função sem alterar assinatura, tabelas ou grants.
-- Reversão: reexecutar 20260517001000_p1_m1_create_rpc_complete_lesson.sql (restaura
-- a versão anterior com v_recruta_id := auth.uid()).
--
-- REFERÊNCIAS
-- -----------
-- Predecessora:          supabase/migrations/20260517001000_p1_m1_create_rpc_complete_lesson.sql
-- Handoff P1-M1.1:       supabase/baseline/P1_M1_1_HANDOFF.md
-- Handoff P1-M1:         supabase/baseline/P1_M1_HANDOFF.md
-- Schema remoto recrutas (ln 8365–8385): supabase/remote/supabase_remote_schema.sql
-- Constraints auth_id (ln 15532–15537):  supabase/remote/supabase_remote_schema.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PASSO 1 — Recriar rpc_complete_lesson com resolução correta de auth_id
-- -----------------------------------------------------------------------------
-- CREATE OR REPLACE preserva owner, dependências e grants existentes.
-- Apenas o corpo ($$...$$) e a lógica de resolução de v_recruta_id são alterados.
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

    -- ── GUARDA 2 — resolver recruta_id via auth_id + validar forca ───────────
    -- CORREÇÃO P1-M1.1: recrutas.id != auth.users.id para usuários legados.
    -- A coluna de vínculo canônica é recrutas.auth_id (UNIQUE constraint
    -- recrutas_auth_id_unique confirmada no dump ln 15532).
    --
    -- Estratégia de resolução (ordem de preferência):
    --   1. r.auth_id = auth.uid()  → caminho canônico (todos os usuários com
    --      auth_id preenchido, incluindo legados como GADELHA)
    --   2. r.id = auth.uid()       → fallback para usuários criados via
    --      rpc_complete_onboarding (insere id = auth.uid() E auth_id = auth.uid())
    --      e para qualquer padrão legado onde id = auth.uid()
    --
    -- ORDER BY (r.auth_id = auth.uid()) DESC garante que, se dois registros
    -- coincidirem (hipotético), o registro com auth_id correto tem prioridade.
    -- LIMIT 1: auth_id é UNIQUE — no máximo 1 linha satisfará a condição primária.
    --
    -- Em um único SELECT: resolve v_recruta_id (recrutas.id canônico para DML
    -- em recruta_progresso e xp_eventos) E v_forca (necessária para xp_eventos
    -- CHECK constraint). Elimina o SELECT separado da versão anterior.
    SELECT r.id, r.forca
    INTO   v_recruta_id, v_forca
    FROM   public.recrutas r
    WHERE  r.auth_id = auth.uid()
       OR  r.id      = auth.uid()
    ORDER BY (r.auth_id = auth.uid()) DESC
    LIMIT 1;

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
    -- v_recruta_id agora é recrutas.id canônico (correto para joins em
    -- recruta_progresso.recruta_id e xp_eventos.recruta_id).
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
    -- v_recruta_id = recrutas.id canônico (resolvido pela Guarda 2 corrigida).
    -- ON CONFLICT (recruta_id, lesson_id) DO NOTHING protege contra race condition.
    -- source = 'rpc_complete_lesson': rastreabilidade da nova RPC.
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
        'completed',
        now(),
        v_xp_valor,
        'rpc_complete_lesson'
    )
    ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

    -- ── PASSO B — Conceder XP canônico em xp_eventos ─────────────────────────
    -- Executado APENAS quando xp_valor > 0.
    -- xp_eventos.quantidade CHECK (quantidade > 0): inserir 0 violaria constraint.
    -- ON CONFLICT DO NOTHING usa ux_xp_eventos_lesson_unique:
    --   ON public.xp_eventos (recruta_id, referencia_id) WHERE origem = 'lesson_complete'
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
            v_forca,
            v_xp_valor,
            'lesson_complete',
            p_lesson_id
        )
        ON CONFLICT DO NOTHING;
    END IF;

    -- ── Retorno ──────────────────────────────────────────────────────────────
    RETURN json_build_object(
        'status',     'ok',
        'xp_granted', (v_xp_valor > 0),
        'xp_added',   v_xp_valor
    );

END;
$$;

-- -----------------------------------------------------------------------------
-- PASSO 2 — Reafirmar grants (idempotente — sem mudança em relação a P1-M1)
-- -----------------------------------------------------------------------------
-- CREATE OR REPLACE preserva grants existentes, mas REVOKE/GRANT são reafirmados
-- explicitamente para garantir estado correto mesmo após eventual DROP acidental.

REVOKE ALL    ON FUNCTION public.rpc_complete_lesson(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_complete_lesson(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_complete_lesson(uuid) TO service_role;

-- -----------------------------------------------------------------------------
-- PASSO 3 — Atualizar registry com nota de correção
-- -----------------------------------------------------------------------------
-- O contrato já está registrado como 'canonical' por P1-M1.
-- Apenas adiciona nota de rastreabilidade do hotfix.

UPDATE public.c6_contract_registry
SET    notes      = notes || ' | P1-M1.1 2026-05-18: fixed auth_id resolution — v_recruta_id now resolved via recrutas.auth_id = auth.uid() with fallback r.id = auth.uid().',
       updated_at = now()
WHERE  contract_name = 'rpc_complete_lesson';

-- =============================================================================
-- TESTES SQL PÓS-APPLY (executar após migration — NÃO parte da migration)
-- =============================================================================
--
-- TESTE DDL-01 — Função existe com SECURITY DEFINER e search_path correto?
--
--   SELECT p.proname, p.prosecdef, p.proconfig,
--          pg_get_function_identity_arguments(p.oid) AS assinatura
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'rpc_complete_lesson';
--   -- Esperado: prosecdef=true, proconfig={search_path=public}, assinatura='p_lesson_id uuid'
--
-- TESTE DDL-02 — Grant para authenticated existe?
--
--   SELECT has_function_privilege(
--       'authenticated',
--       'public.rpc_complete_lesson(uuid)',
--       'EXECUTE'
--   );
--   -- Esperado: true
--
-- TESTE DDL-03 — Grant para anon revogado?
--
--   SELECT has_function_privilege(
--       'anon',
--       'public.rpc_complete_lesson(uuid)',
--       'EXECUTE'
--   );
--   -- Esperado: false
--
-- TESTE DDL-04 — Corpo contém resolução por auth_id (P1-M1.1)?
--
--   SELECT
--       pg_get_functiondef(p.oid) LIKE '%r.auth_id = auth.uid()%' AS tem_auth_id_resolution,
--       pg_get_functiondef(p.oid) LIKE '%v_recruta_id := auth.uid()%' AS tem_assignment_direto
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'rpc_complete_lesson';
--   -- Esperado: tem_auth_id_resolution = true, tem_assignment_direto = false
--   -- tem_assignment_direto = true indica que P1-M1.1 NÃO foi aplicada — bloqueante
--
-- TESTE DDL-05 — complete_lesson ainda existe (coexistência Sprint 2)?
--
--   SELECT proname FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'complete_lesson';
--   -- Esperado: 1 linha
--
-- TESTE DDL-06 — Registry atualizado com nota P1-M1.1?
--
--   SELECT contract_name, status, notes, updated_at
--   FROM public.c6_contract_registry
--   WHERE contract_name = 'rpc_complete_lesson';
--   -- Esperado: status = 'canonical', notes contém 'P1-M1.1'
--
-- ----------------------------------------------------------------------------
-- TESTES FUNCIONAIS — executar com JWT de GADELHA (Run as user no SQL Editor)
-- ----------------------------------------------------------------------------
--
-- PRE-VERIFICACAO — confirmar que auth.uid() resolve para GADELHA:
--
--   SELECT auth.uid();
--   -- Esperado: 918c08f3-8e08-4dc7-a102-da5c729a6ead (auth.users.id de GADELHA)
--
--   SELECT id, auth_id, nome_guerra, forca
--   FROM public.recrutas
--   WHERE auth_id = auth.uid();
--   -- Esperado: 1 linha
--   --   id       = cc41fc7e-ce7d-405d-9178-c14b39e1a017  (recrutas.id canônico)
--   --   auth_id  = 918c08f3-8e08-4dc7-a102-da5c729a6ead  (= auth.uid())
--   --   forca    IN ('marinha','exercito','aeronautica')
--
-- TESTE FUNC-07 — Sem JWT → 42501 (executar como service_role SEM Run as user):
--
--   SELECT public.rpc_complete_lesson('ffffffff-ffff-ffff-ffff-ffffffffffff');
--   -- Esperado: ERROR 42501 "Authentication required: ..."
--
-- TESTE FUNC-08 — Fluxo legítimo com GADELHA (executar com JWT de GADELHA):
--
--   SELECT public.rpc_complete_lesson('aff99e81-afd5-46c0-bcc6-c9dda47af687');
--   -- Esperado: {"status":"ok","xp_granted":true,"xp_added":50}
--
--   -- Validação: recruta_id canônico usado no INSERT (não auth.uid())
--   SELECT rp.recruta_id, rp.lesson_id, rp.xp_granted, rp.source
--   FROM public.recruta_progresso rp
--   WHERE rp.lesson_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
--     AND rp.recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017';
--   -- Esperado: 1 linha com recruta_id = cc41fc7e (NÃO 918c08f3)
--   -- Confirma que v_recruta_id foi resolvido para recrutas.id e não auth.uid()
--
--   SELECT xe.recruta_id, xe.quantidade, xe.forca, xe.origem
--   FROM public.xp_eventos xe
--   WHERE xe.referencia_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
--     AND xe.recruta_id    = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017'
--     AND xe.origem        = 'lesson_complete';
--   -- Esperado: 1 linha com quantidade = 50, forca válida
--
-- TESTE FUNC-09 — Idempotência (segunda chamada com GADELHA):
--
--   SELECT public.rpc_complete_lesson('aff99e81-afd5-46c0-bcc6-c9dda47af687');
--   -- Esperado: {"status":"ok","xp_granted":false,"xp_added":0,"message":"Aula já concluída anteriormente"}
--
--   SELECT COUNT(*) FROM public.recruta_progresso
--   WHERE recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017'
--     AND lesson_id  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';
--   -- Esperado: 1 (não duplicou)
--
--   SELECT COUNT(*) FROM public.xp_eventos
--   WHERE recruta_id    = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017'
--     AND referencia_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
--     AND origem        = 'lesson_complete';
--   -- Esperado: 1 (não duplicou XP)
--
-- TESTE FUNC-10 — xp_valor = 0 (se aula existir):
--
--   SELECT public.rpc_complete_lesson('22222222-2222-2222-2222-222222222222');
--   -- Esperado: {"status":"ok","xp_granted":false,"xp_added":0}  (sem campo "message")
--   -- Se retornar 22023 "Lesson not found": aula não existe — T-10 BLOQUEADO
--
-- TESTE FUNC-11 — Aula inexistente → 22023:
--
--   SELECT public.rpc_complete_lesson('ffffffff-ffff-ffff-ffff-ffffffffffff');
--   -- Esperado: ERROR 22023 "Lesson not found: ffffffff-..."
--
-- TESTE FUNC-12 — source e recruta_id canônico rastreáveis:
--
--   SELECT rp.recruta_id, rp.source,
--          rp.recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017' AS recruta_canonico,
--          rp.recruta_id = '918c08f3-8e08-4dc7-a102-da5c729a6ead' AS recruta_auth_id_errado
--   FROM public.recruta_progresso rp
--   WHERE rp.lesson_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';
--   -- Esperado: recruta_canonico = true, recruta_auth_id_errado = false
--   -- recruta_auth_id_errado = true indica que P1-M1 (versão antiga) foi usada — BLOQUEANTE
--
-- =============================================================================
-- ROLLBACK (executar APENAS se necessário reverter P1-M1.1)
-- =============================================================================
--
-- PASSO R1 — Restaurar corpo da versão P1-M1 (v_recruta_id := auth.uid())
--
-- Reexecutar a migration predecessora:
--   psql -f supabase/migrations/20260517001000_p1_m1_create_rpc_complete_lesson.sql
--
-- OU manualmente:
--
-- CREATE OR REPLACE FUNCTION public.rpc_complete_lesson(p_lesson_id uuid)
-- RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
-- DECLARE
--     v_recruta_id uuid; v_forca text; v_xp_valor integer; v_ja_concluida boolean;
-- BEGIN
--     IF auth.uid() IS NULL THEN
--         RAISE EXCEPTION 'Authentication required: rpc_complete_lesson requires a valid JWT session'
--             USING ERRCODE = '42501';
--     END IF;
--     v_recruta_id := auth.uid();
--     SELECT r.forca INTO v_forca FROM public.recrutas r WHERE r.id = v_recruta_id;
--     IF NOT FOUND THEN
--         RAISE EXCEPTION 'Recruta profile not found for authenticated user. Complete registration first.'
--             USING ERRCODE = '22023';
--     END IF;
--     IF v_forca IS NULL THEN
--         RAISE EXCEPTION 'Recruta forca is not defined. Complete onboarding (rpc_complete_onboarding) first.'
--             USING ERRCODE = '22023';
--     END IF;
--     SELECT a.xp_valor INTO v_xp_valor FROM public.aulas a WHERE a.id = p_lesson_id;
--     IF NOT FOUND THEN
--         RAISE EXCEPTION 'Lesson not found: %. Verify the lesson UUID is correct.', p_lesson_id
--             USING ERRCODE = '22023';
--     END IF;
--     IF v_xp_valor < 0 THEN
--         RAISE EXCEPTION 'Invalid xp_valor for lesson %: value is negative (%). Contact admin to fix aulas.xp_valor.', p_lesson_id, v_xp_valor
--             USING ERRCODE = '22023';
--     END IF;
--     SELECT EXISTS (SELECT 1 FROM public.recruta_progresso rp WHERE rp.recruta_id = v_recruta_id AND rp.lesson_id = p_lesson_id AND rp.completed_at IS NOT NULL) INTO v_ja_concluida;
--     IF v_ja_concluida THEN
--         RETURN json_build_object('status','ok','xp_granted',false,'xp_added',0,'message','Aula já concluída anteriormente');
--     END IF;
--     INSERT INTO public.recruta_progresso (recruta_id, lesson_id, status, completed_at, xp_granted, source)
--     VALUES (v_recruta_id, p_lesson_id, 'completed', now(), v_xp_valor, 'rpc_complete_lesson')
--     ON CONFLICT (recruta_id, lesson_id) DO NOTHING;
--     IF v_xp_valor > 0 THEN
--         INSERT INTO public.xp_eventos (recruta_id, forca, quantidade, origem, referencia_id)
--         VALUES (v_recruta_id, v_forca, v_xp_valor, 'lesson_complete', p_lesson_id)
--         ON CONFLICT DO NOTHING;
--     END IF;
--     RETURN json_build_object('status','ok','xp_granted',(v_xp_valor > 0),'xp_added',v_xp_valor);
-- END; $$;
--
-- PASSO R2 — Remover nota de P1-M1.1 do registry (opcional):
--
-- UPDATE public.c6_contract_registry
-- SET    notes      = regexp_replace(notes, ' \| P1-M1\.1 2026-05-18:.*', ''),
--        updated_at = now()
-- WHERE  contract_name = 'rpc_complete_lesson';
--
-- Verificação pós-rollback:
--   SELECT pg_get_functiondef(p.oid) LIKE '%v_recruta_id := auth.uid()%' AS rollback_ok
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'rpc_complete_lesson';
--   -- Esperado: true
--
-- IMPACTO DO ROLLBACK: usuários legados (recrutas.id != auth.uid()) voltam a
-- receber Guarda 2 NOT FOUND. Fase 1B bloqueada até nova correção.
--
-- =============================================================================
-- REFERÊNCIAS
-- =============================================================================
-- Predecessora P1-M1:    supabase/migrations/20260517001000_p1_m1_create_rpc_complete_lesson.sql
-- Handoff P1-M1.1:       supabase/baseline/P1_M1_1_HANDOFF.md
-- Schema recrutas (ln 8365): supabase/remote/supabase_remote_schema.sql
-- Constraints (ln 15532): supabase/remote/supabase_remote_schema.sql
-- rpc_complete_onboarding: supabase/migrations/20260509001000_fix_rpc_complete_onboarding_upsert.sql
-- =============================================================================
