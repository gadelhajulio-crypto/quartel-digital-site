# AUDITORIA INICIAL — quartel-digital-mobile

> Documento gerado conforme Seção 19 do `FABLE5_RECRUTA_PADRAO_MASTER_SPEC.md`.
> **Auditoria estritamente read-only sobre código de produto.** Nenhuma alteração de lógica, refactor ou correção foi feita. Achados que pareciam bugs rápidos foram anotados, não corrigidos.
> Data: 2026-07-03 · Branch: `sprint2/p1-m1-rpc-complete-lesson`

---

## Escopo desta auditoria

**Este repositório cobre** (do master spec): **Seção 5** (módulos do app), **Seção 11** (instrutor virtual/IA), **Seção 12** (ranking/XP/progressão) e **parte da Seção 7** (tabelas de conteúdo, progresso, chat, identidade).

**Este repositório NÃO cobre** e a auditoria não investiga:
- **Seção 6** — funil de checklist Marinha (`leads_checklist`, `/checklist/acesso`, token) → vive em `recrutapadrao-checklist`.
- **Seções 9/10** — WhatsApp / Evolution API / n8n → vivem em `recrutapadrao-checklist`.

Regra aplicada (Seção 0.1): a ausência de qualquer traço de checklist/WhatsApp neste repo é **esperada** ("está em outro repositório"), não um defeito.

### Identidade do repositório (correção ao mapeamento da Seção 0.1)
| Item | Valor |
|---|---|
| Diretório local | `quartel-digital-mobile` |
| Remote | `github.com/gadelhajulio-crypto/quartel-digital-site.git` (⚠️ nome remoto ≠ nome local) |
| Branch | `sprint2/p1-m1-rpc-complete-lesson` (upstream `origin/...`) |
| Stack | React Native / Expo 54 (expo-router), React 19, TypeScript, Supabase JS `^2.87.1` |
| Supabase project | `fjwvtzvfbhubxicsmbdz` (`quartel-digital`) |

**Nota estrutural:** o repo remoto se chama `quartel-digital-site` e contém, além do app mobile na raiz, um projeto **Next.js aninhado e versionado** em `quartel-digital-site/` e um site estático em `site/`. Ou seja, na prática este é um **repositório-guarda-chuva** (mobile + site), não um repo só-mobile. Os subprojetos web estão **fora do escopo** desta auditoria (não são Seções 5/11/12), mas são registrados abaixo como achado estrutural.

---

## 1. Estado de drift (três eixos)

Alinhado ao padrão de riscos da Seção 17 do spec, registro três formas de drift **observadas agora**, sem resolver nenhuma:

| Eixo | Estado | Observação |
|---|---|---|
| **Banco ↔ git** | Resolvido nesta sessão | Migrations `wave5g`/`wave5g1` já estavam aplicadas em prod porém untracked; foram commitadas (`a9557ec`). |
| **Local ↔ remote (git)** | **Aberto** | Branch está **2 commits à frente do `origin`** (waves 5f/5g/5g-1 + chore .gitignore) — commitados mas **sem push**. Documentado como estado atual; não resolver agora. |
| **Deploy ↔ código** | Verificado / OK para chat | `instrutor-send` e `chat-central` deployados = working tree **byte-a-byte** (download + diff = 0 linhas). Ver §6 para drift de *outras* funções. |

---

## 2. Rotas (expo-router, `app/`)

Roteamento file-based. Grupos:

- **`(auth)`** — `intro`, `login`, `signup`, `forgot-password`, `mfa`, `password-expired`, `locked`, `inactive`, `paywall`.
- **`(onboarding)`** — `welcome`, `nome-guerra`, `instrutor`, `confirmacao` (+ `(stack)/onboarding/*` duplicado — ver achado A-3).
- **`(tabs)`** — `index`, `chat`, `messages`, `notices`, `modules`, `progress`, `ranking`, `champion`, `history`, `reviews`, `profile`, `settings`.
- **`(stack)`** — `lesson/[id]`, `module/[id]`, `review/[id]`, `lessons_list`, `reviews`, `medals`, `notices`, `bell`, `conversations`, `instructor/*`, `mission/concluida`, `continue`, `sessions`.

Cobertura vs. ciclo de progressão (Seção 4 do spec): as perguntas "o que estudar / o que completei / como estou vs. outros / que missão / que nível" têm telas correspondentes (`modules`, `progress`, `ranking`, `champion`, `lesson`). **Sem tela órfã evidente** no nível de rota.

---

## 3. Camada de serviços e hooks

**`src/services/` (17 contratos de escrita/leitura):** `authService`, `billingService`, `bootstrapService`, `c5EventsService`, `chatService`, `eliteService`, `galeria`, `ieaService`, `institutionalEventService`, `lessons`, `onboardingService`, `profileService`, `progressService`, `sessionManagementService`, `stripeService`, `xpService`.

**`src/hooks/` (24 hooks de leitura):** cobrem painel do recruta, módulos/lições, progresso, ranking, campeão, medalhas, notices, mensagens do instrutor, reviews, histórico, chat (unread/draft), push token, identidade canônica.

Disciplina arquitetural observada: services concentram `.rpc()`/`.from()`; hooks consomem views. Consistente com a arquitetura banco-first do spec.

---

## 4. Contratos de dados — RPCs e Views referenciados pelo cliente

> ⚠️ Limite desta auditoria: a lista abaixo é o que o **cliente referencia**. Não validei existência/assinatura de cada objeto contra o schema remoto (exigiria introspecção de DB fora do escopo read-only de código). Divergências vs. `MEMORY.md` estão marcadas como **itens a reconciliar**, não como bugs confirmados.

### RPCs chamadas (17)
`check_total_release`, `consumir_evento_c5`, `get_student_next_lesson`, `registrar_xp`, `rpc_auth_claim_active_client_session`, `rpc_auth_resolve_session_state`, `rpc_auth_revoke_client_session`, `rpc_chat_mark_read`, `rpc_chat_open_conversation`, `rpc_complete_lesson`, `rpc_complete_module`, `rpc_complete_onboarding`, `rpc_mark_instructor_message_read`, `rpc_mark_notice_read`, `rpc_register_push_token`, `rpc_start_module`, `rpc_update_instructor_profile`.

