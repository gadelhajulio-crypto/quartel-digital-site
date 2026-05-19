# Fix-01 e Fix-02 — Handoff de Views Canônicas

**Sprint:** 2 / Pós-QA
**Data:** 2026-05-18
**Veredicto:** AGUARDANDO EXECUÇÃO
**Pré-requisito:** `rpc_complete_lesson` validada e operacional (Sprint 2 Fase 2 — concluída)

---

## 1. Contexto e motivação

A auditoria do fluxo de aulas (`LESSON_CONTENT_CREATION_PLAN.md`) identificou dois bugs estruturais nas views canônicas que impedem a exibição correta de conteúdo e de estado de conclusão:

| Bug | View afetada | Problema | Impacto no app |
|-----|-------------|---------|----------------|
| B-02 | `v_lessons_panel` | `video_url`/`pdf_url` ausentes da view | Tela de aula sempre exibe placeholder — vídeo/PDF nunca renderizados |
| B-03+B-04 | `v_lesson_progress_panel` | Lê tabela legada `lesson_progress`; coluna `user_id` em vez de `recruta_id` | `completed_at` sempre null — botão "MARCAR COMO CONCLUÍDA" nunca some |

---

## 2. Migrations geradas

| Arquivo | Fix | Status |
|---------|-----|--------|
| `supabase/migrations/20260518001000_fix01_v_lessons_panel_media_fields.sql` | Fix-01 | AGUARDANDO EXECUÇÃO |
| `supabase/migrations/20260518002000_fix02_v_lesson_progress_panel_recruta_progresso.sql` | Fix-02 | AGUARDANDO EXECUÇÃO |

---

## 3. Fix-01 — `v_lessons_panel`: adicionar video_url e pdf_url

### O que muda

```sql
-- ANTES (dump remoto ln 13251):
CREATE OR REPLACE VIEW public.v_lessons_panel AS
SELECT a.id AS lesson_id, a.titulo AS title, a.modulo_id AS module,
       a.ordem AS lesson_order, m.forca AS force
FROM public.aulas a JOIN public.modulos m ON m.id = a.modulo_id;

-- DEPOIS:
CREATE OR REPLACE VIEW public.v_lessons_panel AS
SELECT a.id AS lesson_id, a.titulo AS title, a.modulo_id AS module,
       a.ordem AS lesson_order, m.forca AS force,
       a.video_url,   -- NOVO
       a.pdf_url      -- NOVO
FROM public.aulas a JOIN public.modulos m ON m.id = a.modulo_id;
```

### Impacto por consumer

| Consumer | Antes | Depois |
|---------|-------|--------|
| `useLessonData.ts` (select `*`) | `video_url` = undefined → null | `video_url` = string\|null real |
| `ModuleLessonsScreen.tsx` (select `'video_url, pdf_url'`) | PostgREST error → `aulas = []` | Coluna existe → aulas listadas |
| `services/lessons.ts` (select `*`) | Sem impacto (campos ignorados) | Campos disponíveis, sem breaking change |

### Para exibir vídeo após Fix-01

`aulas.video_url` deve conter URL com um dos padrões reconhecidos pelo app (`lesson/[id].tsx:59`):
- `cloudflarestream` — Cloudflare Stream embed
- `customer-` — Cloudflare Stream com domínio customizado
- terminação `.m3u8` — HLS stream direto

URLs que não satisfazem esses padrões continuam exibindo placeholder. PDFs devem terminar em `.pdf`.

### Risco

**MÍNIMO.** `CREATE OR REPLACE VIEW` é não-destrutivo. GRANTs e OWNER são preservados. Rollback é imediato (reverter o `CREATE OR REPLACE`).

---

## 4. Fix-02 — `v_lesson_progress_panel`: migrar para `recruta_progresso`

### O que muda

```sql
-- ANTES (dump remoto ln 13188):
CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
SELECT user_id, lesson_id, completed_at
FROM public.lesson_progress lp;

-- DEPOIS:
CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
SELECT
    rp.recruta_id,
    rp.recruta_id AS user_id,   -- alias de compatibilidade
    rp.lesson_id,
    rp.completed_at,
    rp.xp_granted,
    rp.source
FROM public.recruta_progresso rp
WHERE rp.status = 'completed'
  AND rp.completed_at IS NOT NULL;
```

