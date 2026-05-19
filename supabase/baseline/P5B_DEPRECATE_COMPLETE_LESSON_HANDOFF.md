# Sprint 5B — Deprecate complete_lesson

**Sprint:** 5B
**Data:** 2026-05-19
**Veredicto:** AGUARDANDO EXECUÇÃO (migration) / CONCLUÍDO (frontend)
**Predecessoras:** P5A → P4-M1 → Fix-01 → Fix-02

---

## 1. Dependency Audit Final

Auditoria executada em 2026-05-19. Escopo: todo o repositório.

| Dependência | Tipo | Caller / Local | Bloqueia remoção? | Status |
|------------|------|----------------|-------------------|--------|
| `progressService.ts:61` | Frontend TS | `.rpc('complete_lesson', ...)` dentro de `__DEV__ && USE_LEGACY_COMPLETE_LESSON` | **SIM** — era o único caller | **REMOVIDO** (Sprint 5B frontend cleanup) |
| `USE_LEGACY_COMPLETE_LESSON` flag | Constante DEV | `progressService.ts:8` | Sim — ativava o caller | **REMOVIDO** (Sprint 5B frontend cleanup) |
| `supabase/functions/chat-central/` | Edge Function | grep: zero matches | Não | Limpo |
| `supabase/functions/chat-ai/` | Edge Function | grep: zero matches | Não | Limpo |
| `supabase/functions/instrutor-send/` | Edge Function | grep: zero matches | Não | Limpo |
| `supabase/functions/stripe-create-checkout-session/` | Edge Function | grep: zero matches | Não | Limpo |
| `20260201221400_audit_c2_fix_progress.sql` | Migration histórica | `CREATE OR REPLACE FUNCTION complete_lesson(uuid,uuid)` — versão OLD sem `p_xp`, já sobrescrita por P0-M6 | Não — DDL histórico, não runtime | Inofensivo |
| `20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql` | Migration histórica | `CREATE OR REPLACE FUNCTION complete_lesson(uuid,uuid,integer)` | Não — DDL histórico | Inofensivo |
| Triggers | SQL | grep migrations: zero referências a `complete_lesson` em TRIGGER | Não | Limpo |
| Views | SQL | grep: zero views chamam `complete_lesson` | Não | Limpo |
| Outras RPCs | SQL | grep: zero funções chamam `complete_lesson` | Não | Limpo |
| Cron jobs | SQL/Infra | zero evidências no codebase | Não | Limpo |
| `supabase_risk_matrix.md` | Documentação | Menções históricas | Não — apenas doc | Inofensivo |
| `supabase_next_migrations_plan.md` | Documentação | Menções históricas | Não — apenas doc | Inofensivo |

**Veredicto de auditoria: SAFE TO DEPRECATE. Zero callers ativos.**

---

## 2. O que foi feito nesta sprint

### 2.1 Frontend (CONCLUÍDO)

`src/services/progressService.ts` — removidos:

```diff
-// ─── P1-M1 Sprint 2 Fase 2 ───────────────────────────────
-// Fallback flag: DEV ONLY. Flip para true para reverter ao complete_lesson
-// sem alterar backend. Nunca ativar em produção — __DEV__ garante isso.
-const USE_LEGACY_COMPLETE_LESSON = false;
-// ──────────────────────────────────────────────────────────

 export const completeLesson = async (lessonId: string, userId: string) => {
-    // userId retido na assinatura para compatibilidade com callers existentes.
-    // Não é mais enviado ao banco — identidade derivada de auth.uid() (P1-M1.1).
-
-    // Rollback rápido em DEV: flip USE_LEGACY_COMPLETE_LESSON = true.
-    if (__DEV__ && USE_LEGACY_COMPLETE_LESSON) {
-        try {
-            const { error } = await supabase.rpc('complete_lesson', {
-                p_recruta_id: userId,
-                p_lesson_id: lessonId,
-            });
-            if (error) throw error;
-        } catch (err) {
-            console.error('[PROGRESS] [LEGACY] Error completing lesson:', err);
-            throw err;
-        }
-        return;
-    }
-
+    // userId retido na assinatura por compatibilidade com callers (lesson/[id].tsx).
+    // Não é enviado ao banco — identidade resolvida por auth.uid() (P1-M1.1).
+    // Sprint 5B: bloco USE_LEGACY_COMPLETE_LESSON removido — complete_lesson depreciada.
     try {
```

