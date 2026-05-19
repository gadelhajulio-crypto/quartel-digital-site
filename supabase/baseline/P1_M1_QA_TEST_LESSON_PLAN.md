# P1-M1 QA — Plano de Aula de Teste para Expo Go

**Sprint:** 2 / Fase 2 — QA pós-migração frontend
**Data:** 2026-05-18
**Objetivo:** Criar módulo e aula de teste visíveis no app para validar
`rpc_complete_lesson` pelo Expo Go sem tocar em conteúdo real.

---

## 1. Diagnóstico das views consumidas pelo app

O app consome 4 views ao exibir e concluir aulas. Cada uma tem requisitos
diferentes sobre o módulo e a aula. A tabela abaixo consolida esses requisitos.

### 1.1 Mapa de views por fluxo

| Hook | View | Quando é lida |
|------|------|--------------|
| `useModulesProgress` | `vw_recruta_module_progress_v2` | Lista de módulos na tela principal |
| `useModuleLessons` | `vw_rdm_lessons_v2` | Lista de aulas dentro de um módulo |
| `useLessonData` | `v_lessons_panel` | Tela de detalhe da aula (header + mídia) |
| `useLessonData` | `v_lesson_progress_panel` | Estado "concluída" na tela de detalhe |

### 1.2 DDL relevante confirmado no schema remoto

```sql
-- modulos (ln 10607)
CREATE TABLE public.modulos (
    id           uuid    DEFAULT gen_random_uuid() NOT NULL,
    forca        text    NOT NULL,                 -- CHECK: marinha|exercito|aeronautica
    titulo       text    NOT NULL,
    descricao    text,
    ordem        integer NOT NULL,
    ativo        boolean DEFAULT true,
    is_degustacao boolean DEFAULT false
);

-- aulas (ln 9075)
CREATE TABLE public.aulas (
    id        uuid    DEFAULT gen_random_uuid() NOT NULL,
    modulo_id uuid    NOT NULL,
    titulo    text    NOT NULL,
    ordem     integer NOT NULL,
    xp_valor  integer DEFAULT 0 NOT NULL,
    video_url text,
    pdf_url   text
);
```

### 1.3 Filtros efetivos por view

#### `vw_rdm_lessons_v2` — lista de aulas do módulo
```sql
WHERE COALESCE(m.ativo, true) = true       -- módulo deve estar ativo
  AND COALESCE(m.is_degustacao, false) = true  -- ← OBRIGATÓRIO: is_degustacao = true
ORDER BY m.ordem, a.ordem
```
> **Atenção:** `is_degustacao DEFAULT false` — sem setar `true` explicitamente,
> a aula NÃO aparece na lista mesmo com `ativo = true`.

#### `vw_recruta_module_progress_v2` — módulos do recruta
```sql
JOIN public.modulos m ON
    COALESCE(m.ativo, true) = true           -- módulo ativo
    AND (m.forca IS NULL OR m.forca = r.forca)  -- força do módulo = força do recruta
```
> **Atenção:** `modulos.forca` tem `NOT NULL` constraint — `m.forca IS NULL`
> nunca será true. O módulo de teste **deve ter a mesma força que GADELHA**.

#### `v_lessons_panel` — detalhe da aula
```sql
SELECT a.id, a.titulo, a.modulo_id AS module, a.ordem, m.forca
FROM public.aulas a JOIN public.modulos m ON m.id = a.modulo_id
-- Sem filtros — qualquer aula com modulo_id válido aparece.
```

#### `v_lesson_progress_panel` — estado "concluída"
```sql
SELECT user_id, lesson_id, completed_at FROM public.lesson_progress lp
-- Lê da tabela lesson_progress (LEGADA), não de recruta_progresso.
```
> **ACHADO IMPORTANTE (ver Seção 2):** esta view não refletirá a conclusão
> via `rpc_complete_lesson`. O QA deve validar via Metro logs e SQL, não via UI.

### 1.4 C9 é obrigatório?

