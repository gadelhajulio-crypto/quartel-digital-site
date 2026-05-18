# XP_EVENTS Legacy Audit — Auditoria Completa Pré-P0-M4
**Data:** 2026-05-16
**Escopo:** Confirmar todos os consumidores ativos de `xp_events` antes de bloquear INSERT.
**Fontes pesquisadas:** `supabase/remote/supabase_remote_schema.sql`, `src/**`, `app/**`,
`supabase/functions/**`, `supabase/migrations/**`

---

## 1. DDL da Tabela `xp_events` (dump ln 14497–14508)

```sql
CREATE TABLE IF NOT EXISTS "public"."xp_events" (
    "id"         uuid    DEFAULT gen_random_uuid() NOT NULL,
    "user_id"    uuid    NOT NULL,
    "tipo"       text    NOT NULL,
    "xp"         integer NOT NULL,
    "periodo"    text    NOT NULL,
    "created_at" timestamp with time zone DEFAULT now(),
    "reference"  text
);
```

| Atributo | Valor |
|----------|-------|
| Schema | `public` |
| Owner | `postgres` |
| PK | `xp_events_pkey` ON `id` (ln 15626) |
| FK | `user_id` → `auth.users(id)` ON DELETE CASCADE (ln 17285) |
| RLS | ENABLED (ln 18450) |
| Índice único | NENHUM |
| Coluna de força | AUSENTE |
| Coluna `forca` | AUSENTE (sem validação de força militar) |

---

## 2. RLS Policies em `xp_events`

| Policy | Operação | CHECK / USING | Para quem | Status |
|--------|----------|--------------|-----------|--------|
| **"Usuário cria XP events"** | INSERT | `auth.uid() = user_id` | authenticated | **ATIVA** |
| *(sem política)* | SELECT | — | authenticated | **BLOQUEADO** (sem policy = sem acesso) |
| *(sem política)* | UPDATE | — | authenticated | **BLOQUEADO** |
| *(sem política)* | DELETE | — | authenticated | **BLOQUEADO** |
| GRANT ALL | todas | BYPASSRLS | service_role | ativo |

**Achado crítico:** Usuários `authenticated` podem fazer INSERT direto em `xp_events`
sem passar por nenhuma RPC. É a vulnerabilidade-alvo de P0-M4.

---

## 3. DDL da Tabela `xp_eventos` (canônica, dump ln 10756–10766)

```sql
CREATE TABLE IF NOT EXISTS "public"."xp_eventos" (
    "id"           uuid    DEFAULT gen_random_uuid() NOT NULL,
    "recruta_id"   uuid    NOT NULL,
    ...
    CONSTRAINT "xp_eventos_forca_check"    CHECK (forca = ANY (ARRAY['marinha','exercito','aeronautica'])),
    CONSTRAINT "xp_eventos_quantidade_check" CHECK (quantidade > 0)
);
```

### RLS Policies em `xp_eventos`

| Policy | Operação | CHECK / USING | Status |
|--------|----------|--------------|--------|
| `xp_eventos_insert_block` | INSERT | `false` | **BLOQUEADA — ninguém insere via RLS** |
| `xp_eventos_no_delete` | DELETE | `false` | **BLOQUEADA** |
| `xp_eventos_no_update` | UPDATE | `false` | **BLOQUEADA** |
| `xp_eventos_select_block` | SELECT | `false` | **BLOQUEADA** |
| GRANT | todas | BYPASSRLS | service_role only |

---

## 4. Comparação: `xp_events` vs `xp_eventos`

| Dimensão | `xp_events` (legada) | `xp_eventos` (canônica) |
|----------|---------------------|------------------------|
| Chave de identidade | `user_id` → `auth.users` | `recruta_id` → `recrutas` |
| Coluna de valor XP | `xp` (integer) | `quantidade` (integer, CHECK > 0) |
| Coluna de período | `periodo` (text, ex: "2026-05") | — (usa `created_at`) |
| Coluna de referência | `reference` (text livre) | `referencia_id` (uuid) |
| Coluna de força | **AUSENTE** | `forca` (com CHECK constraint) |
| Coluna de origem | `tipo` (text) | `origem` (text) |
| Coluna `amount` / alias | — | `amount` (alias via trigger sync) |
| INSERT autenticado | **ABERTO** (policy ativa) | **BLOQUEADO** (WITH CHECK false) |
| SELECT autenticado | Bloqueado (sem policy) | Bloqueado (SELECT policy false) |
| Tabela XP associada | `user_xp` (legacy) | `recrutas.xp` / `recrutas.xp_total` |
| Materialized views | Nenhuma | `mv_xp_mensal_recruta`, `mv_ranking_mensal` |
| Consumers frontend (src/, app/) | **ZERO** | Muitos (via views canônicas) |

