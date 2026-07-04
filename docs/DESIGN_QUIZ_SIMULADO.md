# Design — Quiz (por lição) + Simulado (por módulo) + Conteúdo placeholder 3 forças

> **PROPOSTA para revisão. Nada implementado além da migration de reconciliação `20260704002000` (A-18).**
> Data: 2026-07-04. Decisões de produto já dadas: simulado first-class; anti-farming = 1ª tentativa; valores de XP calibrados abaixo.

## 0. Princípio: reusar C9, não reinventar
A camada **C9** já modela quiz por aula (perguntas/alternativas/tentativas + views seguras + RLS). O design **estende** C9; não cria tabelas paralelas. Schema real de referência: `supabase/remote/supabase_remote_schema.sql` (pós-A-18).

## 1. Requisito não-negociável: identificação estruturada de placeholder
Toda linha placeholder ganha **`is_placeholder boolean NOT NULL DEFAULT false`** (coluna, não prefixo de texto), nas tabelas: `modulos`, `aulas`, `c9_aula_quizzes`, `c9_aula_quiz_perguntas`. (Alternativa `origem='PLACEHOLDER'` existe, mas `is_placeholder` dedicado é mais limpo para a query de auditoria.)

Isso habilita a **query única de "o que falta de conteúdo real"**:
```sql
SELECT 'modulo' t, id, titulo FROM modulos                WHERE is_placeholder
UNION ALL SELECT 'aula', id, titulo FROM aulas            WHERE is_placeholder
UNION ALL SELECT 'quiz', id, titulo FROM c9_aula_quizzes  WHERE is_placeholder
UNION ALL SELECT 'pergunta', id, enunciado FROM c9_aula_quiz_perguntas WHERE is_placeholder;
```
**Tie-in com A-17:** o `[QA] Módulo Teste` deve receber `is_placeholder=true` na mesma leva — passa a ser encontrável por essa query em vez de vazar silenciosamente.

## 2. Simulado first-class (decisão confirmada — Opção 2)
Alterações em `c9_aula_quizzes` para suportar quiz-de-aula **e** simulado-de-módulo na mesma tabela:
- `aula_id` → **nullable** (era NOT NULL).
- **+`modulo_id uuid REFERENCES modulos(id) ON DELETE CASCADE`** (nullable).
- **+`escopo text NOT NULL DEFAULT 'quiz_aula'`** CHECK `('quiz_aula','simulado_modulo')`.
- **+`is_placeholder boolean NOT NULL DEFAULT false`**.
- CHECK: `(escopo='quiz_aula' AND aula_id IS NOT NULL AND modulo_id IS NULL) OR (escopo='simulado_modulo' AND modulo_id IS NOT NULL AND aula_id IS NULL)` (exatamente um dos dois).
- Índice único "1 ativo por aula" já existe; **adicionar** "1 simulado ativo por módulo" (`UNIQUE (modulo_id) WHERE escopo='simulado_modulo' AND ativo AND deleted_at IS NULL`).

`c9_aula_quiz_perguntas`, `c9_aula_quiz_alternativas`, `c9_aula_quiz_tentativas` **não mudam de estrutura** — `tentativas.quiz_id` referencia a mesma tabela, então tentativa/resultado/XP funcionam idênticos para quiz e simulado. (`v_c9_quiz_execucao`/`resultado` também servem os dois de graça.)

## 3. XP — proposta calibrada (âncoras reais do banco)
Valores existentes hoje:
- **Lição:** `rpc_complete_lesson` concede `aulas.xp_valor` (idempotente por lição; anchor legado = **50**). *(distribuição real de `xp_valor` não lida — `aulas` nega SELECT a authenticated; a confirmar.)*
- **Simulado (convenção pré-existente):** `conceder_xp_simulado` = base **40** + bônus **≥90%→60 / ≥80%→40 / ≥70%→20**, idempotente por simulado (`tipo='simulado_concluido'`). Máx **100**.

**Proposta (mantém a lição como fonte principal; simulado > quiz):**

| Ação | XP base | Bônus por desempenho | Máx | Idempotência |
|---|---|---|---|---|
| **Quiz de lição** | 0 | ≥90%→20 · ≥80%→12 · ≥70%→6 | **20** | 1ª tentativa/quiz/recruta |
| **Simulado de módulo** | 40 | ≥90%→60 · ≥80%→40 · ≥70%→20 | **100** | 1ª tentativa/simulado/recruta |

Racional: quiz (≤20) < lição (~50) < simulado (≤100). O simulado **reusa a escala** do `conceder_xp_simulado` já existente (coerência). Quiz é ~⅓, para não desvalorizar o conteúdo.

