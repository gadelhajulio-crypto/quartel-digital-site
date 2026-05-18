# P1-M1.1 Handoff — `rpc_complete_lesson` (hotfix auth_id resolution)

**Sprint:** 2 / Fase 1B
**Migration:** `20260517002000_p1_m1_1_fix_rpc_complete_lesson_auth_id_resolution.sql`
**Predecessora:** `20260517001000_p1_m1_create_rpc_complete_lesson.sql`
**Status:** AGUARDANDO APPLY — bloqueia execucao de T-08 a T-12
**Risco:** BAIXO (substitui apenas corpo da funcao, sem breaking change)
**Data:** 2026-05-18

---

## 1. Problema

### Raiz

A versao P1-M1 de `rpc_complete_lesson` resolvia a identidade do recruta com:

```sql
v_recruta_id := auth.uid();
SELECT r.forca INTO v_forca FROM public.recrutas r WHERE r.id = v_recruta_id;
```

Isso pressupoe `recrutas.id = auth.users.id`. A convencao documentada em MEMORY.md
(`id = auth.uid() por convencao institucional`) estava incorreta para usuarios legados.

### Evidencia do schema remoto

```sql
-- recrutas (dump ln 8365-8385):
CREATE TABLE IF NOT EXISTS "public"."recrutas" (
    "id"      uuid DEFAULT gen_random_uuid() NOT NULL,  -- UUID proprio, nao auth.uid()
    "auth_id" uuid NOT NULL,                            -- vinculo com auth.users.id
    ...
    CONSTRAINT "recrutas_auth_id_unique" UNIQUE ("auth_id"),  -- ln 15532
    CONSTRAINT "recrutas_auth_unique"    UNIQUE ("auth_id")   -- ln 15537
);
```

### Achado em producao (teste Fase 1B com GADELHA)

| Campo | Valor |
|-------|-------|
| `auth.users.id` (= `auth.uid()`) | `918c08f3-8e08-4dc7-a102-da5c729a6ead` |
| `recrutas.id` | `cc41fc7e-ce7d-405d-9178-c14b39e1a017` |
| `recrutas.auth_id` | `918c08f3-8e08-4dc7-a102-da5c729a6ead` |

`recrutas.id != auth.uid()` para GADELHA e qualquer usuario criado antes do padrao
`id = auth.uid()`. A Guarda 2 retornava `NOT FOUND` para esses usuarios, bloqueando
completamente a funcao.

### Por que `rpc_complete_onboarding` funcionava

`rpc_complete_onboarding` insere `id = auth.uid()` E `auth_id = auth.uid()` para
novos usuarios via Google OAuth. Para eles, `id == auth_id == auth.uid()` — o bug
nao se manifestaria. GADELHA foi criado por um caminho diferente (id auto-gerado).

---

## 2. Correcao

### Logica anterior (P1-M1 — INCORRETA para usuarios legados)

```sql
v_recruta_id := auth.uid();                          -- assume id = auth.uid()
SELECT r.forca INTO v_forca
FROM   public.recrutas r
WHERE  r.id = v_recruta_id;                          -- falha para id != auth.uid()
```

### Logica corrigida (P1-M1.1)

```sql
SELECT r.id, r.forca
INTO   v_recruta_id, v_forca
FROM   public.recrutas r
WHERE  r.auth_id = auth.uid()                        -- caminho canonico
   OR  r.id      = auth.uid()                        -- fallback defensivo
ORDER BY (r.auth_id = auth.uid()) DESC               -- preferir auth_id match
LIMIT 1;
```

### Justificativas

| Decisao | Justificativa |
|---------|---------------|
| `WHERE r.auth_id = auth.uid()` como caminho primario | `auth_id` e a coluna de vinculo institucional. Views canonicas ja usam este padrao (`v_recruta_ciclo_atual`, etc.) |
| `OR r.id = auth.uid()` como fallback | Cobre usuarios criados via `rpc_complete_onboarding` onde `id = auth_id = auth.uid()` e qualquer padrao legado |
| `ORDER BY (r.auth_id = auth.uid()) DESC` | Se dois registros coincidirem (hipotetico), prioriza o que tem `auth_id` correto |
| `LIMIT 1` | `auth_id` tem UNIQUE constraint — no maximo 1 linha satisfara a condicao primaria. Protege apenas o fallback |
| SELECT unico para `v_recruta_id` e `v_forca` | Elimina o `v_recruta_id := auth.uid()` e o SELECT separado de `v_forca`. Menos round-trips, mais legivel |

---

## 3. O que NAO muda