**Resultado:** `progressService.ts` não contém nenhuma referência a `complete_lesson`. Zero callers no frontend.

### 2.2 Migration (AGUARDANDO EXECUÇÃO)

`supabase/migrations/20260519003000_p5b_deprecate_complete_lesson.sql`

| Passo | Operação |
|-------|---------|
| 0 | `DO $$ BEGIN IF EXISTS(complete_lesson) THEN RENAME ... END IF $$` — guarda de idempotência |
| 1 | `ALTER FUNCTION complete_lesson RENAME TO __deprecated_complete_lesson` |
| 2 | `COMMENT ON FUNCTION __deprecated_complete_lesson IS 'DEPRECADA Sprint 5B...'` |
| 3 | `UPDATE c6_contract_registry SET status='blocked', notes=...` |

---

## 3. Classificação Final

| Objeto | Classificação | Justificativa |
|--------|--------------|---------------|
| `complete_lesson` RPC | **SAFE TO DEPRECATE** ✓ | Zero callers confirmados. REVOKE aplicado (P5A). Frontend limpo (Sprint 5B). Migration gerada. |
| `__deprecated_complete_lesson` (pós-rename) | **SAFE TO DROP** (Sprint 6) | Aguarda apenas período de observação de 30 dias. |
| `lesson_progress` tabela | **SAFE TO DROP** (Sprint 6) | Zero dependências pós-Fix-02. Aguarda confirmação via Q-07 em produção. |
| `user_id` alias em `v_lesson_progress_panel` | **BLOCKED** | `ModuleLessonsScreen.tsx` ainda usa `.eq('user_id', ...)`. Remover em Sprint 6 após atualizar query. |
| `userId` param em `completeLesson()` | **SAFE TO DROP** (Sprint 6) | Parâmetro nunca enviado ao banco. Remover após limpeza de assinatura em callers. |

---

## 4. Compatibilidade — Verificação de Referências Hardcoded

### Grep completo executado

```bash
# Frontend
grep -r "complete_lesson" src/ app/          → apenas comentário Sprint 5B em progressService.ts
grep -r "complete_lesson" supabase/functions/ → zero matches

# Migrations ativas (runtime)
# Nenhuma migration "ativa" chama complete_lesson em runtime.
# Apenas DDL histórico em 20260201221400 e 20260516006000 (CREATE OR REPLACE) — inofensivo.
```

### Referências residuais documentais (não bloqueantes)

```
supabase_risk_matrix.md       → doc histórico — manter para rastreabilidade
supabase_next_migrations_plan.md → plano antigo — obsoleto
supabase/baseline/*.md        → referências arquivísticas — manter
supabase/migrations/*.sql (comentários) → histórico de decisões — manter
```

Nenhuma das referências documentais acima constitui um "caller" — são apenas texto em documentos.

---

## 5. Telemetria Final

Executar como `service_role` antes e após a migration:

### Q-A: Zero callers recentes (pré-condição)

```sql
-- Confirmar zero atividade recente de complete_lesson
SELECT
    source,
    COUNT(*)           AS total,
    MAX(completed_at)  AS ultima_chamada
FROM public.recruta_progresso
WHERE source = 'lesson_complete'   -- source de complete_lesson
  AND completed_at >= NOW() - INTERVAL '30 days'
GROUP BY source;
-- Esperado: zero linhas (app sem usuários reais)
-- Se retornar linhas: NOT SAFE — investigar antes de prosseguir
```

### Q-B: Confirmar adoção total de rpc_complete_lesson

```sql
SELECT
    source,
    COUNT(*)                   AS total_registros,
    COUNT(DISTINCT recruta_id) AS recrutas,
    MIN(completed_at)          AS desde,
    MAX(completed_at)          AS ate
FROM public.recruta_progresso
WHERE status = 'completed'
GROUP BY source
ORDER BY total_registros DESC;
-- Esperado principal: rpc_complete_lesson com todos os registros recentes
```

### Q-C: Integridade XP (pré-remoção)

```sql
-- Nenhuma conclusão com xp_granted > 0 sem entrada em xp_eventos
SELECT rp.recruta_id, rp.lesson_id, rp.xp_granted, rp.source, rp.completed_at
FROM public.recruta_progresso rp
LEFT JOIN public.xp_eventos xe
    ON  xe.recruta_id    = rp.recruta_id
    AND xe.referencia_id = rp.lesson_id
    AND xe.origem        = 'lesson_complete'
WHERE rp.status = 'completed'
  AND rp.xp_granted > 0
  AND xe.recruta_id IS NULL;
-- Esperado: zero linhas
```

