# P0-M5 Contract Selection — Seleção de Contratos para o Registry
**Data:** 2026-05-16
**Objetivo:** Determinar quais contratos entram na migration P0-M5 com base em evidência
dupla: uso confirmado no frontend E presença confirmada no dump remoto.
**Fontes:** CRITICAL_CONTRACTS_CHECK.md, DRIFT_REPORT.md, modules/11_views_contracts.sql,
grep em `src/**` e `app/**`

---

## Metodologia de Classificação

Um contrato só entra em P0-M5 se satisfizer **todos** os critérios:

| Critério | Requisito |
|----------|-----------|
| Frontend usa? | **SIM** — confirmado por grep em src/ ou app/ |
| Existe no dump? | **SIM** — linha confirmada em CRITICAL_CONTRACTS_CHECK.md ou DRIFT_REPORT.md |
| É versão canônica? | **SIM** — v2/v3 onde existem; não registrar v1 obsoletas |
| É contrato público? | **SIM** — não registrar objetos internos/backend |

---

## Tabela Completa de Classificação

| Objeto | Tipo | Frontend usa? | Existe no dump? | Categoria | Registrar em P0-M5? | Motivo |
|--------|------|:-------------:|:---------------:|-----------|:-------------------:|--------|
| **AUTH / IDENTIDADE** |
| `v_identidade_recruta` | VIEW | SIM | SIM (ln 11251) | CANÔNICO_ATIVO | **SIM** | Frontend: login bootstrap |
| `v_auth_app_config` | VIEW | SIM | SIM (ln 11578) | CANÔNICO_ATIVO | **SIM** | Frontend: auth_contract_version |
| `v_app_bootstrap_institucional_rcc` | VIEW | SIM | SIM (ln 11313) | CANÔNICO_ATIVO | **SIM** | Frontend: cold-start RCC |
| `v_onboarding_status` | VIEW | SIM | SIM (ln 13468) | CANÔNICO_ATIVO | **SIM** | Frontend: fluxo de onboarding |
| `v_auth_session` | VIEW | não confirmado | SIM | INTERNO_BACKEND | NÃO | Sem uso frontend identificado |
| `v_auth_active_sessions` | VIEW | não confirmado | SIM | INTERNO_BACKEND | NÃO | Sem uso frontend identificado |
| `v_identidade_recruta_legacy_20260503` | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | Legacy explícito |
| `rpc_auth_claim_active_client_session` | FUNCTION | SIM | SIM (ln 4329) | CANÔNICO_ATIVO | **SIM** | Frontend: heartbeat de sessão |
| `rpc_auth_resolve_session_state` | FUNCTION | SIM | SIM (ln 4410) | CANÔNICO_ATIVO | **SIM** | Frontend: estado institucional |
| `rpc_auth_revoke_client_session` | FUNCTION | SIM | SIM (ln 4477) | CANÔNICO_ATIVO | **SIM** | Frontend: logout |
| `rpc_complete_onboarding` (c/ params) | FUNCTION | SIM | SIM (ln 6053) | CANÔNICO_ATIVO | **SIM** | Frontend: registro de força e nome |
| `rpc_complete_onboarding` (sem params) | FUNCTION | NÃO | SIM (ln 5983) | LEGADO_DEPRECÁVEL | NÃO | Sobrecarga obsoleta — Sprint 3 |
| **APRENDIZAGEM** |
| `vw_rdm_lessons_v2` | VIEW | SIM | SIM (ln 14177) | CANÔNICO_ATIVO | **SIM** | Frontend: lista de aulas |
| `vw_recruta_module_progress_v2` | VIEW | SIM | SIM (ln 14314) | CANÔNICO_ATIVO | **SIM** | Frontend: progresso por módulo |
| `v_modulos_catalogo` | VIEW | SIM (InstructionsInProgress.tsx:35) | A confirmar | CANÔNICO_ATIVO | **CONDICIONAL** | Dump não verificado linha a linha — grep antes de incluir |
| `v_available_reviews` | VIEW | SIM (useAvailableReviews.ts:22) | A confirmar | CANÔNICO_ATIVO | **CONDICIONAL** | modules/11 lista, dump não verificado linha a linha |
| `v_review_content` | VIEW | SIM (useReviewContent.ts:22) | A confirmar | CANÔNICO_ATIVO | **CONDICIONAL** | modules/11 lista, dump não verificado linha a linha |
| `complete_lesson` | FUNCTION | SIM | SIM (ln 1182) | CANÔNICO_ATIVO | **SIM** | Frontend: via progressService; status ACTIVE_RISK (p_recruta_id externo → P0-M6) |
| `rpc_start_module` | FUNCTION | SIM (progressService.ts:8) | SIM (implícito) | CANÔNICO_ATIVO | **SIM** | Frontend confirmado; dump "SIM implícito" em CRITICAL_CONTRACTS_CHECK |
| `rpc_complete_module` | FUNCTION | SIM (progressService.ts:20) | A verificar | CANÔNICO_ATIVO | **CONDICIONAL** | Frontend confirmado; dump marcado "A verificar" em CRITICAL_CONTRACTS_CHECK |
| `get_student_next_lesson` | FUNCTION | SIM (useRecruitPanel.ts:66) | SIM (implícito) | CANÔNICO_ATIVO | **SIM** | Frontend confirmado |
| `vw_rdm_lessons` (v1) | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | Substituída por v2 |
| `vw_recruta_module_progress` (v1) | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | Substituída por v2 |
| `vw_rdm_aeronautica/exercito/marinha` | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | Substituídas por v2 geral |
| `vw_recruta_module_status_rcc` | VIEW | não confirmado | SIM | INTERNO_BACKEND | NÃO | Sem uso frontend identificado |
| `v_completed_lessons_count` | VIEW | SIM (useRecruitPanel.ts:62) | **NÃO** | NÃO_REGISTRAR | NÃO | **AUSENTE DO DUMP** — P0 crítico separado |
| `v_lessons_panel` | VIEW | NÃO | SIM | INTERNO_BACKEND | NÃO | Panel/admin, não mobile |
| `v_lesson_progress_panel` | VIEW | NÃO | SIM | INTERNO_BACKEND | NÃO | Panel/admin, não mobile |
| `v_c9_aula_execucao` | VIEW | não confirmado | SIM | INTERNO_BACKEND | NÃO | Sem uso frontend identificado no grep |
| `v_c9_quiz_execucao` | VIEW | não confirmado | SIM | INTERNO_BACKEND | NÃO | Sem uso frontend identificado no grep |
| `v_c9_quiz_resultado` | VIEW | não confirmado | SIM | INTERNO_BACKEND | NÃO | Sem uso frontend identificado no grep |
| **CHAT** |
| `v_chat_conversas_recruta` | VIEW | SIM | SIM (ln 12451) | CANÔNICO_ATIVO | **SIM** | Frontend: lista de conversas |
| `v_chat_mensagens_recruta` | VIEW | SIM | SIM (ln 12478) | CANÔNICO_ATIVO | **SIM** | Frontend: mensagens por conversa |
| `v_chat_unread_status` | VIEW | SIM | SIM (ln 12503) | CANÔNICO_ATIVO | **SIM** | Frontend: badge de não lidas |
| `rpc_chat_open_conversation` | FUNCTION | SIM | SIM (ln 5624) | CANÔNICO_ATIVO | **SIM** | Frontend: inicia conversa |
| `rpc_chat_send_message` | FUNCTION | SIM | SIM (ln 5678) | CANÔNICO_ATIVO | **SIM** | Frontend: envia mensagem |
| `rpc_chat_mark_read` | FUNCTION | SIM | SIM (ln 5521) | CANÔNICO_ATIVO | **SIM** | Frontend: marca lida |
| `v_audit_eventos` | VIEW | NÃO | SIM (ln 11465) | INTERNO_BACKEND | NÃO | Read-only UNION ALL — sem uso frontend direto |
| **INSTRUTORES E ASSETS** |
| `v_instrutores_app` | VIEW | SIM | SIM (ln 13125) | CANÔNICO_ATIVO | **SIM** | Frontend: seleção de instrutor |
| `v_institutional_assets` | VIEW | SIM | SIM (ln 13080) | CANÔNICO_ATIVO | **SIM** | Frontend: assets institucionais |
| `v_institutional_notices` | VIEW | SIM (useInstitutionalNotices.ts:22) | A confirmar | CANÔNICO_ATIVO | **CONDICIONAL** | modules/11 lista; dump não verificado linha a linha |
| `v_instructor_messages` | VIEW | SIM (useInstructorMessages.ts:21) | A confirmar | CANÔNICO_ATIVO | **CONDICIONAL** | modules/11 lista; dump não verificado linha a linha |
| `rpc_update_instructor_profile` | FUNCTION | SIM | SIM (ln 6389) | CANÔNICO_ATIVO | **SIM** | Frontend: perfil de instrutor — versão atual |
| `rpc_set_instructor_profile` | FUNCTION | SIM | SIM (ln 6236) | LEGADO_SUPORTADO | NÃO | Sendo substituída por rpc_update — não registrar duplicata |
| `rpc_mark_notice_read` | FUNCTION | SIM (useInstitutionalNotices.ts:39) | SIM (ln 6129) | CANÔNICO_ATIVO | **SIM** | Frontend: marcar aviso lido |
| `rpc_mark_instructor_message_read` | FUNCTION | SIM (useInstructorMessages.ts:37) | A confirmar | CANÔNICO_ATIVO | **CONDICIONAL** | Frontend confirmado; dump não verificado linha a linha |
| **GAMIFICAÇÃO** |
| `v_medals_status_v3` | VIEW | SIM (useMedals.ts:23) | SIM (DRIFT_REPORT) | CANÔNICO_ATIVO | **SIM** | Frontend: status de medalhas — versão canônica |
| `v_medals_status_v2` | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | Intermediária, não usada pelo frontend |
| `v_medals_status` (v1) | VIEW | NÃO | NÃO (apenas v2/v3) | LEGADO_DEPRECÁVEL | NÃO | Ausente do dump |
| `v_historico_atividade_recruta_v3` | VIEW | SIM (useStudentHistory.ts:23, useHistory.ts:27) | SIM (ln 12892) | CANÔNICO_ATIVO | **SIM** | Frontend: histórico de atividade |
| `v_historico_atividade_recruta_v2` | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | Intermediária, não usada |
| `v_historico_atividade_recruta` (v1) | VIEW | NÃO | NÃO | LEGADO_DEPRECÁVEL | NÃO | Ausente do dump |
| `v_historico_progresso_recruta` | VIEW | não confirmado | SIM (ln 12918) | INTERNO_BACKEND | NÃO | Sem uso frontend identificado no grep |
| `v_eventos_pendentes` | VIEW | SIM (c5EventsService.ts:26) | SIM (ln 12750) | CANÔNICO_ATIVO | **SIM** | Frontend: fila de eventos C5 |
| `consumir_evento_c5` | FUNCTION | SIM (c5EventsService.ts:74) | SIM (implícito) | CANÔNICO_ATIVO | **SIM** | Frontend: consome evento C5 |
| `c5_eventos_view` | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | Legacy, sem uso frontend |
| **RANKING, IEA E ELITE** |
| `v_ranking_mensal_rcc` | VIEW | SIM (RankingScreen.tsx:52) | SIM (ln 13567) | CANÔNICO_ATIVO | **SIM** | Frontend: ranking mensal |
| `v_posicao_recruta_mes_rcc` | VIEW | SIM (RankingScreen.tsx:59) | SIM (ln 13480) | CANÔNICO_ATIVO | **SIM** | Frontend: posição do recruta |
| `v_campeoes_mensais_rcc` | VIEW | SIM (RankingScreen.tsx:64) | SIM (DRIFT_REPORT) | CANÔNICO_ATIVO | **SIM** | Frontend: campeões do mês |
| `v_recruta_xp_total` | VIEW | SIM (useRecruitPanel.ts:58) | SIM (ln 13511) | CANÔNICO_ATIVO | **SIM** | Frontend: XP total do recruta |
| `v_iea_atual_v2` | VIEW | SIM (ieaService.ts:11) | SIM (ln 13027) | CANÔNICO_ATIVO | **SIM** | Frontend: score IEA atual |
| `v_elegibilidade_elite_v2` | VIEW | SIM (eliteService.ts:11) | SIM (ln 12739) | CANÔNICO_ATIVO | **SIM** | Frontend: elegibilidade elite |
| `v_classificacao_final_ciclo_v2` | VIEW | SIM (eliteService.ts:48) | SIM (ln 12596) | CANÔNICO_ATIVO | **SIM** | Frontend: classificação por ciclo |
| `v_iea_atual` (v1) | VIEW | NÃO | SIM (ln 8415) | LEGADO_DEPRECÁVEL | NÃO | Substituída por v2 |
| `v_elegibilidade_elite` (v1) | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | Substituída por v2 |
| `v_classificacao_final_ciclo` (v1) | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | Substituída por v2 |
| `v_ranking_global` | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | V1 substituída por _rcc |
| `v_ranking_force` | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | V1 substituída por _rcc |
| `mv_xp_mensal_recruta` | MAT.VIEW | não confirmado | SIM | INTERNO_BACKEND | NÃO | MV interna — requer REFRESH agendado |
| `mv_ranking_mensal` | MAT.VIEW | não confirmado | SIM | INTERNO_BACKEND | NÃO | MV interna — alimenta _rcc views |
| `mv_campeao_mensal` | MAT.VIEW | não confirmado | SIM | INTERNO_BACKEND | NÃO | MV interna — alimenta _rcc views |
| **BILLING** |
| `v_billing_status_recruta_v2` | VIEW | SIM (billingService.ts:13) | SIM (ln 11691) | CANÔNICO_ATIVO | **SIM** | Frontend: acesso liberado, plano atual |
| `v_billing_status_recruta` (v1) | VIEW | NÃO | SIM | LEGADO_DEPRECÁVEL | NÃO | Substituída por v2 |
| `v_billing_trial_monitoramento` | VIEW | NÃO | SIM | INTERNO_BACKEND | NÃO | service_role only — monitoramento |
| `v_modelo_preco_atual` | VIEW | NÃO | SIM | INTERNO_BACKEND | NÃO | service_role — preços de IA |

