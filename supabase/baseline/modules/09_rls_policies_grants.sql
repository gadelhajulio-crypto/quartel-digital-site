-- =============================================================================
-- MÓDULO 09: RLS Policies e Grants — Segurança de Acesso
-- =============================================================================
-- Fonte: supabase/remote/supabase_remote_schema.sql
-- Domínio: Todas as RLS policies e grants do schema public
-- Linhas relevantes: 17000-18500 (RLS), 18500-19500 (grants)
-- Fonte de análise: supabase/baseline/RLS_POLICY_AUDIT.md
-- ATENÇÃO: NÃO executar diretamente. Arquivo de referência/auditoria.
-- =============================================================================

-- =============================================================================
-- RESUMO DE SEGURANÇA RLS
-- =============================================================================
-- Tabelas public com RLS ativo:     ~55
-- Tabelas public sem RLS detectado: ~10 (legadas/admin — inativas)
-- Policies SELECT restritivas:      ~40
-- Policies que bloqueiam INSERT:     8 (xp_eventos, medalhas_concedidas,
--                                       eventos_institucionais, c5_audit, etc.)
-- Tabelas de XP/Mérito protegidas:  SIM — xp_eventos BLOQUEADO para authenticated
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABELAS CRÍTICAS — STATUS DE SEGURANÇA
-- -----------------------------------------------------------------------------

-- ── xp_eventos — PROTEGIDA (todos os vetores de escrita bloqueados) ───────────
ALTER TABLE "public"."xp_eventos" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "xp_eventos_select_block" ON "public"."xp_eventos"
    FOR SELECT USING (false); -- authenticated não lê direto, apenas via views
CREATE POLICY "xp_eventos_insert_block" ON "public"."xp_eventos"
    FOR INSERT WITH CHECK (false); -- INSERT apenas via DEFINER (complete_lesson)
CREATE POLICY "xp_eventos_no_update" ON "public"."xp_eventos"
    FOR UPDATE TO "authenticated", "anon" USING (false);
CREATE POLICY "xp_eventos_no_delete" ON "public"."xp_eventos"
    FOR DELETE TO "authenticated", "anon" USING (false);
-- GRANT: service_role ALL — DEFINER RPCs bypassam RLS

-- ── eventos_institucionais — PROTEGIDA ────────────────────────────────────────
ALTER TABLE "public"."eventos_institucionais" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "eventos_institucionais_select_block" ON "public"."eventos_institucionais"
    FOR SELECT USING (false);
CREATE POLICY "eventos_institucionais_select_c5_authenticated" ON "public"."eventos_institucionais"
    FOR SELECT TO "authenticated"
    USING (("recruta_id" = "c5_recruta_id_for_auth"()) AND ("idempotency_key" IS NOT NULL));
CREATE POLICY "eventos_institucionais_insert_block" ON "public"."eventos_institucionais"
    FOR INSERT WITH CHECK (false);
CREATE POLICY "eventos_institucionais_no_update" ON "public"."eventos_institucionais"
    FOR UPDATE TO "authenticated", "anon" USING (false);
CREATE POLICY "eventos_institucionais_no_delete" ON "public"."eventos_institucionais"
    FOR DELETE TO "authenticated", "anon" USING (false);

-- ── medalhas_concedidas — PROTEGIDA ───────────────────────────────────────────
-- NOTA: nome real pode ser "medalhas_concedidas" (não "recruta_medalhas")
ALTER TABLE "public"."recruta_medalhas" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "medalhas_concedidas_select_block" ON "public"."recruta_medalhas"
    FOR SELECT USING (false); -- leitura via views canônicas
CREATE POLICY "medalhas_concedidas_insert_block" ON "public"."recruta_medalhas"
    FOR INSERT WITH CHECK (false);
CREATE POLICY "medalhas_concedidas_no_update" ON "public"."recruta_medalhas"
    FOR UPDATE USING (false);
CREATE POLICY "medalhas_concedidas_no_delete" ON "public"."recruta_medalhas"
    FOR DELETE USING (false);

-- ── c5_audit_eventos_institucionais — PROTEGIDA ───────────────────────────────
ALTER TABLE "public"."c5_audit_eventos_institucionais" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "c5_audit_no_insert" ON "public"."c5_audit_eventos_institucionais"
    FOR INSERT WITH CHECK (false);
CREATE POLICY "c5_audit_no_update" ON "public"."c5_audit_eventos_institucionais"
    FOR UPDATE USING (false);
CREATE POLICY "c5_audit_no_delete" ON "public"."c5_audit_eventos_institucionais"
    FOR DELETE USING (false);

-- ── recrutas — FORCE ROW LEVEL SECURITY ──────────────────────────────────────
ALTER TABLE ONLY "public"."recrutas" FORCE ROW LEVEL SECURITY;
-- Policies: recruta lê/atualiza apenas o próprio perfil
-- Escrita restrita: onboarding e campos críticos apenas via DEFINER RPCs

-- ── profiles — RLS ativo ──────────────────────────────────────────────────────
ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;
-- Policies: recruta lê o próprio perfil
-- Escrita: instructor_profile_id via rpc_update_instructor_profile (DEFINER)

-- ── recruta_progresso — RLS detalhado (ver módulo 05) ─────────────────────────
-- SELECT/INSERT/UPDATE/DELETE para authenticated (próprio recruta)
-- + service_role policy

-- ── billing_* — service_role apenas (ver módulo 06) ──────────────────────────
-- Todas as tabelas billing_assinaturas, billing_pagamentos, etc.
-- Apenas service_role via policies explícitas

-- ── instrutores — SELECT para authenticated, sem escrita direta ───────────────
-- Ver módulo 08

