# Security Definer Audit — Quartel Digital Supabase

**Data:** 2026-05-16
**Fonte:** `supabase/remote/supabase_remote_schema.sql`
**Critério ALTO:** SECURITY DEFINER sem SET search_path definido

---

## Resumo Executivo

| Categoria | Contagem |
|-----------|----------|
| Funções SECURITY DEFINER com search_path | ~85 |
| Funções SECURITY DEFINER **sem** search_path | **1 confirmada** (`buscar_revisoes_whatsapp`) |
| Funções SECURITY INVOKER (via views) | ~15 views com security_invoker=true |
| Funções expostas a `authenticated` | ~25 |
| Funções expostas a `anon` | ~2 |
| Funções expostas apenas a `service_role` | ~60 |

---

## Funções SECURITY DEFINER sem SET search_path — RISCO ALTO

| Função | Security | Search Path | Grants | Risco | Recomendação |
|--------|----------|-------------|--------|-------|--------------|
| `buscar_revisoes_whatsapp()` | SECURITY DEFINER | **AUSENTE** | service_role | **ALTO** | Adicionar `SET search_path TO 'public'` urgente |

**Justificativa:** Função com SECURITY DEFINER sem `SET search_path` é vulnerável a ataques de `search_path hijacking` — um usuário poderia criar objetos em um schema com precedência sobre `public` e redirecionar chamadas para funções maliciosas.

---

## Funções SECURITY DEFINER com search_path — Catálogo Completo

| Função | Security | Search Path | Grants | Observação |
|--------|----------|-------------|--------|------------|
| `_auth_enforce_single_session()` | SECURITY DEFINER | public, auth | service_role | Trigger de sessão única |
| `_c5_emit_auth_logout(...)` | SECURITY DEFINER | public | service_role | Trigger de logout C5 |
| `_dash_columns()` | SECURITY DEFINER | public | authenticated, service_role | Dashboard legacy |
| `_dash_json(...)` | SECURITY DEFINER | public | authenticated, service_role | Dashboard legacy |
| `_dash_json_v2(...)` | SECURITY DEFINER | public | authenticated, service_role | Dashboard legacy |
| `_dash_key_column()` | SECURITY DEFINER | public | authenticated, service_role | Dashboard legacy |
| `_dash_key_column_v2()` | SECURITY DEFINER | public | authenticated, service_role | Dashboard legacy |
| `_dash_num(...)` | SECURITY DEFINER | public | authenticated, service_role | Dashboard legacy |
| `_dash_num_v2(...)` | SECURITY DEFINER | public | authenticated, service_role | Dashboard legacy |
| `_dash_text(...)` | SECURITY DEFINER | public | authenticated, service_role | Dashboard legacy |
| `_dash_text_v2(...)` | SECURITY DEFINER | public | authenticated, service_role | Dashboard legacy |
| `_emitir_evento_c5_iea_marco(...)` | SECURITY DEFINER | public | service_role | Interno C5/IEA |
| `_is_service_role()` | SECURITY DEFINER | public | authenticated, service_role | Helper de auth |
| `_set_updated_at()` | SECURITY DEFINER | public | service_role | Trigger genérico |
| `aplicar_alteracao_medalha(...)` | SECURITY DEFINER | public | service_role | Admin medalhas |
| `aprovar_alteracao_medalha(...)` | SECURITY DEFINER | public | service_role | Admin medalhas |
| `billing_emitir_evento_c5(...)` | SECURITY DEFINER | public | Sem grants explícitos | **VERIFICAR** |
| `c5_auditar_evento_institucional()` | SECURITY DEFINER | public | service_role | Trigger auditoria C5 |
| `c5_guard_eventos_institucionais()` | SECURITY DEFINER | public | service_role | Trigger guard C5 |
| `c5_normalizar_evento_institucional()` | SECURITY DEFINER | public | service_role | Trigger normalizador |
| `c5_recruta_id_for_auth()` | SECURITY DEFINER | public | authenticated, service_role | Helper RLS C5 |
| `c6_get_iea_score(...)` | SECURITY DEFINER | public | authenticated | IEA scoring |
| `c6_get_simulado_final_score(...)` | SECURITY DEFINER | public | authenticated | IEA simulado |
| `complete_lesson(...)` | SECURITY DEFINER | public | **service_role apenas** | **RISCO DESIGN:** aceita p_recruta_id como param |
| `conceder_medalha_v2(...)` | SECURITY DEFINER | public | service_role | Gamificação canônica |
| `consumir_evento_c5(...)` | SECURITY DEFINER | public | **authenticated** | Exposição ampla — verificar idempotência |
| `emitir_evento_c5(nova assinatura)` | SECURITY DEFINER | public | **authenticated, service_role** | Frontend pode emitir eventos |
| `fn_acquire_conversation_lock(...)` | SECURITY DEFINER | — | authenticated, service_role | Chat lock |
| `fn_release_conversation_lock(...)` | SECURITY DEFINER | — | authenticated, service_role | Chat unlock |
| `promover_recruta(...)` | SECURITY DEFINER | public | service_role | Promoção de patente |
| `rpc_auth_claim_active_client_session(...)` | SECURITY DEFINER | — | authenticated | Heartbeat sessão |
| `rpc_auth_resolve_session_state(...)` | SECURITY DEFINER | — | authenticated | Estado institucional |
| `rpc_auth_revoke_client_session(...)` | SECURITY DEFINER | — | authenticated | Revogação sessão |
| `rpc_chat_mark_read(...)` | SECURITY DEFINER | — | authenticated | Chat |
| `rpc_chat_open_conversation(...)` | SECURITY DEFINER | — | authenticated | Chat |
| `rpc_chat_send_message(...)` | SECURITY DEFINER | — | authenticated | Chat |
| `rpc_chat_summary_upsert(...)` | SECURITY DEFINER | — | authenticated, service_role | Chat sumário |
| `rpc_complete_onboarding()` | SECURITY DEFINER | — | authenticated | Onboarding |
| `rpc_complete_onboarding(p_forca, p_nome_guerra)` | SECURITY DEFINER | — | authenticated | Onboarding v2 |
| `rpc_set_instructor_profile(...)` | SECURITY DEFINER | — | authenticated | Legado |
| `rpc_update_instructor_profile(...)` | SECURITY DEFINER | — | authenticated | Versão atual |
| `rpc_set_recruta_forca(...)` | SECURITY DEFINER | — | authenticated | Define força |
| `verificar_elegibilidade_grau6(...)` | SECURITY DEFINER | — | authenticated | IEA grau 6 |