---

## Resumo por Categoria

| Categoria | Count | Descrição |
|-----------|:-----:|-----------|
| **CANÔNICO_ATIVO** (SIM em P0-M5) | **27** | Frontend SIM + dump SIM + versão canônica |
| **CANÔNICO_ATIVO** (CONDICIONAL) | **6** | Frontend SIM + dump A confirmar |
| **LEGADO_SUPORTADO** | **1** | Em transição — não registrar |
| **LEGADO_DEPRECÁVEL** | **14** | Versões v1 ou objetos substituídos |
| **INTERNO_BACKEND** | **11** | service_role, MVs, admin panel |
| **NÃO_REGISTRAR** | **1** | v_completed_lessons_count (ausente do dump) |

---

## Itens CONDICIONAIS — Verificação Obrigatória Antes de P0-M5

Os 6 itens abaixo têm uso frontend confirmado mas **presença no dump não verificada linha
a linha**. Antes de incluir em P0-M5, executar grep no dump remoto:

```sql
-- Executar no dump: supabase/remote/supabase_remote_schema.sql
-- grep -n "v_institutional_notices\|v_instructor_messages\|v_available_reviews\|v_review_content\|v_modulos_catalogo\|rpc_mark_instructor_message_read\|rpc_complete_module" supabase_remote_schema.sql
```