| Elemento | Status |
|----------|--------|
| Assinatura `rpc_complete_lesson(p_lesson_id uuid)` | IDENTICA |
| `SECURITY DEFINER` | MANTIDO |
| `SET search_path TO 'public'` | MANTIDO |
| Guarda 1 (sem JWT → 42501) | IDENTICA |
| Guarda 2 (NOT FOUND → 22023) | IDENTICA em semantica |
| Guarda 2b (forca IS NULL → 22023) | IDENTICA |
| Guarda 3 (aula nao existe → 22023) | IDENTICA |
| Guarda 4 (xp_valor < 0 → 22023) | IDENTICA |
| Idempotencia (SELECT EXISTS + ON CONFLICT) | IDENTICA |
| PASSO A — INSERT `recruta_progresso` | IDENTICO (v_recruta_id agora correto) |
| PASSO B — INSERT `xp_eventos` | IDENTICO (v_recruta_id e v_forca agora corretos) |
| Retorno JSON `{status, xp_granted, xp_added}` | IDENTICO |
| Grants (authenticated, service_role) | IDENTICOS (reafirmados) |
| `complete_lesson` | NAO REMOVIDA — coexistencia Sprint 2 |
| Frontend (`progressService.ts`) | NAO ALTERADO |
| DDL de `recruta_progresso`, `xp_eventos`, views | SEM MUDANCA |

---

## 4. Impacto nos dados de teste

Apos apply desta migration, as queries de validacao da Fase 1B **devem usar
`recrutas.id` (cc41fc7e...) como recruta_id**, nao `auth.uid()` (918c08f3...).

```sql
-- CORRETO (P1-M1.1): recruta_id = recrutas.id canonico
SELECT * FROM public.recruta_progresso
WHERE recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017'
  AND lesson_id  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';

-- ERRADO (P1-M1 antiga): recruta_id = auth.uid() (nunca existiria no banco)
-- WHERE recruta_id = '918c08f3-8e08-4dc7-a102-da5c729a6ead'
```

O documento `P1_M1_AUTHENTICATED_TEST_EXECUTION.md` deve ser atualizado para
substituir `RECRUTA_ID_TESTE = 0e7b3ac0...` (valor de teste anterior) pelo
ID canonico de GADELHA `cc41fc7e-ce7d-405d-9178-c14b39e1a017`.

---

## 5. Atualizacao necessaria em MEMORY.md

A linha em MEMORY.md:
```
- `recrutas` — perfil gamificado (id = auth.uid(), xp, xp_total, ...)
```

Esta incorreta. Deve ser corrigida para:
```
- `recrutas` — perfil gamificado (id = UUID proprio; auth_id = auth.uid(); xp, xp_total, ...)
```

---

## 6. Testes DDL pos-apply

Executar no SQL Editor como `service_role` (sem JWT):

```sql
-- DDL-01: funcao existe com SECURITY DEFINER?
SELECT p.proname, p.prosecdef, p.proconfig,
       pg_get_function_identity_arguments(p.oid) AS assinatura
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_complete_lesson';
-- Esperado: prosecdef=true, proconfig={search_path=public}

-- DDL-02: grant authenticated?
SELECT has_function_privilege('authenticated','public.rpc_complete_lesson(uuid)','EXECUTE');
-- Esperado: true

-- DDL-03: grant anon revogado?
SELECT has_function_privilege('anon','public.rpc_complete_lesson(uuid)','EXECUTE');
-- Esperado: false

-- DDL-04: corpo contem auth_id resolution e NAO tem assignment direto?
SELECT
    pg_get_functiondef(p.oid) LIKE '%r.auth_id = auth.uid()%' AS tem_auth_id_resolution,
    pg_get_functiondef(p.oid) LIKE '%v_recruta_id := auth.uid()%' AS tem_assignment_direto
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_complete_lesson';
-- Esperado: tem_auth_id_resolution = true, tem_assignment_direto = false

-- DDL-05: complete_lesson ainda existe?
SELECT proname FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'complete_lesson';
-- Esperado: 1 linha

-- DDL-06: registry atualizado?
SELECT contract_name, status, notes FROM public.c6_contract_registry
WHERE contract_name = 'rpc_complete_lesson';
-- Esperado: status='canonical', notes contem 'P1-M1.1'
```

---

## 7. Testes funcionais pos-apply (com JWT de GADELHA)

Selecionar usuario GADELHA no SQL Editor ("Run as user").

### Pre-verificacao obrigatoria

```sql
-- Confirmar que a resolucao de auth_id funciona para GADELHA
SELECT r.id AS recruta_id_canonico, r.auth_id, r.nome_guerra, r.forca
FROM public.recrutas r
WHERE r.auth_id = auth.uid();
-- Esperado: 1 linha
--   recruta_id_canonico = cc41fc7e-ce7d-405d-9178-c14b39e1a017
--   auth_id             = 918c08f3-8e08-4dc7-a102-da5c729a6ead
--   forca               IN ('marinha','exercito','aeronautica')
```

### T-08 — Fluxo legitimo

```sql
SELECT public.rpc_complete_lesson('aff99e81-afd5-46c0-bcc6-c9dda47af687');
-- Esperado: {"status":"ok","xp_granted":true,"xp_added":50}

-- Validacao: recruta_id = cc41fc7e (NAO 918c08f3)
SELECT rp.recruta_id, rp.xp_granted, rp.source
FROM public.recruta_progresso rp
WHERE rp.lesson_id  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
  AND rp.recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017';
-- Esperado: 1 linha, source='rpc_complete_lesson', xp_granted=50
```