**Itens a reconciliar com `MEMORY.md`:**
- Memória lista `rpc_set_instructor_profile`; código usa **`rpc_update_instructor_profile`**.
- Memória lista `complete_lesson` (legado) + `rpc_complete_lesson`; cliente usa **só `rpc_complete_lesson`** (consistente com a depreciação do legado).
- `check_total_release` e `rpc_register_push_token` não constam na lista canônica de RPCs da memória → candidatos a adicionar ao registro.

### Views consultadas (36) — famílias com sufixo de versão
O cliente consome amplamente views versionadas (`_v2`, `_v3`, `_rcc`) que **divergem dos nomes na `MEMORY.md`**:

| Memória (canônico registrado) | Código real usa |
|---|---|
| `v_billing_status_recruta` | `v_billing_status_recruta_v2` |
| `v_elegibilidade_elite` | `v_elegibilidade_elite_v2` |
| `v_iea_atual` | `v_iea_atual_v2` |
| `v_medals_status` | `v_medals_status_v3` |
| `v_historico_atividade_recruta` | `v_historico_atividade_recruta_v3` |
| `v_classificacao_final_ciclo` | `v_classificacao_final_ciclo_v2` |
| `vw_rdm_lessons` / `vw_recruta_module_progress` | `vw_rdm_lessons_v2` / `vw_recruta_module_progress_v2` |
| (não na memória) | `v_app_bootstrap_institucional_rcc`, `v_chat_conversas_recruta`, `v_chat_mensagens_recruta`, `v_chat_unread_status`, `v_instrutores_app`, `v_modulos_catalogo`, `v_forcas_theme`, `v_recruta_xp_total`, `v_campeoes_mensais_rcc`, `v_ranking_mensal_rcc`, `v_posicao_recruta_mes_rcc`, `v_iea_audit` |

→ **Achado A-1 (documentação desatualizada, não bug):** a `MEMORY.md` está atrás do schema real. O contrato de leitura efetivo migrou para famílias `_v2/_v3/_rcc`. Recomenda-se atualizar a memória/documentação canônica — **sem tocar código**.

---

## 5. Tabelas conceituadas (Seção 7 do spec) vs. realidade deste repo

A Seção 7 lista `recrutas, modulos, missoes, progresso_missoes, licoes, recruta_modulos, campeoes_mensais, xp_events, mensagens_chat, leads_checklist`. Observações:

- O cliente **não escreve tabelas diretamente** — acessa via RPCs/views. Portanto os nomes de tabela do spec não aparecem crus no código do app (esperado na arquitetura banco-first).
- `leads_checklist` **não tem nenhum traço aqui** → correto (é do repo checklist).
- Divergências de nomenclatura já conhecidas na memória (ex.: `aulas` vs `licoes`, `recruta_progresso` vs `progresso_missoes`, `xp_eventos` vs `xp_events`) persistem entre spec conceitual e schema real. **Anotado; reconciliação é decisão de schema, fora do escopo desta auditoria.**
- Baseline de schema versionada existe em `supabase/baseline/` (módulos SQL) além de `supabase/migrations/` → confirma o alerta da Seção 0.1 de que o schema está fragmentado em múltiplos locais.

---

## 6. Edge Functions

**Locais (`supabase/functions/`):** `chat-ai`, `chat-central`, `chat-notify`, `instrutor-send`, `stripe-create-checkout-session`.
**Deployadas (prod, via `functions list`):** `create-recruta` (v33), `instrutor-send` (v38), `chat-central` (v57), `stripe-create-checkout-session` (v14), `chat-notify` (v8).

→ **Achado A-2 (drift deploy↔fonte, dois sentidos) — ambos os lados RESOLVIDOS:**

- **`chat-ai`** · ✅ **RESOLVIDO POR REMOÇÃO (2026-07-04).** Deletado `supabase/functions/chat-ai/`; typecheck (`tsc --noEmit`) limpo após a remoção.
  - **Diagnóstico:** protótipo de **primeira geração** do chat do instrutor — usava a **OpenAI Assistants API** (`openai.beta.threads.runs`) com assistant IDs hardcoded por força e retorno assíncrono `{ threadId, runId }` (modelo de polling). Foi **inteiramente superado** pela pipeline atual `instrutor-send` → `chat-central` (migrada para a **Responses API** com SSE streaming na Wave 5f + cache institucional na Wave 5g + guard HMAC). Não deployado, **zero referências em código** (grep repo-wide), e já marcado como "ZERO matches / Limpo" por **auditorias anteriores independentes** (`supabase/baseline/P5B_DEPRECATE_COMPLETE_LESSON_HANDOFF.md`, `XP_EVENTS_LEGACY_AUDIT.md`). Confirmado morto, não desligado temporariamente.
  - **Nota (fora do repo, não-bloqueante):** os assistant IDs hardcoded (`asst_...` por força) que existiam nesse código podem ainda existir na conta OpenAI. Arquivá-los/deletá-los lá é **decisão externa ao repositório** — não impede nem depende desta remoção.

- **`create-recruta`** · ✅ resolvido em duas etapas: fonte **recuperada** e versionada (commit `b386e5d`), depois a função deployada foi **removida de produção** por ser um endpoint sem guard (ver A-9). Drift deploy↔fonte fechado.

**Contrato de resposta (`instrutor-send`) vs. Seção 15 do spec:** a função responde no padrão `{ ok: boolean, reason: string, request_id }` com HTTP status coerente (401/403/400/500). Alinha com o espírito da Seção 15 (nunca inferir sucesso; erro estruturado). Nota: usa `reason` em vez de `error`, e não retorna `checklistAccessUrl` (correto — é campo do funil, não do app). **Contrato internamente consistente.**

---

## 7. Achados de qualidade / higiene

### A-3 — Duplicação de cliente Supabase · ✅ RESOLVIDO POR REMOÇÃO (2026-07-04)

> **STATUS: RESOLVIDO em 2026-07-04.** Removidos `_lib/supabase.ts` (cliente duplicado), `src/components/AvatarUpload.tsx` e `src/components/TacticalLibrary.tsx` (únicos consumidores). Typecheck (`tsc --noEmit`) passou limpo após a remoção. Cliente canônico único: `src/lib/supabase.ts`.

