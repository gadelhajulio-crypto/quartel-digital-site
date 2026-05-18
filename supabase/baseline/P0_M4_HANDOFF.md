# P0-M4 Handoff — Bloquear INSERT direto em `public.xp_events`
**Status:** AGUARDANDO EXECUÇÃO
**Data de geração:** 2026-05-16
**Classificação:** P0 — Segurança
**Arquivo de migration:** `supabase/migrations/20260516004000_p0_m4_block_xp_events_legacy_insert.sql`

---

## Objetivo

Eliminar o vetor de manipulação do sistema XP legado que permite a qualquer usuário
`authenticated` inserir diretamente em `public.xp_events`, contornando as RPCs DEFINER
que aplicam limites diários e idempotência.

A policy "Usuário cria XP events" (dump ln 17415) está ativa no banco remoto e precisa
ser removida e substituída por policies explícitas de bloqueio.

---

## Escopo

| O que muda | O que NÃO muda |
|-----------|----------------|
| Policy "Usuário cria XP events" → **removida** | Estrutura da tabela `xp_events` (DDL intacto) |
| Policy `xp_events_insert_block` → **criada** | FK `xp_events.user_id → auth.users(id)` |
| Policy `xp_events_no_update` → **criada** | GRANT para `service_role` |
| Policy `xp_events_no_delete` → **criada** | Funções `conceder_xp_*` (7 funções — intocadas) |
| | Tabela canônica `xp_eventos` e suas policies |
| | Tabela `user_xp` e seus dados |
| | Nenhuma view, MV, trigger ou Edge Function |

---

## Risco

| Dimensão | Avaliação |
|----------|-----------|
| Severidade da vulnerabilidade | **MÉDIO** — INSERT direto contorna controles de idempotência do sistema legado |
| Exploitabilidade atual | **MÉDIO** — policy ativa, qualquer authenticated pode explorar |
| Impacto no frontend | **ZERO** — `xp_events` tem zero referências em `src/` e `app/` |
| Impacto nas funções DEFINER | **ZERO** — SUPERUSER bypassa RLS (ver seção específica abaixo) |
| Impacto em Edge Functions | **ZERO** — zero referências em `supabase/functions/` |
| Risco da migration em si | **BAIXO** — apenas DDL de RLS policies, sem toque em dados |
| Reversibilidade | **IMEDIATA** — um DROP POLICY + um CREATE POLICY restaura o estado original |

---

## Impacto

### O que muda operacionalmente

- Usuários `authenticated` e `anon` recebem erro RLS ao tentar INSERT direto em `xp_events`.
- Usuários `authenticated` e `anon` recebem erro RLS ao tentar UPDATE ou DELETE em `xp_events`.
- O SELECT já era bloqueado por deny-by-default (ausência de SELECT policy com RLS habilitado) — não muda.

### O que NÃO muda operacionalmente

- As 7 funções `conceder_xp_*` continuam inserindo e lendo em `xp_events` normalmente.
- O sistema de XP canônico (`xp_eventos`) não é afetado em absolutamente nada.
- Nenhuma tela, hook ou serviço do app mobile é afetado.
- Nenhuma Edge Function é afetada.

---

## Pré-condição Manual Pendente

> **Esta é a única verificação que não pode ser feita via dump ou grep no codebase.**

Antes de executar em produção, confirmar manualmente que nenhum dos itens abaixo
acessa `xp_events` ativamente:

```
[ ] Metabase — verificar dashboards e queries salvas por "xp_events"
[ ] Retool   — verificar resources e queries por "xp_events"
[ ] Supabase Studio — verificar queries salvas / table editor em uso
[ ] Scripts externos / cron externo — verificar pipelines de ETL ou relatórios
[ ] Qualquer outro dashboard ou ferramenta de analytics conectada ao banco
```

Se todos retornarem zero consumidores: **prosseguir com a execução.**
Se qualquer item retornar consumidor ativo: **bloquear P0-M4** e tratar separadamente.

---

## Justificativa — Por Que Não Afeta as Funções SECURITY DEFINER

As 7 funções `conceder_xp_*` são declaradas `SECURITY DEFINER` com owner `postgres`.

**Mecanismo de bypass:**