| Item | Consumer frontend | Status recomendado se grep confirmar |
|------|------------------|--------------------------------------|
| `v_institutional_notices` | useInstitutionalNotices.ts:22, useRecruitPanel.ts:68 | CANÔNICO_ATIVO → incluir |
| `v_instructor_messages` | useInstructorMessages.ts:21 | CANÔNICO_ATIVO → incluir |
| `v_available_reviews` | useAvailableReviews.ts:22 | CANÔNICO_ATIVO → incluir |
| `v_review_content` | useReviewContent.ts:22 | CANÔNICO_ATIVO → incluir |
| `v_modulos_catalogo` | InstructionsInProgress.tsx:35 | CANÔNICO_ATIVO → incluir |
| `rpc_mark_instructor_message_read` | useInstructorMessages.ts:37 | CANÔNICO_ATIVO → incluir |
| `rpc_complete_module` | progressService.ts:20 | CANÔNICO_ATIVO → incluir |

**Se o grep retornar resultado:** incluir na migration P0-M5.
**Se o grep retornar zero:** excluir e abrir item de investigação separado.

---

## Lista FINAL — Contratos que entram em P0-M5

### Confirmados (27 itens — entram sem condição)

**VIEWS (22):**

| # | Objeto | Domínio | Status |
|---|--------|---------|--------|
| 1 | `v_identidade_recruta` | auth | ACTIVE |
| 2 | `v_auth_app_config` | auth | ACTIVE |
| 3 | `v_app_bootstrap_institucional_rcc` | auth | ACTIVE |
| 4 | `v_onboarding_status` | auth | ACTIVE |
| 5 | `v_chat_conversas_recruta` | chat | ACTIVE |
| 6 | `v_chat_mensagens_recruta` | chat | ACTIVE |
| 7 | `v_chat_unread_status` | chat | ACTIVE |
| 8 | `vw_rdm_lessons_v2` | learning | ACTIVE |
| 9 | `vw_recruta_module_progress_v2` | learning | ACTIVE |
| 10 | `v_instrutores_app` | instrutores | ACTIVE |
| 11 | `v_institutional_assets` | instrutores | ACTIVE |
| 12 | `v_medals_status_v3` | medals | ACTIVE |
| 13 | `v_historico_atividade_recruta_v3` | historico | ACTIVE |
| 14 | `v_eventos_pendentes` | c5 | ACTIVE |
| 15 | `v_ranking_mensal_rcc` | ranking | ACTIVE |
| 16 | `v_posicao_recruta_mes_rcc` | ranking | ACTIVE |
| 17 | `v_campeoes_mensais_rcc` | ranking | ACTIVE |
| 18 | `v_recruta_xp_total` | ranking | ACTIVE |
| 19 | `v_iea_atual_v2` | iea | ACTIVE |
| 20 | `v_elegibilidade_elite_v2` | elite | ACTIVE |
| 21 | `v_classificacao_final_ciclo_v2` | elite | ACTIVE |
| 22 | `v_billing_status_recruta_v2` | billing | ACTIVE |

