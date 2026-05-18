# P1-M1 Transition Plan — XP Refactor (complete_lesson → rpc_complete_lesson)
**Status:** FASE 2 CONCLUÍDA — frontend migrado para rpc_complete_lesson
**Data:** 2026-05-17
**Atualizado:** 2026-05-18
**Classificacao:** P1 — Transicao de Contrato
**Sprint alvo:** Sprint 2
**Spec de referencia:** `supabase/baseline/P1_M1_COMPLETE_LESSON_XP_REFACTOR.md`

---

## Sumario

Este documento descreve o plano de transicao em 4 fases para migrar de
`complete_lesson` (XP hardcoded, p_recruta_id externo) para `rpc_complete_lesson`
(XP institucional de `aulas.xp_valor`, auth.uid() como unica fonte de recruta).

**Principio:** Zero downtime. Zero breaking change para usuarios finais.
O frontend pode migrar em paralelo com o backend.

---

## Estado Atual vs. Estado Alvo

### Estado Atual (pos P0-M6)

```
Frontend (LessonScreen)
  └─ completeLesson(lessonId, userId)     [app/(stack)/lesson/[id].tsx:101]
       └─ supabase.rpc('complete_lesson', {
              p_recruta_id: userId,        ← auth.uid() validado pela guarda P0-M6
              p_lesson_id: lessonId
          })
            └─ INSERT xp_eventos(quantidade = 50)  ← constante, nao institucional
```

**Problemas:**
- XP = 50 para todas as aulas (constante hardcoded)
- `p_xp` ainda e parametro publico na assinatura (risco residual RR-01)
- `aulas.xp_valor` existe no banco mas e ignorado

### Estado Alvo (pos P1-M1)

```
Frontend (LessonScreen)
  └─ completeLesson(lessonId, userId)     [sem mudanca na tela]
       └─ supabase.rpc('rpc_complete_lesson', {
              p_lesson_id: lessonId       ← apenas o necessario
          })
            └─ SELECT xp_valor FROM aulas  ← XP institucional
                 └─ INSERT xp_eventos(quantidade = aulas.xp_valor)
```

**Melhorias:**
- XP derivado de `aulas.xp_valor` (fonte institucional)
- Nenhum parametro de XP exposto publicamente
- Assinatura minima: apenas `p_lesson_id`
- `auth.uid()` e unica fonte do recruta
- Frontend: mudanca de 1 linha em `progressService.ts`

---

## Fase 0 — Pre-condicao: Auditoria de aulas.xp_valor

**Quando:** Antes de criar `rpc_complete_lesson`
**Quem executa:** DBA / operador com service_role
**Objetivo:** Garantir que `aulas.xp_valor` esta populado para aulas ativas

### F0.1 — Verificar distribuicao atual de xp_valor

```sql
-- Executar no Supabase SQL Editor como service_role
SELECT
    COUNT(*)                                    AS total_aulas,
    COUNT(*) FILTER (WHERE xp_valor = 0)        AS aulas_xp_zero,
    COUNT(*) FILTER (WHERE xp_valor > 0)        AS aulas_com_xp,
    MIN(xp_valor) FILTER (WHERE xp_valor > 0)   AS xp_minimo,
    MAX(xp_valor)                               AS xp_maximo,
    ROUND(AVG(xp_valor) FILTER (WHERE xp_valor > 0), 1) AS xp_medio
FROM public.aulas;
```

**Criterio de bloqueio:** Se `aulas_xp_zero / total_aulas > 0.80` (mais de 80% com xp=0),
a Fase 2 deve aguardar populacao dos dados.

### F0.2 — Listar aulas com xp_valor = 0

```sql
SELECT
    a.id,
    a.titulo,
    a.xp_valor,
    m.titulo AS modulo,
    a.ordem
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id
WHERE a.xp_valor = 0
ORDER BY m.titulo, a.ordem;
```

### F0.3 — Decisao sobre aulas com xp_valor = 0

| Opcao | SQL (NAO executar sem aprovacao) | Risco |
|-------|-----------------------------------|-------|
| A: Manter 0 (aula sem XP, comportamento explicito) | Nenhum — sem mudanca | Usuarios que concluirem nao ganham XP |
| B: Atualizar todas para 50 (valor legado) | `UPDATE aulas SET xp_valor = 50 WHERE xp_valor = 0` | Retrocompatibildade com valor anterior |
| C: Atualizar individualmente por aula | UPDATE seletivo por equipe de produto | Maior precisao |

