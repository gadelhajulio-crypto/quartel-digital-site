-- =============================================================================
-- Migration:  20260519001000_p4_m1_contract_registry_legacy_update.sql
-- Classificação: P4-M1 — Sprint 4 / Legacy Cleanup & Contract Consolidation
-- Data:       2026-05-19
-- Autor:      institutional-sprint4-2026-05-19
-- Revisão:    AGUARDANDO EXECUÇÃO — não executar sem aprovação institucional
-- =============================================================================
--
-- OBJETIVO
-- --------
-- Atualizar o c6_contract_registry para refletir o estado arquitetural real
-- após Sprint 2 (rpc_complete_lesson validado end-to-end) e Sprint 3
-- (identidade canônica migrada no frontend).
--
-- OPERAÇÕES
-- ---------
-- 1. complete_lesson       → UPDATE status = 'legacy'
-- 2. rpc_complete_lesson   → UPDATE notes (adiciona validação Sprint 2 QA)
-- 3. v_lessons_panel       → INSERT 'canonical' (Fix-01 — não estava no registry)
-- 4. v_lesson_progress_panel → INSERT 'canonical' (Fix-02 — não estava no registry)
--
-- O QUE NÃO MUDA
-- ---------------
-- - Nenhuma função RPC é alterada.
-- - Nenhuma view é alterada.
-- - Nenhuma tabela é alterada.
-- - Apenas metadados em c6_contract_registry são modificados.
-- - complete_lesson NÃO é removida — apenas marcada como legacy no registry.
-- - lesson_progress NÃO é removida — não pertence ao registry (contract_type
--   não inclui 'table'; remoção tratada em Sprint 5 migration separada).
--
-- IDEMPOTÊNCIA
-- -------------
-- UPDATE: reexecutar com mesmo status/notes é no-op funcional.
-- INSERT ... ON CONFLICT DO UPDATE: sempre seguro para reexecução.
--
-- RISCO
-- -----
-- MÍNIMO — apenas metadados. Zero impacto em dados funcionais ou no frontend.
-- Reversível com os blocos de rollback ao final.
--
-- PRÉ-CONDIÇÕES
-- -------------
-- 1. Fix-01 (20260518001000) aplicado em produção — v_lessons_panel tem video_url/pdf_url
-- 2. Fix-02 (20260518002000) aplicado em produção — v_lesson_progress_panel → recruta_progresso
-- 3. Sprint 2 QA aprovado — rpc_complete_lesson validado end-to-end no Expo Go
-- 4. Sprint 3 frontend migrado — useCanonicalIdentity() ativo nos consumers críticos
--
-- REFERÊNCIAS
-- -----------
-- Inventário Sprint 3:     supabase/baseline/SPRINT3_CANONICAL_IDENTITY.md
-- Fix-01/Fix-02 handoff:   supabase/baseline/FIX_01_02_HANDOFF.md
-- Sprint 4 handoff:        supabase/baseline/SPRINT4_LEGACY_CLEANUP_HANDOFF.md
-- P1-M1 (rpc_complete_lesson): supabase/migrations/20260517001000_p1_m1_create_rpc_complete_lesson.sql
-- P1-M1.1 (auth fix):     supabase/migrations/20260517002000_p1_m1_1_fix_rpc_complete_lesson_auth_id_resolution.sql
-- =============================================================================


-- =============================================================================
-- PASSO 1 — Marcar complete_lesson como legacy
-- =============================================================================
-- Estado anterior: status = 'canonical' (inserido em P0-M5 com nota de risco)
-- Estado novo:     status = 'legacy'
--
-- Justificativa:
--   - Frontend migrado para rpc_complete_lesson em Sprint 2 Fase 2
--   - progressService.ts:54 retém a assinatura (userId param) mas rota para
--     rpc_complete_lesson internamente (USE_LEGACY_COMPLETE_LESSON = false)
--   - complete_lesson ainda existe no banco para rollback rápido (flag DEV)
--   - Remoção planejada para Sprint 5 após 30 dias de monitoramento sem chamadas
--
-- Idempotência: UPDATE de status='canonical' para status='legacy' é idempotente
-- (executar novamente quando já='legacy' não muda nada).