**Não.** As views `vw_rdm_lessons_v2`, `v_lessons_panel` e `vw_recruta_module_progress_v2`
não referenciam `c9_aula_conteudos`, `c9_aula_flashcards` nem `c9_aula_quizzes`.
A aula de teste pode ter `video_url = NULL` e `pdf_url = NULL` — a tela exibirá
o placeholder "Conteúdo Institucional".

---

## 2. Achado: v_lesson_progress_panel lê tabela legada

```sql
-- v_lesson_progress_panel (schema remoto ln 13188)
CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
SELECT user_id, lesson_id, completed_at
FROM public.lesson_progress lp;
-- ↑ lesson_progress é uma tabela LEGADA
-- rpc_complete_lesson escreve em recruta_progresso (tabela canônica)
```

O hook `useLessonData` consulta esta view com:
```typescript
.eq('recruta_id', userId)   // mas a coluna da view é "user_id", não "recruta_id"
```

**Consequência para QA:**
- Após `rpc_complete_lesson`, a tela de detalhe da aula **não exibirá** o estado
  "concluída" visualmente (botão não some, `completed_at` continua null).
- Isso é comportamento esperado da view legada — **não é bug do `rpc_complete_lesson`**.
- A validação correta do QA é via **Metro logs** + **query SQL em `recruta_progresso`**.
- Este achado deve ser tratado como issue separada (migração de `v_lesson_progress_panel`
  para ler de `recruta_progresso`).

---

## 3. Requisitos do módulo/aula de teste

### Resumo de campos obrigatórios

| Campo | Tabela | Valor | Motivo |
|-------|--------|-------|--------|
| `forca` | `modulos` | `'marinha'` (ou força de GADELHA) | NOT NULL + CHECK; `vw_recruta_module_progress_v2` filtra por `m.forca = r.forca` |
| `ativo` | `modulos` | `true` | Filtro em `vw_rdm_lessons_v2` e `vw_recruta_module_progress_v2` |
| `is_degustacao` | `modulos` | `true` | Filtro obrigatório em `vw_rdm_lessons_v2`; DEFAULT é `false` |
| `ordem` | `modulos` | `9999` | Aparece no final da lista sem interferir na ordem dos módulos reais |
| `xp_valor` | `aulas` | `50` | Validação de T-08: `xp_added = 50` |
| `modulo_id` | `aulas` | UUID do módulo de teste | FK obrigatória |
| `titulo` | `modulos` e `aulas` | Prefixo `[TESTE DEV]` | Identificação visual imediata no app |

### Força de GADELHA

Verificar antes de executar o SQL:
```sql
-- Executar como service_role para confirmar a força de GADELHA
SELECT id, auth_id, nome_guerra, forca
FROM public.recrutas
WHERE auth_id = '918c08f3-8e08-4dc7-a102-da5c729a6ead';
-- Anotar o valor de "forca" e substituir em STEP-01 se não for 'marinha'
```

---

## 4. Script SQL manual (NÃO executar automaticamente)

> **Executar no SQL Editor do Supabase como `service_role`.**
> **Não usar como migration — dados de teste não pertencem ao histórico de schema.**
> **Executar STEP-00, STEP-01 e STEP-02 em sequência.**

### STEP-00 — Verificar que os UUIDs de teste não existem

```sql
-- Confirmar que os UUIDs fixos de teste estão livres antes de inserir
SELECT 'modulo' AS tipo, id, titulo FROM public.modulos
WHERE id = '00000000-0000-0000-0000-000000010001'
UNION ALL
SELECT 'aula', id, titulo FROM public.aulas
WHERE id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 0 linhas
-- Se retornar linhas: este script já foi executado antes. Ver ROLLBACK (Seção 5).
```

### STEP-01 — Criar módulo de teste

```sql
-- [TESTE DEV] Módulo QA P1-M1
-- UUIDs fixos para facilitar rollback sem precisar consultar id.
-- forca = 'marinha': ajustar se GADELHA tiver outra força (ver STEP-00 acima).
INSERT INTO public.modulos (
    id,
    forca,
    titulo,
    descricao,
    ordem,
    ativo,
    is_degustacao
) VALUES (
    '00000000-0000-0000-0000-000000010001',
    'marinha',
    '[TESTE DEV] QA P1-M1',
    'Módulo de teste para QA do rpc_complete_lesson. Remover após Fase 2.',
    9999,
    true,
    true    -- OBRIGATÓRIO: false tornaria o módulo invisível em vw_rdm_lessons_v2
);

-- Verificação STEP-01:
SELECT id, titulo, forca, ativo, is_degustacao, ordem
FROM public.modulos
WHERE id = '00000000-0000-0000-0000-000000010001';
-- Esperado: 1 linha com is_degustacao=true, ativo=true, ordem=9999
```

