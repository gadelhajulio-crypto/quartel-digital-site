# RLS Policy Audit — Quartel Digital Supabase

**Data:** 2026-05-16
**Fonte:** `supabase/remote/supabase_remote_schema.sql`

---

## Resumo Executivo

| Categoria | Contagem |
|-----------|----------|
| Tabelas public com RLS ativo | ~55 |
| Tabelas public sem RLS detectado | ~10 (legadas/admin) |
| Policies SELECT restritivas | ~40 |
| Policies que bloqueiam INSERT direto | 8 (xp_eventos, medalhas_concedidas, eventos_institucionais, c5_audit, etc.) |
| Tabelas de XP/Mérito protegidas | **SIM** — xp_eventos bloqueado para authenticated |

---

## Tabelas Críticas — Auditoria Detalhada

### xp_eventos — PROTEGIDA
| Operação | Policy | Role | USING | Risco |
|----------|--------|------|-------|-------|
| SELECT | `xp_eventos_select_block` | public | `false` | BAIXO |
| INSERT | `xp_eventos_insert_block` | public | `false` | **BLOQUEADO** |
| UPDATE | `xp_eventos_no_update` | authenticated, anon | `false` | BLOQUEADO |
| DELETE | `xp_eventos_no_delete` | authenticated, anon | `false` | BLOQUEADO |

**Status: SEGURO** — Nenhum usuário autenticado pode escrever diretamente. Apenas service_role tem acesso via `complete_lesson`.

### eventos_institucionais (C5) — PROTEGIDA
| Operação | Policy | Role | USING | Risco |
|----------|--------|------|-------|-------|
| SELECT | `eventos_institucionais_select_block` | public | `false` | — |
| SELECT | `eventos_institucionais_select_c5_authenticated` | authenticated | recruta próprio + idempotency_key NOT NULL | BAIXO |
| INSERT | `eventos_institucionais_insert_block` | public | `false` | BLOQUEADO |
| UPDATE | `eventos_institucionais_no_update` | authenticated, anon | `false` | BLOQUEADO |
| DELETE | `eventos_institucionais_no_delete` | authenticated, anon | `false` | BLOQUEADO |

**Status: SEGURO** — Apenas service_role pode inserir. Recruta pode ver apenas seus próprios eventos idempotentes.

### medalhas_concedidas — PROTEGIDA
| Operação | Policy | Risco |
|----------|--------|-------|
| SELECT | `medalhas_concedidas_select_block` → false | BLOQUEADO (leitura via views) |
| INSERT | `medalhas_concedidas_insert_block` → false | BLOQUEADO |
| UPDATE | `medalhas_concedidas_no_update` → false | BLOQUEADO |
| DELETE | `medalhas_concedidas_no_delete` → false | BLOQUEADO |

**Status: SEGURO** — Acesso exclusivo via service_role e views canônicas.

### c5_audit_eventos_institucionais — PROTEGIDA
| Operação | Policy | Risco |
|----------|--------|-------|
| SELECT | service_role apenas | BAIXO |
| INSERT | `c5_audit_no_insert` → false | BLOQUEADO |
| UPDATE | `c5_audit_no_update` → false | BLOQUEADO |
| DELETE | `c5_audit_no_delete` → false | BLOQUEADO |

**Status: SEGURO** — Auditoria imutável para authenticated/anon.

### recrutas — CONTROLADA
| Operação | Policy | Role | Condição | Risco |
|----------|--------|------|----------|-------|
| SELECT | `recrutas_select_own` | authenticated | `auth.uid() = auth_id` | BAIXO |
| INSERT | `recrutas_insert_own` | authenticated | `auth.uid() = auth_id` | BAIXO |
| UPDATE | `recrutas_update_own` | authenticated | `auth.uid() = auth_id` | BAIXO |
| ALL | `recrutas_service_role_all` | service_role | true | Necessário |

**Status: OK** — Recruta acessa apenas próprios dados.

**ATENÇÃO:** `SELECT,INSERT,UPDATE` concedido a authenticated via `GRANT` (linha 19043). Combinado com RLS, deve ser seguro, mas verificar se `INSERT` tem proteção de `auth_id` forçado.

### profiles — CONTROLADA
| Operação | Policy | Role | Condição | Risco |
|----------|--------|------|----------|-------|
| SELECT | `profiles_select_own` | public | `auth.uid() = id` | BAIXO |
| UPDATE | `profiles_update_own` | public | `auth.uid() = id` | BAIXO |
| UPDATE | `User can update own instructor` | public | `auth.uid() = id` | BAIXO |

**Status: OK** — INSERT em profiles não tem policy explícita. Verificar se `handle_new_user` trigger faz o INSERT via service_role.

### chat_conversas — SEM POLICY EXPLÍCITA VISÍVEL
RLS ativo mas sem policies explícitas encontradas no dump para authenticated. Acesso via views `v_chat_conversas_recruta` (security_invoker=true).

**RISCO MÉDIO** — Verificar se há policy implícita ou se o acesso é 100% via view.

### chat_mensagens — COM POLICIES
| Operação | Policy | Risco |
|----------|--------|-------|
| ALL | service_role | Necessário |
| SELECT | (via view security_invoker) | BAIXO |

