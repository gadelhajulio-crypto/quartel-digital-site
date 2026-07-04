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

→ **Achado A-2 (drift deploy↔fonte, dois sentidos):**
- **`chat-ai`** existe como fonte local mas **não está deployada** e **não é invocada por ninguém** (`grep` só encontra a própria definição). → **candidato a código morto** (provável predecessora de `chat-central`/`instrutor-send`). Não removido — anotado.
- **`create-recruta`** está **deployada (v33, 2025-12-14)** mas **não tem fonte no repo**. → função em produção **sem código versionado localmente**. Risco de manutenção: não há fonte para auditar/reproduzir. Anotado.

**Contrato de resposta (`instrutor-send`) vs. Seção 15 do spec:** a função responde no padrão `{ ok: boolean, reason: string, request_id }` com HTTP status coerente (401/403/400/500). Alinha com o espírito da Seção 15 (nunca inferir sucesso; erro estruturado). Nota: usa `reason` em vez de `error`, e não retorna `checklistAccessUrl` (correto — é campo do funil, não do app). **Contrato internamente consistente.**

---

## 7. Achados de qualidade / higiene

### A-3 — Duplicação de cliente Supabase (potencial inconsistência de sessão)
Existem **dois clientes Supabase**:
- `src/lib/supabase.ts` — **canônico**, com adapter `expo-secure-store` para persistência de sessão.
- `_lib/supabase.ts` (raiz) — cliente **"pelado"**, `createClient(url, anon)` **sem adapter de storage/sessão**.

`_lib/supabase.ts` é importado por **`src/components/AvatarUpload.tsx`** e **`src/components/TacticalLibrary.tsx`**. Como não compartilha o storage de sessão do cliente canônico, esses componentes podem operar com uma sessão diferente (ou não-persistida) da do resto do app. → **Achado a investigar depois** (não corrigido). Risco: chamadas autenticadas desses componentes podem falhar de RLS ou usar identidade divergente.

### A-4 — Rotas de onboarding duplicadas
Existe onboarding em `app/(onboarding)/*` **e** em `app/(stack)/onboarding/*` (`instructor-select`, `instructor-confirm`, `instructor-confirmed`, `index`). Possível legado/duplicação de fluxo. Anotado para consolidação futura.

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

### 🔴 A-9 (URGENTE — possível exposição ATIVA, não item de roadmap): endpoint de criação de contas sem authorization guard

`create-recruta` cria usuários Auth com senha arbitrária e `email_confirm: true` usando `service_role`, com CORS `*`, e **não faz nenhuma verificação de autorização de quem chama** (grep confirma: zero checagem de role/claim/admin no código — só leitura de env e header CORS).

**Por que isto pode ser exploração ativa hoje, independente do código:**
- No Supabase, `verify_jwt = true` exige apenas um JWT **válido** — e a **anon key é um JWT válido** (`role=anon`). A anon key é **pública** (embarcada no app cliente; neste repo o `.env` que a contém está inclusive *tracked no git* — ver §8). Portanto, mesmo com `verify_jwt = true`, qualquer detentor da anon key pode invocar o endpoint.
- Se `verify_jwt = false`, é pior: chamável **sem token algum**.
- Em ambos os casos, como o código não valida papel/admin, o resultado é: **quem tiver a URL + a anon key pública pode criar contas arbitrárias em produção agora**.

**Estado da verificação (limite honesto):** o `verify_jwt` **real da função deployada não pôde ser confirmado** nesta sessão — `create-recruta` **não está declarada** em `supabase/config.toml` (as declaradas: `instrutor-send`=true, `chat-central`=false, `chat-notify`=false, `stripe-...`=true), e a Management API não foi acessível read-only daqui (token do CLI no keyring do OS). **Não foi feito teste ao vivo** do endpoint por ser ação destrutiva (criaria usuário real). A escalada **independe** do valor exato de `verify_jwt` pelas razões acima.

**Ação recomendada IMEDIATA (decisão do responsável, fora do escopo read-only):** confirmar no painel Supabase o `verify_jwt` de `create-recruta` e, independentemente do valor, mitigar já — uma das opções: (a) desabilitar/pausar a função se não estiver em uso; (b) adicionar guard de autorização no código (checar JWT de admin/role antes de criar); (c) restringir invocação. Tratar **antes** e **separado** dos riscos internos A-10/A-11/A-12.

### 🟠 A-10 — Bug latente de identidade (`recruta_id` recebendo `auth_id`)
A RPC é chamada com `atribuir_missao_inicial({ p_recruta_id: data.user.id })`, mas `data.user.id` é o **`auth_id`** (auth.uid()), **não** o `recrutas.id`. A convenção canônica avisa que `recrutas.id ≠ auth_id`. Se a RPC espera `recrutas.id`, recebe o identificador errado. Como `missaoError` é apenas logado (não fatal), **falha silenciosamente** — a missão inicial pode nunca ser atribuída. Contido (bug interno), mas real.

### 🟠 A-11 — Divergência de schema no INSERT em `recrutas`
O INSERT usa colunas `email, nome, plano:"basico", status:"ativo"` que **não constam** na descrição canônica atual de `recrutas` (que fala em `tipo_acesso`, `nome_guerra`, `onboarding_concluido`). Função é de dez/2025, anterior às waves recentes — se o schema mudou desde então, o INSERT pode quebrar. Não confirmável sem introspecção de schema.

### 🟠 A-12 — RPC órfã `atribuir_missao_inicial`
Não consta na lista canônica de RPCs (`MEMORY.md`) nem é referenciada pelo cliente. RPC "órfã" do ponto de vista do app — verificar existência/assinatura antes de assumir que funciona.

### 🟢 Sem segredos hardcoded
Usa env `PROJECT_URL`/`SERVICE_ROLE_KEY` (nomes custom, server-side — ok). Libs antigas (`std@0.168.0`), sem risco direto.
