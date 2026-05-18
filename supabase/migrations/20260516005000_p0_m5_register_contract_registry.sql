-- =============================================================================
-- Migration:  20260516005000_p0_m5_register_contract_registry.sql
-- Classificação: P0-M5 — Rastreabilidade de Contratos
-- Data:       2026-05-16
-- Autor:      institutional-audit-2026-05-16
-- Revisão:    AGUARDANDO APROVAÇÃO — não executar sem aprovação institucional
-- =============================================================================
--
-- OBJETIVO
-- --------
-- Registrar os contratos canônicos ativos do RCC-0.5 na tabela
-- public.c6_contract_registry, fornecendo um catálogo consultável de todos
-- os objetos SQL consumidos pelo app mobile em produção.
--
-- O registro permite que auditorias futuras façam:
--   SELECT * FROM v_c6_contracts_validos;
-- para obter a lista de contratos ativos sem precisar grep no codebase.
--
-- ESTRUTURA REAL DA TABELA (dump ln 9765–9775)
-- ---------------------------------------------
-- CREATE TABLE IF NOT EXISTS "public"."c6_contract_registry" (
--     "contract_name"  text        NOT NULL,          ← PK
--     "contract_type"  text        NOT NULL,          ← CHECK: 'view','materialized_view','rpc'
--     "status"         text        NOT NULL,          ← CHECK: 'canonical','system','legacy','admin_audit','blocked'
--     "frontend_scope" text,                          ← nullable — descrição do consumer
--     "notes"          text,                          ← nullable — observações
--     "registered_at"  timestamptz DEFAULT now(),
--     "updated_at"     timestamptz DEFAULT now()
-- );
-- PK: c6_contract_registry_pkey ON (contract_name)
-- RLS: ENABLED — sem policies → deny-by-default para authenticated/anon
-- GRANT: nenhum explícito no dump → apenas owner (postgres) e service_role têm acesso
--
-- NOTA CRÍTICA SOBRE DIVERGÊNCIA DO RASCUNHO
-- -------------------------------------------
-- O rascunho em P0_DECISION_PACKET.md §2 usou colunas e valores INCORRETOS:
--   Rascunho (errado)          Dump real (correto)
--   ─────────────────────────  ──────────────────────────────────────────
--   object_name                contract_name
--   object_type                contract_type
--   domain                     (coluna não existe)
--   status = 'ACTIVE'          status = 'canonical'  (CHECK constraint)
--   validated_at               (coluna não existe — é registered_at)
--
-- Esta migration usa EXCLUSIVAMENTE os nomes reais confirmados no dump.
--
-- VERIFICAÇÃO DOS 7 CONTRATOS CONDICIONAIS (realizada em 2026-05-16)
-- -------------------------------------------------------------------
-- Resultado do grep no dump remoto:
--   v_institutional_notices        → CONFIRMADO (ln 13098) → incluído
--   v_instructor_messages          → CONFIRMADO (ln 13112) → incluído
--   v_modulos_catalogo             → CONFIRMADO (ln 13436) → incluído
--   v_available_reviews            → NÃO ENCONTRADO        → excluído
--   v_review_content               → NÃO ENCONTRADO        → excluído
--   rpc_mark_instructor_message_read → NÃO ENCONTRADO      → excluído
--   rpc_complete_module            → NÃO ENCONTRADO        → excluído
--
-- Os 4 itens ausentes do dump requerem investigação separada:
--   v_available_reviews, v_review_content → verificar se foram dropadas ou renomeadas
--   rpc_complete_module → verificar se função existe com nome diferente
--   rpc_mark_instructor_message_read → tabela instructor_message_reads existe (ln 10263)
--                                      mas a RPC não está no dump
--
-- TOTAL DE CONTRATOS REGISTRADOS: 38
--   Views:  25  (status = 'canonical')
--   RPCs:   13  (status = 'canonical'; complete_lesson com notes de risco)
--
-- O QUE NÃO MUDA
-- ---------------
-- - Nenhuma view ou RPC é alterada.
-- - Nenhuma RLS policy é criada ou alterada.
-- - Nenhum dado funcional do app é tocado.
-- - A migration é puramente INSERT de metadados em tabela interna.
--
-- IDEMPOTÊNCIA
-- -------------
-- ON CONFLICT (contract_name) DO NOTHING garante reexecução segura.
--
-- RISCO
-- -----
-- MÍNIMO — append-only em tabela de registry interna.
-- Sem impacto em dados funcionais. Sem impacto no frontend.
-- Reversível com DELETE WHERE registered_at >= '<timestamp>'.
--
-- =============================================================================