### T-09 — Idempotencia

```sql
SELECT public.rpc_complete_lesson('aff99e81-afd5-46c0-bcc6-c9dda47af687');
-- Esperado: {"status":"ok","xp_granted":false,"xp_added":0,"message":"Aula já concluída anteriormente"}

SELECT COUNT(*) FROM public.xp_eventos
WHERE recruta_id    = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017'
  AND referencia_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
  AND origem        = 'lesson_complete';
-- Esperado: 1
```

### T-11 — Aula inexistente (seguro, zero DML)

```sql
SELECT public.rpc_complete_lesson('ffffffff-ffff-ffff-ffff-ffffffffffff');
-- Esperado: ERROR 22023 "Lesson not found: ffffffff-..."
```

### T-12 — Source e recruta_id canonico

```sql
SELECT
    rp.recruta_id,
    rp.source,
    rp.recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017' AS recruta_id_correto,
    rp.recruta_id = '918c08f3-8e08-4dc7-a102-da5c729a6ead' AS recruta_id_errado_auth_uid
FROM public.recruta_progresso rp
WHERE rp.lesson_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';
-- Esperado: recruta_id_correto=true, recruta_id_errado_auth_uid=false, source='rpc_complete_lesson'
-- recruta_id_errado_auth_uid=true indica que P1-M1 (versao antiga) foi usada — BLOQUEANTE
```

---

## 8. Criterio de aprovacao

| Teste | Condicao obrigatoria | Status |
|-------|---------------------|--------|
| DDL-04 | `tem_auth_id_resolution = true` E `tem_assignment_direto = false` | [ ] |
| Pre-verificacao | `recruta_id_canonico = cc41fc7e...` com JWT de GADELHA | [ ] |
| T-08 | Retorna `xp_added=50` E `recruta_id=cc41fc7e...` no banco | [ ] |
| T-09 | COUNT progresso=1, COUNT xp_eventos=1 | [ ] |
| T-11 | ERRO 22023 "Lesson not found" | [ ] |
| T-12 | `recruta_id_correto=true`, `source='rpc_complete_lesson'` | [ ] |

### APROVADO

Todos os criterios obrigatorios satisfeitos:
- Fase 1B retomada a partir de T-08
- Rollback dos dados de teste da tentativa anterior (se houver) antes de reexecutar

### REPROVADO

- DDL-04 mostra `tem_assignment_direto = true`: migration nao foi aplicada ou falhou
- T-08 retorna NOT FOUND apos apply: verificar se `recrutas.auth_id` esta preenchido para GADELHA
- T-12 mostra `recruta_id_errado_auth_uid = true`: dados do teste anterior contaminaram — fazer rollback e reexecutar

---

## 9. Rollback

Reexecutar a migration predecessora para restaurar a versao P1-M1:

```bash
# Via Supabase CLI (se disponivel)
supabase db push supabase/migrations/20260517001000_p1_m1_create_rpc_complete_lesson.sql

# OU via SQL Editor (service_role):
# Copiar o bloco de rollback da Secao ROLLBACK da migration P1-M1.1
```

**Impacto do rollback:** usuarios legados (como GADELHA) voltam a receber
`Guarda 2 NOT FOUND`. Fase 1B continua bloqueada.

---

## 10. Atualizacao do documento de teste

O arquivo `supabase/baseline/P1_M1_AUTHENTICATED_TEST_EXECUTION.md` foi gerado
antes deste achado e usa `RECRUTA_ID_TESTE = 0e7b3ac0...` como placeholders.

**Apos apply desta migration**, atualizar todas as queries de validacao para:

```
RECRUTA_ID_TESTE (para DML/validacao) = cc41fc7e-ce7d-405d-9178-c14b39e1a017
JWT / auth.uid() de GADELHA           = 918c08f3-8e08-4dc7-a102-da5c729a6ead
```

O `SELECT public.rpc_complete_lesson(...)` continua inalterado (sem parametro de recruta_id).

---

## 11. Referencias

| Documento | Caminho |
|-----------|---------|
| Migration P1-M1.1 | `supabase/migrations/20260517002000_p1_m1_1_fix_rpc_complete_lesson_auth_id_resolution.sql` |
| Migration P1-M1 (predecessora) | `supabase/migrations/20260517001000_p1_m1_create_rpc_complete_lesson.sql` |
| Handoff P1-M1 | `supabase/baseline/P1_M1_HANDOFF.md` |
| Testes funcionais | `supabase/baseline/P1_M1_FUNCTIONAL_TESTS.md` |
| Documento de execucao autenticada | `supabase/baseline/P1_M1_AUTHENTICATED_TEST_EXECUTION.md` |
| Schema recrutas (ln 8365) | `supabase/remote/supabase_remote_schema.sql` |
| Constraints auth_id (ln 15532) | `supabase/remote/supabase_remote_schema.sql` |
| rpc_complete_onboarding | `supabase/migrations/20260509001000_fix_rpc_complete_onboarding_upsert.sql` |