### Decisão de design: dual-alias

Dois consumers da view têm expectativas diferentes sobre o nome da coluna de identidade:

| Consumer | Filtro usado | Coluna esperada |
|---------|-------------|-----------------|
| `useLessonData.ts:39` | `.eq('recruta_id', userId)` | `recruta_id` |
| `ModuleLessonsScreen.tsx:89` | `.eq('user_id', userId)` | `user_id` |

Expor `rp.recruta_id` e `rp.recruta_id AS user_id` preserva ambos os contratos sem alterar frontend. Ambas as colunas contêm o mesmo valor (`recruta_progresso.recruta_id`).

### Colunas adicionais sem impacto

`xp_granted` e `source` são adicionadas como informacionais. Nenhum consumer atual as lê — `select('completed_at')` e `select('lesson_id')` não são afetados por colunas extras.

### RLS — funcionamento após Fix-02

`recruta_progresso` tem RLS habilitado com política SELECT:
```sql
USING (recruta_id = (SELECT recrutas.id FROM recrutas WHERE recrutas.auth_id = auth.uid()))
```

A view herda o RLS (SECURITY INVOKER é o padrão no PostgreSQL). Quando consultada por um usuário autenticado, a view retorna automaticamente apenas os registros daquele recruta. O `GRANT SELECT TO authenticated` permite o acesso.

### Limitação conhecida — Fix-03 necessário

Fix-02 muda a tabela fonte mas **não** resolve o mapeamento auth.uid() → recrutas.id nos consumers:

```
Situação para GADELHA:
  auth.uid()  = '918c08f3-...'   (auth.users.id)
  recrutas.id = 'cc41fc7e-...'   (PK do recruta — diferente para usuários legados)

useLessonData.ts:39:  .eq('recruta_id', '918c08f3-...')
  → recruta_progresso.recruta_id = 'cc41fc7e-...' ≠ '918c08f3-...'
  → RLS filtra para 'cc41fc7e', mas .eq() filtra para '918c08f3' → 0 linhas

Resultado: completed_at ainda retorna null para GADELHA após Fix-02.
Fix-03 (Sprint 3): substituir userId (auth.uid()) por recrutas.id no frontend.
```

**Fix-02 é pré-requisito de Fix-03.** Sem Fix-02, a tabela fonte está errada. Com Fix-02, o único impedimento restante é o mapeamento no frontend.

### Comportamento pré/pós para cada consumer

| Consumer | Antes do Fix-02 | Depois do Fix-02 |
|---------|-----------------|-----------------|
| `useLessonData.ts` | `lesson_progress` vazia → `completed_at = null` | `recruta_progresso` com dados da RPC → `completed_at` correto quando Fix-03 aplicado |
| `ModuleLessonsScreen.tsx` | `.eq('user_id', ...)` casa com `lesson_progress.user_id` → vazio (sem dados da RPC) | `.eq('user_id', ...)` casa com alias `recruta_id AS user_id` → sem erro PostgREST |

### Risco

**BAIXO.** View recriada, tabelas não alteradas. `lesson_progress` continua existindo intacta. Alias `user_id` garante zero breaking change nos consumers existentes.

---

## 5. Ordem de execução e independência

Fix-01 e Fix-02 são **independentes** — cada um pode ser executado sem o outro. Ordem recomendada:

```
Fix-01 → Fix-02
```

Razão: Fix-01 é menor risco e valida o pipeline de migration antes do Fix-02.

Para aplicar via Supabase CLI:
```bash
supabase db push
# ou manualmente no SQL Editor como service_role, em ordem
```

---

## 6. Verificações pós-execução

Executar após cada migration como `service_role`:

### Fix-01
```sql
-- Confirmar colunas da view
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'v_lessons_panel'
ORDER BY ordinal_position;
-- Esperado: lesson_id, title, module, lesson_order, force, video_url, pdf_url (7 colunas)

-- Confirmar que video_url chega ao frontend (se aulas preenchidas existirem)
SELECT lesson_id, video_url, pdf_url FROM public.v_lessons_panel
WHERE video_url IS NOT NULL OR pdf_url IS NOT NULL LIMIT 3;
```

