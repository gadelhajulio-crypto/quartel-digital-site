-- =============================================================================
-- Migration:  20260516002000_p0_m2_register_baseline_audit.sql
-- Classificação: P0-M2 — Rastreabilidade
-- Data:       2026-05-16
-- Autor:      institutional-audit-2026-05-16
-- Revisão:    AGUARDANDO APROVAÇÃO — não executar sem aprovação institucional
-- =============================================================================
--
-- OBJETIVO
-- --------
-- Registrar no banco que o baseline remoto de 2026-05-16 foi auditado,
-- revisado e aprovado institucionalmente. O registro é feito na tabela
-- public._qd_migration_snapshots, que funciona como ledger de rastreabilidade
-- das auditorias e do estado do schema em momentos específicos.
--
-- ESTRUTURA DA TABELA (dump ln 9018–9022)
-- ----------------------------------------
--   CREATE TABLE IF NOT EXISTS "public"."_qd_migration_snapshots" (
--       "migration_id" text     NOT NULL,          ← PK
--       "applied_at"   timestamptz DEFAULT now(),
--       "snapshot"     jsonb    NOT NULL
--   );
--   PK: _qd_migration_snapshots_pkey ON (migration_id)
--
-- NOTA SOBRE COLUNA
-- -----------------
-- O rascunho em P0_DECISION_PACKET.md §2 usou nomes de coluna incorretos
-- (snapshot_key, snapshot_data, created_at). Esta migration usa os nomes
-- REAIS confirmados no dump: migration_id, applied_at, snapshot.
--
-- O QUE NÃO MUDA
-- ---------------
-- - Nenhuma tabela funcional do app é alterada.
-- - Nenhum dado de recruta, sessão, XP, chat ou billing é tocado.
-- - Nenhuma view, RPC, trigger ou policy é criada ou alterada.
-- - A migration é puramente um INSERT de metadados de rastreabilidade.
--
-- IDEMPOTÊNCIA
-- -------------
-- ON CONFLICT (migration_id) DO NOTHING garante que reexecutar a migration
-- (em staging múltiplas vezes, ou acidentalmente em produção) não gera erro
-- e não sobrescreve o registro original.
--
-- RISCO
-- -----
-- MÍNIMO — append-only em tabela de rastreabilidade interna.
-- Sem impacto em dados funcionais. Sem impacto no frontend.
-- Reversível com DELETE de uma linha.
--
-- =============================================================================