**Diagnóstico completo (o que a investigação profunda revelou):**
Existiam **dois clientes Supabase**:
- `src/lib/supabase.ts` — **canônico**, com adapter `expo-secure-store` (`persistSession:true`, `autoRefreshToken:true`). 41 consumidores (services, hooks, screens, AuthContext).
- `_lib/supabase.ts` (raiz) — cliente **"pelado"**, `createClient(url, anon)` **sem adapter de storage/sessão**. Por ser instância separada sem acesso à sessão persistida no SecureStore, **operava sempre como `anon`** (nunca via o recruta logado).

O `_lib` era importado por **apenas 2 arquivos**, ambos **código morto/órfão** — **nenhum é renderizado ou importado em qualquer lugar do repo**:
- `TacticalLibrary.tsx` — importava o cliente mas o único uso de `supabase` era uma **linha comentada** (`// ...rpc('check_total_release')`). Import 100% morto.
- `AvatarUpload.tsx` — usava o `_lib` de fato (`storage.from('avatars').upload/download`), mas nunca era montado. Bônus: o path de upload (`${Date.now()}.ext`) não era escopado por usuário.

**Conclusão:** A-3 **não era bug ativo** — era cliente duplicado importado por componentes órfãos. O risco de sessão inconsistente (upload como anon → falha de RLS) era **latente**, materializável só se alguém plugasse o `AvatarUpload` no futuro. Histórico git achatado (tudo em `adec321`, 2026-01-22); evidência circunstancial forte de scaffold inicial superado pelo canônico e nunca limpo. Nenhuma justificativa para um segundo cliente anon (o único uso real era autenticado). Por isso a rota escolhida foi **remoção**, não migração.

> ⚠️ **Se o upload de avatar voltar ao roadmap:** implementar **do zero** sobre o cliente canônico (`src/lib/supabase.ts`), com path escopado por `auth.uid()` e a RLS do bucket `avatars` verificada. **Não** reaproveitar o código deletado (`AvatarUpload.tsx`) — ele usava o cliente anon e path não-escopado.

### A-4 — Rotas de onboarding duplicadas · ✅ RESOLVIDO POR REMOÇÃO (2026-07-04)

> **STATUS: RESOLVIDO em 2026-07-04.** Removido o grupo legado `app/(stack)/onboarding/` inteiro (5 arquivos: `_layout`, `index`, `instructor-select`, `instructor-confirm`, `instructor-confirmed`). `app/(stack)/_layout.tsx` não registrava nenhuma `Stack.Screen name="onboarding/..."` — sem linha órfã a remover. Typecheck (`tsc --noEmit`) limpo.

**Diagnóstico completo:** existiam dois grupos de rota de onboarding:
- **Grupo 1 `app/(onboarding)/`** (welcome → nome-guerra → instrutor → confirmacao) — **VIVO**: é o destino do roteador pós-auth `BootstrapGate.tsx` (`onboarding → '/(onboarding)/welcome'` quando `onboarding_concluido=false`), também referenciado por `ChatScreen`, e documentado como o onboarding em `docs/EXECUCAO_DECI-02_2026-03-13.md`. Edições git mais recentes (até 05-21).
- **Grupo 2 `app/(stack)/onboarding/`** — **ÓRFÃO E QUEBRADO**: nada no app navegava para ele (zero refs externas a `/onboarding` cru); cobria só seleção de instrutor (versão parcial anterior, sem força/nome-guerra); e `instructor-select.tsx` empurrava para `/(onboarding)/instructor-confirm`, alvo **inexistente** no Grupo 1 → fluxo quebraria no meio. Parou de ser editado em 05-15, ausente do doc de execução.

**Conclusão:** duplicação real (Grupo 2 superado pelo Grupo 1), não dois fluxos legítimos. **Não confundir** com `app/(stack)/instructor/*` (`select`/`index`) — fluxo **separado e vivo** de trocar instrutor pós-onboarding (usado por `profile.tsx`, `InstructorButton.tsx`, `ChatScreen`), **preservado**.

### A-14 — (NOVO, não resolvido) Possível duplicação de lógica de seleção de instrutor
Após remover o Grupo 2, restam **dois pickers de instrutor vivos**: `app/(onboarding)/instrutor.tsx` (passo do onboarding) e `app/(stack)/instructor/select.tsx` (trocar instrutor depois). Podem compartilhar lógica duplicada de listagem/seleção. **Fora do escopo do A-4** (que era o grupo de rotas duplicado) — anotado para investigação futura de consolidação de componente. Não é bug ativo; é oportunidade de DRY.

### A-15 — Views sem `GRANT` a `authenticated` · ✅ RESOLVIDO (2026-07-04)

> **STATUS: RESOLVIDO em 2026-07-04.** Migration `20260704001000_a15_grant_module_views_authenticated.sql` adiciona `GRANT SELECT ... TO authenticated` a `v_modulos_catalogo`, `vw_recruta_module_progress_v2` e `vw_rdm_lessons_v2` (esta última também não tinha grant e é usada pelo `useModuleLessons` no detalhe de módulo). Aplicada via `supabase db push` (versionada + aplicada, sem drift) e **verificada ao vivo**: query autenticada a `v_modulos_catalogo` que antes dava `42501` agora retorna 13 módulos. Os consumidores mortos (`InstructionsInProgress`, `useModulesProgress`, `ModulesScreen`) foram **removidos** junto do A-16.

**Diagnóstico original.** Descoberto ao mapear completude (2026-07-04): as views `v_modulos_catalogo` e `vw_recruta_module_progress_v2` **negam permissão (`42501 permission denied`) a um usuário `authenticated`** — confirmado ao vivo (login de teste) e no schema (`supabase/remote/supabase_remote_schema.sql`: **nenhum GRANT** para essas duas, ao contrário de peers recruta-facing como `v_lessons_panel` e `v_medals_status_v3`, que têm `GRANT SELECT TO authenticated`).

**Não é RLS admin-only intencional** — são views voltadas ao recruta (catálogo de módulos, progresso de módulo por recruta). É um **GRANT ausente** (oversight de configuração), inconsistente com as views irmãs.

