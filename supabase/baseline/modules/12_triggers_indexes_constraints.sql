-- =============================================================================
-- MÓDULO 12: Triggers, Índices e Constraints — Infraestrutura
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Domínio: Triggers, índices PK/FK/UNIQUE, constraints de integridade
-- Linhas relevantes: 20000-21000 (constraints), 21000-22000 (indexes), 22000+ (triggers)
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- =============================================================================
-- TRIGGERS — Por tabela
-- =============================================================================

-- ── auth.sessions ─────────────────────────────────────────────────────────────
-- TRIGGER: trg_auth_enforce_single_session
--   FUNCTION: _auth_enforce_single_session() SECURITY DEFINER, search_path=public,auth
--   WHEN: AFTER INSERT ON auth.sessions FOR EACH ROW
--   Propósito: Forçar sessão única por dispositivo (revoga sessões anteriores)

-- TRIGGER: trg_c5_emit_auth_logout
--   FUNCTION: _c5_emit_auth_logout() SECURITY DEFINER, search_path=public
--   WHEN: AFTER DELETE ON auth.sessions FOR EACH ROW
--   Propósito: Emite evento C5 de logout para gamificação

-- ── eventos_institucionais ────────────────────────────────────────────────────
-- TRIGGER: trg_c5_guard_before_insert
--   FUNCTION: c5_guard_eventos_institucionais() SECURITY DEFINER, search_path=public
--   WHEN: BEFORE INSERT ON public.eventos_institucionais FOR EACH ROW
--   Propósito: Valida tipo_evento contra c5_taxonomia_eventos, aplica idempotência

-- TRIGGER: trg_c5_audit_evento
--   FUNCTION: c5_auditar_evento_institucional() SECURITY DEFINER, search_path=public
--   WHEN: AFTER INSERT ON public.eventos_institucionais FOR EACH ROW
--   Propósito: Insere em c5_audit_eventos_institucionais (ledger imutável)

-- TRIGGER: trg_c5_normalizar_evento
--   FUNCTION: c5_normalizar_evento_institucional() SECURITY DEFINER, search_path=public
--   WHEN: BEFORE INSERT ON public.eventos_institucionais FOR EACH ROW
--   Propósito: Normaliza payload, preenche campos derivados

-- ── recruta_iea ───────────────────────────────────────────────────────────────
-- TRIGGER: trg_iea_marco_c5
--   FUNCTION: _emitir_evento_c5_iea_marco() SECURITY DEFINER, search_path=public
--   WHEN: AFTER INSERT OR UPDATE ON public.recruta_iea FOR EACH ROW
--   Propósito: Emite evento C5 quando recruta atinge marco de IEA

-- ── xp_eventos ────────────────────────────────────────────────────────────────
-- TRIGGER: trg_sync_xp_aliases
--   FUNCTION: fn_sync_xp_evento_aliases() SECURITY DEFINER
--   WHEN: BEFORE INSERT ON public.xp_eventos FOR EACH ROW
--   Propósito: Sincroniza user_id ↔ recruta_id e amount ↔ xp (aliases)
--   Migration: 20260503001000

-- ── v_audit_eventos ───────────────────────────────────────────────────────────
-- TRIGGER: trg_audit_evento_smart (INSTEAD OF INSERT)
--   FUNCTION: fn_insert_audit_evento_smart() SECURITY INVOKER (BUG — deve ser DEFINER)
--   WHEN: INSTEAD OF INSERT ON public.v_audit_eventos
--   Propósito: Redireciona INSERT na view para chat_audit_log
--   BUG: INVOKER não tem permissão em chat_audit_log — falha silenciosa

-- ── Tabelas com updated_at automático ─────────────────────────────────────────
-- TRIGGER: trg_set_updated_at
--   FUNCTION: _set_updated_at() SECURITY DEFINER, search_path=public
--   WHEN: BEFORE UPDATE FOR EACH ROW
--   Tabelas: recrutas, profiles, aulas, modulos, billing_assinaturas, instrutores,
--            c9_aula_conteudos, c9_aula_quizzes, auth_client_sessions, etc.

-- =============================================================================
-- ÍNDICES CRÍTICOS
-- =============================================================================

-- ── recruta_progresso ─────────────────────────────────────────────────────────
-- UNIQUE INDEX: recruta_progresso_recruta_lesson_key (recruta_id, lesson_id)
-- Propósito: Idempotência de complete_lesson via ON CONFLICT DO NOTHING

-- ── xp_eventos ────────────────────────────────────────────────────────────────
-- INDEX: idx_xp_eventos_user_id (user_id) — query performance
-- INDEX: idx_xp_eventos_recruta_id (recruta_id) — alias
-- INDEX planejado: idx_xp_eventos_user_source (user_id, source_id) WHERE source_id IS NOT NULL
--   (Migration 04 — idempotência de registrar_xp)

-- ── billing_pagamentos ────────────────────────────────────────────────────────
-- UNIQUE INDEX: billing_pagamentos_gateway_event_unq (gateway_nome, gateway_event_id)
-- Propósito: Idempotência de processamento de webhook

-- ── c9_aula_conteudos ─────────────────────────────────────────────────────────
-- UNIQUE INDEX parcial: c9_aula_conteudos_um_ativo_por_tipo
--   ON c9_aula_conteudos (aula_id, tipo) WHERE ativo=true AND deleted_at IS NULL
-- Propósito: Apenas um conteúdo ativo por tipo por aula