**Recomendacao:** Opcao C — equipe de produto define XP por aula conforme curriculo.
Se nao houver bandwidth, Opcao B e aceitavel como transicao com valor legacy 50.

### F0.4 — Checklist de aprovacao da Fase 0

```
[ ] Distribuicao de xp_valor verificada (F0.1)
[ ] Lista de aulas xp_valor=0 revisada (F0.2)
[ ] Decisao sobre aulas xp_valor=0 documentada
[ ] Se necessario: aulas atualizadas para xp_valor > 0
[ ] Confirmado: pelo menos 80% das aulas com xp_valor > 0
[ ] Aprovado por: ___________________________
[ ] Data: ___________________________________
```

---

## Fase 1 — Criar rpc_complete_lesson no banco — CONCLUÍDA

**Status:** CONCLUÍDA — 2026-05-17. T-01 a T-06 APROVADOS. Migration aplicada.
**Quando:** Apos Fase 0 aprovada
**Tipo de mudanca:** Additive — nova funcao, nada removido
**Breaking change:** NENHUM — `complete_lesson` continua funcionando
**Downtime:** ZERO

### F1.1 — O que a migration deve fazer

```
[CREATE] public.rpc_complete_lesson(p_lesson_id uuid)
   - SECURITY DEFINER
   - SET search_path TO 'public'
   - Guarda: IF auth.uid() IS NULL THEN RAISE EXCEPTION 42501
   - v_recruta_id := auth.uid()
   - SELECT xp_valor FROM aulas WHERE id = p_lesson_id
   - IF NOT FOUND: RAISE EXCEPTION 22023
   - Verificar idempotencia (recruta_progresso)
   - INSERT INTO recruta_progresso (source = 'rpc_complete_lesson')
   - INSERT INTO xp_eventos (quantidade = xp_valor)
   - RETURN json

[GRANT] EXECUTE TO authenticated
[REVOKE] FROM PUBLIC

[INSERT] c6_contract_registry: rpc_complete_lesson como 'canonical'
```

**Arquivo de migration:** `supabase/migrations/2026????000000_p1_m1_create_rpc_complete_lesson.sql`
(timestamp a definir no momento de criacao)

### F1.2 — Nenhuma mudanca no frontend ainda

O frontend continua chamando `complete_lesson`. A nova funcao existe mas nao e usada.

### F1.3 — Testes pos-Fase 1

```sql
-- T1: Nova funcao existe
SELECT proname, prosecdef, proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'rpc_complete_lesson';
-- Esperado: 1 linha, prosecdef=true, proconfig={search_path=public}

-- T2: Grant para authenticated
SELECT has_function_privilege(
    'authenticated',
    'public.rpc_complete_lesson(uuid)',
    'EXECUTE'
);
-- Esperado: true

-- T3: anon nao tem EXECUTE
SELECT has_function_privilege(
    'anon',
    'public.rpc_complete_lesson(uuid)',
    'EXECUTE'
);
-- Esperado: false

-- T4: complete_lesson continua funcionando
SELECT proname FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'complete_lesson';
-- Esperado: 1 linha (nao foi removida)

-- T5: Registry atualizado
SELECT contract_name, contract_type, status
FROM public.c6_contract_registry
WHERE contract_name = 'rpc_complete_lesson';
-- Esperado: 1 linha, status = 'canonical'
```

### F1.4 — Rollback da Fase 1

```sql
-- Se a migration precisar ser revertida (APENAS SE necessario):
DROP FUNCTION IF EXISTS public.rpc_complete_lesson(uuid);
DELETE FROM public.c6_contract_registry WHERE contract_name = 'rpc_complete_lesson';
```

Sem impacto no frontend — nada muda para o usuario.

---

## Fase 1B — Testes Funcionais (T-07 a T-12) — CONCLUÍDA

**Status:** APROVADA em 2026-05-18. T-07 a T-12 APROVADOS.
**Documento:** `supabase/baseline/P1_M1_FUNCTIONAL_TESTS.md`
**Gate:** desbloqueou Fase 2.

---

## Fase 2 — Migrar frontend para rpc_complete_lesson — CONCLUÍDA

**Status:** CONCLUÍDA em 2026-05-18.
**Arquivo alterado:** `src/services/progressService.ts`
**Quando:** Apos Fase 1B (T-07 a T-12) aprovada
**Tipo de mudanca:** Frontend — progressService.ts
**Breaking change:** NENHUM para o usuario final
**Downtime:** ZERO

