# Sprint 4 — Legacy Cleanup & Canonical Contract Consolidation

**Sprint:** 4
**Data:** 2026-05-19
**Status:** PLANO APROVADO — aguardando execução de Fix-01/Fix-02 antes de P4-M1

---

## 1. Inventário de Legado Restante

### 1.1 Tabela de Auditoria

| Objeto | Tipo | Caller / Local | Risco | Pode remover? |
|--------|------|----------------|-------|---------------|
| `complete_lesson(uuid,uuid,int)` | RPC backend | `progressService.ts:61` (path legado, só quando `USE_LEGACY_COMPLETE_LESSON=true`) | **BAIXO** — desativado por padrão; flag `__DEV__` garante nunca em produção | Sprint 5, após monitoramento 30 dias |
| `USE_LEGACY_COMPLETE_LESSON` flag | Constante DEV | `progressService.ts:8` | **NENHUM** — `false` por padrão, protegido por `__DEV__` | Sprint 5, junto com remoção de `complete_lesson` |
| `lesson_progress` (tabela) | Tabela banco | `v_lesson_progress_panel` **antes** do Fix-02 (ln 13188 dump) | **NENHUM** após Fix-02 — view não lê mais esta tabela | Sprint 5, após verificação de zero dependências |
| `user_id` alias em `v_lesson_progress_panel` | Coluna alias (view) | `ModuleLessonsScreen.tsx:89` — `.eq('user_id', recruta_id)` | **NENHUM** — após Fix-03 (Sprint 3), `recruta_id` é passado corretamente; alias é redundante | Sprint 5, após migrar query para `.eq('recruta_id', ...)` |
| `session.user.id` em `confirmacao.tsx:68` | Auth param | Passado como `_recrutaId` para `saveOnboardingData` | **NENHUM** — param ignorado (prefixo `_`); RPC usa auth.uid() internamente | Sprint 5 (TODO Sprint 4 já anotado) |
| `_userId` param em `startModule` | Param ignorado | `progressService.ts:11` | **NENHUM** — nunca enviado ao banco | Sprint 5, limpeza de assinatura |
| `_userId` param em `completeModule` | Param ignorado | `progressService.ts:23` | **NENHUM** — nunca enviado ao banco | Sprint 5, limpeza de assinatura |
| `userId` param em `completeLesson` | Param compat | `progressService.ts:54`; callers: `lesson/[id].tsx:102` | **NENHUM** — retido por compat mas ignorado internamente | Sprint 5, remover após remoção de `complete_lesson` |
| `source = 'lesson_complete'` em `recruta_progresso` | Dado legado | Registros antigos de `complete_lesson` | **NENHUM** — dados corretos, só source diferente | Não remover; preservar histórico |
| `source = 'lesson_completion'` em `recruta_progresso` | Dado legado | DEFAULT da tabela, pré-RPC | **NENHUM** — dados históricos | Não remover; preservar histórico |

### 1.2 Objetos sem consumers ativos

| Objeto | Evidência | Ação |
|--------|-----------|------|
| `useRecruitPanel.ts` | Nenhuma chamada encontrada em `app/**` | Investigar Sprint 5 — hook morto ou integração pendente |
| `complete_lesson` backend | `progressService` não chama em produção (`USE_LEGACY=false`) | Monitorar 30 dias → remover Sprint 5 |

---

## 2. Contract Registry — Estado Atualizado

### Migration gerada: `20260519001000_p4_m1_contract_registry_legacy_update.sql`

| contract_name | Antes | Depois | Operação |
|---------------|-------|--------|----------|
| `complete_lesson` | `canonical` | `legacy` | UPDATE |
| `rpc_complete_lesson` | `canonical` (notas Sprint 2) | `canonical` (notas + QA 2026-05-19) | UPDATE notas |
| `v_lessons_panel` | não registrado | `canonical` | INSERT |
| `v_lesson_progress_panel` | não registrado | `canonical` | INSERT |

### Queries de verificação pós-apply

```sql
-- Estado geral
SELECT status, COUNT(*) FROM public.c6_contract_registry GROUP BY status;
-- Esperado: canonical >= 40, legacy = 1

-- Detalhe dos objetos alterados
SELECT contract_name, status, LEFT(notes, 80) AS notes_preview, updated_at
FROM public.c6_contract_registry
WHERE contract_name IN (
    'complete_lesson', 'rpc_complete_lesson',
    'v_lessons_panel', 'v_lesson_progress_panel'
)
ORDER BY contract_name;
```