-- ── institutional_assets — SELECT ativo para authenticated ───────────────────
-- Ver módulo 08

-- ── chat_audit_log — service_role apenas ─────────────────────────────────────
ALTER TABLE "public"."chat_audit_log" ENABLE ROW LEVEL SECURITY;
-- Policy: INSERT/SELECT apenas service_role
-- RISCO SEC-05: fn_insert_audit_evento_smart é INVOKER (não DEFINER) → falha silenciosa

-- -----------------------------------------------------------------------------
-- GRANTS CONHECIDOS — Funções
-- Linhas dump: 18500-19500
-- -----------------------------------------------------------------------------

-- authenticated (usuário do app)
REVOKE ALL ON FUNCTION "public"."complete_lesson"("p_recruta_id" "uuid", "p_lesson_id" "uuid", "p_xp" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_lesson"("p_recruta_id" "uuid", "p_lesson_id" "uuid", "p_xp" integer) TO "service_role";
-- NOTA: complete_lesson NÃO está exposta a authenticated — mitigação parcial de SEC-01

GRANT EXECUTE ON FUNCTION "public"."consumir_evento_c5"("p_evento_id" "uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."emitir_evento_c5"("p_tipo" "text", "p_payload" "jsonb") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."emitir_evento_c5"("p_tipo" "text", "p_payload" "jsonb") TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."rpc_update_instructor_profile"("p_instructor_profile_id" "text") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."rpc_complete_onboarding"("p_forca" "text", "p_nome_guerra" "text") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."rpc_auth_claim_active_client_session"("p_client_instance_id" "text") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."rpc_auth_resolve_session_state"("p_client_instance_id" "text") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."rpc_auth_revoke_client_session"("p_session_id" "uuid") TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."c6_get_iea_score"("p_recruta_id" "uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."c6_get_simulado_final_score"("p_recruta_id" "uuid", "p_ciclo_id" "uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."verificar_elegibilidade_grau6"("p_recruta_id" "uuid") TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."rpc_chat_open_conversation"("p_instrutor_slug" "text") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."rpc_chat_send_message"("p_conversa_id" "uuid", "p_content" "text") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."rpc_chat_mark_read"("p_conversa_id" "uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."rpc_billing_status_recruta"() TO "authenticated";

-- service_role (Edge Functions, webhooks)
GRANT EXECUTE ON FUNCTION "public"."rpc_billing_processar_evento_pagamento"() TO "service_role";
GRANT EXECUTE ON FUNCTION "public"."rpc_billing_corrigir_divergencias"() TO "service_role";
GRANT EXECUTE ON FUNCTION "public"."rpc_billing_reconciliar_pagamentos"() TO "service_role";
GRANT EXECUTE ON FUNCTION "public"."rpc_billing_verificar_idempotencia"() TO "service_role";
GRANT EXECUTE ON FUNCTION "public"."rpc_billing_verificar_trial_expirando"() TO "service_role";
GRANT EXECUTE ON FUNCTION "public"."conceder_medalha_v2"("p_recruta_id" "uuid", "p_medalha_codigo" "text") TO "service_role";
GRANT EXECUTE ON FUNCTION "public"."promover_recruta"("p_recruta_id" "uuid", "p_patente_codigo" "text", "p_motivo" "text") TO "service_role";

-- billing_emitir_evento_c5 — SEM GRANTS EXPLÍCITOS VISÍVEIS
-- RISCO: Pode estar acessível por herança de PUBLIC ou completamente inacessível
-- AÇÃO: Confirmar via \dp billing_emitir_evento_c5 no remoto (linha 18590 do dump)

-- -----------------------------------------------------------------------------
-- GRANTS — Tabelas
-- Linhas dump: 19193-19255
-- -----------------------------------------------------------------------------

GRANT ALL ON TABLE "public"."aulas" TO "service_role";
GRANT SELECT ON TABLE "public"."aulas" TO "authenticated";

GRANT ALL ON TABLE "public"."aulas_concluidas" TO "service_role";
GRANT SELECT ON TABLE "public"."aulas_concluidas" TO "authenticated";

GRANT SELECT, INSERT, UPDATE ON TABLE "public"."c9_aula_conteudos" TO "service_role";
GRANT SELECT, INSERT, UPDATE ON TABLE "public"."c9_aula_flashcards" TO "service_role";
GRANT SELECT, INSERT, UPDATE ON TABLE "public"."c9_aula_quiz_alternativas" TO "service_role";
GRANT SELECT, INSERT, UPDATE ON TABLE "public"."c9_aula_quiz_perguntas" TO "service_role";
GRANT SELECT, INSERT, UPDATE ON TABLE "public"."c9_aula_quizzes" TO "service_role";

GRANT SELECT ON TABLE "public"."instrutores" TO "authenticated";
GRANT ALL ON TABLE "public"."instrutores" TO "service_role";

GRANT SELECT ON TABLE "public"."institutional_assets" TO "authenticated";
GRANT ALL ON TABLE "public"."institutional_assets" TO "service_role";

-- =============================================================================
-- ANÁLISE DE RISCO RLS
-- =============================================================================
-- SEGURO:     xp_eventos, eventos_institucionais, medalhas_concedidas, c5_audit
-- RISCO ALTO: recruta_progresso — INSERT direto possível para authenticated
--             (mitigação: UNIQUE constraint, mas valor amount não validado)
-- RISCO MÉDIO: emitir_evento_c5 exposta a authenticated (idempotência?)
-- BUG:        fn_insert_audit_evento_smart INVOKER → chat audit inoperante
-- =============================================================================