INSERT INTO public.c6_contract_registry (
    contract_name,
    contract_type,
    status,
    frontend_scope,
    notes,
    registered_at,
    updated_at
)
VALUES

    -- =========================================================================
    -- DOMÍNIO: AUTH / IDENTIDADE
    -- =========================================================================

    (
        'v_identidade_recruta',
        'view',
        'canonical',
        'login bootstrap — perfil completo recruta+profiles',
        NULL,
        now(), now()
    ),
    (
        'v_auth_app_config',
        'view',
        'canonical',
        'auth_contract_version — cold-start config',
        NULL,
        now(), now()
    ),
    (
        'v_app_bootstrap_institucional_rcc',
        'view',
        'canonical',
        'RCC cold-start bootstrap (security_invoker=true)',
        NULL,
        now(), now()
    ),
    (
        'v_onboarding_status',
        'view',
        'canonical',
        'fluxo de onboarding por auth.uid()',
        NULL,
        now(), now()
    ),
    (
        'rpc_auth_claim_active_client_session',
        'rpc',
        'canonical',
        'heartbeat de sessão por dispositivo',
        NULL,
        now(), now()
    ),
    (
        'rpc_auth_resolve_session_state',
        'rpc',
        'canonical',
        'estado institucional da sessão',
        NULL,
        now(), now()
    ),
    (
        'rpc_auth_revoke_client_session',
        'rpc',
        'canonical',
        'logout — revoga sessão específica',
        NULL,
        now(), now()
    ),
    (
        'rpc_complete_onboarding',
        'rpc',
        'canonical',
        'registro de força e nome de guerra',
        'Atenção: duas sobrecargas no dump (ln 5983 sem params — obsoleta; ln 6053 com params — esta). Sprint 3: deprecar versão sem params.',
        now(), now()
    ),

    -- =========================================================================
    -- DOMÍNIO: CHAT (RCC Wave 1)
    -- =========================================================================

    (
        'v_chat_conversas_recruta',
        'view',
        'canonical',
        'lista de conversas por instrutor (security_invoker=true)',
        NULL,
        now(), now()
    ),
    (
        'v_chat_mensagens_recruta',
        'view',
        'canonical',
        'mensagens por conversa (security_invoker=true)',
        NULL,
        now(), now()
    ),
    (
        'v_chat_unread_status',
        'view',
        'canonical',
        'badge de não lidas por conversa (security_invoker=true)',
        NULL,
        now(), now()
    ),
    (
        'rpc_chat_open_conversation',
        'rpc',
        'canonical',
        'inicia ou recupera conversa com instrutor',
        NULL,
        now(), now()
    ),
    (
        'rpc_chat_send_message',
        'rpc',
        'canonical',
        'envia mensagem na conversa',
        NULL,
        now(), now()
    ),
    (
        'rpc_chat_mark_read',
        'rpc',
        'canonical',
        'marca mensagens como lidas',
        NULL,
        now(), now()
    ),

    -- =========================================================================
    -- DOMÍNIO: INSTRUTORES E ASSETS
    -- =========================================================================

    (
        'v_instrutores_app',
        'view',
        'canonical',
        'instrutores ativos com URLs de avatar (security_invoker=true)',
        NULL,
        now(), now()
    ),
    (
        'v_institutional_assets',
        'view',
        'canonical',
        'assets institucionais ativos',
        NULL,
        now(), now()
    ),
    (
        'v_institutional_notices',
        'view',
        'canonical',
        'avisos institucionais — useInstitutionalNotices, useRecruitPanel',
        NULL,
        now(), now()
    ),
    (
        'v_instructor_messages',
        'view',
        'canonical',
        'mensagens de instrutor — useInstructorMessages',
        NULL,
        now(), now()
    ),
    (
        'rpc_update_instructor_profile',
        'rpc',
        'canonical',
        'atualiza perfil de instrutor selecionado',
        NULL,
        now(), now()
    ),
    (
        'rpc_mark_notice_read',
        'rpc',
        'canonical',
        'marca aviso institucional como lido (idempotente)',
        NULL,
        now(), now()
    ),

    -- =========================================================================
    -- DOMÍNIO: APRENDIZAGEM
    -- =========================================================================

    (
        'vw_rdm_lessons_v2',
        'view',
        'canonical',
        'lista de aulas do recruta com status (auth.uid())',
        NULL,
        now(), now()
    ),
    (
        'vw_recruta_module_progress_v2',
        'view',
        'canonical',
        'progresso por módulo com percentual (auth.uid())',
        NULL,
        now(), now()
    ),
    (
        'v_modulos_catalogo',
        'view',
        'canonical',
        'catálogo de módulos com is_degustacao — InstructionsInProgress',
        NULL,
        now(), now()
    ),
    (
        'complete_lesson',
        'rpc',
        'canonical',
        'registra conclusão de aula + XP (via progressService)',
        'RISCO ATIVO: aceita p_recruta_id como parâmetro externo. Mitigado por grants service_role only. Correção planejada em P0-M6.',
        now(), now()
    ),
    (
        'rpc_start_module',
        'rpc',
        'canonical',
        'inicia módulo — upsert idempotente em recruta_modulos',
        NULL,
        now(), now()
    ),
    (
        'get_student_next_lesson',
        'rpc',
        'canonical',
        'próxima aula do recruta — useRecruitPanel',
        NULL,
        now(), now()
    ),

    -- =========================================================================
    -- DOMÍNIO: GAMIFICAÇÃO (C5)
    -- =========================================================================

    (
        'v_eventos_pendentes',
        'view',
        'canonical',
        'fila de eventos C5 não processados — c5EventsService',
        NULL,
        now(), now()
    ),
    (
        'consumir_evento_c5',
        'rpc',
        'canonical',
        'marca evento C5 como processado (idempotente)',
        NULL,
        now(), now()
    ),

    -- =========================================================================
    -- DOMÍNIO: GAMIFICAÇÃO (MEDALHAS E HISTÓRICO)
    -- =========================================================================

    (
        'v_medals_status_v3',
        'view',
        'canonical',
        'status de medalhas do recruta — useMedals',
        NULL,
        now(), now()
    ),
    (
        'v_historico_atividade_recruta_v3',
        'view',
        'canonical',
        'histórico de atividade — useStudentHistory, useHistory',
        NULL,
        now(), now()
    ),

    -- =========================================================================
    -- DOMÍNIO: RANKING
    -- =========================================================================

    (
        'v_ranking_mensal_rcc',
        'view',
        'canonical',
        'ranking mensal por força (security_invoker=true) — RankingScreen',
        NULL,
        now(), now()
    ),
    (
        'v_posicao_recruta_mes_rcc',
        'view',
        'canonical',
        'posição do recruta no mês (security_invoker=true) — RankingScreen',
        NULL,
        now(), now()
    ),
    (
        'v_campeoes_mensais_rcc',
        'view',
        'canonical',
        'campeões mensais por força (security_invoker=true) — RankingScreen',
        NULL,
        now(), now()
    ),
    (
        'v_recruta_xp_total',
        'view',
        'canonical',
        'XP total do recruta — useRecruitPanel',
        NULL,
        now(), now()
    ),

    -- =========================================================================
    -- DOMÍNIO: IEA E ELITE
    -- =========================================================================

    (
        'v_iea_atual_v2',
        'view',
        'canonical',
        'score IEA atual do recruta — ieaService',
        NULL,
        now(), now()
    ),
    (
        'v_elegibilidade_elite_v2',
        'view',
        'canonical',
        'elegibilidade para elite — eliteService',
        NULL,
        now(), now()
    ),
    (
        'v_classificacao_final_ciclo_v2',
        'view',
        'canonical',
        'classificação por ciclo formativo — eliteService',
        NULL,
        now(), now()
    ),

    -- =========================================================================
    -- DOMÍNIO: BILLING
    -- =========================================================================

    (
        'v_billing_status_recruta_v2',
        'view',
        'canonical',
        'acesso liberado, plano atual, trial restante — billingService',
        NULL,
        now(), now()
    )