### Q-D: Pós-rename — confirmar PostgREST retorna 404 para complete_lesson

```sql
-- complete_lesson não existe mais no pg_proc
SELECT COUNT(*) FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'complete_lesson';
-- Esperado: 0

-- __deprecated_complete_lesson existe
SELECT proname FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = '__deprecated_complete_lesson';
-- Esperado: 1 linha
```

### Q-E: Erros 42501 nos últimos 7 dias (monitoring pós-deploy)

```sql
-- Se o banco tiver tabela de audit/log de erros, consultar aqui.
-- Alternativa: monitorar logs do Supabase Dashboard → Logs → PostgREST
-- Filtrar por: "complete_lesson" OR "42501"
-- Esperado após P5A: zero (authenticated não tem mais EXECUTE desde P5A)
-- Esperado após P5B: PostgREST retorna 404, não 42501
```

---

## 6. Rollback

### 6.1 Rollback da migration P5B (banco)

```sql
-- PASSO R-01: Restaurar nome original
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = '__deprecated_complete_lesson'
    ) THEN
        EXECUTE 'ALTER FUNCTION public.__deprecated_complete_lesson(uuid, uuid, integer)
                 RENAME TO complete_lesson';
    END IF;
END;
$$;

-- PASSO R-02: Remover COMMENT
COMMENT ON FUNCTION public.complete_lesson(uuid, uuid, integer) IS NULL;

-- PASSO R-03: Registry → legacy
UPDATE public.c6_contract_registry
SET
    status     = 'legacy',
    notes      = 'LEGADO RESTRITO (Sprint 5A). EXECUTE revogado de authenticated. '
              || 'Rollback de P5B aplicado em ' || now()::text || '.',
    updated_at = now()
WHERE contract_name = 'complete_lesson';
```

### 6.2 Rollback do frontend (progressService.ts)

Se necessário restaurar o bloco legado após rollback do banco:

```typescript
// Adicionar no topo do arquivo (após imports):
const USE_LEGACY_COMPLETE_LESSON = false; // Manter false; ativar só em emergência DEV

// Substituir o início de completeLesson:
export const completeLesson = async (lessonId: string, userId: string) => {
    if (__DEV__ && USE_LEGACY_COMPLETE_LESSON) {
        const { error } = await supabase.rpc('complete_lesson', {
            p_recruta_id: userId,
            p_lesson_id: lessonId,
        });
        if (error) throw error;
        return;
    }
    // ... resto do código
};
```

**Nota:** O rollback do frontend só é necessário se o banco precisar voltar a aceitar `complete_lesson` de `authenticated` (exigiria também reverter P5A). Cenário altamente improvável.

---

## 7. Sprint 6 Preview

### 7.1 DROP __deprecated_complete_lesson

**Pré-condições:**
- [ ] 30 dias sem chamadas de `service_role` a `__deprecated_complete_lesson`
- [ ] Q-A limpo (zero `source='lesson_complete'` recente)
- [ ] QA completo em staging confirmando zero impacto

**Migration Sprint 6:**
```sql
-- 20260619001000_p6_drop_deprecated_complete_lesson.sql
DROP FUNCTION IF EXISTS public.__deprecated_complete_lesson(uuid, uuid, integer);
UPDATE public.c6_contract_registry
SET status='blocked',
    notes='DROPADA Sprint 6 (2026-06-19). Auditoria: P5B_DEPRECATE_COMPLETE_LESSON_HANDOFF.md',
    updated_at=now()
WHERE contract_name = 'complete_lesson';
```

### 7.2 DROP lesson_progress

**Pré-condições:**
- [ ] Confirmar zero dependências via Q-D em SPRINT4_LEGACY_CLEANUP_HANDOFF.md §3
- [ ] v_lesson_progress_panel não referencia lesson_progress (pós-Fix-02)
- [ ] Verificar FK constraints: nenhuma outra tabela referencia lesson_progress

**Migration Sprint 6:**
```sql
-- 20260619002000_p6_archive_lesson_progress.sql
-- FASE 1 (Sprint 6): Renomear (conservador)
ALTER TABLE public.lesson_progress RENAME TO _lesson_progress_archived;
-- FASE 2 (Sprint 7, após 30 dias): DROP definitivo
-- DROP TABLE public._lesson_progress_archived;
```

