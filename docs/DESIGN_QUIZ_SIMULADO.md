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

Racional: quiz (≤20) < lição (~50) < simulado (≤100). Os **valores** (base 40 + 20/40/60) e o **cap diário de 200 XP** vêm do `conceder_xp_simulado` — mas **só os valores**, não o encanamento (ver ⚠️ abaixo). Quiz é ~⅓, para não desvalorizar o conteúdo.

> ⚠️ **Correção pós-A-20:** `conceder_xp_simulado` **NÃO deve ser reaproveitada** — ela é uma RPC órfã que grava num subsistema de XP **legado** (`xp_events`/`user_xp`), distinto do `xp_eventos` canônico do `rpc_complete_lesson`. Reusá-la gravaria XP na ledger errada. O RPC novo deve escrever no **mesmo ledger que o `rpc_complete_lesson`** para consistência.

**Grant via RPC único** `rpc_c9_submit_attempt(p_quiz_id, p_respostas jsonb)` `SECURITY DEFINER`:
1. Avalia acertos **server-side** (gabarito nunca sai do banco).
2. Insere `c9_aula_quiz_tentativas` (respostas, total_perguntas, total_acertos, percentual).
3. **XP só na 1ª tentativa** daquele `quiz_id`+recruta: `IF NOT EXISTS (SELECT 1 FROM c9_aula_quiz_tentativas WHERE quiz_id=? AND recruta_id=auth.uid())` **antes** de inserir a tentativa → concede; senão registra a tentativa sem XP.
4. **Ledger de destino RESOLVIDO (A-20): `xp_eventos`.** É a ledger canônica que o ranking lê (`mv_xp_mensal_recruta = SUM(quantidade) FROM xp_eventos` → todo o ranking) e onde o `rpc_complete_lesson` grava. O RPC insere em **`xp_eventos`** (`quantidade`, `forca` — resolver do recruta p/ o CHECK, `tipo` = `quiz_aula_concluido`/`simulado_modulo_concluido`, `referencia_id` = quiz_id). **NÃO** usar `xp_events`/`user_xp` (subsistema legado morto, invisível ao ranking). Respeitar cap diário (herdado do padrão 200/dia).
5. **Nota operacional:** ranking é MATERIALIZED — XP novo só aparece após REFRESH das MVs (sem schedule hoje). O RPC grava certo; a visibilidade no ranking depende do refresh (fora do escopo do RPC).

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
3. ~~Reaproveitar `conceder_xp_simulado`~~ → **RESOLVIDO (A-20): NÃO reaproveitar** (subsistema de XP legado). Criar `rpc_c9_submit_attempt` novo, escrevendo na ledger canônica.
4. ~~CRÍTICO: qual ledger o ranking lê?~~ → **RESOLVIDO (A-20): `xp_eventos`.** Bloqueio do RPC de XP removido.
5. Nomes/estrutura dos módulos placeholder de Ex/Aero (espelhar Marinha 1:1 ou lista adaptada?).

## 9. Status de implementação (backend — 2026-07-04)
1. ✅ **Schema** (`20260704003000`): `is_placeholder` em modulos/aulas/c9_aula_quizzes/c9_aula_quiz_perguntas; simulado first-class (`aula_id` nullable + `modulo_id` + `escopo` + CHECKs + índice 1-simulado/módulo); índice parcial `ux_xp_eventos_quiz_unique`.
2. ✅ **View de agregação + RPC** (`20260704004000` + fix `20260704006000`): `v_c9_simulado_execucao` (agrega perguntas das lições do módulo, esconde gabarito) e `rpc_c9_submit_attempt` (avalia server-side, tentativa, XP em `xp_eventos` só na 1ª tentativa).
3. ✅ **Seed** (`20260704005000`): esqueleto mínimo Ex/Aero — 4 módulos, 8 aulas, 8 quizzes, 4 simulados, 16 perguntas, 64 alternativas, tudo `is_placeholder=true`.
4. ✅ **UI** (2026-07-04): `src/services/quizService.ts` (fetch + submit), `src/hooks/useQuizExecucao.ts` (useLessonQuiz/useModuleSimulado), `src/components/quiz/QuizRunner.tsx` (responder+enviar+resultado, reutilizável), telas `app/(stack)/quiz/[aulaId].tsx` e `app/(stack)/simulado/[moduloId].tsx`. CTAs **condicionais** (só quando há quiz/simulado): botão "Testar conhecimento (+XP)" no rodapé da lição (não bloqueia `complete_lesson`) e "Fazer simulado do módulo (+XP)" no topo do detalhe do módulo. Rotas registradas em `(stack)/_layout.tsx`. A-22 corrigido nas 3 views antes da UI.