**Por que não é bug ATIVO hoje:** os únicos consumidores dessas views são **código morto** (0 referências vivas): `src/components/dashboard/InstructionsInProgress.tsx` (`v_modulos_catalogo`), `src/hooks/useModulesProgress.ts` e `src/screens/ModulesScreen.tsx` (`vw_recruta_module_progress_v2`). Nenhum é renderizado/roteado. A tab de módulos viva **não** usa essas views (ver A-16). → **Latente:** se algum desses consumidores for revivido sem antes adicionar o GRANT, um recruta real quebra com 42501. Correção futura: `GRANT SELECT ... TO authenticated` (ou remover as views se confirmadas obsoletas junto do código morto).

### A-16 — Dupla fonte de verdade do currículo: constante hardcoded vs banco · ✅ RESOLVIDO (2026-07-04)

> **STATUS: RESOLVIDO em 2026-07-04 (Opção A).** A tab de módulos agora é **DB-driven**:
> - Novo hook `src/hooks/useModulesCatalog.ts` busca `v_modulos_catalogo` (módulos por força) + `v_lessons_panel` (lições por força, view canônica RCC), agrupa lições por módulo e aplica gate por módulo (`canAccessModule` — degustação/plano). **Cadeado por lição = `false` sempre** e intencional: o banco não sabe travar lição (`vw_rdm_lessons_v2.status` é `'available'` fixo) — cadeado real fica para quando existir quiz/pré-requisito (comentado no código).
> - `app/(tabs)/modules.tsx` trocou `MARINHA_CURRICULUM` pelo hook, preservando o visual `ModuleAccordion`, com estados de loading e **"Conteúdo em desenvolvimento"** (para força sem currículo, em vez de lista vazia).
> - **Removidos** (código morto): `src/constants/marinhaCurriculum.ts`, `src/screens/ModulesScreen.tsx`, `src/hooks/useModulesProgress.ts`, `src/components/dashboard/InstructionsInProgress.tsx`.
> - `tsc --noEmit` limpo. Validado via consulta autenticada (usuário de teste, Marinha): a tab renderiza os **11 módulos reais / 49 lições** do banco.
>
> **Desvio do plano literal (reportado):** o plano citava `vw_rdm_lessons_v2` como fonte de lições, mas descobriu-se que ela é **degustação-only** (`WHERE is_degustacao = true`) e já usada por `useModuleLessons`. Fonte correta = `v_lessons_panel` (canônica, currículo completo). Intent (DB-driven) preservado.
>
> **Notas de acompanhamento (não-bloqueantes, achados de dados):**
> 1. Exército/Aeronáutica têm **1 módulo de degustação intencional cada** ("Regulamento Disciplinar…", 1 lição) — **não é placeholder incompleto**, é o conteúdo grátis proposital dessas forças. Comportamento correto: a tab mostra esse módulo (não cai em "em desenvolvimento"). **Decisão de produto (2026-07-04): manter como está — threshold descartado, sem ação.**
> 2. `tipo_acesso` real inclui **`'premium'`**, ausente do tipo `Profile` (`'degustacao'|'completo'`); `canAccessModule` cai no default-allow (funciona, mas é divergência tipo↔dados — parente do A-1).
> 3. Ver A-17 (módulo de QA visível em prod).

**Diagnóstico original.** A tab de módulos viva (`app/(tabs)/modules.tsx`) renderiza **100% de uma constante local** `MARINHA_CURRICULUM` (`src/constants/marinhaCurriculum.ts`, 110 linhas, títulos de módulo/lição e flags `locked` **hardcoded**), via `ModuleAccordion` — que é **display-only** (só expande/colapsa; **não** navega para lição, **não** lê o banco). Não há mistura em runtime (a tab não toca o DB).

**O risco real é dupla fonte de verdade**, não crash: o currículo **exibido** ao recruta (constante congelada) pode **divergir do banco** (fonte real: **13 módulos / 51 lições**, 49 Marinha — usado pelo fluxo de lição `lesson/[id]`/`module/[id]`, progresso e XP). Dois problemas concretos:
1. Se o currículo mudar no DB (add/remove/reordenar lição), a tab **não reflete** — mostra a constante estática.
2. O estado `locked` é **hardcoded na constante**, não deriva do acesso/progresso real do recruta no DB — ou seja, o "cadeado" exibido não corresponde necessariamente ao que o recruta realmente pode abrir.

Além disso, os IDs da constante (`mod_0`, …) não são os UUIDs do DB, então a visão-geral e o conteúdo real são universos separados. → **Risco de inconsistência/manutenção real** (não bug ativo). Reconciliação futura: alimentar a tab de módulos a partir do banco (mesma fonte do fluxo de lição), aposentando a constante — provavelmente junto com a revitalização/limpeza do código morto do A-15.

### A-17 — (NOVO, pendência PRÉ-LANÇAMENTO) Módulo de QA visível em produção
Descoberto ao validar o A-16 (2026-07-04): o módulo **`[QA] Módulo Teste rpc_complete_lesson`** (força Marinha, 1 lição) existe em produção e **aparece na tab de módulos para recrutas reais**. É conteúdo de teste/QA que vazou para o catálogo de produção.

**Prioridade: baixa AGORA** (não há usuários reais em produção), mas **bloqueador de lançamento público** — deve ser removido/despublicado do banco (ou marcado `ativo=false`, já que `v_modulos_catalogo` filtra por `ativo=true`) **antes** de qualquer divulgação. Não é bug de código; é higiene de dados. Sem ação nesta sessão por decisão de produto.

### A-18 — Drift de schema da camada C9 (migration local no-op ≠ remoto) · ✅ RECONCILIADO (2026-07-04)

> **STATUS: RECONCILIADO em 2026-07-04.** Migration `20260704002000_c9_reconcile_remote_drift.sql` aplicada (`supabase db push`) — **no-op perfeito no prod** (todas as colunas reais retornaram "already exists, skipping", confirmando que a reconciliação bate 100% com o remoto). Repo agora reflete o schema c9 verdadeiro.

**Diagnóstico:** a migration `20260427214001_create_c9_didactic_layer.sql` era uma "migration de sincronização" com `CREATE TABLE IF NOT EXISTS`. As tabelas c9_ **já existiam no prod** (criadas direto no banco), então a migration foi **no-op ao ser aplicada** — consta como aplicada (Local==Remote), mas **descrevia colunas que nunca vigoraram**. O repo documentava um schema c9 falso. Drift do tipo banco↔git da Seção 17, mascarado por `IF NOT EXISTS`.

