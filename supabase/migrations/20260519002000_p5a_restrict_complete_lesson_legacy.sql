-- =============================================================================
-- Migration:  20260519002000_p5a_restrict_complete_lesson_legacy.sql
-- Classificação: P5A — Sprint 5A / Legacy Restriction
-- Data:       2026-05-19
-- Autor:      institutional-sprint5a-2026-05-19
-- Revisão:    AGUARDANDO EXECUÇÃO — não executar sem aprovação institucional
-- =============================================================================
--
-- OBJETIVO
-- --------
-- Revogar EXECUTE de `authenticated` em `public.complete_lesson`, impedindo
-- que qualquer chamada do frontend use a RPC legada.
--
-- GRANT de `service_role` é preservado para:
--   - Rollback de emergência via scripts administrativos (service_role)
--   - Chamadas internas de seed/migration com impersonation
--   - Compatibilidade com ferramentas Supabase Dashboard (service_role)
--
-- CONTEXTO
-- --------
-- Estado atual (pós P0-M6):
--   GRANT ALL     ON FUNCTION complete_lesson TO service_role;   ← mantido
--   GRANT EXECUTE ON FUNCTION complete_lesson TO authenticated;  ← REVOGAR
--
-- Situação do frontend (pré-condição confirmada):
--   progressService.ts:8  — USE_LEGACY_COMPLETE_LESSON = false
--   progressService.ts:59 — path legado protegido por __DEV__ && USE_LEGACY_COMPLETE_LESSON
--   Resultado: NENHUMA chamada de authenticated atinge complete_lesson em produção.
--   O REVOKE é um enforcement de segurança que formaliza o estado de fato.
--
-- SITUAÇÃO DO APP
-- ---------------
-- App ainda não em uso real — zero alunos cadastrados.
-- Nenhuma chamada legada ativa. REVOKE não impacta nenhum usuário.
--
-- O QUE NÃO MUDA
-- ---------------
-- - Corpo da função: intacto.
-- - SECURITY DEFINER: mantido.
-- - GRANT para service_role: mantido.
-- - rpc_complete_lesson: intocada.
-- - Tabelas recruta_progresso, xp_eventos: intocadas.
-- - Frontend: nenhuma alteração de código necessária (USE_LEGACY=false já bloqueia o path).
--
-- IMPACTO NO FRONTEND
-- --------------------
-- progressService.ts — path normal (USE_LEGACY_COMPLETE_LESSON = false):
--   → usa rpc_complete_lesson → NÃO afetado por este REVOKE
--
-- progressService.ts — path legado (USE_LEGACY_COMPLETE_LESSON = true, __DEV__ only):
--   → chamaria complete_lesson → retornaria 42501 permission denied
--   → comportamento esperado: DEV developer veria erro claro ao tentar ativar o flag
--
-- IDEMPOTÊNCIA
-- -------------
-- REVOKE: executar quando grant já foi revogado é no-op seguro no PostgreSQL.
-- GRANT service_role: reafirmar é no-op se já existe.
-- UPDATE registry: idempotente (sobrescreve notes e updated_at).
--
-- RISCO
-- -----
-- MÍNIMO.
--   - Zero impact em usuários reais (app não em produção).
--   - Zero impact no path canônico (rpc_complete_lesson não é afetada).
--   - Reversível instantaneamente com GRANT EXECUTE TO authenticated (ver rollback).
--
-- REFERÊNCIAS
-- -----------
-- P0-M6 (grant original):  supabase/migrations/20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql
-- P4-M1 (legacy status):   supabase/migrations/20260519001000_p4_m1_contract_registry_legacy_update.sql
-- Handoff Sprint 4:        supabase/baseline/SPRINT4_LEGACY_CLEANUP_HANDOFF.md §5 Fase C
-- Handoff Sprint 5A:       supabase/baseline/P5A_RESTRICT_COMPLETE_LESSON_HANDOFF.md
-- =============================================================================


-- =============================================================================
-- PASSO 1 — Revogar EXECUTE de authenticated
-- =============================================================================
-- A assinatura completa é usada para evitar ambiguidade caso existam sobrecargas.
-- (O dump confirma uma única sobrecarga: complete_lesson(uuid, uuid, integer))

REVOKE EXECUTE ON FUNCTION public.complete_lesson(uuid, uuid, integer) FROM authenticated;


-- =============================================================================
-- PASSO 2 — Reafirmar GRANT para service_role (idempotente)
-- =============================================================================
-- Explicitamente reafirmado para documentar intenção: service_role mantém acesso.

GRANT ALL ON FUNCTION public.complete_lesson(uuid, uuid, integer) TO service_role;


-- =============================================================================
-- PASSO 3 — Atualizar c6_contract_registry
-- =============================================================================

UPDATE public.c6_contract_registry
SET
    notes      = 'LEGADO RESTRITO (Sprint 5A — 2026-05-19). '
              || 'EXECUTE revogado de authenticated. Apenas service_role mantém acesso. '
              || 'Frontend bloqueado por REVOKE + USE_LEGACY_COMPLETE_LESSON=false (dupla proteção). '
              || 'Substituída por rpc_complete_lesson (Sprint 2 / P1-M1). '
              || 'Mantida no banco para rollback de emergência via service_role. '
              || 'Remoção (DROP): Sprint 5B — aguarda decisão institucional. '
              || 'Pré-condição para DROP: zero chamadas de service_role nos últimos 30 dias '
              || '(confirmar via telemetria Q-05 em SPRINT4_LEGACY_CLEANUP_HANDOFF.md).',
    updated_at = now()