**Validação (read-only):** `v_c9_simulado_execucao` → 4 simulados × 4 perguntas; `v_c9_quiz_execucao` por aula → quiz com 2 perguntas × 4 alternativas; `correta` não vaza em nenhuma; `v_c9_quiz_resultado` escopada ao próprio recruta. Forma bate com o que o `QuizRunner` consome. `tsc --noEmit` limpo. **RPC de submissão NÃO exercitada ao vivo** (criaria tentativa+xp_eventos em prod não-limpáveis) — deploy + lógica verificados por leitura. **Teste end-to-end (responder de verdade → XP) será manual, feito por você no app** (login de teste), quando o dado de teste em prod é esperado.

**Descoberta durante a validação (A-22):** as views de execução C9 eram `security_invoker`, mas as tabelas `c9_*` têm RLS sem GRANT a `authenticated` — e **não devem** ganhar GRANT porque `c9_aula_quiz_alternativas.correta` é o gabarito. Padrão correto = view **`security definer`** (roda como owner, projeta sem `correta`), com GRANT só na view. Aplicado à `v_c9_simulado_execucao`. **Pendente (UI phase):** `v_c9_quiz_execucao`/`v_c9_quiz_resultado` (pré-existentes) têm o mesmo problema e precisam do mesmo tratamento antes da UI de quiz. Ver A-22.

**Pendências abertas do design:** `xp_valor` real das lições Marinha (§8.2, A-19 bloqueia leitura direta); força-filtering na leitura de simulado (UI); cap diário de XP (não implementado — decisão foi só "1ª tentativa").

## 10. Roteiro de teste manual (no app, login de teste)
O teste end-to-end (responder → creditar XP) é **manual**, feito no app — nunca por chamada isolada de agente (mesma cautela do A-17). A partir daqui o dado de teste em prod é esperado; você decide se limpa depois.

> ⚠️ **Nota (esperado NESTE teste, não é bug):** o usuário de teste é **Marinha**, mas o conteúdo placeholder de quiz/simulado só existe para **Exército/Aeronáutica**. Logo, durante este teste específico, um recruta Marinha verá/abrirá conteúdo de outra força para exercitar o pipeline. Isso é **intencional agora** — a filtragem por força na navegação de quiz/simulado é um refinamento de UI ainda pendente (ver "Pendências abertas"). Não confundir com bug.

**Passos:**
1. Login de teste no app.
2. Navegar até uma **lição placeholder** (Exército ou Aeronáutica) → botão **"Testar conhecimento (+XP)"** no rodapé → responder as 2 perguntas → **Enviar** → conferir o resultado (acertos/% + XP).
3. No **detalhe de um módulo placeholder** → botão **"Fazer simulado do módulo (+XP)"** → responder as 4 perguntas agregadas → conferir XP (maior que o quiz: base 40 + bônus).
4. **Anti-farm:** refazer o mesmo quiz/simulado → confirmar que a tentativa é registrada mas **não credita XP de novo** (retorno `primeira_tentativa=false`, `xp_concedido=0`).
5. **Ranking (A-21):** o XP grava em `xp_eventos` (visível no perfil/ledger), mas o **ranking só reflete após REFRESH das MVs** — que não tem schedule hoje. Então não estranhe se o ranking não mexer logo após o teste.

**Se algo falhar** (erro no envio, XP não credita, etc.): capturar o retorno JSON da RPC `rpc_c9_submit_attempt` (`ok`/`reason`/`percentual`/`xp_concedido`) e reportar — o diagnóstico parte daí.
