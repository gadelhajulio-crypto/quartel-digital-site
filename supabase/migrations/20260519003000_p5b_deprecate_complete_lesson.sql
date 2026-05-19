-- =============================================================================
-- Migration:  20260519003000_p5b_deprecate_complete_lesson.sql
-- Classificação: P5B — Sprint 5B / Legacy Deprecation
-- Data:       2026-05-19
-- Autor:      institutional-sprint5b-2026-05-19
-- Revisão:    AGUARDANDO EXECUÇÃO — não executar sem aprovação institucional
-- =============================================================================
--
-- OBJETIVO
-- --------
-- Renomear public.complete_lesson → public.__deprecated_complete_lesson.
-- A função continua existindo no banco (sem DROP) mas com nome explicitamente
-- marcado como depreciado, tornando qualquer chamada acidental óbvia nos logs.
--
-- PREDECESSORAS OBRIGATÓRIAS
-- ---------------------------
-- 1. P5A (20260519002000): EXECUTE revogado de authenticated — sem este passo,
--    a função renomeada ainda seria chamável pelo frontend se alguém revertesse
--    o code path.
-- 2. Frontend cleanup (Sprint 5B): remoção do bloco USE_LEGACY_COMPLETE_LESSON
--    em progressService.ts — confirmar antes de executar esta migration.
--
-- DEPENDENCY AUDIT — RESULTADO
-- ----------------------------
-- Executado em 2026-05-19. Zero dependências ativas bloqueantes encontradas.
-- Ver tabela completa em P5B_DEPRECATE_COMPLETE_LESSON_HANDOFF.md §1.
--
-- Resumo:
--   Frontend          : progressService.ts:61 → .rpc('complete_lesson') dentro de
--                       __DEV__ && USE_LEGACY_COMPLETE_LESSON (false) — DEAD CODE
--                       REMOVIDO nesta sprint (ver changelog frontend)
--   Edge Functions    : zero referências (grep em supabase/functions/**)
--   SQL Triggers      : zero referências (grep em migrations/*.sql)
--   SQL Views         : zero referências
--   Outras RPCs       : zero referências
--   Cron jobs         : zero evidências no codebase
--   Migrations hist.  : 20260201221400 contém CREATE de versão OLD da função
--                       (assinatura diferente: sem p_xp) — DDL histórico, não caller
--
-- O QUE MUDA
-- ----------
-- 1. public.complete_lesson        → public.__deprecated_complete_lesson  (RENAME)
-- 2. COMMENT adicionado ao corpo                                           (COMMENT)
-- 3. c6_contract_registry status   → 'blocked'                            (UPDATE)
--
-- O QUE NÃO MUDA
-- ---------------
-- - Corpo da função: intacto (RENAME preserva tudo).
-- - SECURITY DEFINER: preservado.
-- - SET search_path: preservado.
-- - GRANTs: transferidos automaticamente para o novo nome.
--   (service_role mantém EXECUTE; authenticated continua sem acesso — P5A)
-- - Tabelas recruta_progresso, xp_eventos: intocadas.
-- - rpc_complete_lesson: intocada.
-- - Dados históricos em recruta_progresso (source='lesson_complete'): preservados.
--
-- COMPORTAMENTO PÓS-RENAME
-- -------------------------
-- Chamada via supabase.rpc('complete_lesson', ...):
--   → PostgREST retorna 404 "Could not find the function complete_lesson..."
--   → (função não existe mais com esse nome)
--
-- Chamada via supabase.rpc('__deprecated_complete_lesson', ...):
--   → authenticated → 42501 (grant revogado em P5A, transferido para novo nome)
--   → service_role → executa (para rollback de emergência se necessário)
--
-- IDEMPOTÊNCIA
-- -------------
-- ALTER FUNCTION RENAME: NÃO é idempotente.
--   - Primeira execução: complete_lesson → __deprecated_complete_lesson (OK)
--   - Segunda execução: ERROR — complete_lesson não existe mais
--   - Proteção: ver guarda DO $$ abaixo que verifica existência antes do RENAME
-- COMMENT: idempotente (sobrescreve).
-- UPDATE registry: idempotente.
--
-- RISCO
-- -----
-- BAIXO.
--   - Zero callers ativos confirmados.
--   - App sem usuários reais.
--   - Reversível instantaneamente com RENAME inverso (ver rollback).
--   - Sem DROP: dados e corpo preservados para inspeção post-mortem.
--
-- REFERÊNCIAS
-- -----------
-- P5A predecessor:    supabase/migrations/20260519002000_p5a_restrict_complete_lesson_legacy.sql
-- P4-M1 registry:     supabase/migrations/20260519001000_p4_m1_contract_registry_legacy_update.sql
-- Handoff:            supabase/baseline/P5B_DEPRECATE_COMPLETE_LESSON_HANDOFF.md
-- Sprint 4 handoff:   supabase/baseline/SPRINT4_LEGACY_CLEANUP_HANDOFF.md
-- =============================================================================


-- =============================================================================
-- PASSO 0 — Verificar que função existe antes do RENAME (guarda de idempotência)
-- =============================================================================
-- Se a função já foi renomeada (reexecução acidental), o DO block não tenta o
-- RENAME novamente — evita ERROR fatal que interromperia a migration.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'complete_lesson'
    ) THEN
        -- Função ainda tem o nome original — executar RENAME
        EXECUTE 'ALTER FUNCTION public.complete_lesson(uuid, uuid, integer)
                 RENAME TO __deprecated_complete_lesson';
        RAISE NOTICE 'P5B: complete_lesson renomeada para __deprecated_complete_lesson';
    ELSE
        RAISE NOTICE 'P5B: complete_lesson não encontrada — possivelmente já renomeada. Verificar.';
    END IF;
END;
$$;


-- =============================================================================
-- PASSO 1 — Adicionar COMMENT explicando deprecação
-- =============================================================================
-- COMMENT persiste no pg_description e é visível em psql \df+
-- e em ferramentas como DBeaver, pgAdmin e Supabase Dashboard.

COMMENT ON FUNCTION public.__deprecated_complete_lesson(uuid, uuid, integer) IS
    'DEPRECADA Sprint 5B (2026-05-19). '
    'Renomeada de complete_lesson. NÃO USAR — sem callers ativos. '
    'Substituída por rpc_complete_lesson (P1-M1, Sprint 2). '
    'EXECUTE revogado de authenticated (P5A, Sprint 5A). '
    'Mantida temporariamente para inspeção post-mortem e rollback de emergência. '
    'DROP planejado: Sprint 6 (aguarda decisão institucional final). '
    'Auditoria de dependências: supabase/baseline/P5B_DEPRECATE_COMPLETE_LESSON_HANDOFF.md';


-- =============================================================================
-- PASSO 2 — Atualizar c6_contract_registry
-- =============================================================================
-- status = 'blocked': mais próximo semanticamente de "inutilizável/retirada de serviço"
-- dentro dos valores válidos do CHECK constraint
-- ('canonical','system','legacy','admin_audit','blocked').
-- Nota: 'deprecated' não é valor válido no CHECK — usar 'blocked'.

UPDATE public.c6_contract_registry
SET
    status     = 'blocked',
    notes      = 'BLOCKED/DEPRECATED — Sprint 5B (2026-05-19). '
              || 'Renomeada para __deprecated_complete_lesson no banco. '
              || 'Chamadas via .rpc(''complete_lesson'') retornam 404 PostgREST. '
              || 'Chamadas via .rpc(''__deprecated_complete_lesson'') retornam 42501 (authenticated). '
              || 'service_role mantém acesso para inspeção/rollback de emergência. '
              || 'Zero callers confirmados em auditoria Sprint 5B (2026-05-19). '
              || 'Frontend: bloco USE_LEGACY_COMPLETE_LESSON removido de progressService.ts. '
              || 'DROP planejado: Sprint 6 — migration 20260619001000_p6_drop_deprecated_complete_lesson.sql.',
    updated_at = now()
WHERE contract_name = 'complete_lesson';


-- =============================================================================
-- TESTES SQL PÓS-APPLY
-- (executar após migration — NÃO parte da migration)
-- =============================================================================

-- TESTE T-01 — complete_lesson NÃO existe mais com o nome original?
--
--   SELECT COUNT(*) FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'complete_lesson';
--   -- Esperado: 0

-- TESTE T-02 — __deprecated_complete_lesson existe com o corpo preservado?
--
--   SELECT proname, prosecdef,
--          LEFT(pg_get_functiondef(oid), 100) AS body_preview
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = '__deprecated_complete_lesson';
--   -- Esperado: 1 linha, prosecdef = true, body contém 'p_recruta_id'

-- TESTE T-03 — COMMENT aplicado?
--
--   SELECT obj_description(p.oid, 'pg_proc') AS func_comment
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = '__deprecated_complete_lesson';
--   -- Esperado: string contém 'DEPRECADA Sprint 5B'

-- TESTE T-04 — authenticated NÃO tem EXECUTE na função renomeada?
--
--   SELECT has_function_privilege(
--       'authenticated',
--       'public.__deprecated_complete_lesson(uuid, uuid, integer)',
--       'EXECUTE'
--   );
--   -- Esperado: false
--   -- (grant revogado em P5A foi transferido automaticamente pelo RENAME)

-- TESTE T-05 — service_role ainda tem EXECUTE?
--
--   SELECT has_function_privilege(
--       'service_role',
--       'public.__deprecated_complete_lesson(uuid, uuid, integer)',
--       'EXECUTE'
--   );
--   -- Esperado: true

-- TESTE T-06 — registry status = 'blocked'?
--
--   SELECT contract_name, status, LEFT(notes, 80) AS notes_preview
--   FROM public.c6_contract_registry
--   WHERE contract_name = 'complete_lesson';
--   -- Esperado: status = 'blocked'

-- TESTE T-07 — rpc_complete_lesson intocada?
--
--   SELECT has_function_privilege(
--       'authenticated',
--       'public.rpc_complete_lesson(uuid)',
--       'EXECUTE'
--   );
--   -- Esperado: true

-- TESTE T-08 — [Funcional] PostgREST retorna 404 para 'complete_lesson'?
--   (simular chamada do frontend)
--
--   -- Via Expo Go: tentar ativar USE_LEGACY_COMPLETE_LESSON = true em DEV
--   -- Esperado: erro "Could not find the function complete_lesson" (PostgREST 404)
--   -- (não 42501 — pois a função não existe mais com esse nome)

-- TESTE T-09 — [Funcional] rpc_complete_lesson continua funcionando?
--   (teste de regressão do path canônico)
--
--   -- Via SQL Editor → Run as user → GADELHA:
--   SELECT public.rpc_complete_lesson('00000000-0000-0000-0000-000000010002');
--   -- Esperado: {"status":"ok","xp_granted":false,"message":"Aula já concluída anteriormente"}


-- =============================================================================
-- ROLLBACK
-- (executar APENAS se necessário restaurar o estado anterior a P5B)
-- =============================================================================

-- PASSO R-01 — Renomear de volta para complete_lesson
--
-- DO $$
-- BEGIN
--     IF EXISTS (
--         SELECT 1 FROM pg_proc p
--         JOIN pg_namespace n ON n.oid = p.pronamespace
--         WHERE n.nspname = 'public'
--           AND p.proname = '__deprecated_complete_lesson'
--     ) THEN
--         EXECUTE 'ALTER FUNCTION public.__deprecated_complete_lesson(uuid, uuid, integer)
--                  RENAME TO complete_lesson';
--         RAISE NOTICE 'ROLLBACK P5B: função restaurada para complete_lesson';
--     END IF;
-- END;
-- $$;

-- PASSO R-02 — Remover COMMENT (restaurar estado anterior — sem comment)
--
-- COMMENT ON FUNCTION public.complete_lesson(uuid, uuid, integer) IS NULL;

-- PASSO R-03 — Reverter registry para status = 'legacy'
--
-- UPDATE public.c6_contract_registry
-- SET
--     status     = 'legacy',
--     notes      = 'LEGADO RESTRITO (Sprint 5A — 2026-05-19). '
--               || 'EXECUTE revogado de authenticated. Apenas service_role mantém acesso. '
--               || 'Substituída por rpc_complete_lesson (Sprint 2 / P1-M1). '
--               || 'Mantida no banco para rollback de emergência via service_role. '
--               || 'Remoção (DROP): Sprint 5B — aguarda decisão institucional.',
--     updated_at = now()
-- WHERE contract_name = 'complete_lesson';

-- PASSO R-04 — Se frontend foi limpo (USE_LEGACY removido), restaurar manualmente
--   Ver diff em P5B_DEPRECATE_COMPLETE_LESSON_HANDOFF.md §6.2
--
-- Verificação pós-rollback completo:
--   SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'complete_lesson';
--   -- Esperado: 1 linha
--
--   SELECT contract_name, status FROM public.c6_contract_registry
--   WHERE contract_name = 'complete_lesson';
--   -- Esperado: status = 'legacy'

-- =============================================================================
-- SPRINT 6 PREVIEW — DROP definitivo (NÃO executar nesta migration)
-- =============================================================================
--
-- Após 30 dias de monitoramento sem chamadas a __deprecated_complete_lesson
-- (confirmar via telemetria Q-05), executar:
--
-- -- Migration: 20260619001000_p6_drop_deprecated_complete_lesson.sql
-- DROP FUNCTION IF EXISTS public.__deprecated_complete_lesson(uuid, uuid, integer);
--
-- UPDATE public.c6_contract_registry
-- SET status = 'blocked',
--     notes  = 'DROPADA em Sprint 6 (2026-06-19). Auditoria em P5B_HANDOFF.md.',
--     updated_at = now()
-- WHERE contract_name = 'complete_lesson';

-- =============================================================================
-- VEREDICTO: AGUARDANDO EXECUÇÃO
-- =============================================================================
-- Pré-condição 1: P5A aplicada em produção
-- Pré-condição 2: progressService.ts — bloco USE_LEGACY_COMPLETE_LESSON removido
-- Responsável: DBA / Supabase Admin
-- Executar: SQL Editor como service_role OU supabase db push
-- =============================================================================
