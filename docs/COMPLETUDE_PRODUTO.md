# Completude do Produto — quartel-digital-mobile

> Levantamento read-only do que **existe de fato** no app hoje, comparado ao modelo de produto das Seções 5/11/12 do master spec. Nenhum código foi alterado.
> Data: 2026-07-04 · Escopo: este repositório (app mobile). Item 10 (WhatsApp) vive em `recrutapadrao-checklist` — fora de escopo.

## Método e limitações
- **Código:** rotas (`app/`), telas (`src/screens`), hooks, services, Edge Functions — mapeados por leitura/grep.
- **Dados de conteúdo (contagens):** obtidos por **consulta REST read-only autenticada** com as credenciais de teste de `.env.test.local` (`userc@…`) — apenas `SELECT`, nada foi escrito. Anon é bloqueado por RLS.
- **Limitação:** algumas views retornaram `permission denied` mesmo autenticado (`v_modulos_catalogo`, `vw_recruta_module_progress_v2`) — números de módulos/lições vêm de `v_lessons_panel` (acessível). Contagens refletem o estado em 2026-07-04.

Legenda: ✅ completo e em uso · 🟡 schema/backend existe mas UI ausente ou incompleta · ⚪ não existe

---

## 1. Onboarding (Seção 5, item 1) — 🟡
- Captura **força** (`welcome.tsx`: marinha/exercito/aeronautica) ✅ e **nome de guerra** (`nome-guerra.tsx`) ✅.
- Escrita via `rpc_complete_onboarding(p_forca, p_nome_guerra)` (`onboardingService.ts`); grupo de rotas vivo confirmado no A-4.
- **Falta o "estágio atual"** (pré-incorporação / internato / formação / rotina) descrito no spec — **nenhuma tela ou campo** captura isso; a RPC não recebe estágio. → **Gap real vs spec.**

## 2. Conteúdo (item 2) — ✅ Marinha · ⚪ Exército/Aeronáutica
Dados reais (via `v_lessons_panel`, autenticado):
- **51 lições** em **13 módulos distintos**.
- Por força: **49 marinha · 1 exército · 1 aeronáutica** → conteúdo é **essencialmente Marinha**; Exército/Aeronáutica têm só 1 lição-stub cada.
- UI existe e consome: tab `modules` (renderiza de `src/constants/marinhaCurriculum` + `ModuleAccordion`), rotas `module/[id]`, `lesson/[id]`, `lessons_list`; hooks `useModuleLessons`, `useModulesProgress`, `useLessonData`, `useLessonMedia`.
- O próprio `chat-central` corrobora: `MATERIAL_SCOPE` marca `scope_is_real = (forca === "marinha")`; Exército/Aeronáutica são stubs.
- **Nota arquitetural:** a listagem de módulos na tab usa uma **constante local** (`MARINHA_CURRICULUM`) além do DB — vale reconciliar depois se constante e banco divergem.

## 3. Missões (item 3) — ⚪ (sistema não existe)
- **Não há sistema de missões diárias/desafios.** Grep: `desafio` 0, `streak` 0; nenhuma tela "minhas missões" consumindo `missoes`/`progresso_missoes`.
- O que existe: `atribuir_missao_inicial` (RPC backend — mas era chamada só pela `create-recruta`, já removida) e a rota `mission/concluida.tsx`, que é apenas a **animação de conclusão de lição** ("+XP adicionado ao perfil"), **não** um sistema de missões.
- `complete_lesson` existe e concede XP, mas isso é conclusão de lição, não missão. → **Sistema de missões/desafios: inexistente.**

## 4. Revisão (item 4) — 🟡 (existe, mas não é repetição espaçada)
- Rotas existem: tab `reviews`, `reviews/index`, `review/[id]`; hooks `useAvailableReviews`, `useReviewContent`, `useRevision`.
- **Mas o conteúdo é mídia de revisão `audio | video`** (`media_url`), **não** repetição espaçada nem flashcards (`flashcard` = 0 arquivos). `useRevision.ts` inclusive anota "RevisaoAudioScreen não está roteada".
- → Existe UI de "revisão por mídia", mas o mecanismo de **revisão espaçada/priorização por desempenho** do spec **não está implementado**.

