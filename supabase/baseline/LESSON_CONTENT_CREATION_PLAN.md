# Plano de Criação de Conteúdo Real de Aulas

**Sprint:** 2 / Pós-QA
**Data:** 2026-05-18
**Objetivo:** Mapear exatamente o que precisa existir no banco — e o que precisa ser corrigido no app — para uma aula real aparecer, ser navegável e ser concluída no Expo Go.

---

## 1. Resultado da Auditoria

### 1.1 Dois fluxos paralelos — apenas um é dinâmico

#### Fluxo A — Estático (Tab "Módulos")
```
app/(tabs)/modules.tsx
  → MARINHA_CURRICULUM (constante TypeScript hardcoded)
  → ModuleAccordion (accordion visual)
  → SEM navegação para tela de aula
  → SEM consulta ao banco
```
**Conclusão:** Tab "Módulos" é cosmética. Exibe o currículo hardcoded com ícones de cadeado. Não navega para nenhuma tela de aula. Não lê nenhuma view.

#### Fluxo B — Dinâmico (The Real Flow)
```
app/(tabs)/index.tsx ("Continuar estudando")
  → router.push('/(stack)/module/1')   ← UUID hardcoded como "1"

app/(stack)/module/[id].tsx
  → useModuleLessons(id)
  → vw_rdm_lessons_v2 WHERE module_id = id ORDER BY lesson_order
  → LessonRow (status 'available' → navegável)
  → router.push('/(stack)/lesson/<lesson_id>')

app/(stack)/lesson/[id].tsx
  → useLessonData(lessonId, userId) → 2 queries:
      1. v_lessons_panel WHERE lesson_id = lessonId
      2. v_lesson_progress_panel WHERE lesson_id = lessonId AND recruta_id = userId
  → renderContent(): vídeo | PDF | placeholder
  → handleComplete() → completeLesson(id) → rpc_complete_lesson(p_lesson_id)
```

#### Fluxo C — Legado Quebrado (lessons_list.tsx)
```
app/(stack)/lessons_list.tsx
  → fetchLessons() → v_lessons_panel WHERE force='marinha'
  → router.push({ pathname: '/aula/[id]', ... })  ← rota não existe
```
**Conclusão:** Este screen navega para `/aula/[id]`, rota que não existe no sistema de arquivos (`app/(stack)/lesson/[id].tsx` é o correto). Inacessível e não relevante para criação de conteúdo real.

---

### 1.2 Mapa de views por tela

| Tela / Hook | View consultada | Método | Filtros |
|-------------|-----------------|--------|---------|
| `useModuleLessons` | `vw_rdm_lessons_v2` | SELECT * | `module_id = <id>` ORDER `lesson_order` |
| `useLessonData` (dados) | `v_lessons_panel` | SELECT * | `lesson_id = <id>` |
| `useLessonData` (progresso) | `v_lesson_progress_panel` | SELECT `completed_at` | `lesson_id = <id>` AND `recruta_id = userId` |
| `useModulesProgress` | `vw_recruta_module_progress_v2` | SELECT * | nenhum (filtra por auth.uid() via JOIN recrutas) |

---

### 1.3 Definição das views — contrato real de leitura

#### `vw_rdm_lessons_v2` (schema remoto ln 14177)
```sql
SELECT a.id AS lesson_id, a.ordem AS lesson_order, a.titulo AS lesson_title,
       'available'::text AS status,   -- CONSTANTE — não reflete conclusão
       m.id AS module_id, m.titulo AS module_title,
       m.forca, m.is_degustacao,
       a.video_url, a.pdf_url
FROM aulas a
JOIN modulos m ON m.id = a.modulo_id
WHERE COALESCE(m.ativo, true) = true
  AND COALESCE(m.is_degustacao, false) = true   -- FILTRO CRÍTICO
ORDER BY m.ordem, a.ordem;
```
> `status` é sempre `'available'` — a view não calcula progresso por usuário.
> `is_degustacao = true` é **obrigatório**. Sem ele: 0 aulas retornadas.

