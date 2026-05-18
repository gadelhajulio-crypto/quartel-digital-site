# Drift Report — Quartel Digital Supabase

**Data:** 2026-05-16
**Fontes comparadas:**
- `supabase/remote/supabase_remote_schema.sql` — estado real do banco remoto
- `supabase/migrations/**/*.sql` — migrations locais
- `src/**/*.ts`, `app/**/*.tsx` — consumo frontend

---

## ACHADO P0 — Breaking Change Ativa

### `v_completed_lessons_count` — AUSENTE no dump, USADA no frontend

| Item | Estado |
|------|--------|
| Existe no dump remoto? | **NÃO** |
| Existe em migrations locais? | SIM (`20260119233000`, `20260503004000`) |
| Usada pelo frontend? | **SIM** — `src/hooks/useRecruitPanel.ts:62` |
| Impacto | `useRecruitPanel.ts` provavelmente retorna erro silencioso ou 0 |

**Evidência frontend:**
```ts
// src/hooks/useRecruitPanel.ts:61-62
// 2. Completed Count (v_completed_lessons_count mantém alias user_id)
supabase.from('v_completed_lessons_count')
```

**Evidência dump:** Grep por `v_completed_lessons_count` no dump retorna **zero resultados**.

**Hipóteses:**
1. A view foi dropada no remoto após uma migration não rastreada localmente
2. A view foi substituída internamente por uma subquery direta (sem view nomeada)
3. O frontend está silenciosamente recebendo array vazio (0 lições completas) sem erro

**Ação P0:** Criar migration para recriar `v_completed_lessons_count` no remoto apontando para `recruta_progresso` (tabela canônica), ou migrar o frontend para usar a view correta.

---

## Objetos presentes nas migrations locais mas AUSENTES no dump remoto

| Objeto | Tipo | Migration que criou | Presente no dump? | Análise |
|--------|------|---------------------|:-----------------:|---------|
| `v_completed_lessons_count` | VIEW | 20260119233000, 20260503004000 | **NÃO** | **P0** — usado no frontend |
| `v_medals_status` (v1) | VIEW | 20260503010000 | **NÃO** | OK — frontend migrou para v3 |
| `v_historico_atividade_recruta` (v1) | VIEW | 20260503010000 | **NÃO** | OK — frontend usa v3 |
| `rpc_set_instructor_profile` (restrição a 3 valores) | FUNCTION | 20260503011000 | SIM (mas expandido) | Versão remota expandida |
| `registrar_xp` | FUNCTION | Referenciada em MEMORY | **NÃO** | Removida ou nunca migrada |
| `grant_medal` | FUNCTION | Referenciada em MEMORY | **NÃO** | Removida ou renomeada para `conceder_medalha_v2` |

---

## Objetos presentes no dump remoto mas AUSENTES nas migrations locais

Estes objetos existem no banco de produção mas não têm migration local correspondente.
Foram criados diretamente no remoto ou via migrations não sincronizadas.

### Versionamento de Views (v2/v3 sem migration local)
| Objeto | Presente no dump | Migration local? | Risco |
|--------|:----------------:|:----------------:|-------|
| `v_medals_status_v2` | SIM | NÃO | MÉDIO — existe no remoto mas não reproduzível via migrations |
| `v_medals_status_v3` | SIM | NÃO | MÉDIO — idem, canonical para frontend |
| `v_historico_atividade_recruta_v2` | SIM | NÃO | MÉDIO |
| `v_historico_atividade_recruta_v3` | SIM | NÃO | **ALTO** — usado pelo frontend, não reproduzível |
| `v_app_bootstrap_institucional_rcc` | SIM | 20260503013000 (base) | BAIXO — provavelmente migrado |
| `v_iea_atual_v2` | SIM | NÃO | MÉDIO |
| `v_elegibilidade_elite_v2` | SIM | NÃO | MÉDIO |
| `v_classificacao_final_ciclo_v2` | SIM | NÃO | MÉDIO |
| `v_billing_status_recruta_v2` | SIM | NÃO | MÉDIO |
| `v_campeoes_mensais_rcc` | SIM | NÃO | BAIXO |
| `v_ranking_mensal_rcc` | SIM | NÃO | MÉDIO |
| `v_posicao_recruta_mes_rcc` | SIM | NÃO | MÉDIO |
| `v_identidade_recruta_legacy_20260503` | SIM | NÃO | BAIXO — legacy |

### Funções/RPCs sem migration local
| Objeto | Presente no dump | Migration local? | Risco |
|--------|:----------------:|:----------------:|-------|
| `rpc_update_instructor_profile` | SIM | 20260513002000 | BAIXO — migração existe |
| `rpc_set_recruta_forca` | SIM | NÃO | MÉDIO |
| `rpc_mark_onboarding_complete` | SIM | NÃO | MÉDIO |
| `rpc_select_force` | SIM | NÃO | MÉDIO |
| `rpc_billing_*` (série) | SIM | NÃO | MÉDIO |
| `rpc_c5_*` (série) | SIM | NÃO | MÉDIO |
| `garantir_recruta_ciclo_status_me` | SIM | NÃO | MÉDIO |
| `c6_get_iea_score`, `c6_get_simulado_final_score` | SIM | NÃO | MÉDIO |
| `fn_acquire_conversation_lock`, `fn_release_conversation_lock` | SIM | NÃO | ALTO — crítico para chat |
| `rpc_chat_*` (série) | SIM | NÃO | ALTO — crítico para chat |
| `fn_registrar_evento`, `fn_sync_xp_evento_aliases` | SIM | 20260503001000 (trigger) | BAIXO |