## 5. Simulados e quizzes (item 5) — ⚪
- **Não existe.** `quiz` = 0 arquivos, `simulado` = só menção a "simulador/emulador" em `usePushToken`. Nenhuma tela ou lógica de quiz/feedback.

## 6. Ranking e mérito (item 6) — ✅
- **Ranking:** tab `ranking` consome `useRankingList(userForce)` (FlatList com posição/highlight). ✅
- **Área do campeão:** tab `champion` consome `useMonthlyChampion(userForce)`. ✅ (ver item 9)
- **Medalhas:** 3 medalhas definidas (`v_medals_status_v3` = 3); rota `medals/index`, hook `useMedals` (18 arquivos referenciam medal). ✅
- **XP:** `xpService`, `xp_events`/`registrar_xp`, `mission/concluida` exibe "+XP". ✅
- → Camada de mérito/gamificação **completa e em uso**.

## 7. Instrutor virtual (item 7) — ✅ Marinha · 🟡 cobertura de força
- Pipeline avançada (`instrutor-send` → `chat-central`): Responses API + SSE streaming (Wave 5f) + cache institucional (Wave 5g) + guard HMAC. ✅
- **3 instrutores** cadastrados (`v_instrutores_app` = 3).
- **Cobertura de força:** wired para as 3 forças, mas **só Marinha tem material real** (`MATERIAL_SCOPE`: exercito/aeronautica são stubs; `scope_is_real = marinha`). → funcional de fato só para Marinha.

## 8. Biblioteca (item 8) — ⚪
- **Não existe tela nem dados de biblioteca.** Única ocorrência: label `"BIBLIOTECA ESTRATÉGICA"` em `WebNavBar.tsx` (nav web), sem destino/conteúdo real.

## 9. Área do campeão (item 9) — ✅
- Tab `champion` (119 linhas) consome `useMonthlyChampion(userForce)`, exibindo o campeão do mês (war_name/nome). Integrada ao ranking. ✅

## 10. Notificações/WhatsApp (item 10) — fora de escopo
- WhatsApp/nutrição vive em `recrutapadrao-checklist`. *(Nota: push notifications do chat existem aqui — `usePushToken`, `chat-notify` — mas é outra coisa.)*

---

## Tabela resumo

| # | Módulo (spec) | Status | Evidência-chave |
|---|---|---|---|
| 1 | Onboarding | 🟡 | Força + nome de guerra ✅; **falta "estágio atual"** |
| 2 | Conteúdo | ✅ Marinha / ⚪ outras | 13 módulos, 51 lições (**49 marinha**, 1+1 stub) |
| 3 | Missões | ⚪ | Só `mission/concluida` (celebração de lição); sem sistema de missões |
| 4 | Revisão | 🟡 | Revisão por mídia áudio/vídeo; **sem repetição espaçada/flashcards** |
| 5 | Simulados/quizzes | ⚪ | Inexistente (quiz = 0) |
| 6 | Ranking e mérito | ✅ | Ranking + campeão + 3 medalhas + XP, todos em uso |
| 7 | Instrutor virtual | ✅ Marinha / 🟡 força | Pipeline avançada; 3 personas; material real só Marinha |
| 8 | Biblioteca | ⚪ | Só label em WebNavBar; sem tela/dados |
| 9 | Área do campeão | ✅ | Tab champion + `useMonthlyChampion` |
| 10 | Notificações/WhatsApp | — | Fora de escopo (outro repo) |

## Leitura para roadmap (síntese, sem priorizar por você)
- **Espinha dorsal Marinha existe e funciona:** conteúdo (49 lições/13 módulos), progressão, XP, ranking, campeão, medalhas, instrutor virtual. O "ciclo de progressão" da Seção 4 está **parcialmente fechado** (Conteúdo → Progressão → Mérito), mas **quebrado nos elos Prática/Avaliação** (sem quiz/simulado) e **Revisão** (sem repetição espaçada).
- **Maiores lacunas vs spec:** ⚪ Simulados/quizzes, ⚪ Missões/desafios, ⚪ Biblioteca, 🟡 Revisão espaçada, 🟡 estágio no onboarding.
- **Expansão de força:** toda a arquitetura (instrutor, temas, onboarding) suporta 3 forças, mas **conteúdo real é só Marinha** — Exército/Aeronáutica são 1 lição-stub cada.
