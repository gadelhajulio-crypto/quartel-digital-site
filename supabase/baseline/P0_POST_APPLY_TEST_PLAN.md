# P0 Post-Apply Test Plan — Pacote P0-M1 a P0-M6
**Versao:** 1.0
**Data de geracao:** 2026-05-17
**Escopo:** Validacao pos-migration de P0-M1, P0-M2, P0-M4, P0-M5 e P0-M6
**Gerado por:** institutional-audit-2026-05-17
**Modo:** Somente leitura — NENHUM SQL deste documento altera dados de producao
**Instrucao ao operador:** Executar cada bloco SQL no Supabase SQL Editor.
  Anotar o resultado no Relatorio de Execucao (Secao 10).

> **IMPORTANTE:** P0-M3 e VOID (falso positivo confirmado). Nenhum teste e necessario para ela.
> P0-M4 tem pre-condicao manual pendente — ver Secao 4 e PRE_DEPLOY_GATE.md.

---

## Indice

1. [Identificacao do Ambiente](#1-identificacao-do-ambiente)
2. [Testes P0-M1 — buscar_revisoes_whatsapp](#2-testes-p0-m1)
3. [Testes P0-M2 — Baseline Snapshot](#3-testes-p0-m2)
4. [Testes P0-M4 — Bloqueio xp_events](#4-testes-p0-m4)
5. [Testes P0-M5 — Contract Registry](#5-testes-p0-m5)
6. [Testes P0-M6 — complete_lesson auth guard](#6-testes-p0-m6)
7. [Smoke Test Frontend](#7-smoke-test-frontend)
8. [Criterios de Aprovacao](#8-criterios-de-aprovacao)
9. [Criterios de Rollback](#9-criterios-de-rollback)
10. [Relatorio de Execucao](#10-relatorio-de-execucao)

---

## 1. Identificacao do Ambiente

Executar antes de qualquer teste para confirmar que o ambiente e o esperado.

### 1.1 Versao do PostgreSQL e role atual

```sql
SELECT
    version()                   AS postgres_version,
    current_user                AS role_atual,
    current_setting('role')     AS role_configurado;
```

**Esperado:** PostgreSQL 14+ ; `current_user` = `postgres` ou `service_role`

---

### 1.2 Migrations aplicadas pelo Supabase CLI

```sql
SELECT version_id, inserted_at
FROM supabase_migrations.schema_migrations
WHERE version_id LIKE '202605160%'
ORDER BY version_id;
```

**Esperado (apos apply completo do pacote P0):**

| version_id       | Migracao correspondente  |
|------------------|--------------------------|
| 20260516001000   | P0-M1 buscar_revisoes    |
| 20260516002000   | P0-M2 baseline_audit     |
| 20260516004000   | P0-M4 xp_events block    |
| 20260516005000   | P0-M5 contract_registry  |
| 20260516006000   | P0-M6 complete_lesson    |

> Observacao: 20260516003000 (P0-M3) nao deve aparecer — arquivo void, nunca existiu.

---

### 1.3 Objetos criados ou alterados confirmados no banco

```sql
SELECT
    n.nspname   AS schema,
    p.proname   AS funcao,
    p.prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('buscar_revisoes_whatsapp', 'complete_lesson')
ORDER BY p.proname;
```

**Esperado:** 2 linhas, ambas com `security_definer = true`

---

## 2. Testes P0-M1

**Migration:** `20260516001000_p0_m1_fix_buscar_revisoes_whatsapp_search_path.sql`
**Objetivo:** Confirmar que `buscar_revisoes_whatsapp()` tem `search_path` fixado e grants corretos.

---

### M1-T1 — Funcao existe, SECURITY DEFINER ativo, search_path aplicado?

```sql
SELECT
    p.proname       AS funcao,
    p.prosecdef     AS security_definer,
    p.proconfig     AS configuracao
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'buscar_revisoes_whatsapp';
```

**Esperado:**
```
funcao                    | security_definer | configuracao
buscar_revisoes_whatsapp  | true             | {search_path=public,pg_catalog}
```

**Falha indica:** P0-M1 nao foi aplicada, ou o ALTER FUNCTION nao persistiu.

---

### M1-T2 — search_path contem exatamente 'public' e 'pg_catalog'?

```sql
SELECT
    unnest(p.proconfig) AS parametro
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'buscar_revisoes_whatsapp';
```

**Esperado:** 1 linha: `search_path=public,pg_catalog`

---

### M1-T3 — Grant preservado apenas para service_role?

```sql
SELECT
    grantee,
    privilege_type,
    is_grantable
FROM information_schema.role_routine_grants
WHERE routine_schema = 'public'
  AND routine_name   = 'buscar_revisoes_whatsapp'
ORDER BY grantee;
```

**Esperado:**
```
grantee      | privilege_type | is_grantable
service_role | EXECUTE        | NO
```

Nenhuma outra linha. Em particular: `postgres` pode aparecer como owner (normal), mas `PUBLIC` e `anon` nao devem aparecer.

---

### M1-T4 — PUBLIC nao tem EXECUTE?

```sql
SELECT grantee
FROM information_schema.role_routine_grants
WHERE routine_name = 'buscar_revisoes_whatsapp'
  AND grantee = 'PUBLIC';
```

**Esperado:** zero linhas

---

### M1-T5 — Funcao executa sem erro (chamada funcional como service_role)?

```sql
SELECT * FROM public.buscar_revisoes_whatsapp() LIMIT 1;
```

**Esperado:** 0 ou mais linhas com colunas `(revisao_id, recruta_id, missao_id, forca)`.
Nenhum erro de permissao ou schema. O resultado vazio e valido se nao houver revisoes whatsapp pendentes.

---

### Resultado M1

| Teste | Query | Esperado | Obtido | Status |
|-------|-------|----------|--------|--------|
| M1-T1 | proconfig | {search_path=public,pg_catalog} | | |
| M1-T2 | unnest proconfig | search_path=public,pg_catalog | | |
| M1-T3 | role_routine_grants | service_role EXECUTE | | |
| M1-T4 | PUBLIC grant | 0 linhas | | |
| M1-T5 | chamada funcional | sem erro | | |

---

## 3. Testes P0-M2

**Migration:** `20260516002000_p0_m2_register_baseline_audit.sql`
**Objetivo:** Confirmar que o snapshot de auditoria foi inserido com dados corretos em `_qd_migration_snapshots`.

---

### M2-T1 — Registro foi inserido?

```sql
SELECT
    migration_id,
    applied_at
FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
```

**Esperado:** 1 linha com `migration_id = 'baseline_audit_2026_05_16'` e `applied_at` preenchido (timestamp nao nulo).

---

### M2-T2 — Contagens do snapshot estao corretas?

```sql
SELECT
    snapshot->>'baseline_date'                                      AS baseline_date,
    snapshot->>'auditor'                                            AS auditor,
    jsonb_array_length(snapshot->'security_issues_confirmed')       AS security_issues,
    jsonb_array_length(snapshot->'false_positives_found')           AS false_positives,
    jsonb_array_length(snapshot->'critical_contracts_confirmed')    AS contracts_confirmados,
    jsonb_array_length(snapshot->'contracts_missing')               AS contracts_ausentes
FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
```

**Esperado:**
```
baseline_date       | 2026-05-16
auditor             | institutional-audit-2026-05-16
security_issues     | 6
false_positives     | 1
contracts_confirmados | 25
contracts_ausentes  | 1
```

---

### M2-T3 — Campo security_issues_confirmed contem os 6 IDs esperados?

```sql
SELECT
    item->>'id'         AS id_achado,
    item->>'severity'   AS severidade,
    item->>'status'     AS status_achado
FROM public._qd_migration_snapshots,
     jsonb_array_elements(snapshot->'security_issues_confirmed') AS item
WHERE migration_id = 'baseline_audit_2026_05_16'
ORDER BY item->>'id';
```

**Esperado:** 6 linhas com IDs SEC-01, SEC-02, SEC-03, SEC-04, SEC-05, SEC-06.

---

### M2-T4 — Campo false_positives_found contem FP-01?

```sql
SELECT
    item->>'id'     AS id_fp,
    item->>'object' AS objeto,
    item->>'status' AS status_fp
FROM public._qd_migration_snapshots,
     jsonb_array_elements(snapshot->'false_positives_found') AS item
WHERE migration_id = 'baseline_audit_2026_05_16';
```

**Esperado:** 1 linha: `FP-01 | public.fn_insert_audit_evento_smart | VOID`

---

### M2-T5 — Campo critical_contracts_confirmed contem 'complete_lesson'?

```sql
SELECT
    item AS contrato
FROM public._qd_migration_snapshots,
     jsonb_array_elements_text(snapshot->'critical_contracts_confirmed') AS item
WHERE migration_id = 'baseline_audit_2026_05_16'
  AND item = 'complete_lesson';
```

**Esperado:** 1 linha com `complete_lesson`

---

### M2-T6 — Idempotencia: contagem permanece 1 apos reexecucao simulada?

```sql
-- Passo 1: anotar contagem antes
SELECT COUNT(*)
FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
-- Esperado: 1

-- Passo 2: reexecutar o INSERT da migration (cole o INSERT completo do arquivo .sql)
-- O resultado do INSERT deve ser: INSERT 0 0 (zero linhas — ON CONFLICT DO NOTHING)

-- Passo 3: verificar que continuam sendo 1 linha
SELECT COUNT(*)
FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
-- Esperado: 1 (inalterado)
```

---

### M2-T7 — applied_at nao foi sobrescrito pela reexecucao?

```sql
-- Executar ANTES da reexecucao:
SELECT applied_at AS applied_at_original
FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';

-- Executar o INSERT novamente (ON CONFLICT DO NOTHING).

-- Executar APOS a reexecucao — deve ser o mesmo timestamp:
SELECT applied_at AS applied_at_pos_reexecucao
FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
-- Esperado: applied_at_original = applied_at_pos_reexecucao
```

---

### Resultado M2

| Teste | Query | Esperado | Obtido | Status |
|-------|-------|----------|--------|--------|
| M2-T1 | registro existe | 1 linha | | |
| M2-T2 | contagens snapshot | 6 / 1 / 25 / 1 | | |
| M2-T3 | security_issues_confirmed | SEC-01..SEC-06 | | |
| M2-T4 | false_positives_found | FP-01 VOID | | |
| M2-T5 | complete_lesson no snapshot | 1 linha | | |
| M2-T6 | idempotencia INSERT | 1 linha apos reexec | | |
| M2-T7 | applied_at preservado | timestamp igual | | |

---

## 4. Testes P0-M4

**Migration:** `20260516004000_p0_m4_block_xp_events_legacy_insert.sql`
**Objetivo:** Confirmar que INSERT/UPDATE/DELETE direto em `xp_events` foi bloqueado para `authenticated`/`anon` e que as funcoes `conceder_xp_*` continuam funcionando.

> **PRE-CONDICAO OBRIGATORIA** (verificar antes de executar os testes):
> ```
> [ ] Metabase — zero queries ativas com INSERT em public.xp_events
> [ ] Retool   — zero queries ativas com INSERT em public.xp_events
> [ ] Supabase Studio — nenhuma query salva com INSERT em public.xp_events
> [ ] Scripts / ETL externos — zero consumidores ativos de public.xp_events
> ```
> Se qualquer item acima nao foi verificado, os testes de metadados (M4-T1 a M4-T6) podem ser
> executados com seguranca, mas o teste M4-T7 (funcional) deve aguardar confirmacao.

---

### M4-T1 — Policy permissiva original foi removida?

```sql
SELECT polname
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename  = 'xp_events'
  AND polname    = 'Usuário cria XP events';
```

**Esperado:** zero linhas

**Falha indica:** P0-M4 nao foi aplicada, ou o DROP nao funcionou.

---

### M4-T2 — RLS esta habilitado na tabela xp_events?

```sql
SELECT
    relname             AS tabela,
    relrowsecurity      AS rls_ativo,
    relforcerowsecurity AS rls_forcado
FROM pg_class
WHERE relname        = 'xp_events'
  AND relnamespace   = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```

**Esperado:** `rls_ativo = true`

---

### M4-T3 — Tres policies de bloqueio foram criadas com roles corretos?

```sql
SELECT
    polname,
    polcmd,
    polroles::text
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename  = 'xp_events'
ORDER BY polname;
```

**Esperado:** exatamente 3 linhas:

```
polname                | polcmd | polroles
-----------------------|--------|--------------------
xp_events_insert_block | i      | {authenticated,anon}
xp_events_no_delete    | d      | {authenticated,anon}
xp_events_no_update    | u      | {authenticated,anon}
```

Nenhuma outra policy deve estar presente (em particular: `Usuário cria XP events` nao deve existir).

---

### M4-T4 — Policies de bloqueio tem WITH CHECK / USING (false)?

```sql
SELECT
    polname,
    polcmd,
    pg_get_expr(polwithcheck, polrelid)  AS with_check_expr,
    pg_get_expr(polqual,      polrelid)  AS using_expr
FROM pg_policy
JOIN pg_class ON pg_class.oid = pg_policy.polrelid
WHERE pg_class.relname      = 'xp_events'
  AND pg_class.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY polname;
```

**Esperado:**

| polname | polcmd | with_check_expr | using_expr |
|---------|--------|-----------------|------------|
| xp_events_insert_block | i | false | (null) |
| xp_events_no_delete | d | (null) | false |
| xp_events_no_update | u | (null) | false |

---

### M4-T5 — Grants de service_role em xp_events foram preservados?

```sql
SELECT
    grantee,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name   = 'xp_events'
  AND grantee      = 'service_role'
ORDER BY privilege_type;
```

**Esperado:** pelo menos SELECT, INSERT, UPDATE, DELETE para `service_role`.

---

### M4-T6 — Funcoes conceder_xp_* ainda existem no banco?

```sql
SELECT
    proname         AS funcao,
    prosecdef       AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname LIKE 'conceder_xp_%'
ORDER BY p.proname;
```

**Esperado:** 7 linhas, todas com `security_definer = true`:
- `conceder_xp_modulo`
- `conceder_xp_revisao_recomendada`
- `conceder_xp_revisao_voluntaria`
- `conceder_xp_simulado`
- `conceder_xp_streak_5_dias`
- `conceder_xp_uso_diario`
- `conceder_xp_whatsapp`

---

### M4-T7A — [SEGURO POR METADADOS] Verificar que policy de INSERT tem WITH CHECK (false)

```sql
SELECT
    polname,
    pg_get_expr(polwithcheck, polrelid) AS with_check_expr
FROM pg_policy
JOIN pg_class ON pg_class.oid = pg_policy.polrelid
WHERE pg_class.relname      = 'xp_events'
  AND pg_class.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND polname               = 'xp_events_insert_block';
```

**Esperado:** `with_check_expr = 'false'`

Isso confirma sem inserir nenhum dado que o bloqueio esta configurado corretamente.

---

### M4-T7B — [FUNCIONAL OPCIONAL — APENAS STAGING ou com dados de teste]

> **NAO EXECUTAR EM PRODUCAO** sem UUID de teste dedicado.
> Envolve INSERT real (com ROLLBACK para nao persistir).

```sql
-- Executar como usuario authenticated com JWT valido no SQL Editor do Studio.
-- O Studio executa como service_role por padrao — para testar authenticated,
-- usar a opcao "Auth > Run as user" do Supabase Studio ou uma chamada via SDK.

-- Teste de bloqueio (wrapped em transacao para seguranca):
BEGIN;
INSERT INTO public.xp_events (user_id, tipo, xp, periodo)
VALUES (auth.uid(), 'test_p0_m4_block', 1, '2026-05');
-- Esperado: ERROR: new row violates row-level security policy for table "xp_events"
ROLLBACK;
```

**Esperado:** erro 42501 / "new row violates row-level security policy" — o INSERT falha e a transacao e revertida.

---

### Resultado M4

| Teste | Query | Esperado | Obtido | Status |
|-------|-------|----------|--------|--------|
| M4-T1 | policy antiga removida | 0 linhas | | |
| M4-T2 | RLS habilitado | true | | |
| M4-T3 | 3 policies novas | 3 linhas corretas | | |
| M4-T4 | WITH CHECK / USING false | false em todas | | |
| M4-T5 | grants service_role | SELECT/INSERT/UPDATE/DELETE | | |
| M4-T6 | 7 funcoes conceder_xp_* | 7 linhas | | |
| M4-T7A | with_check_expr = false | false | | |
| M4-T7B | INSERT bloqueado (opcional) | erro RLS | | |

---

## 5. Testes P0-M5

**Migration:** `20260516005000_p0_m5_register_contract_registry.sql`
**Objetivo:** Confirmar que 38 contratos canonicos foram registrados em `c6_contract_registry`.

---

### M5-T1 — Total de contratos canonical inseridos?

```sql
SELECT COUNT(*) AS total_canonical
FROM public.c6_contract_registry
WHERE status = 'canonical';
```

**Esperado:** `38`

---

### M5-T2 — Distribuicao por tipo esta correta?

```sql
SELECT
    contract_type,
    COUNT(*) AS quantidade
FROM public.c6_contract_registry
WHERE status = 'canonical'
GROUP BY contract_type
ORDER BY contract_type;
```

**Esperado:**
```
contract_type | quantidade
--------------+----------
rpc           | 13
view          | 25
```

---

### M5-T3 — complete_lesson tem nota de risco ativo?

```sql
SELECT
    contract_name,
    contract_type,
    status,
    notes
FROM public.c6_contract_registry
WHERE contract_name = 'complete_lesson';
```

**Esperado:** `notes` contem a string `'RISCO ATIVO'`.

> Apos confirmar P0-M6 aplicado com sucesso, o campo `notes` pode ser atualizado manualmente
> conforme OBS-01 em PRE_DEPLOY_GATE.md.

---

### M5-T4 — v_c6_contracts_validos retorna os 38 registros?

```sql
SELECT COUNT(*) AS total_validos
FROM public.v_c6_contracts_validos;
```

**Esperado:** `38`

> Esta view filtra `status IN ('canonical','system')`. Se retornar diferente de 38,
> verificar se existiam contratos pre-existentes com status 'system' na tabela.

---

### M5-T5 — v_completed_lessons_count NAO foi registrado (estava ausente no dump)?

```sql
SELECT contract_name
FROM public.c6_contract_registry
WHERE contract_name = 'v_completed_lessons_count';
```

**Esperado:** zero linhas

Esta view foi excluida da migration por estar ausente no dump remoto.
Se aparecer, significa que foi adicionada fora deste pacote.

---

### M5-T6 — Contratos de dominio critico estao presentes?

```sql
SELECT contract_name, contract_type
FROM public.c6_contract_registry
WHERE contract_name IN (
    -- Chat
    'v_chat_conversas_recruta',
    'rpc_chat_send_message',
    'rpc_chat_mark_read',
    -- Onboarding
    'rpc_complete_onboarding',
    'v_onboarding_status',
    -- Ranking
    'v_ranking_mensal_rcc',
    'v_posicao_recruta_mes_rcc',
    -- Billing
    'v_billing_status_recruta_v2',
    -- Progresso
    'complete_lesson',
    'vw_rdm_lessons_v2',
    'vw_recruta_module_progress_v2'
)
ORDER BY contract_name;
```

**Esperado:** 11 linhas, todas com `status = 'canonical'` (verificar via JOIN se necessario).

---

### M5-T7 — Nenhum valor invalido viola os CHECK constraints?

```sql
SELECT
    contract_name,
    contract_type,
    status
FROM public.c6_contract_registry
WHERE contract_type NOT IN ('view', 'materialized_view', 'rpc')
   OR status        NOT IN ('canonical', 'system', 'legacy', 'admin_audit', 'blocked');
```

**Esperado:** zero linhas

---

### M5-T8 — Idempotencia: reexecucao nao insere linhas extras?

```sql
-- Passo 1: registrar contagem atual
SELECT COUNT(*) FROM public.c6_contract_registry WHERE status = 'canonical';
-- Deve ser 38

-- Passo 2: reexecutar o INSERT da migration (cole o bloco VALUES completo do .sql)
-- Esperado: INSERT 0 0

-- Passo 3: verificar que contagem nao mudou
SELECT COUNT(*) FROM public.c6_contract_registry WHERE status = 'canonical';
-- Esperado: 38 (inalterado)
```

---

### Resultado M5

| Teste | Query | Esperado | Obtido | Status |
|-------|-------|----------|--------|--------|
| M5-T1 | COUNT canonical | 38 | | |
| M5-T2 | COUNT por tipo | rpc=13, view=25 | | |
| M5-T3 | complete_lesson notes | 'RISCO ATIVO' | | |
| M5-T4 | v_c6_contracts_validos | 38 | | |
| M5-T5 | v_completed_lessons_count ausente | 0 linhas | | |
| M5-T6 | contratos criticos presentes | 11 linhas | | |
| M5-T7 | sem violacao CHECK | 0 linhas invalidas | | |
| M5-T8 | idempotencia | 38 apos reexec | | |

---

## 6. Testes P0-M6

**Migration:** `20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql`
**Objetivo:** Confirmar que `complete_lesson` tem a guarda `auth.uid()`, os grants corretos
e que o comportamento de seguranca e o esperado.

---

### M6-T1 — Funcao existe com SECURITY DEFINER e search_path correto?

```sql
SELECT
    p.proname       AS funcao,
    p.prosecdef     AS security_definer,
    p.proconfig     AS configuracao,
    pg_get_function_identity_arguments(p.oid) AS assinatura
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'complete_lesson';
```

**Esperado:**
```
funcao          | security_definer | configuracao           | assinatura
complete_lesson | true             | {search_path=public}   | p_recruta_id uuid, p_lesson_id uuid, p_xp integer
```

---

### M6-T2 — Corpo da funcao contem a guarda auth.uid()?

```sql
SELECT
    pg_get_functiondef(p.oid) AS corpo_funcao
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'complete_lesson';
```

**Verificar manualmente no resultado que o corpo contem as tres strings obrigatorias:**

| String obrigatoria | Proposito |
|--------------------|-----------|
| `auth.uid() IS NOT NULL` | Preserva chamadas via service_role sem JWT |
| `IS DISTINCT FROM` | Comparacao segura com NULL (evita bypass via NULL) |
| `ERRCODE = '42501'` | Codigo correto para insufficient_privilege |

---

### M6-T3 — Grant para authenticated existe?

```sql
SELECT has_function_privilege(
    'authenticated',
    'public.complete_lesson(uuid, uuid, integer)',
    'EXECUTE'
) AS authenticated_tem_execute;
```

**Esperado:** `true`

---

### M6-T4 — Grant para service_role foi preservado?

```sql
SELECT has_function_privilege(
    'service_role',
    'public.complete_lesson(uuid, uuid, integer)',
    'EXECUTE'
) AS service_role_tem_execute;
```

**Esperado:** `true`

---

### M6-T5 — anon nao tem EXECUTE?

```sql
SELECT has_function_privilege(
    'anon',
    'public.complete_lesson(uuid, uuid, integer)',
    'EXECUTE'
) AS anon_tem_execute;
```

**Esperado:** `false`

---

### M6-T6 — Grants completos por role (visao consolidada)?

```sql
SELECT
    grantee,
    privilege_type,
    is_grantable
FROM information_schema.role_routine_grants
WHERE routine_schema = 'public'
  AND routine_name   = 'complete_lesson'
ORDER BY grantee;
```

**Esperado:**

| grantee | privilege_type | is_grantable |
|---------|----------------|--------------|
| authenticated | EXECUTE | NO |
| service_role  | EXECUTE | NO |

`postgres` pode aparecer como owner (normal). `PUBLIC` e `anon` nao devem aparecer com EXECUTE.

---

### M6-T7A — [SEGURO POR METADADOS] Verificar guarda via pg_get_functiondef sem inserir dados

```sql
-- Confirmar que o corpo contem 'IS DISTINCT FROM' (fundamental para seguranca contra NULL bypass):
SELECT
    CASE
        WHEN pg_get_functiondef(p.oid) LIKE '%IS DISTINCT FROM%'
        THEN 'GUARDA PRESENTE'
        ELSE 'GUARDA AUSENTE — FALHA CRITICA'
    END AS status_guarda_distinto,
    CASE
        WHEN pg_get_functiondef(p.oid) LIKE '%auth.uid() IS NOT NULL%'
        THEN 'SERVICE_ROLE BYPASS PRESENTE'
        ELSE 'SERVICE_ROLE BYPASS AUSENTE — EDGE FUNCTIONS PODEM QUEBRAR'
    END AS status_bypass_service_role,
    CASE
        WHEN pg_get_functiondef(p.oid) LIKE '%42501%'
        THEN 'ERRCODE CORRETO'
        ELSE 'ERRCODE INCORRETO — REVISAR'
    END AS status_errcode
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'complete_lesson';
```

**Esperado:** todas as tres colunas com o valor 'PRESENTE' / 'CORRETO'.

---

### M6-T7B — [FUNCIONAL OPCIONAL — APENAS STAGING]

> **NAO EXECUTAR EM PRODUCAO.**
> Requer UUID de recruta e aula de teste. Envolve DML real — usar ROLLBACK.

#### Teste de Spoofing (deve FALHAR):

```sql
-- Executar como usuario authenticated (Role = authenticated no Studio)
-- Substituir <uuid_de_outro_recruta> e <uuid_de_aula_qualquer> por valores de staging

BEGIN;

SELECT public.complete_lesson(
    '<uuid_de_outro_recruta>',
    '<uuid_de_aula_qualquer>'
);
-- Esperado: ERROR 42501 — "Unauthorized: p_recruta_id must match the authenticated user session"

ROLLBACK;
```

#### Teste de Chamada Legitima (deve PASSAR):

```sql
-- Executar como usuario authenticated (o proprio usuario do JWT)

BEGIN;

SELECT public.complete_lesson(
    auth.uid(),
    '<uuid_de_aula_valida_nao_concluida>'
);
-- Esperado: {"status":"ok","xp_granted":true,"xp_added":50}
-- OU:       {"status":"ok","xp_granted":false,"message":"Aula já concluída anteriormente"}

ROLLBACK;
-- Usar ROLLBACK em staging para nao sujar o estado de progresso dos recrutas de teste.
-- Em producao real (se habilitado): remover o ROLLBACK e confirmar via historico.
```

#### Teste de Idempotencia (nao duplica XP):

```sql
-- Executar como authenticated — chamar duas vezes com a mesma aula

BEGIN;

SELECT public.complete_lesson(auth.uid(), '<uuid_aula_teste>');
SELECT public.complete_lesson(auth.uid(), '<uuid_aula_teste>');

SELECT COUNT(*)
FROM public.xp_eventos
WHERE recruta_id    = auth.uid()
  AND referencia_id = '<uuid_aula_teste>'
  AND origem        = 'lesson_complete';
-- Esperado: 1 (uma unica entrada, nao 2)

ROLLBACK;
```

---

### M6-T8 — Chamada via service_role (sem JWT) nao e bloqueada pela guarda?

```sql
-- Executar como service_role (padrao no SQL Editor do Supabase Studio)
-- Nao inserir dados reais — usar BEGIN/ROLLBACK

BEGIN;
SELECT public.complete_lesson(
    '<uuid_recruta_valido>',
    '<uuid_aula_valida>'
);
-- Esperado: sem erro 42501.
-- A guarda IS NOT NULL garante que service_role (auth.uid()=NULL) passa livremente.
ROLLBACK;
```

---

### Resultado M6

| Teste | Query | Esperado | Obtido | Status |
|-------|-------|----------|--------|--------|
| M6-T1 | funcao existe + DEFINER + search_path | true / {search_path=public} | | |
| M6-T2 | corpo contem 3 strings criticas | todas presentes | | |
| M6-T3 | authenticated EXECUTE | true | | |
| M6-T4 | service_role EXECUTE | true | | |
| M6-T5 | anon EXECUTE | false | | |
| M6-T6 | grants consolidados | authenticated + service_role | | |
| M6-T7A | guarda via pg_get_functiondef | PRESENTE / CORRETO | | |
| M6-T7B | spoofing bloqueado (staging) | erro 42501 | | |
| M6-T7B | chamada legitima (staging) | status ok | | |
| M6-T7B | idempotencia XP (staging) | COUNT = 1 | | |
| M6-T8 | service_role sem JWT passa | sem erro | | |

---

## 7. Smoke Test Frontend

Checklist manual a ser executado apos todas as migrations aplicadas.
Executar no dispositivo/simulador conectado ao ambiente alvo (staging ou producao).

### 7.1 Auth e Sessao

```
[ ] Login com usuario valido → tela principal carrega sem erro
[ ] Token JWT e recebido e armazenado
[ ] rpc_auth_claim_active_client_session e chamado (verificar logs ou network)
[ ] rpc_auth_resolve_session_state retorna estado correto
[ ] Logout → sessao revogada
[ ] Login novamente apos logout → funciona normalmente
```

### 7.2 Onboarding

```
[ ] Novo usuario passa pelo fluxo de onboarding
[ ] rpc_complete_onboarding(p_forca, p_nome_guerra) e chamado
[ ] v_onboarding_status retorna onboarding_concluido = true apos conclusao
[ ] Reabrir app apos onboarding: nao repete fluxo
```

### 7.3 Painel Principal

```
[ ] Painel carrega sem erro (v_identidade_recruta OK)
[ ] XP total exibido corretamente (v_recruta_xp_total OK)
[ ] Proxima aula exibida (get_student_next_lesson OK)
[ ] Avisos institucionais carregados (v_institutional_notices OK)
[ ] Mensagens de instrutor carregadas se existentes (v_instructor_messages OK)
```

### 7.4 Modulos e Aulas

```
[ ] Lista de modulos carrega (vw_recruta_module_progress_v2 OK)
[ ] Progresso percentual exibido por modulo
[ ] Lista de aulas do modulo carrega (vw_rdm_lessons_v2 OK)
[ ] Aulas marcadas como concluidas aparecem com status correto
```

### 7.5 Conclusao de Aula (P0-M6 — critico)

```
[ ] Abrir aula → botao de concluir disponivel
[ ] Clicar em concluir → complete_lesson(auth.uid(), lesson_id) e chamado
[ ] Resposta: {"status":"ok","xp_granted":true,"xp_added":50}
[ ] XP atualizado no painel
[ ] Aula aparece como concluida na lista
[ ] Segunda conclusao da mesma aula: sem duplicacao de XP
[ ] Sem erro 42501 (guarda nao bloqueou chamada legitima)
```

### 7.6 Historico

```
[ ] Tela de historico carrega (v_historico_atividade_recruta_v3 OK)
[ ] Conclusao de aula aparece no historico
```

### 7.7 Medalhas

```
[ ] Tela de medalhas carrega (v_medals_status_v3 OK)
[ ] Status de medalhas reflete conquistas do usuario
```

### 7.8 Ranking

```
[ ] Tela de ranking carrega (v_ranking_mensal_rcc, v_posicao_recruta_mes_rcc OK)
[ ] Posicao do recruta exibida corretamente
[ ] Campeoes mensais exibidos (v_campeoes_mensais_rcc OK)
```

### 7.9 Billing

```
[ ] Status de acesso correto (v_billing_status_recruta_v2 OK)
[ ] Trial ou plano exibido conforme cadastro
[ ] Acesso a conteudo bloqueado/liberado conforme status billing
```

### 7.10 Chat

```
[ ] Lista de conversas carrega (v_chat_conversas_recruta OK)
[ ] Mensagens de conversa carregam (v_chat_mensagens_recruta OK)
[ ] Envio de mensagem funciona (rpc_chat_send_message OK)
[ ] Badge de nao lidas atualiza (v_chat_unread_status OK)
[ ] Marcar como lido funciona (rpc_chat_mark_read OK)
```

### 7.11 Resultado Smoke Test Frontend

| Dominio | Status | Observacoes |
|---------|--------|-------------|
| Auth / Sessao | | |
| Onboarding | | |
| Painel Principal | | |
| Modulos e Aulas | | |
| Conclusao de Aula (P0-M6) | | |
| Historico | | |
| Medalhas | | |
| Ranking | | |
| Billing | | |
| Chat | | |

---

## 8. Criterios de Aprovacao

### APROVADO

Todos os criterios abaixo devem ser atendidos:

```
[ ] M1: Todos os 5 testes (M1-T1 a M1-T5) passaram
[ ] M2: Todos os 7 testes (M2-T1 a M2-T7) passaram
[ ] M4: Testes M4-T1 a M4-T7A passaram
        Pre-condicao de dashboards externos confirmada
[ ] M5: Todos os 8 testes (M5-T1 a M5-T8) passaram
[ ] M6: Testes M6-T1 a M6-T8 passaram (testes por metadados)
        M6-T7A: 3 strings criticas presentes no corpo
[ ] Smoke Test Frontend: todos os 10 dominios com check verde
```

---

### APROVADO COM RESSALVAS

Aprovado se os seguintes testes falharem com justificativa documentada:

| Condicao | Justificativa aceitavel |
|----------|------------------------|
| M4-T7B (teste funcional de spoofing) nao executado | Ambiente de producao sem UUIDs de teste — teste de metadados M4-T7A suficiente |
| M6-T7B (testes funcionais) nao executado | Idem — M6-T7A por metadados confirmou guarda |
| M5-T4 retorna > 38 | Contratos pre-existentes com status 'system' na tabela — verificar e documentar |
| Smoke test de billing com resultado parcial | Plano trial expirado em conta de teste — nao e falha da migration |

---

### REPROVADO

Qualquer um dos criterios abaixo **bloqueia** o pacote:

```
[ ] M1-T1: proconfig IS NULL ou nao contem search_path
[ ] M1-T3: PUBLIC aparece com EXECUTE em buscar_revisoes_whatsapp
[ ] M2-T1: snapshot nao inserido
[ ] M2-T2: contagens incorretas (security_issues != 6, false_positives != 1)
[ ] M4-T1: "Usuário cria XP events" ainda existe
[ ] M4-T2: RLS desabilitado em xp_events
[ ] M4-T3: policies de bloqueio nao foram criadas
[ ] M5-T1: COUNT != 38 (sem justificativa)
[ ] M5-T7: linhas com valores invalidos (violacao de CHECK)
[ ] M6-T1: complete_lesson sem SECURITY DEFINER ou sem search_path
[ ] M6-T3: authenticated NAO tem EXECUTE (GRANT-01 nao corrigido)
[ ] M6-T5: anon TEM EXECUTE (regressao grave de seguranca)
[ ] M6-T7A: qualquer das 3 strings criticas ausente no corpo
[ ] Smoke Test: conclusao de aula retorna erro 42501 para chamada legitima
[ ] Smoke Test: conclusao de aula duplica XP
```

---

## 9. Criterios de Rollback

### P0-M1

**Quando rollbackar:**
- M1-T1 falha (search_path nao aplicado) E o ALTER causou erro no banco
- Comportamento inesperado em producao (revisoes whatsapp parou de funcionar)

**Query indicadora de falha:**
```sql
SELECT proconfig FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'buscar_revisoes_whatsapp';
-- Falha se: proconfig IS NULL
```

**Rollback:**
```sql
ALTER FUNCTION public.buscar_revisoes_whatsapp() RESET search_path;
```

**Arquivo de referencia:** `supabase/baseline/P0_M1_HANDOFF.md` — secao Rollback

---

### P0-M2

**Quando rollbackar:**
- Registro corrompeu tabela `_qd_migration_snapshots` (improvavel — INSERT idempotente)
- Solicitacao institucional de reverter o registro de auditoria

**Query indicadora de falha:**
```sql
SELECT COUNT(*) FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
-- Falha se: COUNT > 1 (duplicata — indica bug no ON CONFLICT)
```

**Rollback:**
```sql
DELETE FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
```

**Arquivo de referencia:** `supabase/baseline/P0_M2_HANDOFF.md` — secao Rollback

---

### P0-M4

**Quando rollbackar:**
- Dashboard externo nao identificado na pre-condicao comeca a falhar com erro RLS
- Funcoes `conceder_xp_*` retornam erro inesperado (nao deve ocorrer — SUPERUSER bypassa RLS)

**Query indicadora de falha:**
```sql
SELECT polname FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'xp_events';
-- Falha se: 0 policies (RLS habilitado mas sem policies = deny-all acidental)
-- Falha se: policy "Usuário cria XP events" ausente MAS as 3 novas tambem ausentes
```

**Rollback:**
```sql
DROP POLICY IF EXISTS "xp_events_insert_block" ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_no_update"    ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_no_delete"    ON public.xp_events;

CREATE POLICY "Usuário cria XP events"
    ON public.xp_events
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);
```

**Arquivo de referencia:** `supabase/baseline/P0_M4_HANDOFF.md` — secao Rollback

---

### P0-M5

**Quando rollbackar:**
- CHECK constraint da tabela `c6_contract_registry` rejeitou algum valor (indicaria bug no arquivo .sql)
- Contratos incorretos foram inseridos (verificar M5-T7)

**Query indicadora de falha:**
```sql
SELECT contract_name, contract_type, status
FROM public.c6_contract_registry
WHERE contract_type NOT IN ('view','materialized_view','rpc')
   OR status NOT IN ('canonical','system','legacy','admin_audit','blocked');
-- Falha se: retorna linhas
```

**Rollback:**
```sql
-- Substitua '<timestamp_da_migration>' pelo valor real registrado em registered_at
DELETE FROM public.c6_contract_registry
WHERE registered_at >= '<timestamp_da_migration>';
```

**Arquivo de referencia:** `supabase/baseline/P0_M5_HANDOFF.md` — secao Rollback

---

### P0-M6

**Quando rollbackar:**
- M6-T7A falha (guarda ausente no corpo — indica CREATE OR REPLACE nao persistiu)
- Smoke Test: conclusao de aula retorna 42501 para chamada legitima (guarda quebrada)
- Smoke Test: conclusao de aula retorna "permission denied" (grant nao aplicado)

**Query indicadora de falha:**
```sql
-- Grant ausente:
SELECT has_function_privilege('authenticated',
    'public.complete_lesson(uuid, uuid, integer)', 'EXECUTE');
-- Falha se: false

-- Guarda ausente:
SELECT pg_get_functiondef(p.oid) LIKE '%IS DISTINCT FROM%' AS guarda_ok
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'complete_lesson';
-- Falha se: false
```

**Rollback:** Ver `supabase/baseline/P0_M6_HANDOFF.md` — secao Rollback (Passos R1 e R2).
O rollback recria a funcao com o corpo original do dump (ln 1182–1246) e revoga o grant de `authenticated`.

**Arquivo de referencia:** `supabase/baseline/P0_M6_HANDOFF.md` — secao Rollback

---

## 10. Relatorio de Execucao

**Preencher apos cada sessao de testes.**

### 10.1 Identificacao da Sessao

| Campo | Valor |
|-------|-------|
| Data de execucao | |
| Ambiente (staging / producao) | |
| Operador responsavel | |
| Aprovador institucional | |
| Project ref Supabase | |
| Versao PostgreSQL (M1-T1) | |
| Role atual (M1-T1) | |

---

### 10.2 Migrations Aplicadas

| Migration | Timestamp apply | Aplicada por | Status |
|-----------|-----------------|--------------|--------|
| P0-M1 (20260516001000) | | | |
| P0-M2 (20260516002000) | | | |
| P0-M3 (20260516003000) | VOID — nao existe | N/A | N/A |
| P0-M4 (20260516004000) | | | |
| P0-M5 (20260516005000) | | | |
| P0-M6 (20260516006000) | | | |

---

### 10.3 Resultados dos Testes

| ID Teste | Descricao | Esperado | Obtido | PASS/FAIL | Observacoes |
|----------|-----------|----------|--------|-----------|-------------|
| M1-T1 | proconfig search_path | {search_path=public,pg_catalog} | | | |
| M1-T2 | unnest proconfig | search_path=public,pg_catalog | | | |
| M1-T3 | grants service_role | EXECUTE apenas | | | |
| M1-T4 | PUBLIC sem EXECUTE | 0 linhas | | | |
| M1-T5 | chamada funcional | sem erro | | | |
| M2-T1 | snapshot inserido | 1 linha | | | |
| M2-T2 | contagens snapshot | 6/1/25/1 | | | |
| M2-T3 | security_issues SEC-01..06 | 6 ids | | | |
| M2-T4 | false_positives FP-01 | 1 linha | | | |
| M2-T5 | complete_lesson no snapshot | 1 linha | | | |
| M2-T6 | idempotencia M2 | 1 linha apos reexec | | | |
| M2-T7 | applied_at preservado | igual | | | |
| M4-T1 | policy antiga removida | 0 linhas | | | |
| M4-T2 | RLS habilitado | true | | | |
| M4-T3 | 3 policies criadas | 3 linhas | | | |
| M4-T4 | WITH CHECK / USING false | false em todas | | | |
| M4-T5 | grants service_role | SELECT/INSERT/... | | | |
| M4-T6 | 7 funcoes conceder_xp | 7 linhas | | | |
| M4-T7A | insert_block with_check=false | false | | | |
| M4-T7B | INSERT bloqueado (opcional) | erro RLS | | | |
| M5-T1 | COUNT canonical | 38 | | | |
| M5-T2 | COUNT por tipo | rpc=13 view=25 | | | |
| M5-T3 | complete_lesson notes | RISCO ATIVO | | | |
| M5-T4 | v_c6_contracts_validos | 38 | | | |
| M5-T5 | v_completed_lessons_count ausente | 0 linhas | | | |
| M5-T6 | contratos criticos | 11 linhas | | | |
| M5-T7 | sem violacao CHECK | 0 linhas | | | |
| M5-T8 | idempotencia M5 | 38 apos reexec | | | |
| M6-T1 | funcao DEFINER search_path | true / {search_path=public} | | | |
| M6-T2 | corpo com 3 strings | todas presentes | | | |
| M6-T3 | authenticated EXECUTE | true | | | |
| M6-T4 | service_role EXECUTE | true | | | |
| M6-T5 | anon sem EXECUTE | false | | | |
| M6-T6 | grants consolidados | auth + svc_role | | | |
| M6-T7A | guarda via pg_get_functiondef | PRESENTE/CORRETO | | | |
| M6-T7B | spoofing bloqueado (opt) | erro 42501 | | | |
| M6-T7B | chamada legitima (opt) | status ok | | | |
| M6-T7B | idempotencia XP (opt) | COUNT=1 | | | |
| M6-T8 | service_role sem JWT | sem erro | | | |
| SMOKE-AUTH | Login / Logout / Sessao | tudo ok | | | |
| SMOKE-ONBOARD | Onboarding completo | tudo ok | | | |
| SMOKE-PAINEL | Painel principal | tudo ok | | | |
| SMOKE-MODULOS | Modulos e Aulas | tudo ok | | | |
| SMOKE-AULA | Conclusao de Aula (P0-M6) | sem erro 42501 | | | |
| SMOKE-HIST | Historico | tudo ok | | | |
| SMOKE-MEDAL | Medalhas | tudo ok | | | |
| SMOKE-RANK | Ranking | tudo ok | | | |
| SMOKE-BILLING | Billing | tudo ok | | | |
| SMOKE-CHAT | Chat | tudo ok | | | |

---

### 10.4 Pre-condicao P0-M4 (preencher antes de aplicar M4)

| Item | Verificado? | Resultado | Verificado por |
|------|-------------|-----------|----------------|
| Metabase — zero INSERT em xp_events | | | |
| Retool — zero INSERT em xp_events | | | |
| Supabase Studio — zero uso ativo | | | |
| Scripts / ETL externos | | | |

**Decisao:** `[ ] P0-M4 pode ser aplicada` / `[ ] P0-M4 BLOQUEADA — consumidor encontrado: _______________`

---

### 10.5 Pre-condicao P0-M6 (preencher antes de aplicar M6)

```sql
SELECT has_function_privilege(
    'authenticated',
    'public.complete_lesson(uuid, uuid, integer)',
    'EXECUTE'
);
```

**Resultado antes do apply:** `[ ] TRUE (grant implicito ja existia)` / `[ ] FALSE (GRANT-01 era bug ativo)`

**Acao de comunicacao necessaria:** `[ ] Nao` / `[ ] Sim — comunicar equipe de produto resolucao de bug`

---

### 10.6 Veredicto Final

| Item | Status |
|------|--------|
| P0-M1 | `[ ] APROVADO` / `[ ] APROVADO COM RESSALVAS` / `[ ] REPROVADO` |
| P0-M2 | `[ ] APROVADO` / `[ ] APROVADO COM RESSALVAS` / `[ ] REPROVADO` |
| P0-M4 | `[ ] APROVADO` / `[ ] APROVADO COM RESSALVAS` / `[ ] REPROVADO` |
| P0-M5 | `[ ] APROVADO` / `[ ] APROVADO COM RESSALVAS` / `[ ] REPROVADO` |
| P0-M6 | `[ ] APROVADO` / `[ ] APROVADO COM RESSALVAS` / `[ ] REPROVADO` |
| Smoke Test Frontend | `[ ] APROVADO` / `[ ] APROVADO COM RESSALVAS` / `[ ] REPROVADO` |
| **PACOTE P0 COMPLETO** | `[ ] APROVADO` / `[ ] APROVADO COM RESSALVAS` / `[ ] REPROVADO` |

---

### 10.7 Observacoes e Acoes Pos-Deploy

```
1.

2.

3.
```

---

### 10.8 Acoes Recomendadas Pos-Aprovacao (nao bloqueantes)

Conforme OBS-01 do PRE_DEPLOY_GATE.md — apos confirmar P0-M6 aplicado com sucesso:

```sql
-- Atualizar nota de complete_lesson no registry para refletir que SEC-03 foi mitigado.
-- Executar SOMENTE apos confirmacao de P0-M6 em producao.

UPDATE public.c6_contract_registry
SET notes      = 'RISCO MITIGADO em P0-M6 (2026-05-16): auth.uid() guard adicionado. GRANT EXECUTE TO authenticated incluido. Risco residual: p_xp externo manipulavel (Sprint 2).',
    updated_at = now()
WHERE contract_name = 'complete_lesson';
```

**Executado:** `[ ] Sim — data: ____________` / `[ ] Adiado para Sprint 2`

---

### 10.9 Assinaturas

| Papel | Nome | Data | Assinatura |
|-------|------|------|------------|
| Operador de testes | | | |
| Aprovador tecnico | | | |
| Responsavel institucional | | | |

---

**Fim do Plano de Testes P0**

*Este documento e gerado automaticamente a partir dos handoffs P0-M1 a P0-M6 e do PRE_DEPLOY_GATE.md.*
*Versao: 1.0 — 2026-05-17*