Em PostgreSQL, o role `postgres` tem o atributo `SUPERUSER`. O manual do PostgreSQL
estabelece que superusuários sempre contornam verificações de Row Level Security,
independente de qualquer política definida na tabela.

```
SUPERUSER → BYPASSRLS → as policies WITH CHECK (false) são ignoradas para postgres
```

O parâmetro `TO authenticated, anon` nas policies criadas por esta migration reforça
isso explicitamente: a policy sequer é avaliada para roles fora dessa lista.

**Rastreio de execução de uma chamada típica:**

```
service_role chama conceder_xp_uso_diario(p_user_id)
  └─ função executa como owner=postgres (SECURITY DEFINER)
      └─ SELECT FROM xp_events → postgres = SUPERUSER → bypassa RLS → lê normalmente
      └─ INSERT INTO xp_events → postgres = SUPERUSER → bypassa RLS → insere normalmente
      └─ UPDATE user_xp        → operação separada, não afetada
  └─ retorna JSON com xp_concedido e motivo
```

Nenhum passo desse fluxo é interceptado pelas policies desta migration.

### As 7 funções afetadas (confirmadas no dump — NÃO alteradas)

| Função | Dump ln | Operações em `xp_events` | Grants |
|--------|---------|--------------------------|--------|
| `conceder_xp_modulo(p_user_id, p_modulo_id)` | 1389 | SELECT + INSERT | service_role |
| `conceder_xp_revisao_recomendada(p_user_id, p_revisao_id)` | 1479 | SELECT + INSERT | service_role |
| `conceder_xp_revisao_voluntaria(p_user_id, p_revisao_id)` | 1567 | SELECT + INSERT | service_role |
| `conceder_xp_simulado(p_user_id, p_simulado_id, p_pct)` | 1655 | SELECT + INSERT | service_role |
| `conceder_xp_streak_5_dias(p_user_id)` | 1755 | SELECT + INSERT | service_role |
| `conceder_xp_uso_diario(p_user_id)` | 1848 | SELECT + INSERT | service_role |
| `conceder_xp_whatsapp(p_user_id)` | 1926 | SELECT + INSERT | service_role |

---

## SQL Exato da Migration

```sql
-- Step 1 — Remover a policy permissiva original
DROP POLICY IF EXISTS "Usuário cria XP events" ON public.xp_events;

-- Step 2 — Idempotência: remover policies de bloqueio se já existirem
DROP POLICY IF EXISTS "xp_events_insert_block" ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_no_update"    ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_no_delete"    ON public.xp_events;

-- Step 3 — Bloquear INSERT para authenticated e anon
CREATE POLICY "xp_events_insert_block"
    ON public.xp_events
    FOR INSERT
    TO authenticated, anon
    WITH CHECK (false);

-- Step 4 — Bloquear UPDATE para authenticated e anon
CREATE POLICY "xp_events_no_update"
    ON public.xp_events
    FOR UPDATE
    TO authenticated, anon
    USING (false);

-- Step 5 — Bloquear DELETE para authenticated e anon
CREATE POLICY "xp_events_no_delete"
    ON public.xp_events
    FOR DELETE
    TO authenticated, anon
    USING (false);
```

**Observação sobre SELECT:** Nenhuma policy de SELECT é criada. Com RLS habilitado
e sem policy de SELECT, `authenticated` já vê zero linhas por deny-by-default do
PostgreSQL. Criar uma nova policy de SELECT poderia ampliar acesso inadvertidamente.

---

## Testes SQL Pós-Apply

### Teste 1 — Policy permissiva foi removida?
```sql
SELECT polname
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename  = 'xp_events'
  AND polname    = 'Usuário cria XP events';
```
**Esperado:** zero linhas.

---

### Teste 2 — Três policies de bloqueio foram criadas com roles corretos?
```sql
SELECT polname, polcmd, polroles::text
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename  = 'xp_events'
ORDER BY polname;
```
**Esperado:** exatamente 3 linhas:
```
polname                | polcmd | polroles
-----------------------|--------|------------------------
xp_events_insert_block | i      | {authenticated,anon}
xp_events_no_delete    | d      | {authenticated,anon}
xp_events_no_update    | u      | {authenticated,anon}
```

---