#### `v_lessons_panel` (schema remoto ln 13251)
```sql
SELECT a.id AS lesson_id, a.titulo AS title,
       a.modulo_id AS module, a.ordem AS lesson_order, m.forca AS force
FROM aulas a
JOIN modulos m ON m.id = a.modulo_id;
```
> **ACHADO CRÍTICO:** `v_lessons_panel` NÃO expõe `video_url` nem `pdf_url`.
> `useLessonData` lê `lessonData.video_url ?? null` e `lessonData.pdf_url ?? null`.
> Como os campos não existem na view, ambos são `undefined` → coerção `?? null` → `null`.
> **Resultado:** A tela de aula sempre exibe placeholder "Conteúdo Institucional", mesmo com URL preenchida em `aulas.video_url`.

#### `v_lesson_progress_panel` (schema remoto ln 13188)
```sql
SELECT user_id, lesson_id, completed_at
FROM public.lesson_progress lp;  -- TABELA LEGADA
```
> **ACHADO CRÍTICO:** Lê a tabela `lesson_progress` (legada), não `recruta_progresso` (canônica).
> `useLessonData` filtra com `.eq('recruta_id', userId)` mas a coluna da view é `user_id`.
> Filtro nunca casa → `completed_at` sempre `null` → botão "MARCAR COMO CONCLUÍDA" sempre visível.
> Já documentado em P1_M1_QA_TEST_LESSON_PLAN.md (Issue A + Issue B).

---

### 1.4 C9 — não é consumido pela tela de aula

```
Busca no frontend por: c9_aula | C9 | flashcard | quiz | conteudo
Resultado em app/: 0 arquivos
Resultado em src/: 8 arquivos — todos relacionados ao chat/instrutor, NENHUM à tela de aula
```

As tabelas C9 (`c9_aula_conteudos`, `c9_aula_flashcards`, `c9_aula_quizzes`, etc.) são consumidas apenas pela view `v_c9_aula_execucao` (ln 12350), que não é lida por nenhum hook de lição. C9 é infraestrutura do AI Factory/Chat — **não é requisito para a tela de aula funcionar**.

---

### 1.5 Bugs estruturais que bloqueiam o fluxo completo

| # | Localização | Problema | Impacto |
|---|-------------|---------|---------|
| B-01 | `app/(tabs)/index.tsx:93` | Dashboard usa `router.push('/(stack)/module/1')` (UUID hardcoded `"1"`) | Navega para módulo inexistente → "Nenhuma aula disponível" |
| B-02 | `v_lessons_panel` (ln 13251) | View não expõe `video_url` nem `pdf_url` | Vídeo/PDF nunca renderizados — sempre placeholder |
| B-03 | `v_lesson_progress_panel` (ln 13188) | Lê `lesson_progress` (legacy) em vez de `recruta_progresso` | `completed_at` sempre null — botão sempre visível após conclusão |
| B-04 | `useLessonData` (`useLessonData.ts:39`) | Filtra `v_lesson_progress_panel` com `.eq('recruta_id', ...)` mas coluna da view é `user_id` | Filtro silenciosamente ignorado |
| B-05 | `app/(stack)/lessons_list.tsx:67` | Navega para `/aula/[id]` — rota não existe | Crash ou tela em branco |

**B-01 é bloqueante para QA via caminho normal.** Para contornar sem alterar código: acessar a rota diretamente via deep link ou construir URL com UUID real do módulo.

---

## 2. Campos mínimos obrigatórios

### 2.1 `public.modulos`

| Campo | Tipo | Obrigatório | Valor mínimo | Motivo |
|-------|------|-------------|-------------|--------|
| `id` | uuid | sim | gen_random_uuid() | PK |
| `forca` | text | sim | `'marinha'` | NOT NULL + CHECK; filtro em `vw_recruta_module_progress_v2` |
| `titulo` | text | sim | qualquer string | NOT NULL; exibido como `module_title` |
| `ordem` | integer | sim | qualquer inteiro | NOT NULL; ordenação nas views |
| `ativo` | boolean | sim | `true` | filtro `COALESCE(ativo, true) = true` nas views |
| `is_degustacao` | boolean | **CRÍTICO** | `true` | filtro `COALESCE(is_degustacao, false) = true` em `vw_rdm_lessons_v2` — DEFAULT `false` |
| `descricao` | text | não | null | não exibido nas views do app |
| `created_at` | timestamptz | não | now() | DEFAULT automático |

### 2.2 `public.aulas`