---

## 3. Telemetria de Adoção — Queries SQL

Executar como `service_role` no SQL Editor do Supabase.

### Q-01: Distribuição por source (adoção vs legado)

```sql
-- Qual RPC está sendo usada para registrar conclusões?
SELECT
    source,
    COUNT(*)                  AS total_conclusoes,
    COUNT(DISTINCT recruta_id) AS recrutas_unicos,
    MIN(completed_at)          AS primeira_conclusao,
    MAX(completed_at)          AS ultima_conclusao
FROM public.recruta_progresso
WHERE status = 'completed'
GROUP BY source
ORDER BY total_conclusoes DESC;
-- Esperado após Sprint 2 QA:
--   rpc_complete_lesson | N  | ...  (canônico — novo)
--   lesson_complete     | M  | ...  (de complete_lesson — legado)
--   lesson_completion   | K  | ...  (default antigo — legado)
```

### Q-02: Verificar adoção por recruta (migração completa?)

```sql
-- Recrutas que ainda têm registros APENAS com source legado (sem rpc_complete_lesson)
SELECT
    rp.recruta_id,
    r.nome_guerra,
    COUNT(*) FILTER (WHERE rp.source = 'rpc_complete_lesson') AS via_rpc_novo,
    COUNT(*) FILTER (WHERE rp.source IN ('lesson_complete','lesson_completion')) AS via_legado
FROM public.recruta_progresso rp
LEFT JOIN public.recrutas r ON r.id = rp.recruta_id
WHERE rp.status = 'completed'
GROUP BY rp.recruta_id, r.nome_guerra
HAVING COUNT(*) FILTER (WHERE rp.source = 'rpc_complete_lesson') = 0
ORDER BY via_legado DESC;
-- Esperado: recrutas que completaram aulas apenas pela via legada
-- (ou nenhum, se toda atividade pós-Sprint 2 usou rpc_complete_lesson)
```

### Q-03: Verificar duplicações (mesma aula com sources diferentes)

```sql
-- Existe o mesmo (recruta_id, lesson_id) com sources diferentes?
-- Não deveria ocorrer por causa do UNIQUE(recruta_id, lesson_id) em recruta_progresso
-- Mas confirmar que constraint está íntegra
SELECT
    recruta_id,
    lesson_id,
    COUNT(*)    AS total_rows,
    STRING_AGG(source, ', ' ORDER BY completed_at) AS sources
FROM public.recruta_progresso
WHERE status = 'completed'
GROUP BY recruta_id, lesson_id
HAVING COUNT(*) > 1;
-- Esperado: zero linhas (UNIQUE constraint garante isso)
```

### Q-04: Verificar inconsistências xp_eventos vs recruta_progresso

```sql
-- Conclusões em recruta_progresso sem correspondência em xp_eventos
-- (esperado para xp_valor = 0; suspeito para xp_valor > 0)
SELECT
    rp.recruta_id,
    rp.lesson_id,
    rp.xp_granted,
    rp.source,
    rp.completed_at,
    xe.quantidade AS xp_eventos_quantidade
FROM public.recruta_progresso rp
LEFT JOIN public.xp_eventos xe
    ON  xe.recruta_id    = rp.recruta_id
    AND xe.referencia_id = rp.lesson_id
    AND xe.origem        = 'lesson_complete'
WHERE rp.status = 'completed'
  AND rp.xp_granted > 0
  AND xe.recruta_id IS NULL
ORDER BY rp.completed_at DESC;
-- Esperado: zero linhas (toda conclusão com xp_granted>0 deve ter entrada em xp_eventos)
-- Se não vazio: inconsistência de ledger — investigar antes de Sprint 5
```

### Q-05: Atividade recente de complete_lesson (legada)

```sql
-- Algum authenticated ainda chama complete_lesson diretamente?
-- (verificar nos últimos 7 dias)
SELECT
    rp.recruta_id,
    r.nome_guerra,
    rp.lesson_id,
    rp.completed_at,
    rp.source
FROM public.recruta_progresso rp
LEFT JOIN public.recrutas r ON r.id = rp.recruta_id
WHERE rp.source = 'lesson_complete'
  AND rp.completed_at >= NOW() - INTERVAL '7 days'
ORDER BY rp.completed_at DESC;
-- Se retornar linhas recentes: algum client ainda usa complete_lesson
-- Pré-condição Sprint 5 NÃO satisfeita — não remover ainda
```