### F2.1 — Mudanca em progressService.ts

**Arquivo:** `src/services/progressService.ts`

**Antes:**
```typescript
export const completeLesson = async (lessonId: string, userId: string) => {
    try {
        const { error } = await supabase.rpc('complete_lesson', {
            p_recruta_id: userId,
            p_lesson_id: lessonId
        });
        if (error) throw error;
    } catch (err) {
        console.error('[PROGRESS] Error completing lesson:', err);
        throw err;
    }
};
```

**Depois (mudanca minima — 1 linha de RPC e 1 parametro removido):**
```typescript
export const completeLesson = async (lessonId: string, userId: string) => {
    try {
        const { error } = await supabase.rpc('rpc_complete_lesson', {
            p_lesson_id: lessonId
            // p_recruta_id removido: derivado de auth.uid() no banco
            // userId mantido na assinatura para retrocompatibilidade futura
        });
        if (error) throw error;
    } catch (err) {
        console.error('[PROGRESS] Error completing lesson:', err);
        throw err;
    }
};
```

**Nota:** O parametro `userId` pode ser mantido na assinatura de `completeLesson` por ora
para nao exigir mudancas na tela (`[id].tsx`). Ele simplesmente nao e mais enviado ao banco.

### F2.2 — Nenhuma mudanca na tela

`app/(stack)/lesson/[id].tsx` continua chamando:
```typescript
await completeLesson(String(id), userId);
```
Sem mudancas na UI.

### F2.3 — Testes pos-Fase 2

**Smoke test manual:**

```
[ ] Abrir app no dispositivo/simulador
[ ] Login com usuario valido
[ ] Navegar ate uma aula nao concluida
[ ] Clicar em "MARCAR AULA COMO CONCLUIDA"
[ ] Sem erro 42501 (autenticacao funciona)
[ ] Sem erro "function not found"
[ ] Router.back() executado (retorno para lista)
[ ] XP atualizado no painel (v_recruta_xp_total)
[ ] Aula aparece como concluida na lista (recruta_progresso)
```

**Verificacao de banco (executar apos conclusao de aula teste):**

```sql
-- Verificar que o registro usa a nova funcao (source = 'rpc_complete_lesson')
SELECT
    recruta_id,
    lesson_id,
    status,
    xp_granted,
    source,
    completed_at
FROM public.recruta_progresso
WHERE source = 'rpc_complete_lesson'
ORDER BY completed_at DESC
LIMIT 5;
-- Esperado: linhas com source = 'rpc_complete_lesson'

-- Verificar que xp_granted reflete aulas.xp_valor
SELECT
    rp.recruta_id,
    rp.lesson_id,
    rp.xp_granted AS xp_registrado,
    a.xp_valor    AS xp_da_aula
FROM public.recruta_progresso rp
JOIN public.aulas a ON a.id = rp.lesson_id
WHERE rp.source = 'rpc_complete_lesson'
  AND rp.xp_granted != a.xp_valor;
-- Esperado: zero linhas (xp_granted sempre = xp_valor da aula)

-- Verificar idempotencia
SELECT COUNT(*) AS registros_em_xp_eventos
FROM public.xp_eventos
WHERE recruta_id    = '<uuid_recruta_teste>'
  AND referencia_id = '<uuid_aula_teste>'
  AND origem        = 'lesson_complete';
-- Esperado: 1 (nao importa quantas vezes completou)
```

### F2.4 — Rollback da Fase 2

Trivial — reverter `progressService.ts` para `complete_lesson`:

```typescript
// Reverter em progressService.ts:
const { error } = await supabase.rpc('complete_lesson', {
    p_recruta_id: userId,
    p_lesson_id: lessonId
});
```

`complete_lesson` continua no banco — rollback instantaneo sem downtime.

---

## Fase 3 — Deprecar complete_lesson

**Quando:** Sprint 3+ — apos Fase 2 estavel em producao por pelo menos 2 semanas
**Tipo de mudanca:** Backend — marcar funcao como deprecated no registry
**Breaking change:** NENHUM — funcao ainda existe
**Downtime:** ZERO

### F3.1 — Atualizar c6_contract_registry

```sql
-- Executar como service_role (NAO migration formal — pode ser UPDATE manual)
UPDATE public.c6_contract_registry
SET status     = 'legacy',
    notes      = 'DEPRECATED: substituida por rpc_complete_lesson (P1-M1). Frontend migrado em Sprint 2. Remover apos confirmacao de zero callers.',
    updated_at = now()
WHERE contract_name = 'complete_lesson';
```