### Teste 3 — INSERT direto bloqueado para `authenticated`?
*(executar como usuário authenticated com JWT válido)*
```sql
INSERT INTO public.xp_events (user_id, tipo, xp, periodo)
VALUES (auth.uid(), 'test_block', 1, '2026-05');
```
**Esperado:** `ERROR: new row violates row-level security policy for table "xp_events"`

---

### Teste 4 — `service_role` ainda consegue INSERT?
*(executar como service_role — confirma que funções DEFINER não quebram)*
```sql
INSERT INTO public.xp_events (user_id, tipo, xp, periodo)
VALUES ('<uuid_valido>', 'test_service_role', 1, '2026-05');
```
**Esperado:** `INSERT 0 1` — sucesso (service_role bypassa RLS).

Limpar após teste:
```sql
DELETE FROM public.xp_events WHERE tipo = 'test_service_role';
```

---

### Teste 5 — Funções `conceder_xp_*` ainda funcionam?
*(executar como service_role com um recruta_id/user_id válido)*
```sql
SELECT * FROM public.conceder_xp_uso_diario('<uuid_de_user_valido>');
```
**Esperado:** JSON com `xp_concedido` e `motivo` — sem erro de permissão.
*(pode retornar `xp_concedido: 0` com `motivo: "ja_concedido_hoje"` — isso é comportamento normal)*

---

### Teste 6 — RLS está habilitado na tabela?
```sql
SELECT relname, relrowsecurity
FROM pg_class
WHERE relname = 'xp_events'
  AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```
**Esperado:** `relrowsecurity = true`

---

### Teste 7 — Grants de `service_role` preservados?
```sql
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name   = 'xp_events'
  AND grantee      = 'service_role';
```
**Esperado:** pelo menos `SELECT`, `INSERT`, `UPDATE`, `DELETE` para `service_role`.

---

## Rollback

Caso a migration precise ser revertida:

**Passo 1 — Remover as policies de bloqueio:**
```sql
DROP POLICY IF EXISTS "xp_events_insert_block" ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_no_update"    ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_no_delete"    ON public.xp_events;
```

**Passo 2 — Recriar a policy permissiva original (dump ln 17415):**
```sql
CREATE POLICY "Usuário cria XP events"
    ON public.xp_events
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);
```

**Verificação pós-rollback:**
```sql
SELECT polname, polcmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'xp_events';
-- Esperado: apenas "Usuário cria XP events" com polcmd = i
```

---

## Referências

| Documento | Localização |
|-----------|-------------|
| Arquivo da migration | `supabase/migrations/20260516004000_p0_m4_block_xp_events_legacy_insert.sql` |
| Auditoria completa de xp_events | `supabase/baseline/XP_EVENTS_LEGACY_AUDIT.md` |
| Dump remoto (tabela, ln 14497) | `supabase/remote/supabase_remote_schema.sql` |
| Dump remoto (policy original, ln 17415) | `supabase/remote/supabase_remote_schema.sql` |
| Dump remoto (funções, ln 1389–2010) | `supabase/remote/supabase_remote_schema.sql` |
| Decision Packet (P0-M4) | `supabase/baseline/P0_DECISION_PACKET.md §2` |

---

## Checklist de Aprovação

```
[ ] Dump relido nas linhas 17413–17416 (policy original confirmada)
[ ] XP_EVENTS_LEGACY_AUDIT.md revisado e conclusões aceitas
[ ] Pré-condição manual cumprida:
    [ ] Metabase — zero queries ativas em xp_events
    [ ] Retool   — zero queries ativas em xp_events
    [ ] Supabase Studio — zero uso ativo em xp_events
    [ ] Scripts externos / ETL — zero uso ativo em xp_events
[ ] Migration aplicada em ambiente de staging
[ ] Teste 1 passou em staging (policy permissiva removida)
[ ] Teste 2 passou em staging (3 policies de bloqueio presentes)
[ ] Teste 3 passou em staging (INSERT authenticated bloqueado)
[ ] Teste 4 passou em staging (INSERT service_role bem-sucedido)
[ ] Teste 5 passou em staging (conceder_xp_uso_diario sem erro)
[ ] Aprovado por: ___________________________
[ ] Data de execução em produção: ___________
[ ] Executado por: __________________________
[ ] Testes repetidos em produção pós-apply
[ ] Status atualizado para: EXECUTADO
```

---

## Status

```
AGUARDANDO EXECUÇÃO
```
