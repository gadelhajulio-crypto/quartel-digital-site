-- =============================================================================
-- MÓDULO 11: Views e Contratos de Leitura — Catálogo Canônico
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Domínio: Todas as views canônicas de leitura do schema public
-- Linhas relevantes: 11553-16900 (views)
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- =============================================================================
-- CONVENÇÃO DE NOMENCLATURA
-- =============================================================================
-- v_*          = views read-only para o frontend (contratos canônicos)
-- vw_*         = views derivadas (legadas ou especializadas por força)
-- mv_*         = materialized views (requerem REFRESH periódico)
-- _v2 / _v3   = versões canônicas mais recentes (v1 geralmente legada)
-- security_invoker=true = RLS do usuário é aplicado (correto para dados pessoais)
-- =============================================================================

-- =============================================================================
-- SEÇÃO 1 — IDENTIDADE E AUTH
-- Módulo detalhado: 02_auth_identity_onboarding.sql
-- =============================================================================

-- v_identidade_recruta           — Perfil completo. JOIN recrutas+profiles.
-- v_auth_app_config              — Config institucional (auth_contract_version)
-- v_auth_session                 — Estado da sessão por auth.uid()
-- v_auth_active_sessions         — Sessões ativas por dispositivo
-- v_onboarding_status            — Progresso do onboarding por auth.uid()
-- v_app_bootstrap_institucional_rcc  — Bootstrap cold-start (security_invoker=true)
-- v_identidade_recruta_legacy_20260503  — Legacy

-- =============================================================================
-- SEÇÃO 2 — APRENDIZAGEM
-- Módulo detalhado: 05_learning_modules_lessons_progress.sql
-- =============================================================================

-- vw_rdm_lessons_v2              — CANÔNICA. Aulas do recruta (auth.uid())
--                                  Colunas: lesson_id, lesson_order, lesson_title,
--                                           module (UUID), status, module_title
-- vw_rdm_lessons                 — V1 LEGADA (substituída por v2)
-- vw_rdm_aeronautica/exercito/marinha  — Legadas por força (substituídas por v2)
-- vw_recruta_module_progress_v2  — CANÔNICA. Progresso por módulo (auth.uid())
--                                  Colunas: module_id, module_title, total_lessons,
--                                           completed_lessons, progress_percentage
-- vw_recruta_module_progress     — V1 LEGADA
-- vw_recruta_module_status_rcc   — security_invoker=true
-- v_lessons_panel                — Panel view (lesson_id, title, module, video_url, pdf_url)
-- v_lesson_progress_panel        — Progresso para panel (user_id, lesson_id, completed_at)
-- v_completed_lessons_count      — AUSENTE NO DUMP (P0 crítico!)
--                                  Usada em useRecruitPanel.ts. Recriar urgente.
-- v_modulos_catalogo             — Catálogo com is_degustacao
-- v_c9_aula_execucao             — security_invoker=true. Conteúdo de aula.
-- v_c9_quiz_execucao             — security_invoker=true. Quiz ativo.
-- v_c9_quiz_resultado            — security_invoker=true. Resultado do quiz.
-- v_available_reviews            — Revisões disponíveis (review_id, lesson_title, type)
-- v_review_content               — Conteúdo de revisão (review_id, lesson_title, media_url)

-- =============================================================================
-- SEÇÃO 3 — CHAT
-- Módulo detalhado: 03_chat_rcc_05_wave1.sql
-- =============================================================================

-- v_chat_conversas_recruta       — security_invoker=true. Conversas do recruta.
-- v_chat_mensagens_recruta       — security_invoker=true. Mensagens da conversa.
-- v_chat_unread_status           — security_invoker=true. Contagem não lidas.
-- v_audit_eventos                — WRITABLE VIEW (INSTEAD OF INSERT). Auditoria.

-- =============================================================================
-- SEÇÃO 4 — INSTRUTORES E ASSETS
-- Módulo detalhado: 08_storage_assets.sql
-- =============================================================================

-- v_instrutores_app              — security_invoker=true. Instrutores ativos com URLs.
-- v_institutional_assets         — Assets ativos (ativo=true).
-- v_institutional_notices        — Avisos com is_read=false (placeholder).
-- v_instructor_messages          — Mensagens com is_read=false (placeholder).