| Campo | Tipo | Obrigatório | Valor mínimo | Motivo |
|-------|------|-------------|-------------|--------|
| `id` | uuid | sim | gen_random_uuid() | PK; usado como `lesson_id` nas views |
| `modulo_id` | uuid | sim | UUID do módulo | FK NOT NULL; join em todas as views |
| `titulo` | text | sim | qualquer string | NOT NULL; exibido como `lesson_title` |
| `ordem` | integer | sim | 1 | NOT NULL; ordenação em `vw_rdm_lessons_v2` |
| `xp_valor` | integer | sim | ≥ 0 | NOT NULL; lido por `rpc_complete_lesson`. 0 = registra conclusão sem XP. > 0 = XP concedido |
| `video_url` | text | não | null | exibido como vídeo se URL contiver 'cloudflarestream', 'customer-' ou terminar em '.m3u8' |
| `pdf_url` | text | não | null | exibido com link "Abrir Externamente" se terminar em '.pdf' |
| `created_at` | timestamptz | não | now() | DEFAULT automático |

### 2.3 C9 — nenhum campo obrigatório

As tabelas C9 não são consultadas pelo fluxo de aula atual. **Não criar dados C9 nesta fase.**

---

## 3. SQL de criação de aula real

### STEP-00 — Confirmar UUID do módulo real que queremos usar
```sql
-- Listar módulos Marinha existentes no banco
SELECT id, titulo, forca, ativo, is_degustacao, ordem
FROM public.modulos
WHERE forca = 'marinha'
ORDER BY ordem;
-- Anotar os UUIDs reais para usar em STEP-02 e para navegação
```

### STEP-01 — (Se necessário) Criar módulo com is_degustacao=true
```sql
-- Apenas se o módulo desejado NÃO tiver is_degustacao=true.
-- Opção A: atualizar módulo existente (não cria novo)
UPDATE public.modulos
SET    is_degustacao = true,
       ativo         = true
WHERE  forca = 'marinha'
  AND  ordem = 0;  -- Módulo 0 = Regulamento Disciplinar (primeira aula desbloqueada)

-- Verificação:
SELECT id, titulo, forca, ativo, is_degustacao, ordem
FROM public.modulos
WHERE forca = 'marinha'
  AND ordem = 0;
-- Esperado: is_degustacao = true
```

```sql
-- Opção B: criar módulo novo (se nenhum existente for adequado)
-- Anotar o UUID gerado — será necessário para STEP-02 e para navegação.
INSERT INTO public.modulos (
    forca, titulo, descricao, ordem, ativo, is_degustacao
) VALUES (
    'marinha',
    'Regulamento Disciplinar',
    'Fundamentos e normas disciplinares da Marinha.',
    0,
    true,
    true     -- OBRIGATÓRIO — sem isso a aula não aparece em vw_rdm_lessons_v2
)
RETURNING id, titulo, is_degustacao;
-- Salvar o UUID retornado para STEP-02
```

### STEP-02 — Criar aula real
```sql
-- Substituir <UUID_DO_MODULO> pelo UUID obtido em STEP-00 ou STEP-01.
-- video_url: formato esperado pelo app: URL contendo 'cloudflarestream' ou '.m3u8'
-- pdf_url: URL terminando em '.pdf'
-- Deixar NULL para exibir placeholder "Conteúdo Institucional" (funcional para QA)

INSERT INTO public.aulas (
    modulo_id,
    titulo,
    ordem,
    xp_valor,
    video_url,
    pdf_url
) VALUES (
    '<UUID_DO_MODULO>',
    'Fundamentos do Regulamento Disciplinar para a Marinha (RDM)',
    1,
    100,        -- XP concedido por rpc_complete_lesson
    NULL,       -- sem vídeo ainda: placeholder exibido (ver B-02 abaixo)
    NULL        -- sem PDF ainda
)
RETURNING id, titulo, modulo_id, ordem, xp_valor;
-- Salvar o UUID retornado para STEP-03 e para navegação
```