### Fix-02
```sql
-- Confirmar fonte da view
SELECT pg_get_viewdef('public.v_lesson_progress_panel', true);
-- Esperado: contém 'recruta_progresso', NÃO contém 'lesson_progress'

-- Confirmar colunas (incluindo alias user_id)
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'v_lesson_progress_panel'
ORDER BY ordinal_position;
-- Esperado: recruta_id, user_id, lesson_id, completed_at, xp_granted, source (6 colunas)

-- Confirmar dados pós-QA (após pelo menos uma conclusão via Expo Go)
SELECT recruta_id, lesson_id, completed_at, xp_granted, source
FROM public.v_lesson_progress_panel
WHERE source = 'rpc_complete_lesson'
LIMIT 5;
-- Esperado: linhas com dados reais de conclusão
```

---

## 7. Rollbacks

### Rollback Fix-01
```sql
CREATE OR REPLACE VIEW public.v_lessons_panel AS
SELECT a.id AS lesson_id, a.titulo AS title, a.modulo_id AS module,
       a.ordem AS lesson_order, m.forca AS force
FROM public.aulas a JOIN public.modulos m ON m.id = a.modulo_id;

COMMENT ON VIEW public.v_lessons_panel IS
    'CANONICAL RCC FRONTEND VIEW. Lessons panel projection. Frontend may SELECT through authenticated role.';

GRANT ALL    ON TABLE public.v_lessons_panel TO service_role;
GRANT SELECT ON TABLE public.v_lessons_panel TO authenticated;
```

### Rollback Fix-02
```sql
CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
SELECT user_id, lesson_id, completed_at
FROM public.lesson_progress lp;

COMMENT ON VIEW public.v_lesson_progress_panel IS
    'CANONICAL RCC FRONTEND VIEW. Lesson progress projection. Frontend may SELECT through authenticated role.';

GRANT ALL    ON TABLE public.v_lesson_progress_panel TO service_role;
GRANT SELECT ON TABLE public.v_lesson_progress_panel TO authenticated;
```

---

## 8. Issues abertas após Fix-01 e Fix-02

| ID | Prioridade | Descrição | Sprint |
|----|-----------|-----------|--------|
| Fix-03 | Alta | `useLessonData.ts` envia `auth.uid()` como `recruta_id` — para usuários legados (recrutas.id ≠ auth.uid()) o filtro não casa. Substituir por `recrutas.id`. | Sprint 3 |
| B-01 | Alta | Dashboard hardcoda `module/1` — navega para módulo inexistente. Substituir pelo UUID real do Módulo 0. | Sprint 3 |
| B-05 | Baixa | `lessons_list.tsx` navega para `/aula/[id]` — rota não existe. | Sprint 3 |

---

## 9. Checklist de execução

### Pre-flight
- [ ] Dump `supabase_remote_schema.sql` confirmado como referência (ln 13188, 13251)
- [ ] `rpc_complete_lesson` validada e operacional (pré-requisito)
- [ ] Pelo menos um registro em `recruta_progresso` existente para testes T-05, T-06

### Fix-01
- [ ] Migration aplicada (SQL Editor → service_role ou `supabase db push`)
- [ ] T-01: 7 colunas em `v_lessons_panel` (inclui `video_url`, `pdf_url`)
- [ ] T-04: `has_table_privilege('authenticated', ..., 'SELECT') = true`
- [ ] T-05: COMMENT contém 'Fix-01 2026-05-18'
- [ ] T-06: select explícito com `video_url, pdf_url` não retorna erro

### Fix-02
- [ ] Migration aplicada (SQL Editor → service_role ou `supabase db push`)
- [ ] T-01: 6 colunas em `v_lesson_progress_panel` (inclui `recruta_id` e `user_id`)
- [ ] T-02: `pg_get_viewdef` contém 'recruta_progresso', não 'lesson_progress'
- [ ] T-03: `has_table_privilege('authenticated', ..., 'SELECT') = true`
- [ ] T-05: view retorna dados de `rpc_complete_lesson` (se QA já executado)
- [ ] T-07: RLS filtra corretamente (Run as user → GADELHA → só seus dados)

### QA Expo Go pós-migration
- [ ] Fix-01: tela de aula exibe vídeo/PDF quando `aulas.video_url`/`pdf_url` preenchidos
- [ ] Fix-02 + Fix-03: botão "MARCAR COMO CONCLUÍDA" some após conclusão (requer Fix-03)
