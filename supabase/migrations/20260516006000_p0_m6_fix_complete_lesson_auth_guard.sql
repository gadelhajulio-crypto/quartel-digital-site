-- =============================================================================
-- Migration:  20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql
-- Classificação: P0-M6 — Segurança (SEC-03 + GRANT-01)
-- Data:       2026-05-16
-- Autor:      institutional-audit-2026-05-16
-- Revisão:    AGUARDANDO APROVAÇÃO — não executar sem aprovação institucional
-- =============================================================================
--
-- OBJETIVO
-- --------
-- Corrigir dois problemas confirmados em public.complete_lesson:
--
--   SEC-03: A função aceita p_recruta_id como parâmetro externo sem validar
--           que o valor corresponde ao usuário autenticado. Qualquer chamador
--           com EXECUTE poderia registrar conclusão de aula e XP para outro
--           recruta passando um UUID arbitrário.
--
--   GRANT-01: O dump remoto não contém GRANT EXECUTE TO authenticated.
--             Chamadas do frontend (supabase.rpc com JWT do usuário) podem
--             estar falhando com "permission denied for function complete_lesson".
--             Esta migration corrige o grant garantindo que o frontend funcione.
--
-- ASSINATURA PRESERVADA (sem breaking change)
-- -------------------------------------------
-- complete_lesson(p_recruta_id uuid, p_lesson_id uuid, p_xp integer DEFAULT 50)
--
-- A assinatura não muda. O frontend (progressService.ts:50) continua enviando
-- p_recruta_id: userId sem qualquer alteração necessária.
--
-- MUDANÇAS EM RELAÇÃO AO DUMP (ln 1182–1246)
-- -------------------------------------------
-- 1. Adicionada validação de auth.uid() antes de qualquer operação DML:
--      IF auth.uid() IS NOT NULL AND p_recruta_id IS DISTINCT FROM auth.uid()
--      THEN RAISE EXCEPTION 'Unauthorized: ...'
--    A condição auth.uid() IS NOT NULL preserva chamadas via service_role
--    (que não carregam JWT → auth.uid() = NULL) sem restrição.
--
-- 2. Adicionado GRANT EXECUTE TO authenticated.
--    Corrige GRANT-01: frontend agora pode chamar a função com JWT de usuário.
--
-- O QUE NÃO MUDA
-- ---------------
-- - Assinatura: idêntica ao dump.
-- - SECURITY DEFINER: mantido.
-- - SET search_path TO 'public': mantido.
-- - Owner: postgres (CREATE OR REPLACE preserva owner).
-- - Lógica de negócio: idêntica ao dump (recruta_progresso + xp_eventos).
-- - GRANT ALL TO service_role: mantido (reafirmado para idempotência).
-- - REVOKE ALL FROM PUBLIC: mantido (reafirmado para idempotência).
-- - Idempotência via ON CONFLICT: preservada em ambas as tabelas.
--
-- IDEMPOTÊNCIA
-- -------------
-- CREATE OR REPLACE não faz DROP. Reexecutar é seguro.
-- O REVOKE/GRANT no final é idempotente por natureza em PostgreSQL.
--
-- RISCO
-- -----
-- MÉDIO — substitui corpo de função SECURITY DEFINER em produção.
-- Sem breaking change no frontend. Sem alteração de tabelas ou dados.
-- Reversível com o bloco de rollback ao final deste arquivo.
--
-- PRÉ-CONDIÇÃO RECOMENDADA
-- -------------------------
-- Confirmar comportamento atual do grant antes de aplicar:
--   SELECT has_function_privilege(
--       'authenticated',
--       'public.complete_lesson(uuid, uuid, integer)',
--       'EXECUTE'
--   );
--   TRUE  → GRANT-01 não era um bug ativo (grant implícito existia)
--   FALSE → GRANT-01 era bug ativo; esta migration também corrige o frontend
--
-- REFERÊNCIAS
-- -----------
-- Auditoria pré-P0-M6:  supabase/baseline/P0_M6_PRE_AUDIT.md
-- Função original:       supabase/remote/supabase_remote_schema.sql ln 1182–1246
-- Grants originais:      supabase/remote/supabase_remote_schema.sql ln 18633–18634
-- Decision Packet:       supabase/baseline/P0_DECISION_PACKET.md §2
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PASSO 1 — Substituir complete_lesson com guarda de auth.uid()
-- -----------------------------------------------------------------------------
-- CREATE OR REPLACE preserva owner, dependências e grants já existentes.
-- Apenas o corpo ($$ ... $$) é substituído.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.complete_lesson(
    p_recruta_id uuid,
    p_lesson_id  uuid,
    p_xp         integer DEFAULT 50
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ja_concluida boolean;
BEGIN

  -- ── GUARDA SEC-03 ────────────────────────────────────────────────────────
  -- Valida que o caller autenticado está operando sobre o próprio recruta.
  -- auth.uid() retorna NULL quando chamada via service_role (sem JWT).
  -- Nesse caso a guarda não é aplicada — service_role é confiável por design.
  IF auth.uid() IS NOT NULL AND p_recruta_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: p_recruta_id must match the authenticated user session'
      USING ERRCODE = '42501';
  END IF;
  -- ── FIM DA GUARDA ────────────────────────────────────────────────────────

  -- PASSO 1 — verificação de idempotência (lógica original preservada)
  SELECT EXISTS (
    SELECT 1
    FROM public.recruta_progresso
    WHERE recruta_id   = p_recruta_id
      AND lesson_id    = p_lesson_id
      AND completed_at IS NOT NULL
  ) INTO v_ja_concluida;

  IF v_ja_concluida THEN
    RETURN json_build_object(
      'status',     'ok',
      'xp_granted', false,
      'message',    'Aula já concluída anteriormente'
    );
  END IF;

  -- PASSO 2 — registrar conclusão em recruta_progresso (lógica original preservada)
  INSERT INTO public.recruta_progresso (
    recruta_id,
    lesson_id,
    status,
    completed_at,
    xp_granted,
    source
  )
  VALUES (
    p_recruta_id,
    p_lesson_id,
    'completed',
    now(),
    p_xp,
    'lesson_complete'
  )
  ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

  -- PASSO 3 — conceder XP canônico em xp_eventos (lógica original preservada)
  -- SELECT FROM recrutas garante que o forca do recruta é usado, não um valor externo.
  -- ON CONFLICT apoiado por: UNIQUE INDEX ux_xp_eventos_lesson_unique
  --   ON xp_eventos (recruta_id, referencia_id) WHERE origem = 'lesson_complete'
  INSERT INTO public.xp_eventos (
    recruta_id,
    forca,
    quantidade,
    origem,
    referencia_id
  )
  SELECT
    r.id,
    r.forca,
    p_xp,
    'lesson_complete',
    p_lesson_id
  FROM public.recrutas r
  WHERE r.id = p_recruta_id
  ON CONFLICT DO NOTHING;

  RETURN json_build_object(
    'status',     'ok',
    'xp_granted', true,
    'xp_added',   p_xp
  );

END;
$$;

-- -----------------------------------------------------------------------------
-- PASSO 2 — Ajustar grants
-- -----------------------------------------------------------------------------
-- REVOKE ALL FROM PUBLIC reafirmado (idempotente — já era o estado anterior).
-- GRANT ALL TO service_role reafirmado (idempotente — já era o estado anterior).
-- GRANT EXECUTE TO authenticated: NOVO — corrige GRANT-01.
-- -----------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.complete_lesson(uuid, uuid, integer) FROM PUBLIC;
GRANT ALL     ON FUNCTION public.complete_lesson(uuid, uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_lesson(uuid, uuid, integer) TO authenticated;

-- =============================================================================
-- TESTES SQL PÓS-APPLY (executar após migration — NÃO parte da migration)
-- =============================================================================
--
-- TESTE 1 — Guarda SEC-03: chamada com UUID diferente do auth.uid() é bloqueada?
--   (executar como usuário authenticated com JWT válido — UUID = X)
--
--   SELECT public.complete_lesson(
--       '<uuid_de_outro_recruta>',   -- ← UUID diferente do JWT
--       '<uuid_de_qualquer_aula>'
--   );
--   -- Esperado: ERROR 42501 — "Unauthorized: p_recruta_id must match..."
--
-- TESTE 2 — Fluxo legítimo: chamada com próprio UUID funciona?
--   (executar como usuário authenticated — UUID = Y)
--
--   SELECT public.complete_lesson(
--       auth.uid(),                  -- ← próprio UUID
--       '<uuid_de_aula_valida>'
--   );
--   -- Esperado: {"status":"ok","xp_granted":true,"xp_added":50}
--   --        OU {"status":"ok","xp_granted":false,"message":"Aula já concluída anteriormente"}
--
-- TESTE 3 — Idempotência: chamar duas vezes não duplica XP?
--
--   SELECT public.complete_lesson(auth.uid(), '<uuid_aula>');  -- 1ª vez
--   SELECT public.complete_lesson(auth.uid(), '<uuid_aula>');  -- 2ª vez
--   -- Esperado: 2ª chamada retorna {"xp_granted":false,"message":"Aula já concluída..."}
--
--   SELECT COUNT(*) FROM public.xp_eventos
--   WHERE recruta_id    = auth.uid()
--     AND referencia_id = '<uuid_aula>'
--     AND origem        = 'lesson_complete';
--   -- Esperado: 1 (exatamente um registro)
--
-- TESTE 4 — Grant para authenticated existe?
--
--   SELECT has_function_privilege(
--       'authenticated',
--       'public.complete_lesson(uuid, uuid, integer)',
--       'EXECUTE'
--   );
--   -- Esperado: true
--
-- TESTE 5 — Grant para service_role preservado?
--
--   SELECT has_function_privilege(
--       'service_role',
--       'public.complete_lesson(uuid, uuid, integer)',
--       'EXECUTE'
--   );
--   -- Esperado: true
--
-- TESTE 6 — Grant para anon revogado?
--
--   SELECT has_function_privilege(
--       'anon',
--       'public.complete_lesson(uuid, uuid, integer)',
--       'EXECUTE'
--   );
--   -- Esperado: false
--
-- TESTE 7 — Chamada de service_role sem JWT (auth.uid()=NULL) passa pela guarda?
--   (executar como service_role diretamente — sem JWT)
--
--   SELECT public.complete_lesson(
--       '<uuid_valido_de_recruta>',
--       '<uuid_de_aula_valida>'
--   );
--   -- Esperado: sucesso (auth.uid() IS NULL → guarda não dispara)
--
-- =============================================================================
-- ROLLBACK (executar APENAS se a migration precisar ser revertida)
-- =============================================================================
--
-- PASSO R1 — Recriar função exatamente como estava no dump (ln 1182–1246)
--
-- CREATE OR REPLACE FUNCTION public.complete_lesson(
--     p_recruta_id uuid,
--     p_lesson_id  uuid,
--     p_xp         integer DEFAULT 50
-- )
-- RETURNS json
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- SET search_path TO 'public'
-- AS $$
-- DECLARE
--   v_ja_concluida boolean;
-- BEGIN
--   SELECT EXISTS (
--     SELECT 1
--     FROM public.recruta_progresso
--     WHERE recruta_id = p_recruta_id
--       AND lesson_id  = p_lesson_id
--       AND completed_at IS NOT NULL
--   ) INTO v_ja_concluida;
--
--   IF v_ja_concluida THEN
--     RETURN json_build_object(
--       'status',     'ok',
--       'xp_granted', false,
--       'message',    'Aula já concluída anteriormente'
--     );
--   END IF;
--
--   INSERT INTO public.recruta_progresso (
--     recruta_id, lesson_id, status, completed_at, xp_granted, source
--   )
--   VALUES (
--     p_recruta_id, p_lesson_id, 'completed', now(), p_xp, 'lesson_complete'
--   )
--   ON CONFLICT (recruta_id, lesson_id) DO NOTHING;
--
--   INSERT INTO public.xp_eventos (
--     recruta_id, forca, quantidade, origem, referencia_id
--   )
--   SELECT r.id, r.forca, p_xp, 'lesson_complete', p_lesson_id
--   FROM public.recrutas r
--   WHERE r.id = p_recruta_id
--   ON CONFLICT DO NOTHING;
--
--   RETURN json_build_object(
--     'status',     'ok',
--     'xp_granted', true,
--     'xp_added',   p_xp
--   );
-- END;
-- $$;
--
-- PASSO R2 — Restaurar grants ao estado original do dump (ln 18633–18634)
--
-- REVOKE ALL     ON FUNCTION public.complete_lesson(uuid, uuid, integer) FROM PUBLIC;
-- REVOKE EXECUTE ON FUNCTION public.complete_lesson(uuid, uuid, integer) FROM authenticated;
-- GRANT ALL      ON FUNCTION public.complete_lesson(uuid, uuid, integer) TO service_role;
--
-- Verificação pós-rollback:
--   SELECT has_function_privilege('authenticated',
--       'public.complete_lesson(uuid, uuid, integer)', 'EXECUTE');
--   -- Esperado: false
--   SELECT has_function_privilege('service_role',
--       'public.complete_lesson(uuid, uuid, integer)', 'EXECUTE');
--   -- Esperado: true
--
-- =============================================================================
