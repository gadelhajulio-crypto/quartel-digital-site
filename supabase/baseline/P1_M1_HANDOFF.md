# P1-M1 Handoff — `rpc_complete_lesson`

**Sprint:** 2 / Fase 1
**Migration:** `20260517001000_p1_m1_create_rpc_complete_lesson.sql`
**Status:** FASE 1 CONCLUÍDA — T-01 a T-06 APROVADOS em 2026-05-17
**Próxima etapa:** Fase 1B — execução de T-07 a T-12 (ver `P1_M1_FUNCTIONAL_TESTS.md`)
**Risco:** BAIXO (cria função nova, sem alterar objetos existentes)
**Data:** 2026-05-17

---

## 1. Objetivo

Criar `public.rpc_complete_lesson(p_lesson_id uuid)` — nova RPC server-authoritative que substitui progressivamente `complete_lesson(..., p_xp integer DEFAULT 50)`.

**Problema resolvido:** `complete_lesson` aceita `p_xp` como parâmetro externo, permitindo que o cliente injete qualquer valor de XP. A nova RPC elimina esse vetor: XP é lido exclusivamente de `aulas.xp_valor` no servidor.

**O que NÃO muda nesta migration:**
- `complete_lesson` permanece ativa (coexistência durante Sprint 2)
- Frontend não é alterado (ainda usa `complete_lesson`)
- DDL de `recruta_progresso`, `xp_eventos`, views de ranking/histórico/medalhas: intactos

---

## 2. Escopo da Migration

| Passo | Ação | Objeto |
|-------|------|--------|
| 1 | `CREATE OR REPLACE FUNCTION` | `public.rpc_complete_lesson(uuid)` |
| 2 | `REVOKE ALL FROM PUBLIC` / `GRANT EXECUTE` | `authenticated`, `service_role` |
| 3 | `INSERT ON CONFLICT DO NOTHING` | `public.c6_contract_registry` |

---

## 3. Arquitetura da Função

### Assinatura
```sql
public.rpc_complete_lesson(p_lesson_id uuid) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
```

### Fluxo de execução

```
CALL rpc_complete_lesson(p_lesson_id)
  │
  ├─ GUARDA 1: auth.uid() IS NULL → RAISE 42501 (bloqueio total sem JWT)
  │
  ├─ v_recruta_id := auth.uid()
  │
  ├─ GUARDA 2: recrutas WHERE id = v_recruta_id
  │     NOT FOUND → RAISE 22023 (perfil não criado / onboarding não iniciado)
  │     forca IS NULL → RAISE 22023 (onboarding não concluído)
  │
  ├─ GUARDA 3: aulas WHERE id = p_lesson_id
  │     NOT FOUND → RAISE 22023 (UUID inválido / aula deletada)
  │
  ├─ GUARDA 4: v_xp_valor < 0 → RAISE 22023 (dado corrompido em aulas.xp_valor)
  │
  ├─ Idempotência: recruta_progresso WHERE recruta_id + lesson_id + completed_at IS NOT NULL
  │     já concluída → RETURN {status:ok, xp_granted:false, xp_added:0, message:...}
  │
  ├─ PASSO A: INSERT recruta_progresso ON CONFLICT (recruta_id, lesson_id) DO NOTHING
  │     source = 'rpc_complete_lesson' (rastreabilidade)
  │
  ├─ PASSO B: IF v_xp_valor > 0 THEN
  │     INSERT xp_eventos ON CONFLICT DO NOTHING
  │     (usa ux_xp_eventos_lesson_unique para idempotência em xp)
  │
  └─ RETURN {status:ok, xp_granted:(v_xp_valor > 0), xp_added:v_xp_valor}
```

---

## 4. Guardas Explicadas

### Guarda 1 — Autenticação obrigatória (`ERRCODE 42501`)
`auth.uid()` retorna `NULL` quando chamado sem JWT válido, inclusive em chamadas `service_role` sem impersonation. Diferente de `complete_lesson` (que permitia `service_role` sem JWT), `rpc_complete_lesson` bloqueia qualquer caller sem JWT. Calls administrativos programáticos devem continuar usando `complete_lesson` durante o período de transição.