### STEP-02 — Criar aula de teste

```sql
-- [TESTE DEV] Aula QA rpc_complete_lesson
-- xp_valor = 50 para coincidir com o XP esperado em T-08
-- video_url e pdf_url = NULL: tela exibe placeholder "Conteúdo Institucional"
INSERT INTO public.aulas (
    id,
    modulo_id,
    titulo,
    ordem,
    xp_valor,
    video_url,
    pdf_url
) VALUES (
    '00000000-0000-0000-0000-000000010002',
    '00000000-0000-0000-0000-000000010001',
    '[TESTE DEV] Aula QA rpc_complete_lesson',
    1,
    50,
    NULL,
    NULL
);

-- Verificação STEP-02:
SELECT id, titulo, modulo_id, ordem, xp_valor
FROM public.aulas
WHERE id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 1 linha, xp_valor=50
```

### STEP-03 — Confirmar visibilidade nas views

```sql
-- V-01: aula aparece em vw_rdm_lessons_v2 (lista de aulas do módulo)?
SELECT lesson_id, lesson_title, module_id, forca, is_degustacao, status
FROM public.vw_rdm_lessons_v2
WHERE module_id = '00000000-0000-0000-0000-000000010001';
-- Esperado: 1 linha, status='available'
-- Se 0 linhas: verificar is_degustacao e ativo do módulo

-- V-02: aula aparece em v_lessons_panel (detalhe da aula)?
SELECT lesson_id, title, module, lesson_order, force
FROM public.v_lessons_panel
WHERE lesson_id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 1 linha

-- V-03: módulo aparece em vw_recruta_module_progress_v2 para GADELHA?
-- (Executar como service_role — a view usa recrutas sem RLS de auth.uid())
SELECT recruta_id, module_id, module_title, total_lessons, completed_lessons
FROM public.vw_recruta_module_progress_v2
WHERE module_id  = '00000000-0000-0000-0000-000000010001'
  AND recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017';
-- Esperado: 1 linha, total_lessons=1, completed_lessons=0

-- V-04: rpc_complete_lesson reconhece a aula de teste?
-- (Executar como service_role — apenas verifica o banco, não executa a RPC)
SELECT id, titulo, xp_valor, modulo_id
FROM public.aulas
WHERE id = '00000000-0000-0000-0000-000000010002'
  AND xp_valor > 0;
-- Esperado: 1 linha, xp_valor=50
```

---

## 5. Fluxo de QA no Expo Go

### Pré-condição
- STEP-01 a STEP-03 executados e verificações passando
- App rodando em Expo Go com login de GADELHA

### Passo a passo

```
1. Abrir app → navegar para a lista de módulos
   Verificar: módulo "[TESTE DEV] QA P1-M1" aparece no final da lista

2. Tocar no módulo "[TESTE DEV] QA P1-M1"
   Verificar: aula "[TESTE DEV] Aula QA rpc_complete_lesson" aparece
   Verificar: status visual = disponível (não bloqueada)

3. Tocar na aula
   Verificar: tela de detalhe carrega com título correto
   Verificar: placeholder "Conteúdo Institucional" exibido (video_url = NULL esperado)
   Verificar: botão "MARCAR AULA COMO CONCLUÍDA" visível

4. Tocar em "MARCAR AULA COMO CONCLUÍDA"
   Verificar no Metro:
     [P1-M1] rpc_complete_lesson {"status":"ok","xp_granted":true,"xp_added":50}
   Verificar: app retorna para a tela do módulo (router.back())
   Verificar: SEM Alert de erro

5. Tocar novamente na aula (teste de idempotência)
   Tocar em "MARCAR AULA COMO CONCLUÍDA" de novo
   Verificar no Metro:
     [P1-M1] rpc_complete_lesson {"status":"ok","xp_granted":false,"xp_added":0,"message":"Aula já concluída anteriormente"}
   Verificar: app retorna normalmente (sem erro, sem duplicar XP)
```