### F3.2 — Verificar zero callers

```sql
-- Verificar que nenhum registro recente usa 'lesson_complete' via funcao antiga
SELECT
    source,
    COUNT(*)     AS total,
    MAX(completed_at) AS ultima_conclusao
FROM public.recruta_progresso
WHERE source IN ('lesson_complete', 'rpc_complete_lesson')
GROUP BY source
ORDER BY ultima_conclusao DESC;
-- Esperado: 'lesson_complete' com ultima_conclusao antiga (pre-migracao)
--          'rpc_complete_lesson' com registros recentes
```

### F3.3 — Monitoramento pre-remocao

Aguardar pelo menos:
- 2 semanas sem novos registros com `source = 'lesson_complete'` em producao
- Zero chamadas a `complete_lesson` em logs do PostgREST (se monitoramento disponivel)

---

## Fase 4 — Remover complete_lesson (opcional, Sprint 3+)

**Quando:** Apenas apos confirmacao de zero callers em producao
**Tipo de mudanca:** DROP FUNCTION — irreversivel sem rollback manual
**Decisao:** OPCIONAL — manter a funcao com acesso service_role only e aceitavel como alternativa

### F4.1 — Pre-condicao obrigatoria

```
[ ] Fase 3 concluida (registry marcado como legacy)
[ ] Zero registros com source='lesson_complete' nas ultimas 4 semanas
[ ] Zero Edge Functions usando complete_lesson
[ ] Zero scripts externos usando complete_lesson
[ ] Aprovacao institucional formal
```

### F4.2 — O que fazer se decidir manter (recomendado para Sprint 3)

Ao inves de remover, restringir acesso ao minimo necessario:

```sql
-- Manter apenas service_role (para seeds, migrations de dados, etc.)
REVOKE EXECUTE ON FUNCTION public.complete_lesson(uuid, uuid, integer) FROM authenticated;
-- service_role mantem (ja tinha antes)
```

Isso remove o risco residual de XP manipulavel via frontend sem destruir a funcao.

### F4.3 — Se decidir remover

```sql
-- AVISO: IRREVERSIVEL. Exige rollback manual completo se algo falhar.
-- Executar somente em manutencao planejada.
DROP FUNCTION IF EXISTS public.complete_lesson(uuid, uuid, integer);
DELETE FROM public.c6_contract_registry WHERE contract_name = 'complete_lesson';
```

---

## Mapa Visual das Fases

```
Estado Inicial (pos P0-M6)
├─ complete_lesson (assinatura 3 params, DEFAULT 50)
│    └─ progressService.ts → complete_lesson
│
Fase 0 ─ Auditoria de aulas.xp_valor (DBA)
│
Fase 1 ─ CREATE rpc_complete_lesson (migration banco)
├─ complete_lesson (ATIVO, sem mudanca)
├─ rpc_complete_lesson (NOVO, nao usado pelo frontend ainda)
│    └─ progressService.ts → complete_lesson (sem mudanca)
│
Fase 2 ─ Migrar frontend (PR de 1 linha)
├─ complete_lesson (ATIVO, sem callers do app)
├─ rpc_complete_lesson (ATIVO, callers do app)
│    └─ progressService.ts → rpc_complete_lesson ← MUDANCA
│
Fase 3 ─ Deprecar no registry (UPDATE)
├─ complete_lesson (LEGACY no registry, sem callers do app)
│
Fase 4 ─ Restricao ou Remocao (Sprint 3+)
└─ complete_lesson (service_role only ou removida)
    rpc_complete_lesson (CANONICAL)
         └─ progressService.ts → rpc_complete_lesson
```

---

## Impacto por Arquivo

### Backend

| Arquivo | Fase | Tipo de mudanca |
|---------|------|-----------------|
| Nova migration p1_m1_create_rpc_complete_lesson.sql | F1 | CREATE FUNCTION + GRANT + INSERT registry |
| (Opcional) UPDATE c6_contract_registry | F3 | UPDATE notas de complete_lesson |
| (Opcional) DROP FUNCTION | F4 | Remocao definitiva |

### Frontend

| Arquivo | Fase | Tipo de mudanca |
|---------|------|-----------------|
| `src/services/progressService.ts` | F2 | 1 linha: `'complete_lesson'` → `'rpc_complete_lesson'`, remover `p_recruta_id` |
| `app/(stack)/lesson/[id].tsx` | Nenhuma | Sem mudanca necessaria |
| `src/hooks/useLessonData.ts` | Nenhuma | Sem mudanca necessaria |