### Q-06: Usuários afetados pelo mismatch auth_id vs id (legados)

```sql
-- Recrutas onde auth_id != id (usuários legados como GADELHA)
SELECT
    r.id            AS recruta_id,
    r.auth_id,
    r.nome_guerra,
    r.forca,
    CASE WHEN r.auth_id = r.id THEN 'novo' ELSE 'legado' END AS tipo_usuario
FROM public.recrutas r
ORDER BY tipo_usuario, r.nome_guerra;
-- Esperado: usuários onde auth_id != id precisam de Fix-03 (sprint 3 já aplicado no frontend)
-- Confirmar que rpc_complete_lesson (P1-M1.1) resolve corretamente via recrutas.auth_id
```

### Q-07: Verificar que v_lesson_progress_panel retorna dados corretos

```sql
-- Confirmar que a view retorna dados pós-rpc_complete_lesson (Fix-02)
SELECT
    vlpp.recruta_id,
    r.nome_guerra,
    vlpp.lesson_id,
    a.titulo AS lesson_title,
    vlpp.completed_at,
    vlpp.source
FROM public.v_lesson_progress_panel vlpp
LEFT JOIN public.recrutas r ON r.id = vlpp.recruta_id
LEFT JOIN public.aulas a ON a.id = vlpp.lesson_id
WHERE vlpp.source = 'rpc_complete_lesson'
ORDER BY vlpp.completed_at DESC
LIMIT 10;
-- Esperado: registros com source = 'rpc_complete_lesson' (validação Fix-02 + Sprint 2 QA)
```

---

## 4. Shadow Compatibility Audit

### 4.1 Dependências de `user_id` alias

| Consumer | Coluna usada | Valor passado | Status Fix-03 |
|---------|-------------|---------------|---------------|
| `ModuleLessonsScreen.tsx:89` | `.eq('user_id', recruta_id)` | `profile.id` (recrutas.id) | **CORRETO** — Fix-03 migrou para `recruta_id` |
| `useLessonData.ts:39` | `.eq('recruta_id', userId)` | `profile.id` (recrutas.id) | **CORRETO** — Fix-03 migrou para `recruta_id` |

O alias `user_id` na `v_lesson_progress_panel` ainda é necessário para `ModuleLessonsScreen` que filtra por `.eq('user_id', ...)`. Remover o alias em Sprint 5 requer atualizar `ModuleLessonsScreen` para `.eq('recruta_id', ...)` primeiro.

### 4.2 Dependências diretas de `lesson_progress`

```sql
-- Verificar objetos que referenciam lesson_progress diretamente
SELECT
    dependent.relname     AS dependent_object,
    pg_get_viewdef(dependent.oid, true) AS definition_preview
FROM pg_class dependent
JOIN pg_depend d ON d.objid = dependent.oid
JOIN pg_class source ON source.oid = d.refobjid
WHERE source.relname = 'lesson_progress'
  AND dependent.relkind IN ('v', 'm');
-- Esperado após Fix-02: zero linhas
-- (v_lesson_progress_panel não lê mais lesson_progress)
```

### 4.3 Blockers para Sprint 5

| Blocker | Descrição | Pré-condição |
|---------|-----------|--------------|
| B-S5-01 | `user_id` alias em `v_lesson_progress_panel` | Atualizar `ModuleLessonsScreen.tsx` para `.eq('recruta_id', ...)` |
| B-S5-02 | `userId` param em `completeLesson()` | Remover após `complete_lesson` backend ser dropada |
| B-S5-03 | `_userId` params em `startModule`/`completeModule` | Limpeza de assinatura, zero risco funcional |
| B-S5-04 | `lesson_progress` tabela no banco | Confirmar zero dependências via Q-07 acima |
| B-S5-05 | `USE_LEGACY_COMPLETE_LESSON` flag | Remover junto com `complete_lesson` backend |
| B-S5-06 | `complete_lesson` backend | 30 dias sem chamadas em produção (Q-05 vazio) |

---

## 5. Roadmap de Remoção — Sprint 5