### instrutores — PROTEGIDA CONTRA ESCRITA DIRETA
| Operação | Policy | Role | Risco |
|----------|--------|------|-------|
| SELECT | `instrutores_select_authenticated` | authenticated | WHERE ativo=true | BAIXO |
| INSERT | `instrutores_no_direct_insert` | authenticated | false | BLOQUEADO |
| UPDATE | `instrutores_no_direct_update` | authenticated | false | BLOQUEADO |
| DELETE | `instrutores_no_direct_delete` | authenticated | false | BLOQUEADO |

**Status: SEGURO** — Escrita apenas via service_role/migration.

### recruta_progresso — CONTROLADA
| Operação | Policy | Condição | Risco |
|----------|--------|----------|-------|
| SELECT | `recruta_progresso_select` | recruta_id via recrutas.auth_id | BAIXO |
| INSERT | `recruta_progresso_insert` | recruta_id via recrutas.auth_id | BAIXO |
| UPDATE | `recruta_progresso_update` | recruta_id via recrutas.auth_id | BAIXO |
| DELETE | `recruta_progresso_delete` | recruta_id via recrutas.auth_id | BAIXO |
| ALL | `recruta_progresso_service` | service_role | Necessário |

**ATENÇÃO ARQUITETURAL:** INSERT direto em recruta_progresso por authenticated é permitido pela RLS. Porém o contrato canônico é via `complete_lesson` (service_role). Isso cria um bypass potencial se o frontend tentar INSERT direto.

### aulas_concluidas — CONTROLADA (tabela legada)
Possui policies completas CRUD via `user_id = auth.uid()`. Tabela legada — verificar se ainda é usada pelo frontend.

### billing_assinaturas — PROTEGIDA
Apenas service_role. Correto para dados financeiros.

### billing_pagamentos — PROTEGIDA
Apenas service_role. Correto para dados financeiros.

---

## Tabelas com RLS Ativo mas SEM Policies Explícitas Verificadas

Estas tabelas têm `ENABLE ROW LEVEL SECURITY` mas não foram vistas policies explícitas no dump para authenticated:

| Tabela | RLS Ativo | Policies Found | Risco | Ação |
|--------|:---------:|---------------|-------|------|
| `chat_conversas` | SIM | Nenhuma para authenticated | MÉDIO | Verificar |
| `chat_reads` | Não encontrado | — | A verificar | — |
| `conversation_locks` | SIM | Nenhuma | MÉDIO | Verificar |
| `ciclos_formativos` | SIM | Apenas no_write (authenticated/anon) + select_all | BAIXO | OK |
| `forcas` | SIM | Leitura public para authenticated | BAIXO | OK |
| `modulos` | SIM | `select_modulos_by_forca` via recrutas.forca | BAIXO | OK |
| `iea_marcos_emitidos` | SIM | select_own | BAIXO | OK |
| `iea_snapshots` | SIM | select_own | BAIXO | OK |
| `institutional_assets` | SIM | select_active (ativo=true) | BAIXO | OK |
| `institutional_notices` | SIM | Sem policy encontrada | MÉDIO | Verificar |
| `instructor_messages` | SIM | Sem policy encontrada | MÉDIO | Verificar |
| `patentes_catalogo` | SIM | Public read (true) | BAIXO | OK |
| `medalha_regras` | SIM | Read authenticated, write service_role | BAIXO | OK |
| `medalhas_catalogo` | SIM | Public read (true) | BAIXO | OK |

---

## Tabelas de XP/Mérito — Resumo de Proteção

| Tabela | INSERT direto authenticated? | Observação |
|--------|:---------------------------:|------------|
| `xp_eventos` | NÃO — bloqueado | Seguro |
| `xp_events` (legada) | SIM (`Usuário cria XP events`) | **RISCO** — tabela legada sem proteção |
| `medalhas_concedidas` | NÃO — bloqueado | Seguro |
| `recruta_patentes` | SIM via RLS (recruta_id = auth.uid) | MÉDIO — verificar regras de negócio |
| `user_xp` | NÃO (apenas SELECT via policy) | OK |

**ACHADO CRÍTICO:** `xp_events` (tabela legada, diferente de `xp_eventos`) tem policy `Usuário cria XP events` que permite INSERT se `auth.uid() = user_id`. Se o frontend ainda usa esta tabela, há risco de manipulação de XP.

---

## Recomendações por Prioridade

### P0 — Crítico
1. Verificar se `xp_events` (legada) ainda é consumida pelo frontend — se sim, bloquear INSERT direto
2. Confirmar policies de `chat_conversas` para authenticated
3. Confirmar se INSERT direto em `recruta_progresso` por authenticated deve ser bloqueado

### P1 — Alto
1. Adicionar policies explícitas para `institutional_notices` e `instructor_messages`
2. Verificar acesso a `conversation_locks` por authenticated
3. Confirmar políticas para `profiles` — INSERT inicial via handle_new_user?

### P2 — Médio
1. Revisar se `aulas_concluidas` ainda é usada (tabela legada)
2. Revisar tabelas legadas: `licoes`, `lessons`, `lesson_progress`, `lesson_media`
3. Documentar por que `progresso_recruta` e `recruta_progresso` coexistem