> **Nota sobre o botão:** Após concluir, o botão **não desaparece** da tela
> porque `v_lesson_progress_panel` lê `lesson_progress` (legada) e não reflete
> a conclusão de `rpc_complete_lesson`. Isso é esperado — não é falha do fluxo.
> A conclusão real está em `recruta_progresso` (validada nas queries da Seção 6).

### Logs Metro esperados (fluxo completo)

```
[P1-M1] rpc_complete_lesson {"status":"ok","xp_granted":true,"xp_added":50}
// ↑ primeira conclusão: XP concedido

[P1-M1] rpc_complete_lesson {"status":"ok","xp_granted":false,"xp_added":0,"message":"Aula já concluída anteriormente"}
// ↑ segunda chamada: idempotência confirmada
```

---

## 6. Queries de validação pós-QA (service_role)

```sql
-- QA-01: progresso registrado com recruta_id canônico
SELECT
    rp.recruta_id,
    rp.lesson_id,
    rp.status,
    rp.xp_granted,
    rp.source,
    rp.completed_at,
    rp.recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017' AS recruta_id_correto
FROM public.recruta_progresso rp
WHERE rp.lesson_id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 1 linha
--   status       = 'completed'
--   xp_granted   = 50
--   source       = 'rpc_complete_lesson'
--   recruta_id_correto = true  (cc41fc7e, NÃO 918c08f3)

-- QA-02: XP registrado no ledger
SELECT
    xe.recruta_id,
    xe.forca,
    xe.quantidade,
    xe.origem,
    xe.referencia_id
FROM public.xp_eventos xe
WHERE xe.referencia_id = '00000000-0000-0000-0000-000000010002'
  AND xe.origem        = 'lesson_complete';
-- Esperado: 1 linha, quantidade=50, forca IN ('marinha','exercito','aeronautica')

-- QA-03: idempotência — COUNT = 1 após múltiplas conclusões
SELECT COUNT(*) AS contagem_progresso
FROM public.recruta_progresso
WHERE lesson_id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 1 (nunca > 1)

SELECT COUNT(*) AS contagem_xp
FROM public.xp_eventos
WHERE referencia_id = '00000000-0000-0000-0000-000000010002'
  AND origem = 'lesson_complete';
-- Esperado: 1 (nunca > 1)

-- QA-04: progresso refletido em vw_recruta_module_progress_v2
SELECT recruta_id, module_id, total_lessons, completed_lessons, progress_percentage
FROM public.vw_recruta_module_progress_v2
WHERE module_id  = '00000000-0000-0000-0000-000000010001'
  AND recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017';
-- Esperado: completed_lessons=1, progress_percentage=100
```

---

## 7. Rollback

> Executar SOMENTE após QA concluído (aprovado ou reprovado).
> Executar como `service_role` no SQL Editor.

```sql
-- R-01: remover progresso da aula de teste em recruta_progresso
DELETE FROM public.recruta_progresso
WHERE lesson_id = '00000000-0000-0000-0000-000000010002'
  AND source    = 'rpc_complete_lesson';

-- Verificação R-01:
SELECT COUNT(*) AS deve_ser_zero FROM public.recruta_progresso
WHERE lesson_id = '00000000-0000-0000-0000-000000010002';

-- R-02: remover XP da aula de teste em xp_eventos
DELETE FROM public.xp_eventos
WHERE referencia_id = '00000000-0000-0000-0000-000000010002'
  AND origem        = 'lesson_complete';

-- Verificação R-02:
SELECT COUNT(*) AS deve_ser_zero FROM public.xp_eventos
WHERE referencia_id = '00000000-0000-0000-0000-000000010002';

-- R-03: remover aula de teste
DELETE FROM public.aulas
WHERE id = '00000000-0000-0000-0000-000000010002';

-- Verificação R-03:
SELECT COUNT(*) AS deve_ser_zero FROM public.aulas
WHERE id = '00000000-0000-0000-0000-000000010002';

-- R-04: remover módulo de teste
-- (FK constraint: executar SOMENTE após R-03)
DELETE FROM public.modulos
WHERE id = '00000000-0000-0000-0000-000000010001';

-- Verificação R-04:
SELECT COUNT(*) AS deve_ser_zero FROM public.modulos
WHERE id = '00000000-0000-0000-0000-000000010001';

-- R-05: confirmar que recrutas.xp não ficou contaminado
-- (Se o trigger de sync atualizou recrutas.xp, verificar e corrigir manualmente)
SELECT id, xp FROM public.recrutas
WHERE id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017';
-- Se xp > 0 e era 0 antes: UPDATE recrutas SET xp = <valor_anterior> WHERE id = 'cc41fc7e...';
```