### Guarda 2 — Recruta existe e tem `forca` (`ERRCODE 22023`)
`forca` é necessária para satisfazer `xp_eventos.forca CHECK (forca = ANY(...))`. Recruta sem `forca` indica onboarding não concluído — a RPC não deve tentar conceder XP neste estado. O operador deve verificar via `rpc_complete_onboarding` antes.

### Guarda 3 — Aula existe (`ERRCODE 22023`)
Previne inserções em `recruta_progresso` com `lesson_id` órfão. Também é o ponto onde `xp_valor` é lido — se a aula não existe, não há fonte de XP.

### Guarda 4 — `xp_valor` não negativo (`ERRCODE 22023`)
`aulas.xp_valor` não tem `CHECK (xp_valor >= 0)` no DDL remoto (ver auditoria `P1_M1_XP_VALOR_AUDIT.md`). Um valor negativo violaria `xp_eventos.quantidade CHECK (quantidade > 0)` e corromperia o ledger. A guarda expõe o problema explicitamente em vez de silenciá-lo.

---

## 5. Tratamento de `xp_valor = 0`

`xp_eventos` tem `CONSTRAINT xp_eventos_quantidade_check CHECK (quantidade > 0)`. Inserir `quantidade = 0` viola a constraint com erro.

**Comportamento adotado:**
- `recruta_progresso`: inserido normalmente — a aula foi concluída.
- `xp_eventos`: **não inserido** — `quantidade = 0` seria inválido.
- Retorno: `{"status":"ok","xp_granted":false,"xp_added":0}` (sem campo `message`).

Este é o comportamento correto para aulas informacionais (sem XP). Distingue-se de "já concluída" pela ausência do campo `message`.

---

## 6. Idempotência

Dois mecanismos independentes garantem idempotência:

| Mecanismo | Protege contra |
|-----------|---------------|
| `SELECT EXISTS` em `recruta_progresso` antes dos INSERTs | Retorno rápido sem DML redundante |
| `ON CONFLICT (recruta_id, lesson_id) DO NOTHING` em `recruta_progresso` | Race condition entre verificação e INSERT |
| `ON CONFLICT DO NOTHING` em `xp_eventos` via `ux_xp_eventos_lesson_unique` | Duplicação de XP em race condition |

O índice `ux_xp_eventos_lesson_unique` é definido como:
```sql
ON public.xp_eventos (recruta_id, referencia_id)
WHERE origem = 'lesson_complete'
```
A nova RPC usa `origem = 'lesson_complete'` (mesmo valor do índice parcial), garantindo que `complete_lesson` e `rpc_complete_lesson` compartilhem a mesma barreira de idempotência de XP.

---

## 7. Grants

| Role | EXECUTE | Justificativa |
|------|---------|---------------|
| `PUBLIC` | REVOGADO | Fecha acesso padrão herdado |
| `authenticated` | CONCEDIDO | Frontend via `supabase.rpc()` com JWT |
| `service_role` | CONCEDIDO | Scripts administrativos com impersonation JWT |
| `anon` | NEGADO | Guarda 1 bloquearia de qualquer forma; grant revogado por defesa em profundidade |

---

## 8. Testes Pós-Apply

Os 12 testes SQL estão embutidos no corpo da migration (linhas 287–387) como comentários executáveis. Resumo:

| # | Tipo | Verifica | Resultado |
|---|------|---------|-----------|
| T-01 | DDL | `prosecdef=true`, `proconfig={search_path=public}`, assinatura correta | **APROVADO** |
| T-02 | DDL | `has_function_privilege('authenticated', ..., 'EXECUTE') = true` | **APROVADO** |
| T-03 | DDL | `has_function_privilege('anon', ..., 'EXECUTE') = false` | **APROVADO** |
| T-04 | DDL | `complete_lesson` ainda existe (1 linha) | **APROVADO** |
| T-05 | DDL | Registry: `rpc_complete_lesson` com `status = 'canonical'` | **APROVADO** |
| T-06 | DDL | Corpo contém as 4 guardas (`LIKE '%...'`) | **APROVADO** |
| T-07 | FASE 1B | Sem JWT → erro `42501` | PENDENTE |
| T-08 | FASE 1B | Fluxo legítimo → `{status:ok, xp_granted:true, xp_added:N}` | PENDENTE |
| T-09 | FASE 1B | Segunda chamada → `{..., xp_granted:false, message:...}` + COUNT xp_eventos = 1 | PENDENTE |
| T-10 | FASE 1B | `xp_valor=0` → `recruta_progresso` inserido, `xp_eventos` COUNT = 0 | PENDENTE |
| T-11 | FASE 1B | UUID inexistente → erro `22023 Lesson not found` | PENDENTE |
| T-12 | FASE 1B | `source = 'rpc_complete_lesson'` em `recruta_progresso` | PENDENTE |