### STEP-03 — Verificar visibilidade nas views
```sql
-- V-01: aula aparece em vw_rdm_lessons_v2?
-- Substituir <UUID_DO_MODULO> pelo UUID real.
SELECT lesson_id, lesson_order, lesson_title, status, module_id, forca, is_degustacao
FROM public.vw_rdm_lessons_v2
WHERE module_id = '<UUID_DO_MODULO>'
ORDER BY lesson_order;
-- Esperado: 1 ou mais linhas com status='available', is_degustacao=true
-- Se 0 linhas: módulo não tem is_degustacao=true ou ativo=false — BLOQUEANTE

-- V-02: aula aparece em v_lessons_panel?
SELECT lesson_id, title, module, lesson_order, force
FROM public.v_lessons_panel
WHERE module = '<UUID_DO_MODULO>'
ORDER BY lesson_order;
-- Esperado: mesmas aulas
-- Nota: video_url e pdf_url NÃO aparecem aqui (ver B-02)

-- V-03: módulo aparece em vw_recruta_module_progress_v2 para GADELHA?
SELECT recruta_id, module_id, module_title, total_lessons, completed_lessons
FROM public.vw_recruta_module_progress_v2
WHERE module_id  = '<UUID_DO_MODULO>'
  AND recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017';
-- Esperado: 1 linha com total_lessons >= 1

-- V-04: rpc_complete_lesson reconhece a aula (xp_valor > 0)?
SELECT id, titulo, xp_valor, modulo_id
FROM public.aulas
WHERE modulo_id = '<UUID_DO_MODULO>'
  AND xp_valor > 0;
-- Esperado: aulas criadas em STEP-02 com xp_valor = 100
```

---

## 4. Correções necessárias nas views (B-02 e B-03)

Estas correções são **requisitos para que o conteúdo real seja exibido e o estado de conclusão seja refletido**. Não executar automaticamente — cada uma é uma migration separada.

### Fix-01 — `v_lessons_panel`: expor video_url e pdf_url

**Problema (B-02):** A tela de aula nunca exibe vídeo ou PDF porque a view não expõe essas colunas.

**Migration:**
```sql
-- Migration: YYYYMMDDHHMMSS_fix_v_lessons_panel_add_media_cols.sql
-- NÃO executar automaticamente. Aprovar como migration antes de aplicar.

CREATE OR REPLACE VIEW public.v_lessons_panel AS
SELECT
    a.id          AS lesson_id,
    a.titulo      AS title,
    a.modulo_id   AS module,
    a.ordem       AS lesson_order,
    m.forca       AS force,
    a.video_url,       -- NOVO: mapeamento direto de aulas.video_url
    a.pdf_url          -- NOVO: mapeamento direto de aulas.pdf_url
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id;

-- Regras de renderização do app (lesson/[id].tsx):
--   video_url contém 'cloudflarestream'|'customer-'|'.m3u8' → VideoPlayer
--   pdf_url termina em '.pdf'                               → Link "Abrir Externamente"
--   ambos null                                               → placeholder "Conteúdo Institucional"
```

**Impacto:** baixo — recria view sem alterar tabelas. Nenhum dado é perdido.

**Rollback:**
```sql
CREATE OR REPLACE VIEW public.v_lessons_panel AS
SELECT a.id AS lesson_id, a.titulo AS title,
       a.modulo_id AS module, a.ordem AS lesson_order, m.forca AS force
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id;
```

---

### Fix-02 — `v_lesson_progress_panel`: migrar para recruta_progresso

**Problema (B-03 + B-04):** A view lê `lesson_progress` (legada) e expõe coluna `user_id` em vez de `recruta_id`. O hook filtra por `recruta_id` → filtro nunca casa → `completed_at` sempre null.

**Migration:**
```sql
-- Migration: YYYYMMDDHHMMSS_fix_v_lesson_progress_panel_canonical.sql
-- NÃO executar automaticamente. Aprovar como migration antes de aplicar.

CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
SELECT
    rp.recruta_id,      -- coluna canônica (match com .eq('recruta_id', userId) no hook)
    rp.lesson_id,
    rp.completed_at,
    rp.xp_granted,
    rp.source
FROM public.recruta_progresso rp
WHERE rp.status = 'completed'
  AND rp.completed_at IS NOT NULL;

-- GRANTS (idem ao existente):
-- GRANT SELECT ON public.v_lesson_progress_panel TO authenticated;
-- GRANT ALL    ON public.v_lesson_progress_panel TO service_role;
```

