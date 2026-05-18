-- =============================================================================
-- MÓDULO 10: Funções e RPCs — Catálogo de Segurança
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql + SECURITY_DEFINER_AUDIT.md
-- Domínio: Todas as funções públicas com metadados de segurança
-- Linhas relevantes: 800-6200 (funções), 18500-19000 (grants)
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- =============================================================================
-- CATÁLOGO DE FUNÇÕES — STATUS DE SEGURANÇA
-- =============================================================================
-- Funções SECURITY DEFINER com search_path:    ~85
-- Funções SECURITY DEFINER SEM search_path:      1 (buscar_revisoes_whatsapp)
-- Funções expostas a authenticated:             ~25
-- Funções expostas apenas a service_role:       ~60
-- Funções expostas a anon:                       ~2
-- =============================================================================

-- -----------------------------------------------------------------------------
-- FUNÇÕES CRÍTICAS — RPCs DO FRONTEND
-- Ordem: authenticated RPCs (contratos públicos do app)
-- -----------------------------------------------------------------------------

-- ── rpc_update_instructor_profile(p_instructor_profile_id text) ───────────────
-- SECURITY DEFINER, search_path=— (não confirmado no audit)
-- GRANT: authenticated
-- Migration: 20260513002000
-- Função: Atualiza profiles.instructor_profile_id para o recruta autenticado.
-- Validação: CHECK constraint em profiles.instructor_profile_id
--            (apenas 'objetivo','estrategico','didatico')

-- ── rpc_complete_onboarding(p_forca text, p_nome_guerra text) — v2 canônica ───
-- SECURITY DEFINER
-- GRANT: authenticated
-- Migration: 20260503011000 + 20260509001000 (fix upsert)
-- NOTA: Duas sobrecargas no remoto:
--   (1) rpc_complete_onboarding() — sem params (linha 5983) — obsoleta?
--   (2) rpc_complete_onboarding(p_forca, p_nome_guerra) — canônica (linha 6053)

-- ── rpc_auth_claim_active_client_session(p_client_instance_id text) ───────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Migration: 20260503003000
-- Função: Heartbeat de sessão por dispositivo (renova last_seen_at)

-- ── rpc_auth_resolve_session_state(p_client_instance_id text) → jsonb ────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Função: Retorna estado institucional completo (perfil + billing + config)

-- ── rpc_auth_revoke_client_session(p_session_id uuid) ────────────────────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Função: Revoga sessão específica (logout de outro dispositivo)

-- ── rpc_start_module(p_modulo_id uuid) → void ────────────────────────────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Migration: referenciada em MEMORY.md
-- Função: Upsert em recruta_modulos (first_access_at, status=started)

-- ── rpc_complete_module(p_modulo_id uuid) → void ─────────────────────────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Função: Completa módulo em recruta_modulos.
-- RISCO SEC-02: Chama registrar_xp diretamente (bônus XP via cliente, não idempotente)
-- Correção: Migration 11 move bônus para dentro da RPC

-- ── rpc_mark_notice_read(p_notice_id uuid) → void ────────────────────────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Função: Upsert em institutional_notice_reads. Idempotente.

-- ── rpc_mark_instructor_message_read(p_message_id uuid) → void ───────────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Função: Upsert em instructor_message_reads. Idempotente.

-- ── rpc_chat_open_conversation(p_instrutor_slug text) → uuid ─────────────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Sem migration local. RISCO ALTO.
-- Função: Cria ou recupera conversa com instrutor. Idempotente.

-- ── rpc_chat_send_message(p_conversa_id uuid, p_content text) → uuid ─────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Sem migration local. RISCO ALTO.
-- Função: Insere mensagem e enfileira processamento IA. NÃO idempotente.

-- ── rpc_chat_mark_read(p_conversa_id uuid) → void ────────────────────────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Sem migration local.
-- Função: Marca todas as mensagens da conversa como lidas. Idempotente.

-- ── rpc_billing_status_recruta() → jsonb ─────────────────────────────────────
-- SECURITY DEFINER
-- GRANT: authenticated, service_role
-- Linhas dump: 4954-5020
-- Função: Retorna status de assinatura completo do recruta autenticado.

-- ── consumir_evento_c5(p_evento_id uuid) → void ──────────────────────────────
-- SECURITY DEFINER, search_path=public
-- GRANT: authenticated
-- Função: Marca evento C5 como processado. Idempotente.

-- ── emitir_evento_c5(p_tipo text, p_payload jsonb) → uuid ────────────────────
-- SECURITY DEFINER
-- GRANT: authenticated, service_role — RISCO: recrutas emitem diretamente
-- Função: Insere evento institucional em eventos_institucionais.
-- Proteção: c5_guard_eventos_institucionais valida tipo_evento

-- ── c6_get_iea_score(p_recruta_id uuid) → numeric ────────────────────────────
-- SECURITY DEFINER, search_path=public
-- GRANT: authenticated
-- Sem migration local.
-- Função: Retorna score IEA atual.

-- ── c6_get_simulado_final_score(p_recruta_id uuid, p_ciclo_id uuid) → numeric ─
-- SECURITY DEFINER, search_path=public
-- GRANT: authenticated
-- Sem migration local.