**FUNCTIONS/RPCs (10, sendo 1 com status ACTIVE_RISK):**

| # | Objeto | Domínio | Status |
|---|--------|---------|--------|
| 23 | `rpc_auth_claim_active_client_session` | auth | ACTIVE |
| 24 | `rpc_auth_resolve_session_state` | auth | ACTIVE |
| 25 | `rpc_auth_revoke_client_session` | auth | ACTIVE |
| 26 | `rpc_complete_onboarding` | auth | ACTIVE |
| 27 | `rpc_chat_open_conversation` | chat | ACTIVE |
| 28 | `rpc_chat_send_message` | chat | ACTIVE |
| 29 | `rpc_chat_mark_read` | chat | ACTIVE |
| 30 | `rpc_update_instructor_profile` | instrutores | ACTIVE |
| 31 | `rpc_mark_notice_read` | instrutores | ACTIVE |
| 32 | `complete_lesson` | learning | **ACTIVE_RISK** |
| 33 | `rpc_start_module` | learning | ACTIVE |
| 34 | `get_student_next_lesson` | learning | ACTIVE |
| 35 | `consumir_evento_c5` | c5 | ACTIVE |

**Total confirmado: 35 contratos.**

---

### Condicionais (7 itens — entram SE grep confirmar existência no dump)