WHERE contract_name = 'complete_lesson';


-- =============================================================================
-- TESTES SQL PÓS-APPLY
-- (executar após migration — NÃO parte da migration)
-- =============================================================================

-- TESTE T-01 — EXECUTE de authenticated foi revogado?
--
--   SELECT has_function_privilege(
--       'authenticated',
--       'public.complete_lesson(uuid, uuid, integer)',
--       'EXECUTE'
--   );
--   -- Esperado: false

-- TESTE T-02 — GRANT para service_role preservado?
--
--   SELECT has_function_privilege(
--       'service_role',
--       'public.complete_lesson(uuid, uuid, integer)',
--       'EXECUTE'
--   );
--   -- Esperado: true

-- TESTE T-03 — anon também não tem acesso?
--
--   SELECT has_function_privilege(
--       'anon',
--       'public.complete_lesson(uuid, uuid, integer)',
--       'EXECUTE'
--   );
--   -- Esperado: false

-- TESTE T-04 — Função ainda existe (não foi dropada)?
--
--   SELECT proname, prosecdef
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'complete_lesson';
--   -- Esperado: 1 linha, prosecdef = true

-- TESTE T-05 — registry atualizado?
--
--   SELECT contract_name, status, LEFT(notes, 60) AS notes_preview, updated_at
--   FROM public.c6_contract_registry
--   WHERE contract_name = 'complete_lesson';
--   -- Esperado: status = 'legacy', notes contém 'LEGADO RESTRITO'

-- TESTE T-06 — rpc_complete_lesson intocada?
--
--   SELECT has_function_privilege(
--       'authenticated',
--       'public.rpc_complete_lesson(uuid)',
--       'EXECUTE'
--   );
--   -- Esperado: true (não foi afetada por esta migration)

-- TESTE T-07 — [Funcional DEV] Chamada de authenticated retorna 42501?
--   (executar via SQL Editor → Run as user → qualquer authenticated)
--
--   SELECT public.complete_lesson(
--       auth.uid(),
--       '00000000-0000-0000-0000-000000010002'
--   );
--   -- Esperado: ERROR 42501 — permission denied for function complete_lesson

-- TESTE T-08 — [Funcional] Chamada de service_role ainda funciona?
--   (executar via SQL Editor como service_role — para confirmar rollback disponível)
--
--   SELECT public.complete_lesson(
--       'cc41fc7e-ce7d-405d-9178-c14b39e1a017',  -- recrutas.id de GADELHA
--       '00000000-0000-0000-0000-000000010002'   -- aula QA
--   );
--   -- Esperado: {"status":"ok","xp_granted":false,"message":"Aula já concluída anteriormente"}
--   -- (idempotente — QA anterior já criou o registro)


-- =============================================================================
-- ROLLBACK
-- (executar APENAS se necessário restaurar acesso de authenticated)
-- =============================================================================
--
-- PASSO R-01 — Restaurar GRANT EXECUTE para authenticated
--
-- GRANT EXECUTE ON FUNCTION public.complete_lesson(uuid, uuid, integer) TO authenticated;
--
-- PASSO R-02 — Reverter notas no registry
--
-- UPDATE public.c6_contract_registry
-- SET
--     notes      = 'LEGADO (Sprint 4 — 2026-05-19). '
--               || 'Substituída por rpc_complete_lesson (Sprint 2 / P1-M1). '
--               || 'Frontend migrado: progressService.ts usa rpc_complete_lesson por padrão. '
--               || 'Mantida em coexistência para rollback de emergência via USE_LEGACY_COMPLETE_LESSON flag (DEV only). '
--               || 'Escrita em: recruta_progresso (source=''lesson_complete'') + xp_eventos (origem=''lesson_complete''). '
--               || 'Pré-condição para remoção (Sprint 5): '
--               || '(a) 30+ dias sem chamadas com source=''lesson_complete'' de authenticated; '
--               || '(b) USE_LEGACY_COMPLETE_LESSON removido do progressService; '
--               || '(c) QA completo em staging com rpc_complete_lesson exclusivo.',
--     updated_at = now()
-- WHERE contract_name = 'complete_lesson';
--
-- Verificação pós-rollback:
--   SELECT has_function_privilege('authenticated',
--       'public.complete_lesson(uuid, uuid, integer)', 'EXECUTE');
--   -- Esperado: true
--
-- Impacto do rollback:
--   - authenticated pode chamar complete_lesson novamente.
--   - Frontend permanece usando rpc_complete_lesson (USE_LEGACY=false).
--   - O rollback NÃO ativa o path legado no frontend automaticamente.
--   - Para ativar o path legado: USE_LEGACY_COMPLETE_LESSON = true (DEV only).

-- =============================================================================
-- VEREDICTO: AGUARDANDO EXECUÇÃO
-- =============================================================================
-- Responsável: DBA / Supabase Admin
-- Executar: SQL Editor como service_role OU supabase db push
-- Pré-condição: nenhuma (independente de Fix-01 e Fix-02)
-- Pode ser executada antes ou depois de P4-M1
-- =============================================================================