**Pré-condições obrigatórias antes de executar qualquer remoção:**
- [ ] Q-05 (atividade complete_lesson) retorna zero linhas por 30+ dias
- [ ] Q-03 (duplicações) retorna zero linhas
- [ ] Q-04 (inconsistências XP) retorna zero linhas
- [ ] Fix-01 e Fix-02 aplicados e validados em produção

### Sprint 5 — Sequência recomendada

**Fase A — Frontend (sem migration necessária)**
1. `ModuleLessonsScreen.tsx:89` — alterar `.eq('user_id', ...)` para `.eq('recruta_id', ...)`
2. `confirmacao.tsx:68` — substituir `session.user.id` por `profile?.id` (TODO já anotado)
3. Remover `USE_LEGACY_COMPLETE_LESSON` e o bloco `if (__DEV__ && USE_LEGACY_...)` de `progressService.ts`
4. Remover `userId` param de `completeLesson()` e dos callers
5. Remover `_userId` params de `startModule` e `completeModule`

**Fase B — View cleanup (migration)**
```sql
-- Migration: 20260619001000_p5_m1_v_lesson_progress_panel_drop_user_id_alias.sql
-- Remover alias user_id após Fase A
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
-- NÃO executar antes da Fase A — ModuleLessonsScreen ainda usa user_id alias
```

**Fase C — Backend cleanup (migration)**
```sql
-- Migration: 20260619002000_p5_m2_drop_complete_lesson.sql
-- Remover complete_lesson apenas após 30 dias sem chamadas em produção

DROP FUNCTION IF EXISTS public.complete_lesson(uuid, uuid, integer);

UPDATE public.c6_contract_registry
SET status = 'blocked', notes = 'Removida em Sprint 5 (2026-06-19). Substituída por rpc_complete_lesson.', updated_at = now()
WHERE contract_name = 'complete_lesson';
-- NÃO executar antes de Q-05 vazio por 30 dias
```

**Fase D — Tabela legacy (migration)**
```sql
-- Migration: 20260619003000_p5_m3_archive_lesson_progress.sql
-- APENAS após confirmar zero dependências (Q-07 SELECT zero linhas)

-- OPÇÃO CONSERVADORA: renomear em vez de dropar
ALTER TABLE public.lesson_progress RENAME TO _lesson_progress_archived_sprint5;
-- Monitorar 30 dias → se zero reclamações → DROP

-- OPÇÃO DESTRUTIVA (só após 60 dias de renomeação sem issues):
-- DROP TABLE public._lesson_progress_archived_sprint5;
```

---

## 6. QA Checklist

### 6.1 Usuário legado (GADELHA — auth_id ≠ recrutas.id)

- [ ] Login → perfil carrega corretamente (`v_identidade_recruta` retorna `recrutas.id`)
- [ ] Abrir aula QA (`00000000-0000-0000-0000-000000010002`) → tela exibe "MARCAR COMO CONCLUÍDA"
- [ ] Marcar como concluída → RPC `rpc_complete_lesson` chamada → banco registra `recruta_id = cc41fc7e-...`
- [ ] Fechar e reabrir a mesma aula → banner "AULA CONCLUÍDA" exibido, botão ausente
- [ ] `v_lesson_progress_panel` retorna `completed_at` para GADELHA (Query Q-07)
- [ ] XP correto incrementado (Q-04 sem inconsistências)

### 6.2 Usuário novo (auth_id = recrutas.id)

- [ ] Onboarding completo → `recrutas.id = auth.uid()` registrado
- [ ] Conclusão de aula → `rpc_complete_lesson` funciona identicamente
- [ ] `source = 'rpc_complete_lesson'` em `recruta_progresso`

### 6.3 Onboarding

- [ ] Selecionar força → navegar para confirmação
- [ ] Confirmar → `rpc_complete_onboarding` chamado com sucesso
- [ ] `v_onboarding_status` retorna `onboarding_concluido = true`
- [ ] Redirect para Painel

### 6.4 Replay de aula (conclusão repetida — idempotência)

- [ ] Chamar `rpc_complete_lesson` duas vezes com a mesma aula
- [ ] Segunda chamada retorna `{"status":"ok","xp_granted":false,"message":"Aula já concluída anteriormente"}`
- [ ] XP não duplicado (Q-03 e Q-04 limpos)
- [ ] `recruta_progresso` tem exatamente 1 row por `(recruta_id, lesson_id)`