-- =============================================================================
-- SEÇÃO 5 — GAMIFICAÇÃO
-- Módulo detalhado: 04_c5_eventos_medalhas_patentes.sql
-- =============================================================================

-- v_medals_status_v3             — CANÔNICA. Medalhas do recruta (auth.uid()).
-- v_medals_status_v2             — LEGADA.
-- v_eventos_pendentes            — Eventos C5 não processados do recruta.
-- c5_eventos_view                — security_invoker=true. Legacy.
-- v_historico_atividade_recruta_v3  — CANÔNICA. useStudentHistory.
-- v_historico_atividade_recruta_v2  — Legada.
-- v_historico_atividade_recruta     — V1 legada.
-- v_historico_progresso_recruta     — useHistory (sem migration local confirmada).

-- =============================================================================
-- SEÇÃO 6 — RANKING, IEA E ELITE
-- Módulo detalhado: 07_ranking_iea_elite.sql
-- =============================================================================

-- v_ranking_mensal_rcc           — security_invoker=true. CANÔNICA.
-- v_posicao_recruta_mes_rcc      — security_invoker=true. CANÔNICA.
-- v_campeoes_mensais_rcc         — security_invoker=true. CANÔNICA.
-- v_ranking_global               — V1 legada.
-- v_ranking_force                — V1 por força.
-- mv_xp_mensal_recruta           — MATERIALIZED. Requer REFRESH.
-- mv_ranking_mensal              — MATERIALIZED. Requer REFRESH.
-- mv_campeao_mensal              — MATERIALIZED. Requer REFRESH.
-- v_iea_atual_v2                 — CANÔNICA.
-- v_iea_atual                    — V1 legada.
-- v_elegibilidade_elite_v2       — CANÔNICA.
-- v_elegibilidade_elite          — V1 legada.
-- v_classificacao_final_ciclo_v2 — CANÔNICA.
-- v_classificacao_final_ciclo    — V1 legada.

-- =============================================================================
-- SEÇÃO 7 — BILLING
-- Módulo detalhado: 06_billing.sql
-- =============================================================================

-- v_billing_status_recruta_v2    — CANÔNICA. acesso_liberado, plano_atual, etc.
-- v_billing_status_recruta       — V1 legada.
-- v_billing_trial_monitoramento  — Monitoramento de trials (service_role).
-- v_modelo_preco_atual           — Preço atual dos modelos AI.

-- =============================================================================
-- SEÇÃO 8 — PANEL / ADMIN
-- (Não consumidas pelo app mobile diretamente)
-- =============================================================================

-- v_lessons_panel                — lesson_id, title, module, video_url, pdf_url
-- v_lesson_progress_panel        — user_id, lesson_id, completed_at, xp_granted

-- =============================================================================
-- ANÁLISE DE COBERTURA DE CONTRATOS
-- =============================================================================
-- Views com DDL local (migrations):  ~20
-- Views sem DDL local (remoto only): ~25 (especialmente _v2, _v3, chat)
-- Views com security_invoker=true:   12 (ver SECURITY_DEFINER_AUDIT.md)
-- Views ausentes no dump mas usadas: 1 (v_completed_lessons_count — P0)
-- Views legadas sem uso frontend:    ~8 (vw_rdm_* v1, v_ranking_* v1, etc.)
-- =============================================================================

-- =============================================================================
-- P0 CRÍTICO — v_completed_lessons_count AUSENTE
-- =============================================================================
-- Arquivo: supabase/migrations/20260516005500_recreate_v_completed_lessons_count.sql
-- (sugerida, não criada ainda)
--
-- DDL para recriar:
-- CREATE OR REPLACE VIEW "public"."v_completed_lessons_count" AS
-- SELECT
--     "rp"."recruta_id" AS "user_id",
--     COUNT(*) AS "completed_count"
-- FROM "public"."recruta_progresso" "rp"
-- WHERE "rp"."status" = 'completed'
-- GROUP BY "rp"."recruta_id";
--
-- GRANT SELECT ON "public"."v_completed_lessons_count" TO "authenticated";
--
-- NOTA: A view deve ser filtrada por auth.uid() para que recruta veja apenas
-- o próprio count. Verificar como useRecruitPanel.ts faz o SELECT.
-- =============================================================================