**Status Fase 1 (DDL):** T-01 a T-06 — APROVADOS em 2026-05-17. P1-M1 marcada como `applied`.
**Status Fase 1B (funcional):** T-07 a T-12 — PENDENTE. Ver `supabase/baseline/P1_M1_FUNCTIONAL_TESTS.md`.
**Gate para Fase 2:** T-07 a T-12 devem estar APROVADOS antes de migrar `progressService.ts`.

---

## 9. Rollback

Risco de rollback: **ZERO impacto no usuário final** — frontend ainda chama `complete_lesson`.

```sql
-- Passo 1: remover função
DROP FUNCTION IF EXISTS public.rpc_complete_lesson(uuid);

-- Passo 2: remover do registry
DELETE FROM public.c6_contract_registry
WHERE contract_name = 'rpc_complete_lesson';

-- Verificação:
SELECT proname FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_complete_lesson';
-- Esperado: 0 linhas

SELECT contract_name FROM public.c6_contract_registry
WHERE contract_name = 'rpc_complete_lesson';
-- Esperado: 0 linhas
```

---

## 10. Migração do Frontend (Fase 2 — Sprint 2)

**Arquivo:** `src/services/progressService.ts`

A migração do frontend é uma alteração de uma linha. Aguarda aprovação e execução de T-07 a T-12.

```typescript
// ANTES (complete_lesson — permanece durante Sprint 2)
const { data, error } = await supabase.rpc('complete_lesson', {
    p_recruta_id: userId,
    p_lesson_id: lessonId
});

// DEPOIS (rpc_complete_lesson — Fase 2)
// recruta_id é derivado internamente via auth.uid()
const { data, error } = await supabase.rpc('rpc_complete_lesson', {
    p_lesson_id: lessonId
});
```

**Consequência:** o parâmetro `p_recruta_id` é eliminado do caller. A identidade do recruta passa a ser derivada exclusivamente do JWT. O campo `data` retornará `{status, xp_granted, xp_added}` em vez do formato atual — validar compatibilidade com o consumidor do retorno em `app/(stack)/lesson/[id].tsx`.

---

## 11. Fase 3 — Marcar `complete_lesson` como legacy (Sprint 3)

Após migração total do frontend:

```sql
UPDATE public.c6_contract_registry
SET    status    = 'legacy',
       notes     = notes || ' | Deprecated Sprint 3: use rpc_complete_lesson.',
       updated_at = now()
WHERE  contract_name = 'complete_lesson';
```

DROP de `complete_lesson` é opcional e só deve ocorrer após confirmação de que nenhum caller (frontend, automações, scripts) ainda a referencia.

---

## 12. Referências

| Documento | Caminho |
|-----------|---------|
| Spec arquitetural | `supabase/baseline/P1_M1_COMPLETE_LESSON_XP_REFACTOR.md` |
| Plano de transição | `supabase/baseline/P1_M1_TRANSITION_PLAN.md` |
| Auditoria `xp_valor` | `supabase/baseline/P1_M1_XP_VALOR_AUDIT.md` |
| Migration | `supabase/migrations/20260517001000_p1_m1_create_rpc_complete_lesson.sql` |
| Predecessor P0-M6 | `supabase/migrations/20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql` |
| Schema remoto (`aulas` ln 9075) | `supabase/remote/supabase_remote_schema.sql` |
| Schema remoto (`xp_eventos` ln 10756) | `supabase/remote/supabase_remote_schema.sql` |
| Schema remoto (`ux_xp_eventos_lesson_unique` ln 16464) | `supabase/remote/supabase_remote_schema.sql` |
