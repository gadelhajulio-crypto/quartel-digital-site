# Sprint 3 — Canonical Identity Migration

**Sprint:** 3
**Data:** 2026-05-19
**Objetivo:** Substituir `session.user.id` (auth.uid()) por `recrutas.id` em todas as queries de domínio.

---

## 1. Motivação

Para usuários legados (ex: GADELHA):
- `auth.uid()` = `918c08f3-...` (auth.users.id)
- `recrutas.id` = `cc41fc7e-...` (PK do recruta — diferente)

Queries de domínio que filtram por `auth.uid()` retornam 0 rows silenciosamente,
pois as tabelas canônicas (`recruta_progresso`, `mv_ranking_mensal` etc.) armazenam `recrutas.id`.

`profile.id` (via `useAuth()`) já é `recrutas.id` — populado de `v_identidade_recruta WHERE auth_id = auth.uid()`.
Zero roundtrip adicional necessário.

---

## 2. Inventário Completo

| Arquivo | Linha | Usa | Finalidade | Risco | Sprint 3 |
|---------|-------|-----|-----------|-------|----------|
| `app/(stack)/lesson/[id].tsx` | 15 | `session?.user?.id` → `userId` | `useLessonData(id, userId)` → `.eq('recruta_id', userId)` em `v_lesson_progress_panel` | **ALTO** — `completed_at` sempre null para legados | **MIGRADO** |
| `app/(stack)/lesson/[id].tsx` | 101 | `session?.user?.id` → `userId` | `completeLesson(id, userId)` — param ignorado pelo RPC (usa auth.uid() internamente) | NENHUM — RPC é server-authoritative | **MIGRADO** (param preservado por compat) |
| `src/screens/ModuleLessonsScreen.tsx` | 49 | `session?.user?.id` → `userId` | `.eq('user_id', userId)` em `v_lesson_progress_panel` → lista de aulas concluídas | **ALTO** — `concluidas = []` sempre para legados | **MIGRADO** |
| `app/(tabs)/ranking.tsx` | 16 | `session?.user?.id` → `userId` | `item.user_id === userId` — highlight do usuário no ranking | MÉDIO — ranking desabilitado (stub), prepare para reativação | **MIGRADO** |
| `app/(onboarding)/confirmacao.tsx` | 67 | `session.user.id` | Passado como `_recrutaId` para `saveOnboardingData` — param ignorado (`_` prefix) | NENHUM — RPC usa auth.uid() internamente | TODO Sprint 4 cleanup |
| `src/context/AuthContext.tsx` | 136 | `data.session.user?.id` | Log de debug interno do AuthContext | NENHUM — apenas log | Auth-puro, preservar |
| `src/services/authService.ts` | 23 | `data.user?.id` | Retorno de `userId` no authService | NENHUM — auth puro | Auth-puro, preservar |
| `src/services/progressService.ts` | 54 | `userId: string` | Assinatura de `completeLesson` — param aceito mas ignorado internamente | NENHUM | Auth-server-authoritative, preservar assinatura |
| `src/services/onboardingService.ts` | 32 | `_recrutaId: string` | Assinatura de `saveOnboardingData` — param `_` (ignorado) | NENHUM | Auth-server-authoritative, preservar assinatura |

### Hooks/services sem impacto (não usam userId para domain queries)

| Arquivo | Motivo |
|---------|--------|
| `src/hooks/useRankingList.ts` | Stub — retorna `[]` sem queries |
| `src/hooks/useMonthlyChampion.ts` | Stub — retorna `null` sem queries |
| `src/hooks/useRecruitPanel.ts` | Hook existe mas **não é chamado por nenhuma tela** |
| `src/hooks/useHistory.ts` | Não filtra por userId — usa RLS automaticamente |
| `src/hooks/useModulesProgress.ts` | Sem userId — usa RLS |
| `src/services/eliteService.ts` | Recebe `recrutaId: string` — caller deve passar `profile.id` |
| `src/services/billingService.ts` | Sem userId — usa RLS |

---

## 3. Hook canônico

`src/hooks/useCanonicalIdentity.ts`

```typescript
const { auth_user_id, recruta_id, forca, nome_guerra, isResolved } = useCanonicalIdentity();
```

- `recruta_id` = `profile.id` = `recrutas.id` — usar para todas as queries de domínio
- `auth_user_id` = `session.user.id` = `auth.uid()` — auth puro apenas
- DEV log quando `auth_user_id ≠ recruta_id` (identifica usuários legados)

---

## 4. Consumers migrados nesta sprint

| Consumer | Antes | Depois |
|---------|-------|--------|
| `lesson/[id].tsx` | `session?.user?.id` | `useCanonicalIdentity().recruta_id` |
| `ModuleLessonsScreen.tsx` | `session?.user?.id` | `useCanonicalIdentity().recruta_id` |
| `ranking.tsx` | `session?.user?.id` | `useCanonicalIdentity().recruta_id` |

---

## 5. Issues abertas após Sprint 3

| ID | Prioridade | Descrição | Sprint |
|----|-----------|-----------|--------|
| Fix-04 | Alta | `app/(onboarding)/confirmacao.tsx:67` — substituir `session.user.id` por `profile?.id` (param `_recrutaId` ignorado — sem impacto funcional, mas inconsistente) | Sprint 4 |
| B-06 | Alta | `useRecruitPanel.ts` não é chamado por nenhuma tela — hook morto ou falta integração | Sprint 4 |
| B-07 | Média | `src/services/eliteService.ts` recebe `recrutaId` — verificar se callers passam `profile.id` ou `session.user.id` | Sprint 4 |