INSERT INTO public._qd_migration_snapshots (
    migration_id,
    applied_at,
    snapshot
)
VALUES (
    'baseline_audit_2026_05_16',
    now(),
    jsonb_build_object(

        -- ── Identificação do baseline ────────────────────────────────────────
        'baseline_date',            '2026-05-16',
        'auditor',                  'institutional-audit-2026-05-16',
        'dump_source',              'supabase/remote/supabase_remote_schema.sql',
        'audit_documents',          jsonb_build_array(
            'supabase/baseline/BASELINE_INDEX.md',
            'supabase/baseline/DRIFT_REPORT.md',
            'supabase/baseline/CRITICAL_CONTRACTS_CHECK.md',
            'supabase/baseline/SECURITY_DEFINER_AUDIT.md',
            'supabase/baseline/RLS_POLICY_AUDIT.md',
            'supabase/baseline/modules/02_auth_identity_onboarding.sql',
            'supabase/baseline/modules/03_chat_rcc_05_wave1.sql',
            'supabase/baseline/modules/04_c5_eventos_medalhas_patentes.sql',
            'supabase/baseline/modules/05_learning_modules_lessons_progress.sql',
            'supabase/baseline/modules/06_billing.sql',
            'supabase/baseline/modules/07_ranking_iea_elite.sql',
            'supabase/baseline/modules/08_storage_assets.sql',
            'supabase/baseline/modules/09_rls_policies_grants.sql',
            'supabase/baseline/modules/10_functions_rpcs.sql',
            'supabase/baseline/modules/11_views_contracts.sql',
            'supabase/baseline/modules/12_triggers_indexes_constraints.sql'
        ),

        -- ── Contagens do dump remoto (aproximadas — auditoria manual) ────────
        'schema_counts',            jsonb_build_object(
            'tables',               85,
            'views',                110,
            'materialized_views',   6,
            'functions',            80,
            'triggers',             15,
            'rls_policies',         130,
            'indexes',              120
        ),

        -- ── Achados de segurança confirmados ─────────────────────────────────
        'security_issues_confirmed', jsonb_build_array(
            jsonb_build_object(
                'id',           'SEC-01',
                'object',       'public.buscar_revisoes_whatsapp()',
                'finding',      'SECURITY DEFINER sem SET search_path',
                'severity',     'ALTO',
                'migration',    'P0-M1 — 20260516001000',
                'status',       'MIGRATION_GERADA'
            ),
            jsonb_build_object(
                'id',           'SEC-02',
                'object',       'public.xp_events',
                'finding',      'INSERT direto permitido para authenticated via policy "Usuário cria XP events"',
                'severity',     'MEDIO',
                'migration',    'P0-M4 — 20260516004000',
                'status',       'MIGRATION_GERADA'
            ),
            jsonb_build_object(
                'id',           'SEC-03',
                'object',       'public.complete_lesson(p_recruta_id, p_lesson_id, p_xp)',
                'finding',      'Aceita p_recruta_id como parâmetro externo — design inseguro mitigado por grants service_role',
                'severity',     'MEDIO_ALTO',
                'migration',    'P0-M6 — 20260516006000',
                'status',       'PLANEJADA_ALTO_RISCO'
            ),
            jsonb_build_object(
                'id',           'SEC-04',
                'object',       'public.emitir_evento_c5',
                'finding',      'Exposta a authenticated — vetor de eventos institucionais não autorizados',
                'severity',     'MEDIO',
                'migration',    'Planejada — Sprint 2',
                'status',       'PENDENTE_ANALISE'
            ),
            jsonb_build_object(
                'id',           'SEC-05',
                'object',       'mv_xp_mensal_recruta, mv_ranking_mensal, mv_campeao_mensal',
                'finding',      'Sem REFRESH agendado — ranking permanentemente desatualizado',
                'severity',     'OPERACIONAL',
                'migration',    'Planejada — Sprint 2 (pg_cron)',
                'status',       'PENDENTE_ANALISE'
            ),
            jsonb_build_object(
                'id',           'SEC-06',
                'object',       'public.rpc_complete_onboarding',
                'finding',      'Duas sobrecargas coexistem — versão sem parâmetros pode ser chamada por engano',
                'severity',     'BAIXO',
                'migration',    'Planejada — Sprint 3 (após confirmar zero callers)',
                'status',       'PENDENTE_ANALISE'
            )
        ),

        -- ── Falsos positivos identificados durante a auditoria ───────────────
        'false_positives_found',    jsonb_build_array(
            jsonb_build_object(
                'id',           'FP-01',
                'object',       'public.fn_insert_audit_evento_smart',
                'claim',        'Alegado como SECURITY INVOKER com bug de auditoria inoperante',
                'reality',      'Função não existe no dump. v_audit_eventos é view read-only (UNION ALL). Auditoria de chat opera via Edge Functions por design.',
                'evidence',     'grep no dump: 0 ocorrências. v_audit_eventos ln 11465-11494.',
                'migration',    'P0-M3 — CANCELADA (ver P0_M3_VOID_HANDOFF.md)',
                'status',       'VOID'
            )
        ),

        -- ── Contratos críticos confirmados no dump ───────────────────────────
        'critical_contracts_confirmed', jsonb_build_array(
            'v_app_bootstrap_institucional_rcc',
            'v_identidade_recruta',
            'v_auth_app_config',
            'v_onboarding_status',
            'v_chat_conversas_recruta',
            'v_chat_mensagens_recruta',
            'v_chat_unread_status',
            'rpc_chat_open_conversation',
            'rpc_chat_send_message',
            'rpc_chat_mark_read',
            'vw_rdm_lessons_v2',
            'vw_recruta_module_progress_v2',
            'v_billing_status_recruta_v2',
            'v_instrutores_app',
            'v_ranking_mensal_rcc',
            'v_posicao_recruta_mes_rcc',
            'v_iea_atual_v2',
            'v_elegibilidade_elite_v2',
            'v_classificacao_final_ciclo_v2',
            'rpc_complete_onboarding',
            'rpc_auth_claim_active_client_session',
            'rpc_auth_resolve_session_state',
            'rpc_auth_revoke_client_session',
            'rpc_update_instructor_profile',
            'complete_lesson'
        ),

        -- ── Contratos ausentes (P0 crítico) ─────────────────────────────────
        'contracts_missing',        jsonb_build_array(
            jsonb_build_object(
                'object',   'v_completed_lessons_count',
                'consumer', 'src/hooks/useRecruitPanel.ts:62',
                'severity', 'P0_CRITICO',
                'action',   'Migration adicional: 20260516007000_recreate_v_completed_lessons_count.sql'
            )
        ),

        -- ── Migrations P0 geradas nesta auditoria ────────────────────────────
        'p0_migrations',            jsonb_build_object(
            'P0-M1', jsonb_build_object(
                'file',   '20260516001000_p0_m1_fix_buscar_revisoes_whatsapp_search_path.sql',
                'status', 'GERADA_AGUARDANDO_EXECUCAO'
            ),
            'P0-M2', jsonb_build_object(
                'file',   '20260516002000_p0_m2_register_baseline_audit.sql',
                'status', 'ESTA_MIGRATION'
            ),
            'P0-M3', jsonb_build_object(
                'file',   'VOID — falso positivo confirmado',
                'status', 'CANCELADA'
            ),
            'P0-M4', jsonb_build_object(
                'file',   '20260516004000_p0_m4_block_xp_events_legacy_insert.sql',
                'status', 'GERADA_AGUARDANDO_EXECUCAO'
            ),
            'P0-M5', jsonb_build_object(
                'file',   '20260516005000_p0_m5_register_contract_registry.sql',
                'status', 'PLANEJADA'
            ),
            'P0-M6', jsonb_build_object(
                'file',   '20260516006000_p0_m6_fix_complete_lesson_auth_uid.sql',
                'status', 'PLANEJADA_ALTO_RISCO'
            )
        )
    )
)
ON CONFLICT (migration_id) DO NOTHING;