**Impacto:** médio — altera contrato de leitura. Frontend deve ser verificado para garantir que não use a coluna `user_id` em outros contextos.

**Rollback:**
```sql
CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
SELECT user_id, lesson_id, completed_at
FROM public.lesson_progress lp;
```

---

### Fix-03 — Dashboard: corrigir UUID hardcoded (frontend)

**Problema (B-01):** `app/(tabs)/index.tsx:93` usa `router.push('/(stack)/module/1')`. UUID `"1"` não existe.

**Solução:** Substituir pelo UUID real do módulo de entrada (obtido em STEP-00).
```typescript
// Linha 93 — substituir:
onPress={() => router.push('/(stack)/module/1')}
// Por:
onPress={() => router.push('/(stack)/module/<UUID_REAL_DO_MODULO_0>')}
```
> Não será feito aqui — registrado como issue de frontend para próxima sprint.

---

## 5. Rollback de dados de aula real

```sql
-- R-01: remover progresso (se aula foi concluída durante testes)
DELETE FROM public.recruta_progresso
WHERE lesson_id IN (
    SELECT id FROM public.aulas WHERE modulo_id = '<UUID_DO_MODULO>'
);

-- R-02: remover XP do ledger
DELETE FROM public.xp_eventos
WHERE referencia_id IN (
    SELECT id FROM public.aulas WHERE modulo_id = '<UUID_DO_MODULO>'
)
  AND origem = 'lesson_complete';

-- R-03: remover aulas
DELETE FROM public.aulas
WHERE modulo_id = '<UUID_DO_MODULO>';

-- R-04: remover módulo (apenas se foi criado para teste — não remover módulos reais)
-- DELETE FROM public.modulos WHERE id = '<UUID_DO_MODULO>';

-- R-05: reverter is_degustacao se foi alterado em módulo existente (Opção A do STEP-01)
-- UPDATE public.modulos SET is_degustacao = false WHERE id = '<UUID_DO_MODULO>';
```

---

## 6. Checklist QA Expo Go — aula real

### Pré-condições
- [ ] STEP-01 executado: módulo com `is_degustacao=true`, `ativo=true`, `forca='marinha'`
- [ ] STEP-02 executado: aula com `xp_valor > 0`
- [ ] STEP-03 V-01: aula visível em `vw_rdm_lessons_v2` (1+ linhas)
- [ ] STEP-03 V-04: `xp_valor > 0` confirmado
- [ ] UUID real do módulo anotado

### Navegação (contorno para B-01)
Enquanto `app/(tabs)/index.tsx` aponta para `module/1` (hardcoded), use um dos caminhos alternativos:
- **Expo Go URL manual:** `exp://<ip>:8081/--/(stack)/module/<UUID_REAL>`
- **Ou:** Temporariamente alterar o UUID no dashboard para testar (revert após QA)

### Fluxo de QA
- [ ] Navegar para o módulo pelo UUID real
- [ ] Tela de módulo carrega com lista de aulas (não "Nenhuma aula disponível")
- [ ] Tocar na aula — tela de detalhe carrega com título correto
- [ ] Placeholder "Conteúdo Institucional" exibido (esperado enquanto Fix-01 não for aplicado)
- [ ] Botão "MARCAR AULA COMO CONCLUÍDA" visível
- [ ] Tocar no botão — Metro log mostra:
  ```
  [P1-M1] rpc_complete_lesson {"status":"ok","xp_granted":true,"xp_added":100}
  ```
- [ ] App retorna para tela do módulo sem Alert de erro
- [ ] Segunda conclusão — Metro log mostra `xp_granted:false` + `message`

### Validação SQL pós-QA
```sql
-- QA-01: progresso registrado
SELECT recruta_id, lesson_id, status, xp_granted, source, completed_at
FROM public.recruta_progresso
WHERE lesson_id IN (SELECT id FROM public.aulas WHERE modulo_id = '<UUID_DO_MODULO>');
-- Esperado: source='rpc_complete_lesson', recruta_id='cc41fc7e', xp_granted=100

-- QA-02: XP no ledger
SELECT recruta_id, quantidade, forca, origem
FROM public.xp_eventos
WHERE referencia_id IN (SELECT id FROM public.aulas WHERE modulo_id = '<UUID_DO_MODULO>');
-- Esperado: quantidade=100, forca='marinha'

-- QA-03: progresso em vw_recruta_module_progress_v2
SELECT module_id, total_lessons, completed_lessons, progress_percentage
FROM public.vw_recruta_module_progress_v2
WHERE module_id  = '<UUID_DO_MODULO>'
  AND recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017';
-- Esperado: completed_lessons >= 1, progress_percentage > 0
```