UPDATE public.c6_contract_registry
SET
    status     = 'legacy',
    notes      = 'LEGADO (Sprint 4 — 2026-05-19). '
              || 'Substituída por rpc_complete_lesson (Sprint 2 / P1-M1). '
              || 'Frontend migrado: progressService.ts usa rpc_complete_lesson por padrão. '
              || 'Mantida em coexistência para rollback de emergência via USE_LEGACY_COMPLETE_LESSON flag (DEV only). '
              || 'Escrita em: recruta_progresso (source=''lesson_complete'') + xp_eventos (origem=''lesson_complete''). '
              || 'Difere de rpc_complete_lesson: usa p_recruta_id externo (risco SEC-03, mitigado por P0-M6) '
              || 'e p_xp externo (risco de manipulação). '
              || 'Pré-condição para remoção (Sprint 5): '
              || '(a) 30+ dias sem chamadas com source=''lesson_complete'' em recruta_progresso de authenticated; '
              || '(b) USE_LEGACY_COMPLETE_LESSON removido do progressService; '
              || '(c) QA completo em staging com rpc_complete_lesson exclusivo.',
    updated_at = now()
WHERE contract_name = 'complete_lesson';


-- =============================================================================
-- PASSO 2 — Atualizar notas de rpc_complete_lesson (status permanece 'canonical')
-- =============================================================================
-- Adiciona registro do Sprint 2 QA e do fix P1-M1.1 (auth_id resolution).

UPDATE public.c6_contract_registry
SET
    notes      = 'CANONICAL — Sprint 2 QA aprovado 2026-05-19 (Expo Go end-to-end). '
              || 'Server-authoritative: resolve recruta_id via recrutas.auth_id = auth.uid() (P1-M1.1 fix). '
              || 'aulas.xp_valor como fonte única de XP. '
              || 'GRANT EXECUTE TO authenticated. Requer onboarding concluído (forca definida). '
              || 'xp_valor=0: lesson registrada em recruta_progresso mas xp_eventos não inserido (CHECK quantidade>0). '
              || 'source=''rpc_complete_lesson'' em recruta_progresso para rastreabilidade. '
              || 'Substitui complete_lesson (agora legacy). '
              || 'Assinatura: rpc_complete_lesson(p_lesson_id uuid) RETURNS json. '
              || 'Frontend: progressService.completeLesson() → supabase.rpc(''rpc_complete_lesson'', {p_lesson_id}).',
    updated_at = now()
WHERE contract_name = 'rpc_complete_lesson';


-- =============================================================================
-- PASSO 3 — Registrar v_lessons_panel (não estava no registry)
-- =============================================================================
-- Fix-01 (20260518001000) adicionou video_url e pdf_url à view.
-- Esta view não foi incluída em P0-M5 pois não constava no P0_M5_CONTRACT_SELECTION.md.
-- Sprint 4 formaliza seu status canônico.
--
-- ON CONFLICT DO UPDATE: se por alguma razão já existe, atualiza notas e status.

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
    'v_lessons_panel',
    'view',
    'canonical',
    'detalhe de aula — useLessonData (select *), ModuleLessonsScreen (select video_url, pdf_url)',
    'Fix-01 2026-05-18: adicionados video_url e pdf_url da tabela aulas. '
    || 'Colunas: lesson_id, title, module(UUID), lesson_order, force, video_url, pdf_url (7 total). '
    || 'JOIN aulas × modulos. Filtro por force (forca do módulo). '
    || 'GRANT SELECT TO authenticated. '
    || 'Callers: useLessonData.ts (.eq lesson_id), ModuleLessonsScreen.tsx (.eq module, select video_url,pdf_url). '
    || 'Observação: não tem filtro por recruta — leitura pública por authenticated (RLS não aplicável a aulas).',
    now(), now()
)
ON CONFLICT (contract_name) DO UPDATE SET
    status     = 'canonical',
    notes      = EXCLUDED.notes,
    updated_at = now();


-- =============================================================================
-- PASSO 4 — Registrar v_lesson_progress_panel (não estava no registry)
-- =============================================================================
-- Fix-02 (20260518002000) migrou a view de lesson_progress (legada) para
-- recruta_progresso (canônica). Dual-alias recruta_id + user_id preserva
-- contratos de ambos os consumers.
--
-- ON CONFLICT DO UPDATE: se por alguma razão já existe, atualiza notas e status.

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
    'v_lesson_progress_panel',
    'view',
    'canonical',
    'progresso de aula — useLessonData (.eq recruta_id), ModuleLessonsScreen (.eq user_id alias)',
    'Fix-02 2026-05-18: fonte migrada de lesson_progress (legada) para recruta_progresso (canônica). '
    || 'Dual-alias: recruta_id (canônico) + recruta_id AS user_id (compat legado). '
    || 'Colunas: recruta_id, user_id, lesson_id, completed_at, xp_granted, source (6 total). '
    || 'WHERE status=''completed'' AND completed_at IS NOT NULL. '
    || 'RLS herdado de recruta_progresso: SELECT filtra por recrutas.auth_id = auth.uid(). '
    || 'GRANT SELECT TO authenticated. '
    || 'Sprint 5: remover alias user_id após remoção de callers legados em ModuleLessonsScreen. '
    || 'Blocker para remoção de user_id: ModuleLessonsScreen.tsx usa .eq(''user_id'', recruta_id) — '
    || 'funcional pós-Fix-03, mas alias pode ser removido quando query for atualizada para recruta_id direto.',
    now(), now()
)
ON CONFLICT (contract_name) DO UPDATE SET
    status     = 'canonical',
    notes      = EXCLUDED.notes,
    updated_at = now();