---

## 8. Checklist de QA

### Setup
- [ ] STEP-00: UUIDs livres confirmados (0 linhas)
- [ ] STEP-01: módulo de teste criado (`is_degustacao=true`, `ativo=true`, `forca=marinha`)
- [ ] STEP-02: aula de teste criada (`xp_valor=50`)
- [ ] STEP-03 V-01: aula visível em `vw_rdm_lessons_v2` (`status='available'`)
- [ ] STEP-03 V-02: aula visível em `v_lessons_panel`
- [ ] STEP-03 V-03: módulo visível em `vw_recruta_module_progress_v2` para GADELHA

### QA no app (Expo Go)
- [ ] Módulo "[TESTE DEV] QA P1-M1" aparece na lista de módulos
- [ ] Aula aparece ao tocar no módulo
- [ ] Tela de detalhe carrega sem erro
- [ ] Metro log mostra `[P1-M1] rpc_complete_lesson {status:'ok',xp_granted:true,xp_added:50}`
- [ ] App retorna para lista (`router.back()`) sem Alert de erro
- [ ] Segunda conclusão: Metro log mostra `xp_granted:false` + `message`

### Validação no banco
- [ ] QA-01: `source='rpc_complete_lesson'`, `recruta_id=cc41fc7e`, `xp_granted=50`
- [ ] QA-02: `xp_eventos` com `quantidade=50`, `forca` válida
- [ ] QA-03: COUNT progresso = 1, COUNT xp = 1 (sem duplicatas)
- [ ] QA-04: `vw_recruta_module_progress_v2` mostra `progress_percentage=100`

### Rollback (após QA)
- [ ] R-01 a R-04 executados
- [ ] Verificações de 0 linhas confirmadas
- [ ] `recrutas.xp` verificado

---

## 9. Observações e issues derivadas

### Issue A — `v_lesson_progress_panel` lê tabela legada (prioridade P1)

A view lê `lesson_progress` (legada) em vez de `recruta_progresso` (canônica).
Após conclusão via `rpc_complete_lesson`, o botão "MARCAR COMO CONCLUÍDA" continua
visível pois `completed_at` retorna null da view. Impacto UX: recruta pode tentar
concluir a mesma aula múltiplas vezes — a RPC é idempotente então sem dano ao ledger,
mas a UX não dá feedback de conclusão.

**Ação recomendada (Sprint 3):** criar `v_lesson_progress_panel` lendo de
`recruta_progresso` com `WHERE recruta_id = auth.uid()` ou atualizar a view existente.

### Issue B — `useLessonData` filtra por `recruta_id` em view com coluna `user_id`

```typescript
.eq('recruta_id', userId)  // coluna real da view é "user_id"
```
Isso resulta em filtro não aplicado — a view retorna sem `completed_at`.
**Ação recomendada:** alinhar nome da coluna na view ou no hook.

### Issue C — `modulos.forca NOT NULL` na view `vw_recruta_module_progress_v2`

A view tenta filtrar `m.forca IS NULL OR m.forca = r.forca` mas `forca` é NOT NULL.
A condição `m.forca IS NULL` nunca é verdadeira. Módulos transversais (todas as forças)
são impossíveis no schema atual. Se necessário no futuro, requer ALTER TABLE.