### 7.3 Remover alias `user_id` de v_lesson_progress_panel

**Pré-condição:**
- [ ] Atualizar `ModuleLessonsScreen.tsx:89` de `.eq('user_id', ...)` para `.eq('recruta_id', ...)`

**Migration Sprint 6:**
```sql
-- 20260619003000_p6_v_lesson_progress_drop_user_id_alias.sql
CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
SELECT
    rp.recruta_id,
    rp.lesson_id,
    rp.completed_at,
    rp.xp_granted,
    rp.source
FROM public.recruta_progresso rp
WHERE rp.status = 'completed'
  AND rp.completed_at IS NOT NULL;
GRANT ALL    ON TABLE public.v_lesson_progress_panel TO service_role;
GRANT SELECT ON TABLE public.v_lesson_progress_panel TO authenticated;
```

### 7.4 Limpeza de assinatura no frontend

| Arquivo | Mudança |
|---------|---------|
| `progressService.ts:48` | Remover `userId: string` param de `completeLesson` |
| `lesson/[id].tsx:102` | Remover `recruta_id` da chamada `completeLesson(id, recruta_id)` → `completeLesson(id)` |
| `progressService.ts:17` | Remover `_userId: string` de `startModule` |
| `progressService.ts:23` | Remover `_userId: string` de `completeModule` |

---

## 8. Matriz de Risco

| ID | Risco | Prob. | Impacto | Mitigação |
|----|-------|-------|---------|-----------|
| R-01 | Algum caller não mapeado usa `complete_lesson` | MUITO BAIXA | MÉDIO | Audit completo confirmou zero callers; P5A já bloqueou authenticated |
| R-02 | RENAME quebra referência interna desconhecida | MUITO BAIXA | MÉDIO | grep exhaustivo: zero hits em pg_proc, views, triggers |
| R-03 | Rollback do banco necessário após P5B | BAIXA | BAIXO | Rollback em 2 steps (RENAME + GRANT) < 30 segundos |
| R-04 | `rpc_complete_lesson` afetada por P5B | IMPOSSÍVEL | — | Migration não toca rpc_complete_lesson |
| R-05 | XP duplicado pós-cleanup | MUITO BAIXA | ALTO | ON CONFLICT garante idempotência; Q-C confirma integridade pré-remoção |
| R-06 | Dados históricos em `lesson_progress` perdidos | NENHUM | — | Tabela não é dropada nesta sprint |

---

## 9. Checklist Operacional

### Pre-flight
- [ ] P5A aplicada e testada (T-01 a T-06 passando)
- [ ] Q-A: zero chamadas de `lesson_complete` nos últimos 30 dias
- [ ] Q-C: zero inconsistências de XP
- [ ] Frontend limpo: `grep -r "complete_lesson" src/ app/` retorna zero matches ativos

### Execução migration P5B
- [ ] Executar `20260519003000_p5b_deprecate_complete_lesson.sql` como `service_role`
- [ ] Verificar NOTICE: "P5B: complete_lesson renomeada para __deprecated_complete_lesson"

### Pós-apply obrigatório
- [ ] T-01: `pg_proc` não contém `complete_lesson`
- [ ] T-02: `pg_proc` contém `__deprecated_complete_lesson`
- [ ] T-03: COMMENT aplicado
- [ ] T-04: `authenticated` NÃO tem EXECUTE em `__deprecated_complete_lesson`
- [ ] T-05: `service_role` TEM EXECUTE em `__deprecated_complete_lesson`
- [ ] T-06: registry status = 'blocked'
- [ ] T-07: `rpc_complete_lesson` intocada (authenticated tem EXECUTE)

### Regressão (Expo Go)
- [ ] Abrir aula → "MARCAR COMO CONCLUÍDA" disponível
- [ ] Marcar → sucesso via `rpc_complete_lesson`
- [ ] Reabrir → banner "AULA CONCLUÍDA"
- [ ] Q-B: rpc_complete_lesson tem novos registros

### Monitoramento (30 dias pós-P5B)
- [ ] Q-D verificado semanalmente: zero chamadas a `__deprecated_complete_lesson`
- [ ] Se Q-D limpo após 30 dias → AUTORIZADO Sprint 6 DROP