Deltas reais (local errado → remoto real): `conteudos.conteudo`→`corpo_markdown`(+tipo/versao/origem/metadata); `flashcards.frente/verso`→`pergunta/resposta`; `quiz_perguntas.pergunta`→`enunciado`; `quiz_alternativas.is_correta`→`correta`; `quiz_tentativas.pontuacao/respostas_jsonb/sucesso`→`respostas/total_perguntas/total_acertos/percentual/finalizada`; função `c9_update_updated_at_column`→`c9_set_updated_at`. Introspecção via `supabase/remote/supabase_remote_schema.sql`. Base para o design de quiz/simulado (ver `docs/DESIGN_QUIZ_SIMULADO.md`).

### A-19 — `aulas` nega SELECT a `authenticated` · confirmado, SEM impacto vivo (provável intencional)
Descoberto ao ler `aulas.xp_valor` (2026-07-04): `aulas` só concede a `service_role` (sem `authenticated`) — mesmo padrão de GRANT ausente do A-15. **Mas, ao contrário do A-15, não há consumidor vivo afetado:** nenhum código faz `.from('aulas')` direto; o app lê lições via views (`v_lessons_panel` etc.) e escreve via RPCs `SECURITY DEFINER` (`rpc_complete_lesson` lê `aulas.xp_valor` como definer, contornando o grant). Provavelmente **intencional** — tabela-base acessada só via views canônicas (defesa em profundidade). **Sem correção necessária** (só flagрado; se um dia algo precisar ler `aulas` direto, aí adiciona o grant). Verificação read-only feita antes de qualquer ação, conforme protocolo.

### A-20 — Sistema de simulado "fantasma": RPCs órfãs + tabelas inexistentes + 3 ledgers de XP
Investigação (2026-07-04) da pista `conceder_xp_simulado(p_simulado_id)`. Conclusão: **não existe sistema de simulado** — só fragmentos órfãos/aspiracionais:
- **`conceder_xp_simulado`** — RPC não referenciada pelo app; `p_simulado_id` é **texto livre** (sem FK/tabela). Grava num subsistema de XP **legado** (`xp_events` user_id/xp/periodo/reference + `user_xp`), **distinto** do `xp_eventos` canônico usado por `rpc_complete_lesson`. Aspiracional (plumbing de XP sem feature). Perfil de morto/histórico como o `chat-ai` do A-2.
- **`c6_get_simulado_final_score`** — referencia `simulados_resultados` / `v_simulado_final_ciclo` que **nunca existiram** (só via `to_regclass` defensivo) → sempre retorna NULL; o gate de "simulado final" da elegibilidade C6 nunca passa.
- **Três tabelas de XP divergentes**: `xp_eventos` (canônico, `rpc_complete_lesson`), `xp_events` (legado, `conceder_xp_simulado`), `user_xp`. Parente da divergência de XP já conhecida (MEMORY / A-1).

**Consequências:** (1) o design de simulado first-class sobre C9 **permanece válido** (não há sistema melhor a reaproveitar); (2) reusar `conceder_xp_simulado` está **descartado** (subsistema legado); (3) ver resolução da ledger abaixo. Ver `docs/DESIGN_QUIZ_SIMULADO.md` §3/§8.

**Resolução da ledger canônica (2026-07-04, read-only):**
- **`xp_eventos` é a ledger canônica** — a que o ranking lê. Cadeia confirmada: `mv_xp_mensal_recruta` = `SUM(quantidade) FROM xp_eventos` → `mv_ranking_mensal` → views `v_ranking_mensal_rcc`/`v_posicao_recruta_mes_rcc`/`v_campeoes_mensais_rcc`/`mv_campeao_mensal` (as que o app consome) + `v_recruta_xp_total` (lê `xp_eventos` direto). `rpc_complete_lesson` grava em `xp_eventos` (reconfirmado). **→ O RPC de XP de quiz/simulado DEVE gravar em `xp_eventos`** (com `quantidade`, `forca`, `tipo`, `referencia_id`).
- **`xp_events` + `user_xp` = subsistema legado/paralelo MORTO.** **Nenhum** objeto de ranking os referencia. São escritos/lidos só pela família órfã **`conceder_xp_*`** (7 funções: `conceder_xp_modulo/revisao_recomendada/revisao_voluntaria/simulado/streak_5_dias/uso_diario/whatsapp`) — chamada por **ninguém** (app negativo; nenhum trigger; nenhuma outra função). XP escrito lá é **invisível ao ranking**. Candidatos seguros a aposentar depois (como o A-2), com a ressalva usual: não pude verificar chamadas nos repos do VPS (`recruta-padrao-os`), embora sejam RPCs de gamificação que só o app/backoffice chamaria.
- **Dependência operacional para o design:** o ranking é MATERIALIZED (`mv_xp_mensal_recruta`/`mv_ranking_mensal`) — XP novo em `xp_eventos` só aparece no ranking **após REFRESH** das MVs (que, por alerta conhecido, não tem schedule configurado). O RPC de quiz/simulado grava certo, mas a visibilidade no ranking depende do refresh.

### A-21 — (pendência PRÉ-LANÇAMENTO) Materialized views de ranking sem REFRESH agendado
Confirmado (2026-07-04, read-only): `mv_xp_mensal_recruta`, `mv_ranking_mensal` e `mv_campeao_mensal` são **materialized views** e **não há REFRESH agendado** — sem `pg_cron` (nem instalado), e essas MVs **nem constam** na única função que dá refresh em outras MVs (a de `mv_c7_*`). Consequência: XP gravado em `xp_eventos` (por `rpc_complete_lesson` hoje, e por quiz/simulado no futuro) **só aparece no ranking após um `REFRESH MATERIALIZED VIEW` manual**.

**Prioridade: pré-lançamento (perfil do A-17).** Sem usuários reais, não é urgente. Mas antes de qualquer divulgação pública **precisa ser resolvido** — senão o ranking parece **quebrado/estático** para o primeiro recruta real (ele ganha XP e o ranking não mexe). **Correção NÃO feita agora**: é decisão de infra (provável `pg_cron` agendado ou Edge Function agendada chamando `REFRESH ... CONCURRENTLY`) que merece ser tratada como **tarefa própria**, não de passagem. Só documentado.