-- =============================================================================
-- TESTES SQL PÓS-APPLY (executar após migration — NÃO parte da migration)
-- =============================================================================
--
-- TESTE 1 — Registro foi inserido?
--
--   SELECT migration_id, applied_at
--   FROM public._qd_migration_snapshots
--   WHERE migration_id = 'baseline_audit_2026_05_16';
--   -- Esperado: 1 linha com applied_at próximo de now()
--
-- TESTE 2 — Snapshot contém os campos esperados?
--
--   SELECT
--       snapshot->>'baseline_date'    AS baseline_date,
--       snapshot->>'auditor'          AS auditor,
--       jsonb_array_length(snapshot->'security_issues_confirmed') AS security_issues,
--       jsonb_array_length(snapshot->'false_positives_found')     AS false_positives,
--       jsonb_array_length(snapshot->'critical_contracts_confirmed') AS contracts_ok,
--       jsonb_array_length(snapshot->'contracts_missing')         AS contracts_missing
--   FROM public._qd_migration_snapshots
--   WHERE migration_id = 'baseline_audit_2026_05_16';
--   -- Esperado:
--   --   baseline_date  | 2026-05-16
--   --   auditor        | institutional-audit-2026-05-16
--   --   security_issues| 6
--   --   false_positives| 1
--   --   contracts_ok   | 25
--   --   contracts_missing | 1
--
-- TESTE 3 — Idempotência: reexecutar não gera erro nem duplicata?
--
--   -- Executar novamente o INSERT acima.
--   -- Esperado: INSERT 0 0 (zero linhas inseridas — ON CONFLICT DO NOTHING)
--
--   SELECT COUNT(*) FROM public._qd_migration_snapshots
--   WHERE migration_id = 'baseline_audit_2026_05_16';
--   -- Esperado: 1 (apenas uma linha, mesmo após reexecução)
--
-- TESTE 4 — applied_at não foi sobrescrito pela reexecução?
--
--   -- Registrar applied_at original antes de reexecutar:
--   SELECT applied_at FROM public._qd_migration_snapshots
--   WHERE migration_id = 'baseline_audit_2026_05_16';
--   -- Executar o INSERT novamente.
--   -- Consultar applied_at novamente — deve ser idêntico ao original.
--   -- Esperado: mesmo timestamp (ON CONFLICT DO NOTHING não atualiza)
--
-- =============================================================================
-- ROLLBACK (executar APENAS se a migration precisar ser revertida)
-- =============================================================================
--
-- DELETE FROM public._qd_migration_snapshots
-- WHERE migration_id = 'baseline_audit_2026_05_16';
--
-- Verificação pós-rollback:
--   SELECT COUNT(*) FROM public._qd_migration_snapshots
--   WHERE migration_id = 'baseline_audit_2026_05_16';
--   -- Esperado: 0
--
-- =============================================================================
-- REFERÊNCIAS
-- =============================================================================
-- Dump remoto (tabela):    supabase/remote/supabase_remote_schema.sql ln 9018–9022
-- Dump remoto (PK):        supabase/remote/supabase_remote_schema.sql ln 14831–14832
-- Decision Packet (P0-M2): supabase/baseline/P0_DECISION_PACKET.md §2
-- Handoff:                 supabase/baseline/P0_M2_HANDOFF.md
-- =============================================================================
