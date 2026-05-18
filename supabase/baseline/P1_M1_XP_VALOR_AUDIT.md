# P1-M1 XP Valor Audit — Auditoria de `aulas.xp_valor`
**Status:** AGUARDANDO EXECUCAO PELO OPERADOR
**Data de geracao:** 2026-05-17
**Classificacao:** P1 — Pre-condicao obrigatoria para Fase 0
**Bloqueante de:** P1_M1_TRANSITION_PLAN.md — Fase 1 (create rpc_complete_lesson)
**Fontes lidas:** supabase/remote/supabase_remote_schema.sql, P1_M1_COMPLETE_LESSON_XP_REFACTOR.md, P1_M1_TRANSITION_PLAN.md

> **INSTRUCAO AO OPERADOR**
> Este documento contem queries de **somente leitura** para executar no Supabase SQL Editor.
> Nenhum SQL aqui altera dados. Preencha os resultados na Secao 9 (Relatorio de Execucao).
> A recomendacao final (Secao 8) so pode ser emitida apos o preenchimento.

---

## Indice

1. [Contexto](#1-contexto)
2. [Analise Estatica do DDL](#2-analise-estatica-do-ddl)
3. [Queries de Distribuicao de xp_valor](#3-queries-de-distribuicao-de-xp_valor)
4. [Queries de Aulas Orfas e Modulos Inativos](#4-queries-de-aulas-orfas-e-modulos-inativos)
5. [Queries de Consistencia com Progresso Existente](#5-queries-de-consistencia-com-progresso-existente)
6. [Queries de Contexto do Sistema Legado](#6-queries-de-contexto-do-sistema-legado)
7. [Analise de Risco de xp_valor = 0](#7-analise-de-risco-de-xp_valor--0)
8. [Criterios de Recomendacao](#8-criterios-de-recomendacao)
9. [Relatorio de Execucao](#9-relatorio-de-execucao)

---

## 1. Contexto

A nova RPC `rpc_complete_lesson(p_lesson_id uuid)` (Sprint 2 P1-M1) usara
`aulas.xp_valor` como unica fonte de XP para conclusao de aulas.

Hoje `complete_lesson` usa `p_xp DEFAULT 50` — ignorando `aulas.xp_valor` completamente.
Isso significa que todos os registros historicos em `xp_eventos` com `origem = 'lesson_complete'`
tem `quantidade = 50`, independentemente da aula.

**Ao ativar a nova RPC, o comportamento muda:**
- Aulas com `xp_valor = 50` → sem mudanca para o recruta
- Aulas com `xp_valor > 50` → recruta ganha mais XP do que antes
- Aulas com `xp_valor = 0` → recruta ganha **0 XP** ao concluir (quebra expectativa)
- Aulas com `xp_valor < 50` → recruta ganha menos XP do que antes

Esta auditoria responde: **os dados de `aulas.xp_valor` estao prontos para ser a fonte oficial?**

---

## 2. Analise Estatica do DDL

### 2.1 DDL completo de `aulas` (dump ln 9075–9084)

```sql
CREATE TABLE IF NOT EXISTS "public"."aulas" (
    "id"         "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "modulo_id"  "uuid"  NOT NULL,                           -- FK para modulos (NOT NULL)
    "titulo"     "text"  NOT NULL,
    "ordem"      integer NOT NULL,                           -- ordem dentro do modulo
    "xp_valor"   integer DEFAULT 0 NOT NULL,                 -- FONTE DE XP — DEFAULT 0
    "created_at" timestamp with time zone DEFAULT "now"(),
    "video_url"  "text",                                     -- nullable
    "pdf_url"    "text"                                      -- nullable
);
```

### 2.2 Constraints em `aulas` identificadas no dump

| Constraint | Tipo | Definicao | Fonte (ln) |
|------------|------|-----------|------------|
| `aulas_pkey` | PRIMARY KEY | `(id)` | 14856 |
| `fk_aula_modulo` | FOREIGN KEY | `(modulo_id) → modulos(id) ON DELETE CASCADE` | 16930 |
| (nenhuma) | CHECK em `xp_valor` | **Nao existe** — apenas NOT NULL | — |
| (nenhuma) | UNIQUE em `(modulo_id, ordem)` | **Nao existe** — duas aulas podem ter a mesma ordem | — |

**Achado critico — AUSENCIA DE CHECK CONSTRAINT em xp_valor:**
Nao ha `CHECK (xp_valor >= 0)` nem `CHECK (xp_valor > 0)`. O banco aceita `xp_valor = -999`
sem erro. A integridade dos dados depende inteiramente do processo de criacao de aulas.

### 2.3 RLS em `aulas`

Duas policies de SELECT para `authenticated` foram encontradas no dump:

```sql
-- Dump ln 17371
CREATE POLICY "Permitir leitura de aulas para usuarios autenticados"
    ON "public"."aulas" FOR SELECT TO "authenticated" USING (true);

-- Dump ln 17462
CREATE POLICY "aulas_read_authenticated"
    ON "public"."aulas" FOR SELECT TO "authenticated" USING (true);
```

**Observacoes:**
- Ambas as policies sao identicas e redundantes — possivel duplicata historica
- `authenticated` pode ler TODAS as aulas (USING true = sem restricao de linha)
- `service_role` tem GRANT ALL (dump ln 19193) e bypassa RLS
- `rpc_complete_lesson` (SECURITY DEFINER, owner=postgres=SUPERUSER) bypassa RLS — acesso garantido

### 2.4 Tabelas que referenciam `aulas.id` (escopo de impacto)

| Tabela | FK | ON DELETE | Relevancia para auditoria |
|--------|----|-----------|---------------------------|
| `recruta_progresso` | `lesson_id → aulas.id` | CASCADE | Registros de conclusao — afetados pelo refactor |
| `aulas_concluidas` | `aula_id → aulas.id` | CASCADE | Sistema legado |
| `progresso_aulas` | `aula_id → aulas.id` | CASCADE | Sistema legado alternativo |
| `aula_pipeline_execucoes` | `aula_id → aulas.id` | CASCADE | Pipeline de geracao de conteudo AI |
| `c9_aula_conteudos` | `aula_id → aulas.id` | — | Conteudo rico (roteiros, resumos) |
| `c9_aula_flashcards` | `aula_id → aulas.id` | — | Flashcards |
| `c9_aula_quizzes` | `aula_id → aulas.id` | — | Quizzes |

### 2.5 `aulas` NAO tem coluna `ativo`

A tabela `aulas` nao possui coluna `ativo`. O conceito de "aula ativa" e derivado do modulo:

```sql
-- modulos tem ativo boolean DEFAULT true (dump ln 10613)
-- Views como vw_recruta_module_progress_v2 filtram COALESCE(m.ativo, true) = true
```

Implicacao: uma aula "inativa" nao existe no schema — o que existe sao aulas de modulos inativos.
Se `modulos.ativo = false`, o modulo inteiro (e suas aulas) e omitido das views canonicas.

### 2.6 Pipeline de conteudo AI e xp_valor

O banco possui um pipeline de geracao de conteudo (`aula_pipeline_execucoes`) com 6 agentes:
`AuditorConteudo`, `ComplementadorTecnico`, `Roteirista`, `EditorTextoComplementar`,
`DesignerQuiz`, `RevisorInstitucional`.

**O pipeline NAO inclui `xp_valor` no DDL de saida** — nenhuma coluna de output do pipeline
aponta para `aulas.xp_valor`. Isso sugere que `xp_valor` e definido manualmente por admin
ou via seeding, nao pelo pipeline AI. Isso e um sinal de alerta: se aulas foram criadas
via pipeline sem definir `xp_valor`, elas terao `xp_valor = 0` (DEFAULT).

---

## 3. Queries de Distribuicao de xp_valor

Executar no Supabase SQL Editor como `service_role` ou `postgres`.

---

### Q-01 — Visao geral: distribuicao completa de xp_valor

```sql
-- Q-01: Distribuicao geral de xp_valor
SELECT
    COUNT(*)                                                AS total_aulas,
    COUNT(*) FILTER (WHERE a.xp_valor = 0)                  AS aulas_xp_zero,
    COUNT(*) FILTER (WHERE a.xp_valor > 0)                  AS aulas_xp_positivo,
    COUNT(*) FILTER (WHERE a.xp_valor < 0)                  AS aulas_xp_negativo,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE a.xp_valor = 0) / NULLIF(COUNT(*), 0),
    1)                                                      AS pct_xp_zero,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE a.xp_valor > 0) / NULLIF(COUNT(*), 0),
    1)                                                      AS pct_xp_positivo,
    MIN(a.xp_valor)                                         AS xp_minimo,
    MAX(a.xp_valor)                                         AS xp_maximo,
    ROUND(AVG(a.xp_valor), 1)                               AS xp_medio_geral,
    ROUND(AVG(a.xp_valor) FILTER (WHERE a.xp_valor > 0), 1) AS xp_medio_positivos
FROM public.aulas a;
```

**O que este resultado significa:**

| pct_xp_zero | Interpretacao |
|-------------|--------------|
| <= 5% | Excelente — xp_valor esta bem populado |
| 6%–20% | Aceitavel — algumas aulas sem XP (possivelmente informacionais) |
| 21%–50% | Atencao — curadoria parcial necessaria antes da migracao |
| > 50% | BLOQUEANTE — a maioria das aulas nao tem XP definido |

---

### Q-02 — Distribuicao de xp_valor por modulo

```sql
-- Q-02: xp_valor agrupado por modulo
SELECT
    m.titulo                                                AS modulo,
    m.forca,
    m.ativo,
    COUNT(a.id)                                             AS total_aulas,
    COUNT(a.id) FILTER (WHERE a.xp_valor = 0)              AS aulas_xp_zero,
    COUNT(a.id) FILTER (WHERE a.xp_valor > 0)              AS aulas_xp_positivo,
    MIN(a.xp_valor)                                         AS xp_minimo,
    MAX(a.xp_valor)                                         AS xp_maximo,
    ROUND(AVG(a.xp_valor), 1)                               AS xp_medio
FROM public.modulos m
LEFT JOIN public.aulas a ON a.modulo_id = m.id
GROUP BY m.id, m.titulo, m.forca, m.ativo
ORDER BY m.forca, m.titulo;
```

**O que observar:**
- Modulos com `ativo = false`: suas aulas nao aparecem no app — xp_valor pode ser ignorado
- Modulos com todos `xp_zero = total_aulas`: modulo inteiro sem XP definido — curadoria urgente
- Valores inconsistentes entre aulas do mesmo modulo (ex: algumas 50, outras 100) — verificar intencao

---

### Q-03 — Lista das aulas com xp_valor = 0

```sql
-- Q-03: Todas as aulas sem XP definido
SELECT
    a.id            AS aula_id,
    a.titulo        AS titulo_aula,
    a.ordem,
    a.xp_valor,
    m.titulo        AS modulo,
    m.forca,
    m.ativo         AS modulo_ativo,
    a.created_at
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id
WHERE a.xp_valor = 0
ORDER BY m.forca, m.titulo, a.ordem;
```

**Acao esperada:** Revisar cada linha com a equipe de produto:
- E uma aula informacional/introducao (zero XP e intencional)?
- E uma aula que deveria ter XP mas nao foi configurada?

---

### Q-04 — Frequencia dos valores de xp_valor

```sql
-- Q-04: Histograma de valores distintos de xp_valor
SELECT
    a.xp_valor,
    COUNT(*) AS total_aulas
FROM public.aulas a
GROUP BY a.xp_valor
ORDER BY a.xp_valor;
```

**O que observar:**
- Se todos os valores sao 0 ou 50: xp_valor nao foi curado individualmente por aula
- Se ha variedade (30, 50, 75, 100): curadoria foi feita, e a distribuicao intencional
- Se ha valores negativos: BUG de dados — exige correcao antes da migracao

---

### Q-05 — Aulas com xp_valor negativo (anomalia grave)

```sql
-- Q-05: Verificar se existe xp_valor < 0 (dado invalido)
SELECT
    a.id,
    a.titulo,
    a.xp_valor,
    m.titulo AS modulo
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id
WHERE a.xp_valor < 0;
```

**Esperado:** zero linhas. Se retornar linhas — BLOQUEANTE. Exige correcao de dados antes da migracao.

---

## 4. Queries de Aulas Orfas e Modulos Inativos

---

### Q-06 — Aulas de modulos inativos (nao exibidas no app)

```sql
-- Q-06: Aulas cujo modulo esta inativo (ativo = false)
SELECT
    m.titulo    AS modulo,
    m.forca,
    m.ativo,
    COUNT(a.id) AS total_aulas,
    COUNT(a.id) FILTER (WHERE a.xp_valor = 0) AS aulas_xp_zero
FROM public.modulos m
JOIN public.aulas a ON a.modulo_id = m.id
WHERE m.ativo = false
GROUP BY m.id, m.titulo, m.forca, m.ativo
ORDER BY m.forca, m.titulo;
```

**O que fazer com esses resultados:** Aulas de modulos inativos nao aparecem no frontend.
Seu `xp_valor` nao afeta recrutas ativos. Podem ser ignoradas para fins desta auditoria,
mas devem ser consideradas se o modulo for reativado no futuro.

---

### Q-07 — Verificar se modulos sem aulas existem (modulos vazios)

```sql
-- Q-07: Modulos ativos sem nenhuma aula
SELECT
    m.id,
    m.titulo,
    m.forca,
    m.ativo
FROM public.modulos m
LEFT JOIN public.aulas a ON a.modulo_id = m.id
WHERE a.id IS NULL
  AND COALESCE(m.ativo, true) = true
ORDER BY m.forca, m.titulo;
```

**Esperado:** zero ou poucos. Se existir: modulo ativo sem conteudo — nao afeta auditoria de xp_valor.

---

### Q-08 — Aulas duplicadas por ordem dentro do mesmo modulo

```sql
-- Q-08: Verificar se ha duas aulas com a mesma ordem no mesmo modulo
-- (nao ha UNIQUE constraint — e possivel mas inconsistente)
SELECT
    a.modulo_id,
    m.titulo    AS modulo,
    a.ordem,
    COUNT(*)    AS qtd_aulas_mesma_ordem
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id
GROUP BY a.modulo_id, m.titulo, a.ordem
HAVING COUNT(*) > 1
ORDER BY m.titulo, a.ordem;
```

**Esperado:** zero linhas. Se retornar: inconsistencia de dados — pode causar comportamento
inesperado na exibicao de aulas mas nao bloqueia diretamente o refactor de XP.

---

## 5. Queries de Consistencia com Progresso Existente

---

### Q-09 — Comparar XP historico (quantidade=50) com xp_valor atual das aulas

```sql
-- Q-09: Para aulas ja concluidas, quanto seria a diferenca de XP com a nova logica?
SELECT
    a.titulo        AS titulo_aula,
    a.xp_valor      AS xp_valor_atual,
    COUNT(rp.id)    AS total_conclusoes,
    SUM(rp.xp_granted) AS xp_historico_concedido,  -- sempre 50 hoje
    SUM(a.xp_valor)    AS xp_que_seria_concedido,   -- com nova logica
    SUM(a.xp_valor) - SUM(rp.xp_granted) AS delta_xp_total
FROM public.aulas a
JOIN public.recruta_progresso rp ON rp.lesson_id = a.id
    AND rp.status = 'completed'
    AND rp.completed_at IS NOT NULL
GROUP BY a.id, a.titulo, a.xp_valor
ORDER BY delta_xp_total DESC
LIMIT 20;
```

**O que este resultado mostra:**
- `delta_xp_total` positivo: a nova logica daria mais XP do que foi concedido historicamente
- `delta_xp_total` negativo: a nova logica daria menos XP
- `delta_xp_total = 0`: `xp_valor = 50` — alinhado com o valor atual

> **IMPORTANTE:** A nova RPC afeta APENAS novas conclusoes. Registros historicos
> em `xp_eventos` e `recruta_progresso` NAO sao retroativamente alterados.
> Este query e apenas para entender o impacto operacional futuro.

---

### Q-10 — Recrutas que teriam impacto no ranking com a mudanca

```sql
-- Q-10: Estimar impacto no ranking de novos recrutas (aulas ainda nao concluidas)
-- Mostra quantas aulas ativas com xp_valor != 50 ainda existem por concluir
SELECT
    a.xp_valor,
    COUNT(a.id) AS total_aulas_nao_concluidas_tipicamente
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id
WHERE COALESCE(m.ativo, true) = true
  AND a.xp_valor != 50
GROUP BY a.xp_valor
ORDER BY a.xp_valor;
```

**O que observar:** Se a maioria das aulas ativas tem `xp_valor != 50`, a transicao
tem impacto relevante no XP total que novos recrutas ganharao por conclusao de aulas.

---

### Q-11 — Aulas concluidas que teriam XP = 0 com nova logica

```sql
-- Q-11: Aulas com xp_valor = 0 que JA foram concluidas por recrutas
-- Essas aulas dariam 0 XP com a nova RPC, diferente dos 50 atuais
SELECT
    a.id       AS aula_id,
    a.titulo   AS titulo_aula,
    a.xp_valor,
    m.titulo   AS modulo,
    COUNT(rp.id) AS total_conclusoes
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id
JOIN public.recruta_progresso rp ON rp.lesson_id = a.id
    AND rp.status = 'completed'
    AND rp.completed_at IS NOT NULL
WHERE a.xp_valor = 0
GROUP BY a.id, a.titulo, a.xp_valor, m.titulo
ORDER BY total_conclusoes DESC;
```

**O que observar:**
- Se zero linhas: nenhuma aula xp_valor=0 foi concluida — impacto futuro apenas
- Se existir linhas: essas aulas foram concluidas e renderam 50 XP historicamente.
  Novas conclusoes (de recrutas diferentes) renderiam 0 XP — inconsistencia de XP por aula
  dependendo de quando o recruta completou

---

## 6. Queries de Contexto do Sistema Legado

---

### Q-12 — xp_valor no sistema legado (fn_conceder_xp_aula)

```sql
-- Q-12: Verificar como o legado usava xp_valor (aulas_concluidas)
-- Compara xp_valor da aula com o que foi concedido via trigger legado
SELECT
    a.titulo                AS titulo_aula,
    a.xp_valor              AS xp_valor_atual,
    COUNT(ac.id)            AS total_conclusoes_legado,
    MIN(ac.data_conclusao)  AS primeira_conclusao,
    MAX(ac.data_conclusao)  AS ultima_conclusao
FROM public.aulas a
LEFT JOIN public.aulas_concluidas ac ON ac.aula_id = a.id
WHERE ac.id IS NOT NULL
GROUP BY a.id, a.titulo, a.xp_valor
ORDER BY total_conclusoes_legado DESC
LIMIT 20;
```

**O que observar:**
- Aulas com muitas conclusoes via legado E `xp_valor > 0`: bom sinal — xp_valor foi usado
- Aulas com conclusoes via legado E `xp_valor = 0`: o legado NAO concedeu XP para essas
  (o trigger fn_conceder_xp_aula retorna sem XP quando xp_valor <= 0)

---

### Q-13 — Consistencia entre sistemas de progresso

```sql
-- Q-13: Aulas que aparecem em recruta_progresso mas NAO em aulas_concluidas
-- (recrutas que completaram via RPC RCC, nao pelo sistema legado)
SELECT
    COUNT(DISTINCT rp.lesson_id) AS aulas_com_progresso_rcc_only
FROM public.recruta_progresso rp
WHERE rp.status = 'completed'
  AND NOT EXISTS (
      SELECT 1 FROM public.aulas_concluidas ac
      WHERE ac.aula_id = rp.lesson_id
  );
```

**O que observar:** Um numero alto indica que a maioria das conclusoes ja passa pelo
sistema RCC (complete_lesson), nao pelo legado — confirmando a relevancia da migracao.

---

## 7. Analise de Risco de xp_valor = 0

### 7.1 Origem provavel de xp_valor = 0

Com base na analise do DDL e do pipeline de conteudo:

| Causa | Probabilidade | Impacto |
|-------|--------------|---------|
| DEFAULT nao sobrescrito na criacao da aula | ALTA | Aula sem XP definido — curadoria necessaria |
| Aula criada via pipeline AI sem campo xp_valor | ALTA | Pipeline nao define XP — valor permanece 0 |
| Aula intencional sem XP (introdutoria, informacional) | MEDIA | Comportamento esperado — deve ser documentado |
| Erro de dados (atualizacao falhou) | BAIXA | Exige investigacao pontual |

### 7.2 O que acontece hoje com xp_valor = 0

O sistema legado (`fn_conceder_xp_aula`) trata `xp_valor = 0` corretamente:
```sql
IF v_xp IS NULL OR v_xp <= 0 THEN RETURN new; END IF;  -- nao concede XP
```
Ou seja: o legado **silenciosamente nao concede XP** para aulas com xp_valor = 0.

**O `complete_lesson` atual ignora xp_valor** e concede 50 XP para toda aula, inclusive
as que tem `xp_valor = 0`. Isso significa que **hoje aulas com xp_valor = 0 rendem 50 XP**
via complete_lesson — comportamento que a nova RPC mudaria.

### 7.3 Impacto esperado por faixa de xp_valor

| Cenario | xp_valor | XP hoje (complete_lesson) | XP com nova RPC | Diferenca para recruta |
|---------|----------|---------------------------|-----------------|------------------------|
| Aula informacional | 0 | 50 | 0 | **Perde 50 XP** |
| Aula padrao legado | 50 | 50 | 50 | Sem mudanca |
| Aula basica | 30 | 50 | 30 | Perde 20 XP |
| Aula avancada | 75 | 50 | 75 | Ganha 25 XP |
| Aula especial | 100 | 50 | 100 | Ganha 50 XP |

**Conclusao:** Recrutas que concluirem aulas com `xp_valor = 0` apos a migracao
ganharao 0 XP — impacto negativo perceptivel se a tela de conclusao nao comunicar
o valor de XP esperado.

---

## 8. Criterios de Recomendacao

A recomendacao final depende dos resultados das queries. Use a tabela abaixo:

### 8.1 Arvore de decisao

```
Q-01: pct_xp_zero = ?
├─ <= 5%
│    └─ Q-05: algum xp_valor < 0?
│         ├─ SIM → BLOQUEAR (corrigir dados antes)
│         └─ NAO → RECOMENDACAO A: USAR aulas.xp_valor agora
│
├─ 6%–20%
│    └─ Q-03: aulas xp_valor=0 sao intencionais (introdutorias)?
│         ├─ SIM (documentadas pela equipe de produto)
│         │    └─ RECOMENDACAO A: USAR aulas.xp_valor agora
│         │         (com observacao: aulas introdutorias tem xp=0 por design)
│         └─ NAO (nao documentadas / desconhecidas)
│              └─ RECOMENDACAO B: USAR fallback 50 quando xp_valor = 0
│
├─ 21%–50%
│    └─ Q-11: aulas xp_valor=0 ja foram concluidas?
│         ├─ SIM (muitas conclusoes afetadas)
│         │    └─ RECOMENDACAO B: USAR fallback 50 quando xp_valor = 0
│         │         (ate curadoria completa — Sprint 2 com fallback, curadoria paralela)
│         └─ NAO (aulas xp_valor=0 ainda nao concluidas)
│              └─ RECOMENDACAO C: BLOQUEAR ate curadoria parcial
│                   (priorizar as aulas ativas que serao concluidas em breve)
│
└─ > 50%
     └─ RECOMENDACAO C: BLOQUEAR migracao ate curadoria dos valores
          (a maioria das aulas nao tem XP definido — nao e seguro migrar)
```

---

### 8.2 Descricao das recomendacoes

#### RECOMENDACAO A — USAR aulas.xp_valor agora

**Criterio:** `xp_valor = 0` em <= 5% das aulas E sem `xp_valor < 0`.

**O que significa para P1-M1:**
- `rpc_complete_lesson` usa `xp_valor` diretamente sem fallback
- Se `xp_valor = 0`, a funcao concede 0 XP (comportamento explicito e intencional)
- Aulas introdutorias/informacionais foram curadas para `xp_valor = 0`
- Fase 0 APROVADA — pode seguir para Fase 1

**Codigo de sinalizacao no Relatorio:** `A - APROVADO`

---

#### RECOMENDACAO B — USAR fallback 50 quando xp_valor = 0

**Criterio:** `xp_valor = 0` em 6%–50% das aulas E curadoria em andamento.

**O que significa para P1-M1:**
- `rpc_complete_lesson` usa `COALESCE(xp_valor, 0)` mas com logica:
  - Se `xp_valor > 0`: usa o valor institucional
  - Se `xp_valor = 0`: usa fallback configuravel (ex: 50 como valor legado)
- A especificacao de rpc_complete_lesson precisa ser atualizada para incluir o fallback
- Equipe de produto cura `xp_valor` em paralelo com o Sprint 2
- Ao atingir <= 5% de aulas xp_valor=0, rollback do fallback para Recomendacao A em Sprint 3

**Alteracao necessaria na spec de rpc_complete_lesson:**
```sql
-- Pseudocodigo (NAO e migration — apenas planejamento)
-- Na nova funcao:
SELECT COALESCE(NULLIF(xp_valor, 0), 50) AS xp_efetivo
FROM aulas WHERE id = p_lesson_id;
-- Se xp_valor = 0: usa 50 (compativel com historico)
-- Se xp_valor > 0: usa o valor institucional
```

**Codigo de sinalizacao no Relatorio:** `B - APROVADO COM FALLBACK`

---

#### RECOMENDACAO C — BLOQUEAR migracao ate curadoria dos valores

**Criterio:** `xp_valor = 0` em > 50% das aulas OU `xp_valor < 0` em qualquer aula.

**O que significa para P1-M1:**
- Fase 0 REPROVADA — Fase 1 nao pode comecar
- Acao bloqueante: equipe de produto deve curar `xp_valor` para todas as aulas ativas
- Estimativa de esforco: depende do total de aulas (ver Q-01 e Q-02)
- Recomenda-se criar uma planilha a partir de Q-03 para curadoria em lote
- Re-executar esta auditoria apos curadoria

**Codigo de sinalizacao no Relatorio:** `C - BLOQUEADO`

---

## 9. Relatorio de Execucao

**Preencher apos executar as queries no Supabase SQL Editor.**

### 9.1 Identificacao

| Campo | Valor |
|-------|-------|
| Data de execucao | |
| Operador | |
| Ambiente (staging / producao) | |
| Versao PostgreSQL | |

---

### 9.2 Resultados de Q-01 — Distribuicao geral

| Metrica | Valor obtido |
|---------|-------------|
| total_aulas | |
| aulas_xp_zero | |
| aulas_xp_positivo | |
| aulas_xp_negativo | |
| pct_xp_zero (%) | |
| pct_xp_positivo (%) | |
| xp_minimo | |
| xp_maximo | |
| xp_medio_geral | |
| xp_medio_positivos | |

---

### 9.3 Resultados de Q-04 — Frequencia de valores

| xp_valor | total_aulas |
|----------|-------------|
| (preencher linhas do resultado) | |

---

### 9.4 Resultados de Q-05 — xp_valor negativo

| Resultado | |
|-----------|--|
| Linhas retornadas? | SIM / NAO |
| Se SIM: listar aulas | |

---

### 9.5 Resultados de Q-11 — Aulas xp_valor=0 ja concluidas

| Metrica | Valor obtido |
|---------|-------------|
| Linhas retornadas? | SIM / NAO |
| Total de aulas xp_valor=0 ja concluidas | |
| Total de conclusoes afetadas | |

---

### 9.6 Avaliacao da curadoria

```
[ ] As aulas com xp_valor = 0 sao introdutorias/informacionais intencionalmente?
    Sim / Nao / Parcialmente — Detalhe: ___________________________

[ ] Ha consenso da equipe de produto sobre o valor de XP esperado por aula?
    Sim / Nao — Acao: ___________________________

[ ] O pipeline AI define xp_valor durante criacao de aulas?
    Sim / Nao — Se Nao: processo manual necessario para aulas futuras
```

---

### 9.7 Veredicto Final

```
Resultado de pct_xp_zero: _______ %
Resultado de xp_valor < 0: SIM / NAO

[ ] RECOMENDACAO A — USAR aulas.xp_valor agora
    (pct_xp_zero <= 5% E sem negativos)

[ ] RECOMENDACAO B — USAR fallback 50 quando xp_valor = 0
    (pct_xp_zero entre 6%–50% E curadoria em andamento)
    Observacao: exige atualizacao da spec de rpc_complete_lesson

[ ] RECOMENDACAO C — BLOQUEAR migracao ate curadoria
    (pct_xp_zero > 50% OU xp_valor < 0 encontrado)
    Acao bloqueante: ___________________________
    Prazo estimado para curadoria: ___________________________
```

---

### 9.8 Impacto esperado no ranking (resumo)

```
Aulas com xp_valor = 50:  _______ (sem impacto para recrutas)
Aulas com xp_valor > 50:  _______ (recrutas ganham mais XP por aula)
Aulas com xp_valor < 50 e > 0: _______ (recrutas ganham menos XP por aula)
Aulas com xp_valor = 0:   _______ (recrutas ganham 0 XP por aula — ou 50 com fallback B)
```

---

### 9.9 Proximos Passos por Recomendacao

**Se RECOMENDACAO A:**
```
[ ] Comunicar equipe de produto: a nova RPC usa xp_valor institucional
[ ] Confirmar que aulas xp_valor=0 sao intencionais e documentadas
[ ] Fase 0 APROVADA → Fase 1 pode comecar (criar rpc_complete_lesson)
[ ] Responsavel pela Fase 1: ___________________________
[ ] Data alvo para Fase 1: ___________________________
```

**Se RECOMENDACAO B:**
```
[ ] Atualizar P1_M1_COMPLETE_LESSON_XP_REFACTOR.md: documentar fallback COALESCE(NULLIF(xp_valor, 0), 50)
[ ] Fase 0 APROVADA COM CONDICAO → Fase 1 pode comecar com spec atualizada
[ ] Curadoria de xp_valor em paralelo com Sprint 2 (objetivo: atingir < 5% de xp_valor=0)
[ ] Agendar re-auditoria apos curadoria para remover fallback em Sprint 3
[ ] Responsavel pela curadoria: ___________________________
[ ] Data alvo para curadoria: ___________________________
```

**Se RECOMENDACAO C:**
```
[ ] Fase 0 REPROVADA → Fase 1 BLOQUEADA
[ ] Exportar lista Q-03 para planilha de curadoria (equipe de produto)
[ ] Agendar re-execucao desta auditoria apos curadoria
[ ] Responsavel pela curadoria: ___________________________
[ ] Prazo estimado: ___________________________
[ ] Data de re-auditoria: ___________________________
```

---

### 9.10 Assinaturas

| Papel | Nome | Data |
|-------|------|------|
| Operador das queries | | |
| Validacao de produto (xp_valor intencional) | | |
| Responsavel tecnico P1-M1 | | |

---

## Apendice — Resumo das Queries por Secao

| ID | Query | Proposito | Bloqueante? |
|----|-------|-----------|-------------|
| Q-01 | Distribuicao geral | Metrica principal de decisao | SIM |
| Q-02 | Por modulo | Identificar modulos sem curadoria | Nao |
| Q-03 | Aulas xp_valor=0 | Lista para curadoria | Se C |
| Q-04 | Histograma | Ver variedade de valores | Nao |
| Q-05 | xp_valor negativo | Anomalia de dados | SIM |
| Q-06 | Modulos inativos | Escopo do impacto real | Nao |
| Q-07 | Modulos vazios | Saude geral dos dados | Nao |
| Q-08 | Ordem duplicada | Consistencia estrutural | Nao |
| Q-09 | Delta XP historico | Impacto em dados existentes | Nao |
| Q-10 | Impacto em ranking | Estimativa de impacto futuro | Nao |
| Q-11 | xp_valor=0 ja concluidas | Recrutas afetados | SIM |
| Q-12 | Legado (xp_valor usado) | Validacao de curadoria anterior | Nao |
| Q-13 | RCC vs legado | Confirmar primazia do RCC | Nao |

**Queries obrigatorias para decisao:** Q-01, Q-04, Q-05, Q-11
**Queries recomendadas:** Q-02, Q-03, Q-06, Q-09
**Queries opcionais:** Q-07, Q-08, Q-10, Q-12, Q-13

---

*Documento gerado em 2026-05-17.*
*Predecessor: supabase/baseline/P1_M1_COMPLETE_LESSON_XP_REFACTOR.md*
*Successores: P1_M1_TRANSITION_PLAN.md Fase 1 (bloqueada ate aprovacao desta auditoria)*
