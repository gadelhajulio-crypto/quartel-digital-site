# Critical Contracts Check — Quartel Digital

**Data:** 2026-05-16
**Fonte dump:** `supabase/remote/supabase_remote_schema.sql`
**Metodologia:** grep no dump remoto + grep no frontend (src/, app/)

---

## Tabela de Contratos Críticos

| Contrato | Existe no dump? | Existe no frontend? | Existe em migrations? | Status | Ação |
|----------|:--------------:|:-------------------:|:---------------------:|--------|------|
| `v_chat_conversas_recruta` | **SIM** (ln 12451) | SIM | Não diretamente | OK | Nenhuma |
| `v_chat_mensagens_recruta` | **SIM** (ln 12478) | SIM | Não diretamente | OK | Nenhuma |
| `v_chat_unread_status` | **SIM** (ln 12503) | SIM | Não diretamente | OK | Nenhuma |
| `rpc_chat_open_conversation` | **SIM** (ln 5624) | SIM | Não diretamente | OK | Nenhuma |
| `rpc_chat_send_message` | **SIM** (ln 5678) | SIM | Não diretamente | OK | Nenhuma |
| `rpc_chat_mark_read` | **SIM** (ln 5521) | SIM | Não diretamente | OK | Nenhuma |
| `vw_rdm_lessons_v2` | **SIM** (ln 14177) | SIM | 20260503005000 | OK | Nenhuma |
| `vw_recruta_module_progress_v2` | **SIM** (ln 14314) | SIM | 20260503005000 | OK | Nenhuma |
| `v_billing_status_recruta_v2` | **SIM** (ln 11691) | A confirmar | 20260503007000 | OK | Verificar frontend |
| `v_iea_atual_v2` | **SIM** (ln 13027) | A confirmar | 20260503009000 | OK | Verificar frontend |
| `v_elegibilidade_elite_v2` | **SIM** (ln 12739) | A confirmar | 20260503009000 | OK | Verificar frontend |
| `v_classificacao_final_ciclo_v2` | **SIM** (ln 12596) | A confirmar | 20260503009000 | OK | Verificar frontend |
| `v_identidade_recruta` | **SIM** (ln 11251) | SIM | 20260503002000 | OK | Nenhuma |
| `v_auth_app_config` | **SIM** (ln 11578) | SIM | 20260503003000 | OK | Nenhuma |
| `v_onboarding_status` | **SIM** (ln 13468) | SIM | 20260503014000 | OK | Nenhuma |
| `v_app_bootstrap_institucional_rcc` | **SIM** (ln 11313) | SIM | 20260503013000 | OK | Nenhuma |
| `v_historico_atividade_recruta_v3` | **SIM** (ln 12892) | A confirmar | Não diretamente | OK | Verificar frontend |
| `v_recruta_xp_total` | **SIM** (ln 13511) | A confirmar | Não diretamente | OK | Verificar frontend |
| `v_ranking_mensal_rcc` | **SIM** (ln 13567) | A confirmar | Não diretamente | OK | Verificar frontend |
| `v_posicao_recruta_mes_rcc` | **SIM** (ln 13480) | A confirmar | Não diretamente | OK | Verificar frontend |
| `rpc_complete_onboarding` | **SIM** (ln 6053) | SIM | 20260509001000 | OK | Atenção: 2 sobrecargas |
| `rpc_auth_claim_active_client_session` | **SIM** (ln 4329) | SIM | 20260503003000 | OK | Nenhuma |
| `rpc_auth_resolve_session_state` | **SIM** (ln 4410) | SIM | 20260503003000 | OK | Nenhuma |
| `rpc_auth_revoke_client_session` | **SIM** (ln 4477) | SIM | 20260503003000 | OK | Nenhuma |
| `rpc_set_instructor_profile` | **SIM** (ln 6236) | SIM | 20260503011000 | OK | Substituído por rpc_update_instructor_profile |
| `rpc_update_instructor_profile` | **SIM** (ln 6389) | SIM | 20260513002000 | OK | Versão atual |
| `v_instrutores_app` | **SIM** (ln 13125) | SIM | 20260511120000 | OK | security_invoker=true |
| `v_institutional_assets` | **SIM** (ln 13080) | SIM | 20260511120000 | OK | Nenhuma |
| `complete_lesson` | **SIM** (ln 1182) | SIM | 20260503011000 | **RISCO** | Aceita p_recruta_id — grants só service_role |
| `v_medals_status` | NÃO (apenas v2/v3) | A confirmar | 20260503010000 | **DIVERGENTE** | Verificar se frontend usa v2 |
| `v_historico_atividade_recruta` | NÃO (apenas v2/v3) | A confirmar | Não diretamente | **DIVERGENTE** | Verificar se frontend usa v3 |
| `v_historico_progresso_recruta` | **SIM** (ln 12918) | A confirmar | Não diretamente | OK | Verificar frontend |
| `v_eventos_pendentes` | **SIM** (ln 12750) | A confirmar | 20260503008000 | OK | Nenhuma |
| `v_iea_atual` | **SIM** (ln 8415) | A confirmar | Não diretamente | OK | Versão legada, v2 preferida |
| `rpc_start_module` | **SIM** (implícito) | A confirmar | 20260503011000 | OK | Verificar linha exata |
| `rpc_complete_module` | A verificar | A confirmar | 20260503011000 | A verificar | Verificar dump |
| `rpc_mark_notice_read` | **SIM** (ln 6129) | A confirmar | 20260503011000 | OK | Nenhuma |
| `get_student_next_lesson` | **SIM** (implícito) | A confirmar | 20260503012000 | OK | Nenhuma |

---

## Contratos com Sobrecargas (Overloads)

| Função | Sobrecargas no Dump | Observação |
|--------|---------------------|------------|
| `rpc_complete_onboarding` | 2 (sem params ln 5983; com p_forca+p_nome_guerra ln 6053) | Frontend deve chamar a versão com params |
| `emitir_evento_c5` | 2 (nova assinatura ln 2351; legada ln 2453) | Sobrecargas conflitantes — risco de ambiguidade |

---

## Contratos Presentes APENAS no Dump (não consumidos pelo frontend)

São objetos existentes no banco mas sem uso frontend confirmado — candidatos a deprecação futura:

- `v_c5_*` (série de views de analytics C5)
- `v_c7_*` (série de views de auditoria C7)
- `vw_ranking_mensal_aeronautica/exercito/marinha` (views por força, substituídas por RCC)
- `vw_rdm_aeronautica/exercito/marinha` (idem)
- `debug_concessao_run`, `debug_medalha` (funções de debug)
- `_dash_*` (série de funções de dashboard legacy)
- `mv_c7_*` (materialized views de auditoria)

---

## Legenda de Status

| Status | Significado |
|--------|-------------|
| OK | Presente no dump, sem breaking change imediato |
| RISCO | Presente mas com problema de segurança ou design |
| DIVERGENTE | Diferença entre dump/migrations/frontend |
| AUSENTE_NO_DUMP | Esperado mas não encontrado no dump |
| A confirmar | Necessita verificação no frontend |