-- ── verificar_elegibilidade_grau6(p_recruta_id uuid) → jsonb ─────────────────
-- SECURITY DEFINER
-- GRANT: authenticated
-- Sem migration local.

-- ── get_student_next_lesson(p_user_id uuid) → jsonb ──────────────────────────
-- SECURITY DEFINER, search_path=public
-- GRANT: service_role (provavelmente)
-- Função: Retorna próxima aula não concluída do recruta.
-- NOTA: Corrigida para schema canônico (aulas+modulos+recruta_progresso)

-- -----------------------------------------------------------------------------
-- FUNÇÕES SERVICE_ROLE — Billing
-- Linhas dump: 4568-5060
-- -----------------------------------------------------------------------------

-- rpc_billing_processar_evento_pagamento() — service_role
-- rpc_billing_corrigir_divergencias() — service_role
-- rpc_billing_reconciliar_pagamentos() — service_role
-- rpc_billing_verificar_idempotencia() — service_role
-- rpc_billing_verificar_trial_expirando() — service_role
-- billing_emitir_evento_c5(...) — grants não identificados (RISCO)

-- -----------------------------------------------------------------------------
-- FUNÇÕES SERVICE_ROLE — Gamificação
-- -----------------------------------------------------------------------------

-- conceder_medalha_v2(p_recruta_id uuid, p_medalha_codigo text) — service_role
-- promover_recruta(p_recruta_id uuid, p_patente_codigo text, p_motivo text) — service_role
-- aplicar_alteracao_medalha(...) — service_role
-- aprovar_alteracao_medalha(...) — service_role

-- -----------------------------------------------------------------------------
-- FUNÇÕES INTERNAS — Triggers (SECURITY DEFINER, sem grants diretos)
-- -----------------------------------------------------------------------------

-- _auth_enforce_single_session() — Trigger em auth.sessions
-- _c5_emit_auth_logout(...) — Trigger em auth.sessions AFTER DELETE
-- _emitir_evento_c5_iea_marco(...) — Trigger em recruta_iea AFTER INSERT/UPDATE
-- _set_updated_at() — Trigger genérico de updated_at
-- c5_auditar_evento_institucional() — Trigger em eventos_institucionais
-- c5_guard_eventos_institucionais() — Trigger BEFORE INSERT em eventos_institucionais
-- c5_normalizar_evento_institucional() — Trigger em eventos_institucionais
-- fn_insert_audit_evento_smart() — INSTEAD OF INSERT em v_audit_eventos
--   ↑ BUG: SECURITY INVOKER — deve ser DEFINER. Correção: Migration 03.
-- fn_acquire_conversation_lock(p_conversa_id uuid) → boolean
-- fn_release_conversation_lock(p_conversa_id uuid) → void
-- fn_registrar_evento(...) — Trigger/helper de registro de eventos
-- fn_sync_xp_evento_aliases() — Trigger que sincroniza user_id/amount ↔ recruta_id/xp

-- -----------------------------------------------------------------------------
-- FUNÇÕES LEGACY / DASHBOARD (SECURITY DEFINER, search_path=public)
-- GRANT: authenticated, service_role
-- Prefixo: _dash_* — Dashboard admin legado
-- -----------------------------------------------------------------------------

-- _dash_columns() — Retorna colunas disponíveis no dashboard
-- _dash_json(p_table text, p_filter jsonb) — Retorna dados JSON do dashboard
-- _dash_json_v2(p_table text, p_filter jsonb) — V2 do dashboard
-- _dash_key_column() — Coluna chave do dashboard
-- _dash_key_column_v2() — V2
-- _dash_num(p_table text, p_column text, p_filter jsonb) → numeric
-- _dash_num_v2(p_table text, p_column text, p_filter jsonb) → numeric
-- _dash_text(p_table text, p_column text, p_filter jsonb) → text
-- _dash_text_v2(p_table text, p_column text, p_filter jsonb) → text

-- -----------------------------------------------------------------------------
-- FUNÇÃO COM RISCO P0 — buscar_revisoes_whatsapp
-- -----------------------------------------------------------------------------

-- buscar_revisoes_whatsapp() — SECURITY DEFINER SEM search_path
-- GRANT: service_role
-- Linhas dump: 833-835
-- RISCO: search_path hijacking
-- AÇÃO P0: ALTER FUNCTION public.buscar_revisoes_whatsapp() SET search_path TO 'public';
-- Impacto limitado (apenas service_role) mas vulnerabilidade existe.

-- =============================================================================
-- ANÁLISE GERAL DE SEGURANÇA DAS FUNÇÕES
-- =============================================================================
-- P0  CRÍTICO: buscar_revisoes_whatsapp — DEFINER sem search_path
-- P0  CRÍTICO: fn_insert_audit_evento_smart — INVOKER deve ser DEFINER
-- SEC-01 ALTO: complete_lesson aceita p_recruta_id externo
-- SEC-02 ALTO: registrar_xp não idempotente (chamada pelo cliente)
-- SEC-03 ALTO: ~20+ funções DEFINER sem search_path confirmado (ver — nos grants)
--              fn_acquire/release_conversation_lock, rpc_auth_*, rpc_chat_*,
--              rpc_complete_onboarding, rpc_update_instructor_profile, etc.
-- SEC-04 ALTO: emitir_evento_c5 exposta a authenticated
-- =============================================================================