**Grant via RPC único** `rpc_c9_submit_attempt(p_quiz_id, p_respostas jsonb)` `SECURITY DEFINER`:
1. Avalia acertos **server-side** (gabarito nunca sai do banco).
2. Insere `c9_aula_quiz_tentativas` (respostas, total_perguntas, total_acertos, percentual).
3. **XP só na 1ª tentativa** daquele `quiz_id`+recruta: `IF NOT EXISTS (SELECT 1 FROM c9_aula_quiz_tentativas WHERE quiz_id=? AND recruta_id=auth.uid())` **antes** de inserir a tentativa → concede; senão registra a tentativa sem XP. Grava XP no ledger canônico (`xp_eventos`/`xp_events`) com `tipo` = `quiz_aula_concluido` / `simulado_modulo_concluido` e `referencia`=quiz_id (rastreável, sem farm).

## 4. Placeholder de módulos/lições — Exército & Aeronáutica
Espelhar a estrutura Marinha (10 módulos reais), nomes adaptados por força. Densidade proposta (**recomendada**): **10 módulos × 5 lições = 50 lições/força**. Todos `is_placeholder=true`, `ativo=true`, `is_degustacao=false` (exceto 1 módulo degustação/força, espelhando Marinha). Lições placeholder com `xp_valor=0` (não dão XP até virarem reais).

## 5. Geração de conteúdo placeholder — quiz/simulado nas 3 forças
- **1 quiz por lição** (inclui as **49 lições reais da Marinha**, que hoje não têm quiz — o quiz é placeholder mesmo com lição real).
- **1 simulado por módulo**.
- Perguntas placeholder: `enunciado = "Pergunta de exemplo N — [título da lição/módulo]"`, 4 alternativas dummy (`correta` na 1ª), `explicacao` genérica. Tudo `is_placeholder=true`.
- Densidade proposta: **3 perguntas/quiz de lição**, **5 perguntas/simulado**.

## 6. Estimativa de linhas (na densidade recomendada)

| Entidade | Contagem | Cálculo |
|---|---|---|
| `modulos` (novos Ex+Aero) | **+20** | 10×2 |
| `aulas` (novas Ex+Aero) | **+100** | 50×2 |
| Lições totais c/ quiz | 149 | Mar 49 + Ex 50 + Aero 50 |
| `c9_aula_quizzes` (quiz de lição) | **149** | 1/lição |
| `c9_aula_quizzes` (simulado de módulo) | **31** | Mar 11 + Ex 10 + Aero 10 |
| `c9_aula_quiz_perguntas` | **602** | 149×3 + 31×5 |
| `c9_aula_quiz_alternativas` | **2 408** | 602×4 |
| **TOTAL aproximado** | **~3 310 linhas** | |

Fórmula p/ recalibrar: `perguntas = lições×Q_lição + módulos×Q_simulado`; `alternativas = perguntas×4`. Se quiser mais leve (ex.: Ex/Aero 10 mód × 3 lições = 30 lições/força; 2 perguntas/quiz), cai para **~1 500 linhas**.

## 7. Navegação (proposta)
- **Quiz**: CTA opcional **ao final da lição**, pós-conteúdo. **Não bloqueia `complete_lesson`** (sem gating) — é bônus de XP. Nova tela `quiz/[quizId]` ou seção embutida no `lesson/[id]`.
- **Simulado**: **tela própria por módulo**, CTA no `module/[id]` (e/ou na tab de módulos). Tela `simulado/[moduloId]`.

## 8. O que falta decidir / confirmar antes de implementar
1. **Densidade** (seção 4/6): recomendada (~3 310 linhas) vs leve (~1 500)? Quantos módulos/lições por força de Exército/Aeronáutica?
2. **`xp_valor` real das lições** Marinha (não lido — `aulas` RLS). Confirmar se o anchor de 50 procede ou se varia por lição.
3. **Reaproveitar `conceder_xp_simulado`** (que usa `xp_events`+`p_simulado_id text`) ou criar o `rpc_c9_submit_attempt` novo unificado (recomendado, pois integra tentativa+avaliação+XP no modelo C9)?
4. Nomes/estrutura dos módulos placeholder de Ex/Aero (espelhar Marinha 1:1 ou lista adaptada?).

## 9. Ordem de implementação proposta (pós-aprovação)
1. Migration: `is_placeholder` nas 4 tabelas + alterações de simulado first-class em `c9_aula_quizzes` (+índice) — **versionada**.
2. RPC `rpc_c9_submit_attempt` (avaliação + XP 1ª-tentativa) — **versionada**.
3. Seed placeholder (mass insert) — **script versionado**, revisável, com `is_placeholder=true`.
4. UI: tela de quiz (fim da lição) + tela de simulado (por módulo).
5. Grants nas views c9 a `authenticated` (checar, padrão A-15).
