# Sprint 5A — Restrict Legacy complete_lesson

**Sprint:** 5A
**Data:** 2026-05-19
**Veredicto:** AGUARDANDO EXECUÇÃO
**Predecessora:** P4-M1 (`20260519001000_p4_m1_contract_registry_legacy_update.sql`)

---

## 1. Objetivo

Formalizar em banco o estado de fato: `complete_lesson` não pode mais ser chamada pelo frontend.

O path legado em `progressService.ts` já está bloqueado por software (`USE_LEGACY_COMPLETE_LESSON = false` + guarda `__DEV__`). Esta migration adiciona uma segunda camada de proteção em nível de banco, tornando qualquer tentativa de chamada de `authenticated` um erro explícito `42501`.

---

## 2. O que muda

| Objeto | Antes | Depois |
|--------|-------|--------|
| `GRANT EXECUTE TO authenticated` | Existia (adicionado em P0-M6) | **Revogado** |
| `GRANT ALL TO service_role` | Existia | Preservado (reafirmado) |
| `c6_contract_registry.notes` | "LEGADO (Sprint 4...)" | "LEGADO RESTRITO (Sprint 5A...)" |

### Estado de grants após migration

```
complete_lesson(uuid, uuid, integer):
  authenticated  →  permission denied  (42501)
  anon           →  permission denied  (42501)
  service_role   →  EXECUTE OK
```

---

## 3. Proteção em camadas

```
Camada 1 — Código (progressService.ts):
  USE_LEGACY_COMPLETE_LESSON = false
  → path legado nunca executado em produção

Camada 2 — Guarda DEV (__DEV__):
  if (__DEV__ && USE_LEGACY_COMPLETE_LESSON)
  → path legado inacessível fora de ambiente de desenvolvimento

Camada 3 — Banco (esta migration):
  REVOKE EXECUTE FROM authenticated
  → mesmo que camadas 1 e 2 falhem, o banco rejeita com 42501
```

---

## 4. Impacto no frontend

**Nenhum.** `progressService.completeLesson()` usa `rpc_complete_lesson` por padrão:

```typescript
// progressService.ts — path normal (sempre ativo)
const { data, error } = await supabase.rpc('rpc_complete_lesson', {
    p_lesson_id: lessonId,
});
// ↑ NÃO afetado por este REVOKE

// progressService.ts — path legado (nunca ativo em produção)
if (__DEV__ && USE_LEGACY_COMPLETE_LESSON) {
    await supabase.rpc('complete_lesson', { ... });
    // ↑ Retornaria 42501 se fosse chamado — comportamento esperado para DEV
}
```

---

## 5. Checklist de execução

### Pre-flight
- [ ] `rpc_complete_lesson` validada e operacional (Sprint 2 QA ✓)
- [ ] `USE_LEGACY_COMPLETE_LESSON = false` em `progressService.ts` (confirmado ✓)
- [ ] `c6_contract_registry` com `complete_lesson` = 'legacy' (P4-M1 aplicada OU aplicar junto)

### Execução
- [ ] Migration aplicada como service_role (SQL Editor ou `supabase db push`)

### Pós-apply — Testes SQL obrigatórios
- [ ] T-01: `has_function_privilege('authenticated', ..., 'EXECUTE') = false`
- [ ] T-02: `has_function_privilege('service_role', ..., 'EXECUTE') = true`
- [ ] T-03: `has_function_privilege('anon', ..., 'EXECUTE') = false`
- [ ] T-04: Função ainda existe (`pg_proc` retorna 1 linha)
- [ ] T-05: Registry atualizado (notes contém 'LEGADO RESTRITO')
- [ ] T-06: `rpc_complete_lesson` intocada (authenticated ainda tem EXECUTE)

### Pós-apply — Teste funcional (Expo Go)
- [ ] Abrir aula no app → botão "MARCAR COMO CONCLUÍDA" disponível
- [ ] Marcar como concluída → RPC `rpc_complete_lesson` chamada com sucesso
- [ ] Nenhum erro 42501 visível no app (confirma que o path canônico não foi afetado)

---

## 6. Rollback

**Quando usar:** Se houver qualquer regressão inesperada após a execução.

```sql
-- Restaurar EXECUTE para authenticated
GRANT EXECUTE ON FUNCTION public.complete_lesson(uuid, uuid, integer) TO authenticated;

-- Reverter notas no registry
UPDATE public.c6_contract_registry
SET
    notes      = 'LEGADO (Sprint 4 — 2026-05-19). Substituída por rpc_complete_lesson.',
    updated_at = now()
WHERE contract_name = 'complete_lesson';
```

**Impacto do rollback:**
- `authenticated` pode chamar `complete_lesson` novamente.
- Frontend **não muda** — permanece usando `rpc_complete_lesson` por padrão.
- O path legado no frontend só é ativado se `USE_LEGACY_COMPLETE_LESSON = true` (DEV manual).

---

## 7. Próximos passos — Sprint 5B

Sprint 5B será o DROP definitivo de `complete_lesson`. Pré-condições:

| # | Pré-condição | Como verificar |
|---|-------------|----------------|
| 1 | Zero chamadas de `service_role` nos últimos 30 dias | Q-05 em SPRINT4_LEGACY_CLEANUP_HANDOFF.md §3 |
| 2 | `USE_LEGACY_COMPLETE_LESSON` removido de `progressService.ts` | grep no codebase |
| 3 | `userId` param removido de `completeLesson()` | grep no codebase |
| 4 | Nenhuma referência a `complete_lesson` em migrations ou código ativo | grep no repositório |

Sprint 5B migration (não executar agora):
```sql
-- 20260619001000_p5b_drop_complete_lesson.sql
DROP FUNCTION IF EXISTS public.complete_lesson(uuid, uuid, integer);

UPDATE public.c6_contract_registry
SET status = 'blocked',
    notes  = 'Dropada em Sprint 5B (2026-06-19). Substituída por rpc_complete_lesson.',
    updated_at = now()
WHERE contract_name = 'complete_lesson';
```

---

## 8. Independência de outras migrations

Esta migration é **independente** de Fix-01 e Fix-02:
- Não altera views.
- Não altera tabelas.
- Apenas revoga um GRANT.
- Pode ser executada em qualquer ordem relativa a Fix-01, Fix-02 e P4-M1.

Ordem recomendada para deploy único:
```
Fix-01 → Fix-02 → P4-M1 → P5A
```