### A-22 — Views de execução C9 `security_invoker` sem GRANT nas tabelas (gabarito não pode ser exposto)
Descoberto ao validar o backend de quiz/simulado (2026-07-04): as views `v_c9_quiz_execucao`/`v_c9_quiz_resultado` são `security_invoker=true`, mas as tabelas `c9_*` têm **RLS sem GRANT SELECT a `authenticated`** → um usuário autenticado recebe `42501` ao lê-las. **A camada C9 estava, na prática, inutilizável pelo app** (consistente com 0 referências no código e schema sem dados). **Não** se resolve com GRANT nas tabelas: `c9_aula_quiz_alternativas.correta` é o **gabarito** — expor a tabela crua vazaria a resposta.

**Correção correta:** view **`security definer`** (roda como owner, projeta sem `correta`), GRANT só na view. **✅ RESOLVIDO (2026-07-04)** para as três views:
- `v_c9_simulado_execucao` (`20260704006000`) e `v_c9_quiz_execucao` (`20260704007000`) → definer, sem `correta`. Confirmado por leitura: acessíveis a authenticated, gabarito não vaza.
- `v_c9_quiz_resultado` (`20260704007000`) → recriada como definer **com filtro explícito `recruta_id = auth.uid()`** nas duas CTEs/consulta (como definer o RLS "own attempts" não se aplica; sem o filtro exporia tentativas de outros). Confirmado: retorna só as tentativas do próprio recruta (0 para o test user).
- `rpc_c9_submit_attempt` já é `SECURITY DEFINER` (avalia gabarito server-side) — não afetado.

### A-23 — Filtragem por força nos CTAs de quiz/simulado · ✅ RESOLVIDO (2026-07-04)
Os CTAs "Testar conhecimento" (lição) e "Fazer simulado do módulo" apareciam sempre que existisse quiz/simulado, sem checar se o conteúdo era da força do recruta.

**Correção (mesma fonte/padrão do A-16):** o guard usa `useAuth().profile.forca` (a mesma fonte de força do `useModulesCatalog`) comparada à força do conteúdo **já carregado** — `lesson.force` (de `useLessonData`/`v_lessons_panel`) e `lessons[0].forca` (de `useModuleLessons`/`vw_rdm_lessons_v2`). CTA só aparece quando `conteudo.force === profile.forca`. Sem query nova nem lógica paralela. `tsc --noEmit` limpo; confirmado por leitura (test user Marinha × conteúdo Exército → `'exercito' !== 'marinha'` → CTA escondido).

**Residual (não-bloqueante, defense-in-depth p/ depois):** o guard é no nível de UI (exibição + ponto de entrada de navegação). Um deep-link direto à rota `quiz/[aulaId]`/`simulado/[moduloId]` de outra força ainda carregaria o conteúdo, e o `rpc_c9_submit_attempt` não valida força. **Não é vulnerabilidade** — o XP é atribuído à força do próprio recruta e limitado a 1ª tentativa; responder um quiz de outra força só daria XP uma vez. Endurecer no data-layer (views de execução expondo `forca` + filtro no fetch/RPC) fica como hardening futuro.

> ⚠️ **Impacto no roteiro de teste manual (`docs/DESIGN_QUIZ_SIMULADO.md` §10):** com o filtro, o **usuário de teste atual (Marinha) NÃO vê mais os CTAs** de quiz/simulado — o conteúdo placeholder é só Ex/Aero. Para exercitar quiz/simulado agora é **necessário um usuário de teste de força Exército ou Aeronáutica**.

### A-5 — `catch` silenciosos
Varredura em `src/` encontrou **catch verdadeiramente vazios apenas em `chatService.ts:357` e `:359`**, e ambos são **intencionais e defensáveis** (tentativa best-effort de extrair o body de erro da Edge Function antes de logar `message_send_failed` — o log ocorre logo depois; não há falha engolida sem telemetria). **Sem falha silenciosa crítica identificada** no caminho de chat. Demais `catch` (30 no total) logam ou propagam. Não auditados exaustivamente fora do fluxo de chat.

### A-6 — Falso sucesso no front-end
**Não encontrado no fluxo de chat.** Ao contrário: no caminho de persistência parcial, o `ChatScreen` marca a mensagem como `status: 'failed'` e exibe a resposta **sinalizada como não-persistida** — comportamento honesto, alinhado à Seção 15. Fluxos de lição/XP/onboarding não foram auditados linha a linha para esse critério (recomendado em fase futura).

### A-7 — Bloat / artefatos versionados no repo
Arquivos grandes **rastreados no git** que são artefato de auditoria/ferramenta, não código de produto:
- `quartel-digital-audit.zip` (~13 MB)
- `estrutura.txt` (~3.6 MB)
- `assets/splash/splash.mp4` (~31 MB) e várias PNGs de medalhas ~3 MB cada (assets legítimos, mas pesados para o git).
- SQL ad-hoc solto na raiz: `final_schema_fix.sql`, `fix_database_schema.sql`, `standardize_xp.sql`, `seed_*.sql` — fora de `supabase/migrations/`, sem timestamp, difícil rastrear se aplicados.

→ Higiene de repositório. Anotado; nenhuma remoção feita.

### A-8 — Subprojetos web aninhados
`quartel-digital-site/` (Next.js completo, com `node_modules` próprio e CLAUDE.md) e `site/` (HTML estático) versionados dentro do repo mobile. Fora do escopo Seções 5/11/12. Recomenda-se decisão explícita sobre se pertencem aqui ou devem sair para repo próprio.

---

## 8. Segurança

- **Sem segredos hardcoded** em `src/`/`app/` (varredura por `eyJ…`/`service_role`/`SUPABASE_SERVICE` = nada). ✔
- Apenas **chaves públicas** no cliente: `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_ANON_KEY` (anon key, adequada a client-side com RLS). ✔
- `.env.test.local` (contém `TEST_USER_EMAIL`/`TEST_USER_PASSWORD`) — **confirmado gitignored e não-tracked** (casa com `.env*.local`). ✔
- **`.env` está TRACKED no git** (não ignorado). Contém apenas chaves públicas (`EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_ANON_KEY`) → risco **baixo** (anon key é client-side por design), porém versionar `.env` não é boa prática. → **Achado a decidir depois:** gitignorar `.env` e mover para `.env.example`. Não alterado.
- Edge Functions usam `service_role` **server-side** (correto); a tabela `chat_response_cache` tem RLS restrita a `service_role`. ✔
- **A investigar depois:** o cliente "pelado" de `_lib/supabase.ts` (A-3) e implicações de RLS.