-- =============================================================================
-- TESTES SQL PÓS-APPLY
-- (executar após migration — NÃO parte da migration)
-- =============================================================================

-- TESTE T-01 — complete_lesson está como legacy?
--
--   SELECT contract_name, status, notes
--   FROM public.c6_contract_registry
--   WHERE contract_name = 'complete_lesson';
--   -- Esperado: status = 'legacy', notes contém 'LEGADO (Sprint 4'

-- TESTE T-02 — rpc_complete_lesson ainda é canonical?
--
--   SELECT contract_name, status
--   FROM public.c6_contract_registry
--   WHERE contract_name = 'rpc_complete_lesson';
--   -- Esperado: status = 'canonical'

-- TESTE T-03 — v_lessons_panel registrada?
--
--   SELECT contract_name, status, frontend_scope
--   FROM public.c6_contract_registry
--   WHERE contract_name = 'v_lessons_panel';
--   -- Esperado: 1 linha, status = 'canonical'

-- TESTE T-04 — v_lesson_progress_panel registrada?
--
--   SELECT contract_name, status, notes
--   FROM public.c6_contract_registry
--   WHERE contract_name = 'v_lesson_progress_panel';
--   -- Esperado: 1 linha, status = 'canonical', notes contém 'Fix-02'

-- TESTE T-05 — Contagem por status?
--
--   SELECT status, COUNT(*)
--   FROM public.c6_contract_registry
--   GROUP BY status
--   ORDER BY status;
--   -- Esperado: canonical >= 40, legacy >= 1

-- TESTE T-06 — Idempotência: reexecutar não muda contagens?
--
--   -- Executar migration novamente.
--   -- Esperado: mesmas contagens (UPDATEs idempotentes, INSERTs ON CONFLICT DO UPDATE)


-- =============================================================================
-- ROLLBACK (executar APENAS se necessário reverter P4-M1)
-- =============================================================================

-- R-01: Reverter complete_lesson para canonical
--
-- UPDATE public.c6_contract_registry
-- SET
--     status     = 'canonical',
--     notes      = 'RISCO ATIVO: aceita p_recruta_id como parâmetro externo. '
--               || 'Mitigado por grants service_role only. Correção planejada em P0-M6.',
--     updated_at = now()
-- WHERE contract_name = 'complete_lesson';

-- R-02: Reverter notas de rpc_complete_lesson para versão P1-M1
--
-- UPDATE public.c6_contract_registry
-- SET
--     notes      = 'Server-authoritative: auth.uid() como recruta_id, aulas.xp_valor como XP. '
--               || 'GRANT EXECUTE TO authenticated. '
--               || 'Requer onboarding concluído (forca definida). '
--               || 'xp_valor=0: lesson registrada mas xp_eventos não inserido (CHECK quantidade>0). '
--               || 'Depreca complete_lesson — mantida em coexistência durante Sprint 2.',
--     updated_at = now()
-- WHERE contract_name = 'rpc_complete_lesson';

-- R-03: Remover v_lessons_panel e v_lesson_progress_panel do registry
--
-- DELETE FROM public.c6_contract_registry
-- WHERE contract_name IN ('v_lessons_panel', 'v_lesson_progress_panel');
--
-- Verificação pós-rollback:
--   SELECT contract_name FROM public.c6_contract_registry
--   WHERE contract_name IN ('complete_lesson', 'rpc_complete_lesson',
--                           'v_lessons_panel', 'v_lesson_progress_panel');
--   -- Esperado: 2 linhas (complete_lesson canonical, rpc_complete_lesson canonical)
--               0 para v_lessons_panel e v_lesson_progress_panel

-- =============================================================================
-- VEREDICTO: AGUARDANDO EXECUÇÃO
-- =============================================================================
-- Pré-condições: Fix-01 e Fix-02 aplicados em produção (AGUARDANDO)
-- Responsável: DBA / Supabase Admin
-- Executar: SQL Editor como service_role OU supabase db push
-- =============================================================================