### Tabelas sem migration local
| Tabela | Presente no dump | Migration local? | Risco |
|--------|:----------------:|:----------------:|-------|
| `chat_conversas` | SIM | NÃO | ALTO |
| `chat_mensagens` | SIM | NÃO | ALTO |
| `chat_reads` | SIM | NÃO | ALTO |
| `chat_events` | SIM | NÃO | MÉDIO |
| `chat_summaries` | SIM | NÃO | MÉDIO |
| `conversation_locks` | SIM | NÃO | MÉDIO |
| `instrutores` | SIM | 20260511120000 (dados) | BAIXO |
| `institutional_assets` | SIM | 20260511120000 | BAIXO |
| `c5_alertas_operacionais` | SIM | NÃO | MÉDIO |
| `c5_fatos_analytics` | SIM | NÃO | MÉDIO |
| `c5_taxonomia_eventos` | SIM | NÃO | MÉDIO |
| `c6_contract_registry` | SIM | NÃO | BAIXO |
| `c7_ciclos`, `c7_execucao_diaria_log` | SIM | NÃO | MÉDIO |
| `c9_aula_conteudos` (estrutura) | SIM | 20260427214001 | BAIXO |
| `billing_assinaturas` | SIM | 20260503007000 (básico) | BAIXO |
| `ciclos_formativos`, `iea_snapshots`, `recruta_ciclo_status` | SIM | 20260503009000 (iea) | BAIXO |

---

## Objetos presentes no frontend mas AUSENTES no dump

| Objeto | Arquivo frontend | Presente no dump? | Criticidade |
|--------|-----------------|:-----------------:|-------------|
| `v_completed_lessons_count` | `src/hooks/useRecruitPanel.ts:62` | **NÃO** | **P0 CRÍTICO** |

Todos os outros contratos verificados no frontend foram encontrados no dump.

---

## Objetos presentes nas migrations mas NÃO consumidos pelo frontend

Estes objetos foram criados por migrations mas não há uso frontend identificado.
Candidatos a deprecação futura (não remover sem confirmação):

- `v_lessons_panel` — migration 20260131002700, não encontrado em src/app
- `v_lesson_progress_panel` — migration 20260503005000, não encontrado em src/app
- `vw_rdm_lessons` (v1) — substituído por vw_rdm_lessons_v2
- `vw_rdm_aeronautica/exercito/marinha` — visibilidade por força (substituídas por v2 geral?)
- `v_ranking_global`, `v_ranking_force` — versões v1 (v2 existem, uso frontend a confirmar)
- `progresso_recruta` (migration C2) — pode ter sido substituída por `recruta_progresso`

---

## Objetos Legados Potencialmente Órfãos

Tabelas que provavelmente existiam antes do modelo canônico e podem ser descontinuadas:

| Objeto | Tipo | Legado | Verificação |
|--------|------|--------|-------------|
| `lesson_progress` | TABLE | Pré-RCC | Verificar se `v_lesson_progress_panel` é usada |
| `lesson_media` | TABLE | Pré-RCC | Verificar se vws usam |
| `lessons` | TABLE | Pré-RCC | Verificar se `v_lessons_panel` é usada |
| `licoes` | TABLE | Pré-RCC | Não encontrada em frontend |
| `aulas_concluidas` | TABLE | Legado | Não encontrada em frontend recente |
| `progresso_aulas` | TABLE | Legado | Verificar uso |
| `progresso_missoes` | TABLE | Legado | Verificar uso |
| `progresso_recruta` | TABLE | Legado | Diferente de `recruta_progresso` (canônica) |
| `xp_events` | TABLE | Legado | Diferente de `xp_eventos` (canônica) |
| `user_xp` | TABLE | Legado | Verificar uso |
| `roles` | TABLE | Legado | Verificar uso |
| `sessions` | TABLE | Legado | Diferente de `auth.sessions` |
| `users` | TABLE | Legado | Diferente de `auth.users` |
| `usuarios` | TABLE | Legado | Verificar uso |
| `mensagens_chat` | TABLE | Legado | Diferente de `chat_mensagens` |
| `messages` | TABLE | Legado | Verificar uso |

---

## Divergências de Schema (Colunas)

### `aulas.modulo_id` vs `aulas.module_id`
- **Migrations legadas** (pré-2026): Usam `module_id`
- **View canônica** `vw_rdm_lessons_v2`: Usa `modulo_id`
- **Status no dump:** Coluna `modulo_id` confirmada no dump (linha 9075)
- **Conclusão:** Coluna foi renomeada no remoto (`module_id` → `modulo_id`) sem migration local

### `recrutas.xp` vs `recrutas.xp_total`
- **xp**: Atualizado por `complete_lesson` (ledger de aulas)
- **xp_total**: Atualizado por `registrar_xp` (ledger de eventos — mas `registrar_xp` não está no dump)
- **Status:** Divergência institucional conhecida, bloqueada

### `rpc_complete_onboarding` — Duas sobrecargas
- `rpc_complete_onboarding()` — sem parâmetros (linha 5983 do dump) — versão provavelmente obsoleta
- `rpc_complete_onboarding(p_forca, p_nome_guerra)` — versão canônica (linha 6053 do dump)
- **Migration local** 20260503011000 e 20260509001000 criam a versão com parâmetros
- **Risco:** Ambiguidade de chamada se algum código chama sem parâmetros

---

## Resumo de Risco

| Categoria | Count | Max Risco |
|-----------|:-----:|-----------|
| Objetos no frontend sem correspondência no dump | **1** | **P0** |
| Versionamento de views sem migration local | 13 | MÉDIO/ALTO |
| Funções/RPCs sem migration local | 12 | ALTO |
| Tabelas sem migration local | 12 | ALTO |
| Tabelas legadas potencialmente órfãs | 15 | MÉDIO |
| Divergências de coluna | 2 | MÉDIO/BLOQUEADO |