ON CONFLICT (contract_name) DO NOTHING;

-- =============================================================================
-- TESTES SQL PÓS-APPLY (executar após migration — NÃO parte da migration)
-- =============================================================================
--
-- TESTE 1 — Total de registros inseridos?
--
--   SELECT COUNT(*) FROM public.c6_contract_registry
--   WHERE status = 'canonical';
--   -- Esperado: 38
--
-- TESTE 2 — Contagem por tipo?
--
--   SELECT contract_type, COUNT(*)
--   FROM public.c6_contract_registry
--   WHERE status = 'canonical'
--   GROUP BY contract_type
--   ORDER BY contract_type;
--   -- Esperado:
--   --   rpc   | 13
--   --   view  | 25
--
-- TESTE 3 — complete_lesson tem nota de risco?
--
--   SELECT contract_name, notes
--   FROM public.c6_contract_registry
--   WHERE contract_name = 'complete_lesson';
--   -- Esperado: notes contém 'RISCO ATIVO'
--
-- TESTE 4 — v_c6_contracts_validos retorna os registros?
--   (esta view filtra status IN ('canonical','system'))
--
--   SELECT COUNT(*) FROM public.v_c6_contracts_validos;
--   -- Esperado: 38
--
-- TESTE 5 — Idempotência: reexecutar não gera erro nem duplicata?
--
--   -- Executar novamente o INSERT.
--   -- Esperado: INSERT 0 0 (zero linhas inseridas)
--   SELECT COUNT(*) FROM public.c6_contract_registry WHERE status = 'canonical';
--   -- Esperado: ainda 38
--
-- TESTE 6 — CHECK constraints respeitadas?
--
--   SELECT contract_name, contract_type, status
--   FROM public.c6_contract_registry
--   WHERE contract_type NOT IN ('view','materialized_view','rpc')
--      OR status NOT IN ('canonical','system','legacy','admin_audit','blocked');
--   -- Esperado: zero linhas (nenhum valor inválido)
--
-- =============================================================================
-- ROLLBACK (executar APENAS se a migration precisar ser revertida)
-- =============================================================================
--
-- DELETE FROM public.c6_contract_registry
-- WHERE registered_at >= '<timestamp_da_migration>';
--
-- Verificação pós-rollback:
--   SELECT COUNT(*) FROM public.c6_contract_registry WHERE status = 'canonical';
--   -- Esperado: 0 (assumindo que a tabela estava vazia antes)
--
-- =============================================================================
-- REFERÊNCIAS
-- =============================================================================
-- Dump remoto (tabela, ln 9765):      supabase/remote/supabase_remote_schema.sql
-- Dump remoto (PK, ln 14961):         supabase/remote/supabase_remote_schema.sql
-- Dump remoto (RLS, ln 17598):        supabase/remote/supabase_remote_schema.sql
-- Seleção de contratos:               supabase/baseline/P0_M5_CONTRACT_SELECTION.md
-- Handoff:                            supabase/baseline/P0_M5_HANDOFF.md
-- Decision Packet (P0-M5):            supabase/baseline/P0_DECISION_PACKET.md §2
-- =============================================================================