**Conclusão:** São dois sistemas de XP paralelos e completamente independentes.
Não há sincronização, shadow write ou dual-read entre eles.

---

## 5. Qual é a Tabela Canônica Real?

**`xp_eventos`** é a tabela canônica.

Evidência:
- Alimenta `mv_xp_mensal_recruta`, `mv_ranking_mensal`, `mv_campeao_mensal`
- Referenciada por `v_ranking_mensal_rcc`, `v_posicao_recruta_mes_rcc`, `v_iea_atual_v2`,
  `v_historico_atividade_recruta_v3`, `v_audit_eventos`, `v_classificacao_final_ciclo_v2`
- Alimentada por `complete_lesson` (RPC principal do app mobile)
- Tem constraint de força militar (design intencional do RCC)
- Todas as RLS policies bloqueam escrita direta — proteção correta para sistema DEFINER

**`xp_events`** é o sistema legado.

Evidência:
- Não referenciada por nenhuma view de ranking, IEA, histórico ou gamificação canônica
- Não tem coluna de força (`forca`) — inconsistente com o modelo atual
- Alimenta apenas `user_xp` (outra tabela legada)
- Nenhum hook ou tela do frontend a consome

---

## 6. Sincronização / Shadow Write / Dual-Read

| Mecanismo | Existe? | Detalhe |
|-----------|---------|---------|
| Sincronização `xp_events` → `xp_eventos` | **NÃO** | Sistemas completamente separados |
| Sincronização `xp_eventos` → `xp_events` | **NÃO** | |
| Shadow write (escrita em ambas) | **NÃO** | Nenhuma função escreve nas duas |
| Dual-read (leitura de ambas) | **NÃO** | Nenhuma view ou RPC consolida as duas |
| Trigger de sync | **NÃO** | Trigger `trg_sync_xp_aliases` existe em `xp_eventos`, não em `xp_events` |

---

## 7. Consumidores Ativos por Categoria

### 7a. Funções SQL que usam `xp_events`

Todas são `SECURITY DEFINER`, `SET search_path TO 'public'`, grants `service_role` only.

| Função | Operações | Linha dump | Grants |
|--------|-----------|-----------|--------|
| `conceder_xp_modulo(p_user_id, p_modulo_id)` | SELECT (idempotência, limite diário) + INSERT | 1389 | service_role |
| `conceder_xp_revisao_recomendada(p_user_id, p_revisao_id)` | SELECT + INSERT | 1479 | service_role |
| `conceder_xp_revisao_voluntaria(p_user_id, p_revisao_id)` | SELECT + INSERT | 1567 | service_role |
| `conceder_xp_simulado(p_user_id, p_simulado_id, p_percentual_acerto)` | SELECT + INSERT | 1655 | service_role |
| `conceder_xp_streak_5_dias(p_user_id)` | SELECT + INSERT | 1755 | service_role |
| `conceder_xp_uso_diario(p_user_id)` | SELECT + INSERT | 1848 | service_role |
| `conceder_xp_whatsapp(p_user_id)` | SELECT + INSERT | 1926 | service_role |

**Padrão comum em todas as 7 funções:**
1. SELECT FROM xp_events para verificar idempotência (já concedeu?)
2. SELECT SUM(xp) FROM xp_events para checar limite diário (max 200 XP/dia)
3. INSERT INTO xp_events (registrar evento)
4. UPDATE user_xp (atualizar saldo no sistema legado)

**Chamadores externos confirmados:** ZERO — nenhum Edge Function, nenhum arquivo TypeScript,
nenhuma migration chama `conceder_xp_*` diretamente.

### 7b. Trigger em `xp_events`

**NENHUM.** Nenhum trigger está definido na tabela `xp_events`.

O trigger `trg_xp_aula` existe em `aulas_concluidas` → chama `fn_conceder_xp_aula()`,
mas essa função NÃO usa `xp_events` — ela atualiza `profiles.xp` diretamente (ln 2854–2878).

### 7c. Foreign Keys apontando PARA `xp_events`

**NENHUMA.** Nenhuma tabela tem FK → `xp_events`.

A única FK existente é DE `xp_events` → `auth.users` (ln 17285).

### 7d. Materialized Views

**NENHUMA** referencia `xp_events`.

`mv_xp_mensal_recruta` (ln 10775–10779) usa `xp_eventos` (canônica).

### 7e. Views regulares

**NENHUMA** referencia `xp_events` diretamente.

`vw_xp_lessons`, `vw_xp_reviews`, `vw_xp_module` usam `lessons` e `lesson_progress`
(um terceiro sistema legado, independente de ambas as tabelas XP).

### 7f. Edge Functions