### 6.5 ModuleLessonsScreen — checkmarks

- [ ] Abrir módulo QA → listar aulas
- [ ] Aula já concluída exibe ícone `checkmark-circle`
- [ ] Aula não concluída exibe ícone `play-circle`
- [ ] `loadConcluidas()` retorna IDs corretos via `v_lesson_progress_panel`

### 6.6 Ranking

- [ ] Tela de ranking carrega sem erro (lista vazia — stub ativo)
- [ ] `isCurrentUser` não quebra com `recruta_id` null
- [ ] Quando ranking for reativado: highlight correto para o usuário atual

### 6.7 Histórico e medalhas

- [ ] `v_historico_atividade_recruta_v3` retorna eventos do recruta (RLS automático)
- [ ] Medalhas não bloqueiam nenhuma navegação (RLS + stub)

### 6.8 Offline / Reload

- [ ] Fechar app e reabrir → sessão restaurada → `recruta_id` resolvido corretamente
- [ ] `useLessonData` re-executa query ao montar tela → `completed_at` correto do banco

---

## 7. Plano de Rollback

### R-01: Regressão visual — botão "MARCAR COMO CONCLUÍDA" some mas não deveria

**Causa:** `lesson.completed_at` preenchido incorretamente na view.

**Diagnóstico:**
```sql
SELECT * FROM public.v_lesson_progress_panel
WHERE lesson_id = '<id_da_aula_afetada>';
-- Se retornar linha: dado real. Verificar se completed_at é válido.
-- Se não retornar: view tem problema — executar rollback Fix-02.
```

**Rollback Fix-02** (reverter para `lesson_progress`):
```sql
CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
SELECT user_id, lesson_id, completed_at FROM public.lesson_progress lp;
COMMENT ON VIEW public.v_lesson_progress_panel IS 'ROLLBACK Sprint 4 — restaurado para lesson_progress.';
GRANT ALL ON TABLE public.v_lesson_progress_panel TO service_role;
GRANT SELECT ON TABLE public.v_lesson_progress_panel TO authenticated;
```

### R-02: Perda de progresso — `completed_at` retorna null

**Causa provável A:** Fix-02 não aplicado → view ainda lê `lesson_progress` (sem dados).
- **Fix:** Aplicar Fix-02 em produção.

**Causa provável B:** Fix-03 não ativo → frontend passa `auth.uid()` em vez de `recrutas.id`.
- **Fix:** Confirmar que `useCanonicalIdentity()` está ativo nos consumers. Verificar `profile.id` ≠ null.

**Causa provável C:** `useLessonData` não re-executa após `userId` resolver.
- **Fix:** `setLoading(true)` na função `load()` foi corrigido (Sprint 4 bug fix).

### R-03: XP duplicado

**Diagnóstico:**
```sql
-- Verificar duplicatas em xp_eventos
SELECT recruta_id, referencia_id, COUNT(*) FROM public.xp_eventos
WHERE origem = 'lesson_complete'
GROUP BY recruta_id, referencia_id HAVING COUNT(*) > 1;
```

**Se duplicatas encontradas:** O índice `ux_xp_eventos_lesson_unique` deve prevenir isso. Se violado, investigar se a migration do índice foi aplicada. Não há rollback destrutivo necessário — usar `DELETE` cirúrgico dos registros duplicados mais recentes.

### R-04: Mismatch de identidade — recruta_id errado no banco

**Diagnóstico:**
```sql
SELECT rp.recruta_id, r.auth_id, auth.uid() AS session_uid
FROM public.recruta_progresso rp
JOIN public.recrutas r ON r.id = rp.recruta_id
WHERE rp.source = 'rpc_complete_lesson'
LIMIT 5;
-- Se recruta_id != r.id OU r.auth_id != auth.uid(): resolução incorreta
```

**Rollback:** Reverter `rpc_complete_lesson` para P1-M1 (remover P1-M1.1) usando o rollback documentado em `20260517002000_p1_m1_1_fix_rpc_complete_lesson_auth_id_resolution.sql`.

### R-05: Regressão de contract registry

**Rollback P4-M1** (restaurar estados anteriores):
Ver bloco `-- ROLLBACK` na migration `20260519001000_p4_m1_contract_registry_legacy_update.sql`.