---

## 7. Fases de entrega recomendadas

### Fase 1 — Mínimo viável (dados apenas)
**O que fazer:**
1. `UPDATE modulos SET is_degustacao = true WHERE forca = 'marinha' AND ordem = 0`
2. Confirmar que aulas do Módulo 0 existem com `xp_valor > 0`
3. Navegar para `/(stack)/module/<UUID_M0>` via deep link

**O que funciona:** módulo aparece com lista de aulas, aulas são concluíveis, XP é concedido, Metro log confirma RPC.

**O que NÃO funciona:** vídeo/PDF não renderiza (B-02), botão não some após conclusão (B-03), dashboard ainda aponta para `module/1` (B-01).

### Fase 2 — Exibição de conteúdo (Fix-01)
**Dependência:** Fix-01 aplicado como migration aprovada.
**O que desbloqueia:** `video_url`/`pdf_url` renderizados pelo app.
**Pré-requisito:** `aulas.video_url` deve conter URL válida (Cloudflare Stream ou similar).

### Fase 3 — Estado de conclusão na UI (Fix-02 + fix frontend)
**Dependência:** Fix-02 aplicado + `useLessonData` não precisa alteração (já usa `.eq('recruta_id', ...)` — correto após Fix-02).
**O que desbloqueia:** botão "MARCAR COMO CONCLUÍDA" desaparece após conclusão (ou mostra estado "concluída").

### Fase 4 — Navegação natural pelo app (Fix-03)
**Dependência:** UUID real do módulo inserido no dashboard.
**O que desbloqueia:** "Continuar estudando" no dashboard leva ao módulo correto.

---

## 8. Resumo: o que é necessário vs. o que é opcional

| Item | Necessário para aparecer | Necessário para concluir | Necessário para renderizar mídia |
|------|--------------------------|--------------------------|----------------------------------|
| `modulos.forca = 'marinha'` | ✓ | ✓ (via recrutas.forca) | — |
| `modulos.ativo = true` | ✓ | — | — |
| `modulos.is_degustacao = true` | **✓ CRÍTICO** | — | — |
| `aulas.modulo_id` (FK válida) | ✓ | ✓ | — |
| `aulas.titulo` | ✓ | — | — |
| `aulas.ordem` | ✓ | — | — |
| `aulas.xp_valor >= 0` | — | ✓ (NOT NULL) | — |
| `aulas.video_url` | — | — | ✓ (+ Fix-01) |
| `aulas.pdf_url` | — | — | ✓ (+ Fix-01) |
| `c9_aula_conteudos` | — | — | — (não usado) |
| `c9_aula_flashcards` | — | — | — (não usado) |
| `c9_aula_quizzes` | — | — | — (não usado) |
| Fix-01 (`v_lessons_panel`) | — | — | ✓ |
| Fix-02 (`v_lesson_progress_panel`) | — | — (RPC funciona) | — |
| Fix-03 (dashboard UUID) | — (workaround existe) | — | — |

---

## 9. Issues derivadas registradas

| ID | Localização | Descrição | Prioridade |
|----|-------------|-----------|-----------|
| B-01 | `app/(tabs)/index.tsx:93` | UUID hardcoded `"1"` no dashboard | Alta — bloqueia navegação natural |
| B-02 | `v_lessons_panel` | Não expõe `video_url`/`pdf_url` | Alta — bloqueia exibição de mídia |
| B-03 | `v_lesson_progress_panel` | Lê tabela `lesson_progress` legada em vez de `recruta_progresso` | Média — afeta UX pós-conclusão |
| B-04 | `useLessonData.ts:39` | `.eq('recruta_id', ...)` mas coluna da view é `user_id` | Média — resolvido automaticamente pelo Fix-02 |
| B-05 | `lessons_list.tsx:67` | Navega para `/aula/[id]` (rota inexistente) | Baixa — screen inacessível |