---

## 9. Riscos de UX (nível de mapeamento, não teste)

- Fluxo de chat tem fallback explícito (streaming→polling) e sinalização honesta de falha parcial — bom.
- Duplicação de onboarding (A-4) pode gerar caminhos divergentes de primeira experiência.
- Não houve teste de interação real (fora do escopo desta auditoria documental).

---

## 10. Pendências de working tree (higiene, resolver depois)

- **3 PNGs modificados-não-commitados:** `assets/instructors/cards/ramos-card-selected.png`, `rocha-card-selected.png`, `sara-card-selected.png`. São re-exports de asset, **sem relação com as waves 5f/5g/5g-1**. Deixados fora dos commits desta sessão de propósito. **Pendência de higiene** — decidir depois se commitar (mudança intencional de arte) ou reverter (ruído de re-export).
- **2 commits à frente do `origin` sem push** (ver §1, eixo local↔remote).

---

## 11. Plano de MVP resultante (prioridades justificadas)

> Recomendações priorizadas. **Nenhuma implementada.** Ordem por risco × esforço.

**P0 — Verdade e rastreabilidade (baixo esforço, alto valor):**
1. Resolver o drift local↔remote: `git push` das waves 5f/5g/5g-1 após revisão (ou decisão explícita de segurá-las).
2. Decidir os 3 PNGs (commitar vs reverter) para zerar o working tree.
3. Atualizar `MEMORY.md`/doc canônica com as famílias de view `_v2/_v3/_rcc` e RPCs reais (A-1) — evita que futuros agentes trabalhem sobre nomes obsoletos.

**P1 — Drift de deploy e código morto (médio esforço):**
4. `create-recruta` (A-2): recuperar a fonte da função deployada para dentro do repo (`supabase functions download create-recruta`) e versioná-la — hoje há função em prod sem código local.
5. `chat-ai` (A-2): confirmar que está morta e planejar remoção (não remover sem confirmação).

**P2 — Consistência arquitetural (médio/alto esforço, requer cuidado):**
6. Unificar o cliente Supabase (A-3): migrar `AvatarUpload`/`TacticalLibrary` para `src/lib/supabase.ts` e aposentar `_lib/supabase.ts` — **precisa de teste de sessão/RLS** antes.
7. Consolidar rotas de onboarding duplicadas (A-4).

**P3 — Higiene de repositório (baixo risco):**
8. Remover artefatos versionados desnecessários (A-7: zip de auditoria, `estrutura.txt`), mover SQL ad-hoc para migrations ou `docs/`, e avaliar `.gitignore` para artefatos futuros.
9. Decidir o destino dos subprojetos web aninhados (A-8).

---

## Apêndice — Limites explícitos desta auditoria

- Read-only sobre código; nenhuma lógica alterada. Único arquivo escrito: este documento.
- Não houve introspecção do schema remoto: a existência/assinatura de cada RPC/view não foi validada contra o banco. Divergências são "a reconciliar", não bugs confirmados.
- Auditoria de `catch`/falso-sucesso foi **profunda no fluxo de chat** e **superficial** nos fluxos de lição/XP/onboarding/billing — estes merecem passagem dedicada em fase futura.
- Subprojetos `quartel-digital-site/` e `site/` não foram auditados (fora de escopo).

---

## Adendo 2026-07-03 — Achados da recuperação de `create-recruta` (detalha A-2)

A fonte da função `create-recruta` (deployada em prod, ACTIVE v33 de 2025-12-14, sem código no repo) foi recuperada via `supabase functions download` e versionada em `supabase/functions/create-recruta/index.ts` — **sem qualquer alteração de código**. A leitura revelou os achados abaixo. Nenhum foi corrigido; recuperar a fonte **não introduz nem resolve** estes riscos — apenas os torna visíveis.

**Contexto da função:** provisionamento administrativo de recruta via `service_role` — recebe `{ email, name, senha, forca }`, faz `auth.admin.createUser({ email_confirm: true })`, `INSERT` em `recrutas`, e chama a RPC `atribuir_missao_inicial`. **O app mobile NÃO invoca esta função** (grep de `functions.invoke` em `src/` só acha `instrutor-send` e `stripe-...`) — é provável função de backoffice/OS.

**Versão:** v33 na auditoria e v33 agora — sem alteração em prod nesse intervalo.

### A-9 — endpoint de criação de contas sem authorization guard · ✅ MITIGADO POR REMOÇÃO (2026-07-04)

> **STATUS: RESOLVIDO em 2026-07-04.** A função deployada `create-recruta` foi **removida** (`supabase functions delete create-recruta`) — não consta mais como ACTIVE no projeto. A **fonte permanece versionada** (commit `b386e5d`), então a remoção é **reversível**: reativação futura deve vir acompanhada do guard mínimo descrito ao final desta seção.
>
> **Motivo da remoção:** função sem `verify_jwt`, sem guard de autorização no código, usando `service_role` para criar usuários Auth — e **sem consumidor confirmado** após investigação em código (todos os projetos locais + `recruta-padrao-os` no VPS, grep limpo) e em logs de invocação (vazios, nenhum uso registrado). App mobile não a usa. Painel confirmou `verify_jwt` desabilitado.

O texto abaixo preserva o diagnóstico original (histórico do porquê da decisão):

`create-recruta` criava usuários Auth com senha arbitrária e `email_confirm: true` usando `service_role`, com CORS `*`, e **não fazia nenhuma verificação de autorização de quem chama** (grep confirmou: zero checagem de role/claim/admin no código — só leitura de env e header CORS).

**Por que isto pode ser exploração ativa hoje, independente do código:**
- No Supabase, `verify_jwt = true` exige apenas um JWT **válido** — e a **anon key é um JWT válido** (`role=anon`). A anon key é **pública** (embarcada no app cliente; neste repo o `.env` que a contém está inclusive *tracked no git* — ver §8). Portanto, mesmo com `verify_jwt = true`, qualquer detentor da anon key pode invocar o endpoint.
- Se `verify_jwt = false`, é pior: chamável **sem token algum**.
- Em ambos os casos, como o código não valida papel/admin, o resultado é: **quem tiver a URL + a anon key pública pode criar contas arbitrárias em produção agora**.