---

## 8. Relatório Arquitetural — Estado Pós-Sprint 4

### 8.1 Contratos canônicos ativos

| Domínio | Contrato | Tipo | Observação |
|---------|---------|------|------------|
| Conclusão de aula | `rpc_complete_lesson(p_lesson_id)` | RPC | **Canônico validado** — auth.uid()→recrutas.id (P1-M1.1) |
| Lista de aulas | `v_lessons_panel` | View | Fix-01: video_url+pdf_url adicionados |
| Progresso de aula | `v_lesson_progress_panel` | View | Fix-02: fonte = recruta_progresso (canônica) |
| Identidade frontend | `useCanonicalIdentity()` | Hook TS | Fix-03: `profile.id` = `recrutas.id` |

### 8.2 Legado em coexistência (não remover ainda)

| Objeto | Status | Remoção |
|--------|--------|---------|
| `complete_lesson` RPC | `legacy` no registry | Sprint 5 (30d monitoramento) |
| `lesson_progress` tabela | Sem consumers ativos | Sprint 5 (rename → drop) |
| `user_id` alias na view | Ainda usado por `ModuleLessonsScreen` | Sprint 5 (após fix frontend) |
| `USE_LEGACY_COMPLETE_LESSON` flag | `false` sempre | Sprint 5 (limpeza) |

### 8.3 Divergências conhecidas (bloqueadas — sem sprint definido)

| ID | Descrição | Blocker |
|----|-----------|---------|
| DIV-01 | `recrutas.xp` vs `recrutas.xp_total` — dois campos paralelos de XP | Decisão institucional sobre campo canônico |
| DIV-02 | `checkModuleAccess()` usa `moduloId !== '1'` hardcoded | Requer schema de módulos de degustação |
| DIV-03 | Dashboard (`index.tsx`) usa `module/1` hardcoded (B-01) | Substituir por UUID do Módulo 0 |
| DIV-04 | `useRecruitPanel.ts` sem callers no app | Investigar integração pendente ou remoção |

### 8.4 Matriz de risco residual

| Risco | Probabilidade | Impacto | Mitigação |
|-------|-------------|---------|-----------|
| `complete_lesson` chamada acidentalmente | MUITO BAIXA | MÉDIO | `USE_LEGACY=false` + `__DEV__` guard |
| XP duplicado por race condition | MUITO BAIXA | ALTO | `ON CONFLICT DO NOTHING` + UNIQUE index |
| `completed_at` null para legados | ELIMINADO | — | Fix-02 + Fix-03 aplicados |
| `lesson_progress` referenciada por código novo | MUITO BAIXA | BAIXO | View não lê mais a tabela |
| Identity mismatch post-sprint3 | MUITO BAIXA | ALTO | `useCanonicalIdentity()` ativo + DEV logs |

---

## 9. Entregáveis desta Sprint

| # | Entregável | Arquivo | Status |
|---|-----------|---------|--------|
| 1 | Migration P4-M1 (registry update) | `supabase/migrations/20260519001000_p4_m1_contract_registry_legacy_update.sql` | AGUARDANDO EXECUÇÃO |
| 2 | Inventário de legado | Seção 1 deste documento | CONCLUÍDO |
| 3 | Telemetria SQL (Q-01 a Q-07) | Seção 3 deste documento | PRONTO PARA EXECUÇÃO |
| 4 | Shadow compatibility audit | Seção 4 deste documento | CONCLUÍDO |
| 5 | Roadmap Sprint 5 | Seção 5 deste documento | PLANEJADO |
| 6 | QA Checklist | Seção 6 deste documento | PRONTO |
| 7 | Plano de rollback | Seção 7 deste documento | CONCLUÍDO |
| 8 | Relatório arquitetural | Seção 8 deste documento | CONCLUÍDO |

---

## 10. Dependências de Execução

```
Fix-01 (20260518001000) ──┐
                           ├──> P4-M1 (20260519001000) ──> Sprint 5 Fase A/B/C/D
Fix-02 (20260518002000) ──┘
```

**P4-M1 não deve ser executada antes de Fix-01 e Fix-02**, pois registra `v_lessons_panel` e `v_lesson_progress_panel` como canonical — um registro incoerente se as fixes ainda não foram aplicadas.