-- ── c9_aula_quiz_alternativas ─────────────────────────────────────────────────
-- UNIQUE INDEX parcial: c9_aula_quiz_alternativas_uma_correta
--   ON c9_aula_quiz_alternativas (pergunta_id) WHERE correta=true AND deleted_at IS NULL
-- Propósito: Apenas uma alternativa correta por pergunta

-- ── auth_client_sessions ──────────────────────────────────────────────────────
-- UNIQUE INDEX: auth_client_sessions_instance_unq (client_instance_id) WHERE revoked_at IS NULL
-- Propósito: Uma sessão ativa por dispositivo

-- ── recruta_medalhas ──────────────────────────────────────────────────────────
-- UNIQUE INDEX: recruta_medalhas_unique (recruta_id, medalha_id)
-- Propósito: Idempotência de conceder_medalha_v2

-- ── recruta_iea ───────────────────────────────────────────────────────────────
-- UNIQUE INDEX: recruta_iea_unique (recruta_id, ciclo_id)
-- Propósito: Um score IEA por recruta por ciclo

-- ── instrutores ───────────────────────────────────────────────────────────────
-- UNIQUE INDEX: instrutores_slug_key (slug)
-- UNIQUE INDEX: instrutores_codigo_key (codigo)

-- ── chat_conversas ────────────────────────────────────────────────────────────
-- UNIQUE INDEX: chat_conversas_recruta_instrutor_key (recruta_id, instrutor_slug)
-- Propósito: Uma conversa por instrutor por recruta

-- ── chat_threads ──────────────────────────────────────────────────────────────
-- UNIQUE INDEX: chat_threads_recruta_instrutor_key (recruta_id, instrutor_slug)

-- ── mv_xp_mensal_recruta ──────────────────────────────────────────────────────
-- UNIQUE INDEX: mv_xp_mensal_recruta_key (recruta_id, forca, mes_referencia)
-- Propósito: Permite REFRESH CONCURRENTLY

-- =============================================================================
-- PRIMARY KEYS (tabelas sem DDL local — verificar no remoto)
-- =============================================================================

-- chat_conversas:        PK id uuid
-- chat_mensagens:        PK id uuid
-- chat_reads:            PK id uuid
-- chat_events:           PK id uuid
-- chat_summaries:        PK id uuid
-- chat_threads:          PK id uuid
-- conversation_locks:    PK id uuid
-- eventos_institucionais: PK id uuid
-- c5_alertas_operacionais: PK id uuid
-- c5_fatos_analytics:    PK id uuid
-- iea_snapshots:         PK id uuid
-- ciclos_formativos:     PK id uuid (c7_ciclos pode ser alias)
-- campeoes_mensais:      PK id uuid

-- =============================================================================
-- FOREIGN KEYS CONHECIDAS
-- =============================================================================

-- recruta_progresso.recruta_id   → recrutas(id)
-- recruta_progresso.lesson_id    → aulas(id)
-- recruta_modulos.recruta_id     → recrutas(id)
-- recruta_modulos.modulo_id      → modulos(id)
-- aulas.modulo_id                → modulos(id)
-- xp_eventos.recruta_id          → recrutas(id) [via alias]
-- xp_eventos.user_id             → auth.users(id) [original]
-- recruta_status.recruta_id      → recrutas(id)
-- recruta_iea.recruta_id         → recrutas(id)
-- billing_assinaturas.recruta_id → recrutas(id)
-- billing_pagamentos.recruta_id  → recrutas(id)
-- chat_conversas.recruta_id      → recrutas(id) [inferido]
-- chat_mensagens.conversa_id     → chat_conversas(id) [inferido]

-- INCONSISTÊNCIA CONHECIDA:
-- c9_aula_quiz_tentativas.recruta_id → auth.users(id)  ← DEVE ser recrutas(id)
-- Correção: Migration 12 (20260516012000)

-- =============================================================================
-- CONSTRAINTS DE DOMÍNIO (CHECK)
-- =============================================================================

-- recrutas.forca: ARRAY['marinha','exercito','aeronautica']
-- profiles.forca: ARRAY['marinha','exercito','aeronautica']
-- modulos.forca:  ARRAY['marinha','exercito','aeronautica']
-- aulas: sem constraint de forca (herda de modulos)
-- xp_eventos.forca: ARRAY['marinha','exercito','aeronautica']
-- xp_eventos.quantidade: quantidade > 0
-- profiles.instructor_profile_id: ARRAY['objetivo','estrategico','didatico']
-- recruta_progresso.status: status = 'completed' (única valor aceito)
-- billing_assinaturas.status_assinatura:
--     ARRAY['trial','ativa','inadimplente','cancelada','expirada','suspensa','pendente']

-- =============================================================================
-- NOTAS
-- =============================================================================
-- 1. trg_auth_enforce_single_session precisa de search_path=public,auth
--    (acesso a auth.sessions requer schema auth explícito)
-- 2. fn_insert_audit_evento_smart BUG: INVOKER em vez de DEFINER
--    → auditoria de chat completamente inoperante
-- 3. idx_xp_eventos_user_source NÃO existe ainda (planejado para Migration 04)
-- 4. REFRESH CONCURRENTLY requer índice UNIQUE na materialized view
--    → mv_xp_mensal_recruta_key deve existir (verificar no remoto)
-- 5. c9_aula_quiz_tentativas.recruta_id FK errada → RISCO de cascade delete indevido
-- =============================================================================