**`verify_jwt` — CONFIRMADO desabilitado** (painel Supabase, "Verify JWT with legacy secret" = off). Ou seja, o gateway não exigia token algum antes de a request chegar ao código, e o código não exigia role/admin → endpoint público de criação de contas. `create-recruta` também **não estava declarada** em `supabase/config.toml` (declaradas: `instrutor-send`=true, `chat-central`=false, `chat-notify`=false, `stripe-...`=true). **Nunca foi feito teste ao vivo** do endpoint (criaria usuário real).

**Ação tomada (2026-07-04):** escolhida a opção (a) — **remoção da função** (reversível, fonte versionada). Consumidor procurado e não encontrado em código (local + `recruta-padrao-os`) nem em logs. Reativação futura, se necessária, deve seguir a opção (b): guard de autorização + correção de A-10.

**Guard mínimo para eventual reativação:** `verify_jwt=true` + validar `Authorization: Bearer <JWT>` + checar admin (`app_metadata.role==='admin'` ou allowlist) — nunca confiar só na anon key; manter `service_role` apenas server-side; corrigir A-10 (usar `recrutas.id`, não `auth_id`) e adicionar validação de entrada antes do deploy.

### A-10 — Bug de identidade (`recruta_id` recebendo `auth_id`) · ✅ CORRIGIDO, validado por TESTE ISOLADO (2026-07-04)
**Bug original:** a RPC era chamada com `atribuir_missao_inicial({ p_recruta_id: data.user.id })`, mas `data.user.id` é o **`auth_id`** (auth.uid()), **não** o `recrutas.id`. Como `recrutas.id ≠ auth_id` e a RPC insere em `progresso_missoes(recruta_id,…)` esperando o `recrutas.id`, o identificador errado era passado; como `missaoError` só era logado (não fatal), a missão inicial **falhava silenciosamente**.

**Correção:** lógica extraída para `supabase/functions/create-recruta/core.ts` (`provisionRecruta`), que agora **captura o `recrutas.id` gerado no INSERT** (`.insert({...}).select("id").single()`) e passa **esse id** à RPC. `index.ts` virou só o wiring Deno chamando o core — comportamento HTTP idêntico exceto a correção (e o response agora inclui `recruta_id`).

**Validação — ISOLADA, NÃO integração real:** teste `supabase/functions/create-recruta/test.mts` mocka o cliente Supabase (zero banco, zero Auth, zero Docker) e prova, com `auth_id` e `recrutas.id` deliberadamente distintos, que a RPC recebe o `recrutas.id` e **nunca** o `auth_id` (9/9 asserções passam via `node test.mts`). Email de teste usado no payload mock: `teste-a10-fix@example.com` (só string no mock — nenhum usuário criado).

> ⚠️ **Pendência antes de qualquer redeploy (Opção B):** esta validação é unitária/mock, **não** de integração. Antes de reativar a função em produção é obrigatório um teste de integração real (função servida contra um Supabase — de preferência stack local — confirmando linha em `recrutas` e em `progresso_missoes` com o `recruta_id` correto), **em conjunto** com o guard de autorização do A-9. A função permanece **removida de produção** até lá.

### A-11 — ~~Divergência de schema no INSERT em `recrutas`~~ · ❌ REFUTADO (2026-07-04, evidência de schema)
Flag original (baseado na `MEMORY.md`): o INSERT usaria colunas ausentes do schema. **Refutado por evidência direta.** O `CREATE TABLE public.recrutas` no schema remoto (`supabase/remote/supabase_remote_schema.sql:8365`) contém **todas** as colunas do INSERT: `auth_id`, `email` (NOT NULL), `nome`, `forca` (NOT NULL, CHECK marinha/exercito/aeronautica), `patente`, `plano`, `status`. O INSERT é **schema-válido**. Não há divergência. *(Correção honesta de um over-flag anterior baseado em memória desatualizada, não no schema real.)*

### A-12 — RPC `atribuir_missao_inicial` · corrigido: EXISTE (só não é referenciada pelo app)
Confirmado no schema (`...:782`): a função **existe** (`RETURNS void`, `GRANT ... TO service_role`) e insere em `progresso_missoes(recruta_id, missao_id)` usando `p_recruta_id`. Não é "inexistente" — é apenas **órfã do ponto de vista do app** (só era chamada por `create-recruta`). Reforça A-10: como espera `recrutas.id` e recebia `auth_id`, a atribuição de missão estava quebrada.

### 🟢 Sem segredos hardcoded
Usa env `PROJECT_URL`/`SERVICE_ROLE_KEY` (nomes custom, server-side — ok). Libs antigas (`std@0.168.0`), sem risco direto.

### A-13 — Matriz de risco das demais Edge Functions (2026-07-04): nenhuma outra na mesma condição
Auditoria das funções restantes para garantir que a mitigação de `create-recruta` não deixa equivalente exposta. Guards confirmados por leitura de código + `supabase/config.toml`:

| Função | verify_jwt | service_role | Guard no código | Risco |
|---|---|---|---|---|
| ~~create-recruta~~ | off | sim | **NENHUM** | 🔴 ALTO → **removida (A-9)** |
| `chat-central` | off | não (proxy p/ OpenAI) | **HMAC** (`QD_HMAC_SECRET`, `x-qd-timestamp`, `x-qd-signature`) validado antes de processar | 🟢 baixo |
| `chat-notify` | off | sim (lê push tokens) | header interno `x-qd-notify-key` (shared-secret function-to-function) | 🟡 baixo/médio |
| `instrutor-send` | **on** | sim | JWT (valida `sub`) + resolve identidade via `v_identidade_recruta` | 🟢 baixo |
| `stripe-create-checkout-session` | **on** | — | JWT | 🟢 baixo |

**Conclusão:** `create-recruta` era a **única** função na condição "verify_jwt off + service_role + escrita sensível + sem guard". As duas outras com `verify_jwt=off` têm guard de aplicação (HMAC / chave interna). Nota de acompanhamento (não-bloqueante): revisar depois se a comparação da chave em `chat-notify` é feita de forma robusta (constante-tempo) — é o guard mais fraco do conjunto, mas **não** é exposição equivalente a A-9.