### Tipos TypeScript (se necessario)

O tipo `Lesson` em `src/types/lesson.ts` nao precisa de mudanca — `xp_valor` nao e
exposto pelo frontend. Se no futuro a tela exibir "+XP" para o usuario, o campo `xp_valor`
deve ser adicionado a `v_lessons_panel` e ao tipo `Lesson`.

---

## Criterios de Aprovacao por Fase

### Fase 0
```
[ ] aulas.xp_valor populado: >= 80% das aulas com xp_valor > 0
[ ] Decisao sobre xp_valor=0 documentada
```

### Fase 1 — CONCLUÍDA em 2026-05-17
```
[x] rpc_complete_lesson existe no banco
[x] SECURITY DEFINER ativo
[x] search_path = {public}
[x] authenticated tem EXECUTE
[x] anon nao tem EXECUTE
[x] complete_lesson ainda existe (nao removida)
[x] c6_contract_registry contem rpc_complete_lesson com status=canonical
```

### Fase 2
```
[ ] progressService.ts atualizado para rpc_complete_lesson
[ ] Smoke test completo: login, abrir aula, concluir, XP atualizado
[ ] Sem erro 42501 para chamada legitima
[ ] Sem erro "function not found"
[ ] Registros novos em recruta_progresso com source='rpc_complete_lesson'
[ ] xp_granted = aulas.xp_valor para cada conclusao
[ ] Idempotencia: segunda conclusao nao duplica XP
```

### Fase 3
```
[ ] 2+ semanas sem source='lesson_complete' novos em producao
[ ] c6_contract_registry: complete_lesson marcada como 'legacy'
```

### Fase 4 (se aplicavel)
```
[ ] 4+ semanas sem qualquer uso de complete_lesson
[ ] Aprovacao institucional formal documentada
[ ] DROP executado com sucesso
```

---

## Rollback por Fase

| Fase | Rollback | Impacto para usuario |
|------|----------|---------------------|
| Fase 0 | Nenhuma mudanca revertida | Zero |
| Fase 1 | `DROP FUNCTION rpc_complete_lesson` | Zero — frontend ainda usa complete_lesson |
| Fase 2 | Reverter progressService.ts para complete_lesson | Zero — complete_lesson ainda no banco |
| Fase 3 | UPDATE registry: status='canonical' | Zero — apenas metadados |
| Fase 4 | Nao ha rollback automatico — requer CREATE manual | Potencial impacto se service_role usar |

---

## Checklist de Planejamento de Sprint 2

```
[x] Fase 0 concluida antes do inicio do Sprint 2
[x] Migration P1-M1 (rpc_complete_lesson) incluida no sprint backlog
[x] Migration aplicada — 20260517001000_p1_m1_create_rpc_complete_lesson.sql
[x] T-01 a T-06 (DDL validation) aprovados em 2026-05-17
[x] T-07 a T-12 (testes funcionais Fase 1B) — APROVADOS em 2026-05-18
[x] progressService.ts migrado para rpc_complete_lesson — 2026-05-18
[ ] Smoke test em device/simulador pos-migracao
[ ] Monitoramento 24h: source='rpc_complete_lesson' dominante em recruta_progresso
[ ] Revisao de aulas.xp_valor com equipe de produto agendada
```

---

## Referencias

| Documento | Localizacao |
|-----------|-------------|
| Spec arquitetural completa | `supabase/baseline/P1_M1_COMPLETE_LESSON_XP_REFACTOR.md` |
| P0-M6 Handoff (predecessor) | `supabase/baseline/P0_M6_HANDOFF.md` |
| Caller frontend | `src/services/progressService.ts:48` |
| Tela de aula | `app/(stack)/lesson/[id].tsx` |
| Hook de dados | `src/hooks/useLessonData.ts` |
| aulas DDL | `supabase/remote/supabase_remote_schema.sql` ln 9075 |
| fn_conceder_xp_aula (referencia) | `supabase/remote/supabase_remote_schema.sql` ln 2854 |
| Contract Registry | `supabase/migrations/20260516005000_p0_m5_register_contract_registry.sql` |
| Risk Matrix (RR-01) | `supabase/baseline/PRE_DEPLOY_GATE.md §RR-01` |

---

**Status:** FASE 2 CONCLUÍDA — complete_lesson = LEGACY/FALLBACK — Fase 3 em Sprint 3+