| # | Objeto | Domínio | Status se confirmado |
|---|--------|---------|----------------------|
| 36 | `v_institutional_notices` | instrutores | ACTIVE |
| 37 | `v_instructor_messages` | instrutores | ACTIVE |
| 38 | `v_available_reviews` | learning | ACTIVE |
| 39 | `v_review_content` | learning | ACTIVE |
| 40 | `v_modulos_catalogo` | learning | ACTIVE |
| 41 | `rpc_mark_instructor_message_read` | instrutores | ACTIVE |
| 42 | `rpc_complete_module` | learning | ACTIVE |

**Total máximo com condicionais: 42 contratos.**

---

## Decisão Arquitetural sobre `complete_lesson`

`complete_lesson` entra com status `ACTIVE_RISK` porque:
- É consumida pelo frontend (via progressService)
- Existe no dump (ln 1182)
- É contrato ativo e crítico

O risco (`p_recruta_id` como parâmetro externo) é endereçado por P0-M6, não por P0-M5.
Registrar como `ACTIVE_RISK` documenta o estado real sem omitir o contrato do registry.

---

## O Que NÃO Entra em P0-M5 e Por Quê

| Objeto | Motivo de exclusão |
|--------|-------------------|
| `v_completed_lessons_count` | AUSENTE DO DUMP — requer migration de recriação separada |
| `rpc_set_instructor_profile` | Sendo substituído por `rpc_update_instructor_profile` — não duplicar |
| `rpc_complete_onboarding()` sem params | Sobrecarga obsoleta — Sprint 3 para deprecar |
| Todas as views v1 (14 itens) | Substituídas por v2/v3 — deprecar, não registrar como ativas |
| MVs (`mv_xp_mensal_recruta`, etc.) | Internas — sem uso direto pelo frontend; requerem REFRESH |
| Objetos `INTERNO_BACKEND` (11 itens) | service_role, panel/admin, auditoria interna |
| Funções `conceder_xp_*`, `debug_*`, `_dash_*` | Backend legacy — sem uso frontend |
| `v_audit_eventos` | View interna de auditoria; read-only UNION ALL |
| `v_billing_trial_monitoramento` | service_role only |

---

## Próximo Passo

Antes de gerar o SQL de P0-M5:

1. Executar grep dos 7 itens condicionais no dump remoto.
2. Se confirmados: lista final = 42 contratos.
3. Se não confirmados: lista final = 35 contratos.
4. Verificar DDL de `c6_contract_registry` no dump (ln 9765) para confirmar
   colunas exatas antes de gerar o INSERT.

**Não gerar SQL de P0-M5 antes dessa verificação.**