---

## Views com SECURITY INVOKER

Views configuradas com `security_invoker=true` — RLS do usuário autenticado é respeitado:

| View | security_invoker | Observação |
|------|:----------------:|------------|
| `v_app_bootstrap_institucional_rcc` | true | Bootstrap institucional RCC |
| `v_campeoes_mensais_rcc` | true | Ranking campeões |
| `v_chat_conversas_recruta` | true | Chat — correto |
| `v_chat_mensagens_recruta` | true | Chat — correto |
| `v_chat_unread_status` | true | Chat — correto |
| `v_c9_aula_execucao` | true | Didática C9 |
| `v_c9_quiz_resultado` | true | Quiz C9 |
| `v_instrutores_app` | true | Instrutores |
| `v_posicao_recruta_mes_rcc` | true | Ranking posição |
| `v_ranking_mensal_rcc` | true | Ranking mensal |
| `vw_recruta_module_status_rcc` | true | Status módulo |
| `c5_eventos_view` | true | C5 eventos (legado) |

**Nota:** Views sem `security_invoker=true` executam com o papel do `DEFINER` (postgres), o que pode expor dados de outros recrutas se o filtro WHERE não for explícito. Verificar cada view canônica.

---

## Achados Críticos P0

### 1. `buscar_revisoes_whatsapp` — SECURITY DEFINER sem search_path
- **Linha:** 833-835 do dump
- **Risco:** search_path hijacking
- **Impacto:** Baixo (grants apenas para service_role)
- **Ação:** Adicionar `SET search_path TO 'public'` na próxima migration segura

### 2. `complete_lesson` aceita `p_recruta_id` como parâmetro
- **Linha:** 1182 do dump
- **Risco:** Qualquer service_role poderia marcar aulas completas para qualquer recruta
- **Mitigação atual:** Grants apenas para service_role (não authenticated)
- **Ação Futura:** Migrar para `auth.uid()` interno, conforme padrão canônico

### 3. `billing_emitir_evento_c5` sem grants explícitos visíveis
- **Linha:** 810 do dump
- **Risco:** Pode estar inadvertidamente inacessível ou acessível por herança de PUBLIC
- **Ação:** Confirmar grants via `\dp billing_emitir_evento_c5`

### 4. `emitir_evento_c5` (nova assinatura) exposta a `authenticated`
- **Linha:** 2351 do dump, grant linha 18719
- **Risco:** Recrutas podem emitir eventos C5 diretamente — idempotência protege?
- **Verificar:** Constraints de idempotência na tabela `eventos_institucionais`