| Função | Referência a `xp_events` |
|--------|--------------------------|
| `chat-central/index.ts` | **ZERO** |
| `chat-ai/index.ts` | **ZERO** |
| `instrutor-send/index.ts` | **ZERO** |
| `stripe-create-checkout-session/index.ts` | **ZERO** |

### 7g. Frontend (src/, app/)

| Caminho | Referência a `xp_events` |
|---------|--------------------------|
| `src/**` | **ZERO** |
| `app/**` | **ZERO** |

### 7h. Migrations locais

| Caminho | Referência a `xp_events` |
|---------|--------------------------|
| `supabase/migrations/**` | **ZERO** |

### 7i. Cron Jobs / pg_cron

**NENHUM** encontrado no dump. Nenhuma extensão `pg_cron` instalada ou referenciada.

### 7j. Analytics / Dashboards

**NÃO VERIFICÁVEL** via dump — painéis externos não têm DDL no dump.
Recomendação: verificar manualmente antes de executar P0-M4.

---

## 8. Tabela de Dependências Classificadas

| Dependência | Tipo | Origem | Ativa? | Pode quebrar com P0-M4? | Severidade |
|-------------|------|--------|--------|------------------------|-----------|
| "Usuário cria XP events" INSERT policy | RLS Policy | dump ln 17415 | **SIM** | Não (é o alvo do bloqueio) | P0 — remover |
| `conceder_xp_modulo` SELECT + INSERT | Function DEFINER | dump ln 1389 | Provavelmente SIM (no banco) | **NÃO** (DEFINER = postgres = BYPASSRLS) | MÉDIA |
| `conceder_xp_revisao_recomendada` SELECT + INSERT | Function DEFINER | dump ln 1479 | Provavelmente SIM (no banco) | **NÃO** (BYPASSRLS) | MÉDIA |
| `conceder_xp_revisao_voluntaria` SELECT + INSERT | Function DEFINER | dump ln 1567 | Provavelmente SIM (no banco) | **NÃO** (BYPASSRLS) | MÉDIA |
| `conceder_xp_simulado` SELECT + INSERT | Function DEFINER | dump ln 1655 | Provavelmente SIM (no banco) | **NÃO** (BYPASSRLS) | MÉDIA |
| `conceder_xp_streak_5_dias` SELECT + INSERT | Function DEFINER | dump ln 1755 | Provavelmente SIM (no banco) | **NÃO** (BYPASSRLS) | MÉDIA |
| `conceder_xp_uso_diario` SELECT + INSERT | Function DEFINER | dump ln 1848 | Provavelmente SIM (no banco) | **NÃO** (BYPASSRLS) | MÉDIA |
| `conceder_xp_whatsapp` SELECT + INSERT | Function DEFINER | dump ln 1926 | Provavelmente SIM (no banco) | **NÃO** (BYPASSRLS) | MÉDIA |
| `xp_events_user_id_fkey` → `auth.users` | FK de saída | dump ln 17285 | SIM | NÃO (FK de saída, não entra) | BAIXA |
| Frontend (src/, app/) | TypeScript | — | **NÃO** | NÃO | ZERO |
| Edge Functions | Deno/TypeScript | supabase/functions/ | **NÃO** | NÃO | ZERO |
| Migrations locais | SQL | supabase/migrations/ | **NÃO** | NÃO | ZERO |
| Views canônicas | SQL views | dump | **NÃO** | NÃO | ZERO |
| Materialized views | SQL mv | dump | **NÃO** | NÃO | ZERO |
| Cron jobs | pg_cron | — | **NÃO** | NÃO | ZERO |
| Dashboards externos | — | não verificável | DESCONHECIDO | DESCONHECIDO | A VERIFICAR |

---

## 9. Por Que P0-M4 NÃO Quebra as Funções DEFINER

As 7 funções `conceder_xp_*` são `SECURITY DEFINER` com owner `postgres`.

PostgreSQL: o owner `postgres` tem atributo `SUPERUSER`. SUPERUSER sempre bypassa RLS,
independente de qualquer política definida. Portanto:

```
P0-M4 adiciona:  CREATE POLICY xp_events_insert_block  WITH CHECK (false);
Efeito para authenticated:  INSERT bloqueado ✓
Efeito para conceder_xp_* (owner=postgres, SUPERUSER): RLS ignorado — INSERT continua ✓
Efeito para service_role:  BYPASSRLS — também ignorado ✓
```

A única alteração observável: usuários `authenticated` perdem a capacidade de INSERT direto.
Isso é exatamente o objetivo de P0-M4.

---

## 10. Análise do Risco da Policy "Usuário cria XP events"

A policy ativa permite que qualquer usuário `authenticated` insira em `xp_events` com seu
próprio `user_id`. Isso tem dois vetores de risco:

### Vetor 1 — DoS no sistema legado (MÉDIO)
Um usuário pode inserir um registro falso de `modulo_concluido` para o período atual,
fazendo com que `conceder_xp_modulo` devolva `'motivo': 'revisao_ja_concluida'` e recuse
conceder XP legítimo. Esse é um DoS no sistema XP legado, não no sistema canônico.

**Impacto no app mobile atual:** ZERO — o frontend não usa `conceder_xp_*` nem `xp_events`.

### Vetor 2 — Injeção de limite diário falso (BAIXO)
Inserindo registros com `xp` alto, o usuário pode fazer o limite diário (200 XP) aparecer
atingido, bloqueando os `conceder_xp_*` de conceder XP naquele dia.

**Impacto atual:** Baixo — as funções legacy não são chamadas ativamente pelo frontend.

### Vetor 3 — SELECT bloqueado = usuário não vê seus dados
A tabela não tem SELECT policy. O usuário que insere não consegue ler o que inseriu.
Isso limita significativamente a exploração prática.

---

## 11. Conclusão — P0-M4 pode subir?

| Pergunta | Resposta |
|----------|----------|
| Frontend usa `xp_events`? | **NÃO** — zero referências em src/ e app/ |
| Edge Functions usam `xp_events`? | **NÃO** — zero referências em supabase/functions/ |
| Migrations locais referenciam? | **NÃO** |
| Views canônicas referenciam? | **NÃO** |
| Funções DEFINER são quebradas pela nova policy? | **NÃO** — BYPASSRLS via SUPERUSER |
| FK de entrada existe? | **NÃO** — FK só sai (para auth.users) |
| Cron jobs dependem? | **NÃO** — nenhum pg_cron configurado |
| Dashboards externos? | **DESCONHECIDO** — verificar manualmente |

### Veredicto

**P0-M4 PODE subir com risco BAIXO**, com uma pré-condição pendente:

> **Pré-condição obrigatória antes de executar:**
> Confirmar que nenhum dashboard externo (Metabase, Retool, Supabase Studio queries
> salvas, etc.) faz SELECT ou INSERT em `xp_events` em produção.

Se essa verificação retornar zero consumidores externos, P0-M4 é segura.

### O que P0-M4 deve fazer (precisão cirúrgica)

```
1. DROP POLICY "Usuário cria XP events" ON public.xp_events;
2. CREATE POLICY "xp_events_insert_block" ON public.xp_events
       FOR INSERT WITH CHECK (false);
3. CREATE POLICY "xp_events_no_update" ON public.xp_events
       FOR UPDATE TO authenticated, anon USING (false);
4. CREATE POLICY "xp_events_no_delete" ON public.xp_events
       FOR DELETE TO authenticated, anon USING (false);
```

**O que NÃO fazer em P0-M4:**
- NÃO dropar a tabela (funções DEFINER ainda a usam como ledger)
- NÃO fazer REVOKE em service_role (quebraria conceder_xp_*)
- NÃO adicionar SELECT block policy (já bloqueado por ausência de policy)
- NÃO renomear ou alterar colunas (quebraria SELECT nas funções DEFINER)

---

## 12. Nota sobre `user_xp` (tabela associada)

As funções `conceder_xp_*` também atualizam `user_xp` (ln 11213–11225):
```sql
CREATE TABLE IF NOT EXISTS "public"."user_xp" (
    user_id uuid NOT NULL, -- FK → auth.users
    xp_total integer, xp_periodo integer, xp_merito integer,
    xp_constancia integer, last_xp_at timestamp, updated_at timestamp
);
```

Essa é mais uma tabela do sistema legado. Não é referenciada pelo frontend atual.
Policy: `"Usuário vê seu XP"` FOR SELECT USING (auth.uid() = user_id) — apenas leitura.

P0-M4 não precisa tocar `user_xp`.

---

## 13. Checklist Pré-Execução de P0-M4

```
[x] xp_events DDL lido e confirmado (ln 14497–14508)
[x] RLS policies em xp_events confirmadas (apenas INSERT policy ativa)
[x] grep src/ e app/ — ZERO referências a xp_events
[x] grep supabase/functions/ — ZERO referências a xp_events
[x] grep supabase/migrations/ — ZERO referências a xp_events
[x] 7 funções conceder_xp_* identificadas como consumidoras exclusivas (service_role DEFINER)
[x] Confirmado que DEFINER functions não são quebradas por blocking policy (BYPASSRLS)
[x] Confirmado que xp_eventos e xp_events são sistemas separados sem sync
[x] Nenhum cron job para xp_events no dump
[x] Nenhuma FK entrante em xp_events
[ ] Verificar dashboards externos / queries salvas em produção (manual — não verificável via dump)
[ ] Aprovado por: _______________
[ ] Data de execução: ___________
```
