# Auditoria Institucional Supabase — Quartel Digital
**Data da auditoria:** 2026-05-16
**Projeto:** fjwvtzvfbhubxicsmbdz
**Metodologia:** Leitura somente de migrations locais + código-fonte do app. Nenhuma query destrutiva executada. Nenhum secret exposto.

---

## 1. Sumário Executivo

### Estado Geral do Banco
O banco está em **estado funcional parcial**. A arquitetura institucional (banco-first, RPCs, views canônicas) está bem definida e majoritariamente implementada para o núcleo do app. Porém, existe uma **divergência crítica e sistemática** entre os nomes de objetos nas migrations locais e os nomes consumidos pelo código-fonte do frontend — o que indica que o banco remoto possui objetos com nomes `_v2` e objetos de chat que **nunca foram versionados** em migrations locais.

### Principais Achados
1. **Migrations faltantes (crítico):** ~12 objetos consumidos pelo app (`vw_rdm_lessons_v2`, `vw_recruta_module_progress_v2`, `v_billing_status_recruta_v2`, `v_iea_atual_v2`, `v_elegibilidade_elite_v2`, `v_classificacao_final_ciclo_v2`, `v_app_bootstrap_institucional_rcc`, `v_chat_conversas_recruta`, `v_chat_mensagens_recruta`, `v_chat_unread_status`, `rpc_chat_open_conversation`, `rpc_chat_send_message`, `rpc_chat_mark_read`) não têm DDL local. O banco remoto está à frente do repositório.
2. **Tabelas core sem DDL local:** `recrutas`, `profiles`, `recruta_modulos`, `instrutores`, `institutional_assets` são referenciadas em políticas/funções mas nunca foram criadas por migrations locais.
3. **Segurança: `complete_lesson` aceita `p_recruta_id` externo** — qualquer usuário autenticado pode completar aulas em nome de outro recruta via RPC.
4. **Trigger `fn_insert_audit_evento_smart` não é SECURITY DEFINER** — inserções em `v_audit_eventos` por usuários autenticados irão falhar silenciosamente pois `chat_audit_log` só aceita `service_role`.
5. **`registrar_xp` não é idempotente** — chamado pelo cliente após `rpc_complete_module`, permite acúmulo ilimitado de XP de módulo via retry/replay.
6. **Materialized views sem REFRESH agendado** — `mv_xp_mensal_recruta`, `mv_ranking_mensal`, `mv_campeao_mensal` ficam estagnadas indefinidamente.
7. **`check_total_release` e `registrar_xp` sem `SET search_path`** — SECURITY DEFINER sem search_path fixado é vetor de injeção de schema.

### Riscos Críticos
- Bypass de XP via `registrar_xp` (não idempotente) + `complete_lesson` (aceita user_id externo).
- Chat completamente sem DDL versionado — qualquer rollback ou migrate destrói o histórico.
- Dados de ranking sempre desatualizados (materialized views sem refresh).

### Prioridades Recomendadas
1. **Criar migrations de captura** para todos os objetos remotos sem DDL local (especialmente chat e `_v2` views).
2. **Corrigir `complete_lesson`** para usar `auth.uid()` internamente em vez de aceitar `p_recruta_id`.
3. **Agendar REFRESH** das materialized views via pg_cron ou Edge Function cron.
4. **Adicionar `SET search_path`** a todas as funções SECURITY DEFINER legadas.
5. **Tornar `fn_insert_audit_evento_smart` SECURITY DEFINER** ou remover a dependência da view writable.

---

## 2. Inventário Completo

### Schemas Identificados
| Schema | Uso |
|--------|-----|
| `public` | Todas as tabelas, views, funções do app |
| `auth` | Supabase Auth nativo — `auth.users`, `auth.uid()` |
| `storage` | Supabase Storage — `storage.buckets`, `storage.objects` |

---

### Tabelas (com DDL em migrations locais)

| Tabela | Schema | DDL Local | RLS | Notas |
|--------|--------|-----------|-----|-------|
| `xp_eventos` | public | Sim (20240114220000) | Sim | Colunas duplas: `user_id`/`amount` (originais) + `recruta_id`/`xp` (aliases) |
| `modulos` | public | Sim (20240114223000) | Sim | `forca` aceita 'navy'/'army'/'airforce' (legado) e 'marinha'/'exercito'/'aeronautica' |
| `aulas` | public | Sim (20240114223000) | Sim | Coluna `module_id` legada vs `modulo_id` canônica — renomeada no remoto sem migration |
| `recruta_progresso` | public | Sim (20260201221400) | Sim | Tabela canônica de progresso — UNIQUE(recruta_id, lesson_id) |
| `medalhas` | public | Sim (20260202123000) | Sim | Catálogo de medalhas |
| `medalha_regras` | public | Sim (20260202123000) | Sim | Regras dinâmicas por medalha |
| `recruta_medalhas` | public | Sim (20260202123000) | Sim | Ledger de concessões |
| `patentes_catalogo` | public | Sim (20260202183000) | Sim | Catálogo de patentes com hierarquia de nível |
| `patente_regras` | public | Sim (20260202183000) | Sim | Regras de promoção |
| `recruta_patentes` | public | Sim (20260202183000) | Sim | Histórico de promoções — append-only |
| `c9_aula_conteudos` | public | Sim (20260427214001) | Sim | Conteúdo rich text por aula |
| `c9_aula_flashcards` | public | Sim (20260427214001) | Sim | Flashcards por aula |
| `c9_aula_quizzes` | public | Sim (20260427214001) | Sim | Quiz header por aula |
| `c9_aula_quiz_perguntas` | public | Sim (20260427214001) | Sim | Perguntas do quiz |
| `c9_aula_quiz_alternativas` | public | Sim (20260427214001) | Sim | Alternativas por pergunta |
| `c9_aula_quiz_tentativas` | public | Sim (20260427214001) | Sim | `recruta_id` referencia `auth.users` (inconsistência) |
| `auth_app_config` | public | Sim (20260503003000) | Sim | Key-value config — seed: auth_contract_version=RCC-0.3 |
| `auth_client_sessions` | public | Sim (20260503003000) | Sim | Sessões por dispositivo |
| `aula_midias` | public | Sim (20260503005000) | Sim | Mídias complementares (revisões) |
| `institutional_notices` | public | Sim (20260503006000) | Sim | Avisos institucionais |
| `institutional_notice_reads` | public | Sim (20260503006000) | Sim | Ledger de leituras |
| `instructor_messages` | public | Sim (20260503006000) | Sim | Mensagens personalizadas por recruta |
| `instructor_message_reads` | public | Sim (20260503006000) | Sim | Ledger de leituras |
| `recruta_billing` | public | Sim (20260503007000) | Sim | Billing — UNIQUE(recruta_id) |
| `c5_eventos` | public | Sim (20260503008000) | Sim | Eventos institucionais gamificados |
| `recruta_iea` | public | Sim (20260503009000) | Sim | IEA por ciclo — UNIQUE(recruta_id, ciclo_id) |
| `ciclo_classificacao` | public | Sim (20260503009000) | Sim | Classificação final por ciclo — preenchido externamente |
| `chat_audit_log` | public | Sim (20260120170000) | Sim | Auditoria de interações de chat |

### Tabelas sem DDL local (existem no remoto, sem migration)

| Tabela | Evidência | Risco |
|--------|-----------|-------|
| `recrutas` | ALTER TABLE/INSERT/UPDATE em várias migrations | **CRÍTICO** — tabela core sem CREATE TABLE local |
| `profiles` | ALTER TABLE, políticas, JOINs em várias migrations | **CRÍTICO** — tabela core sem CREATE TABLE local |
| `recruta_modulos` | INSERT/UPDATE em RPCs, sem CREATE TABLE | **ALTO** — tabela de progresso modular sem DDL |
| `instrutores` | DELETE/INSERT em 20260511120000 | **ALTO** — catálogo de instrutores sem DDL |
| `institutional_assets` | DELETE/INSERT em 20260511120000 | **ALTO** — catálogo de assets sem DDL |

---

### Views Canônicas

| View | Migration | Tabelas Base | Consumidor | Breaking Change? |
|------|-----------|-------------|------------|-----------------|
| `v_identidade_recruta` | 20260503002000 | recrutas, profiles, v_recruta_patente_atual | AuthContext, instrutor-send, stripe-checkout | **SIM — crítica** |
| `v_auth_app_config` | 20260503003000 | auth_app_config | AuthContext | Sim |
| `v_auth_session` | 20260503003000 | auth_client_sessions | sessionGuardian | Sim |
| `v_auth_active_sessions` | 20260503003000 | auth_client_sessions | sessionManagementService | Sim |
| `v_onboarding_status` | 20260503014000 | recrutas | onboardingService, BootstrapGate | Sim |
| `v_app_bootstrap_institucional` | 20260503013000 | auth_app_config, modulos, aulas, medalhas, patentes_catalogo | bootstrapService | Sim |
| `v_lessons_panel` | 20260131002700 | aulas, modulos | painel de aulas | Sim |
| `v_lesson_progress_panel` | 20260201221400 | recruta_progresso | painel | Sim |
| `v_completed_lessons_count` | 20260503004000 | recruta_progresso | hooks de contagem | Sim |
| `vw_rdm_lessons` | 20260503005000 | aulas, recruta_progresso | useModuleLessons (mas usa `vw_rdm_lessons_v2`) | Parcial |
| `vw_recruta_module_progress` | 20260503005000 | modulos, aulas, recruta_progresso | useModulesProgress (mas usa `_v2`) | Parcial |
| `v_available_reviews` | 20260503005000 | aula_midias, aulas, recruta_progresso | useAvailableReviews | Sim |
| `v_review_content` | 20260503005000 | aula_midias, aulas | useReviewContent | Sim |
| `v_institutional_notices` | 20260503006000 | institutional_notices, institutional_notice_reads | useInstitutionalNotices | Sim |
| `v_instructor_messages` | 20260503006000 | instructor_messages, instructor_message_reads | useInstructorMessages | Sim |
| `v_billing_status_recruta` | 20260503007000 | recrutas, recruta_billing | billingService (usa `_v2`) | Parcial |
| `v_eventos_pendentes` | 20260503008000 | c5_eventos | c5EventsService | Sim |
| `v_iea_atual` | 20260503009000 | recruta_iea | ieaService (usa `_v2`) | Parcial |
| `v_iea_audit` | 20260503009000 | recruta_iea | ieaService | Sim |
| `v_classificacao_final_ciclo` | 20260503009000 | ciclo_classificacao | eliteService (usa `_v2`) | Parcial |
| `v_elegibilidade_elite` | 20260503009000 | ciclo_classificacao | eliteService (usa `_v2`) | Parcial |
| `v_medals_status` | 20260503010000 | medalhas, recruta_medalhas | useMedals | Sim |
| `v_historico_atividade_recruta` | 20260503010000 | recruta_progresso, xp_eventos, recruta_medalhas, recruta_patentes | useStudentHistory | Sim |
| `v_historico_progresso_recruta` | 20260503010000 | recruta_progresso, xp_eventos, recruta_medalhas | useHistory | Sim |
| `v_ranking_global` | 20260503001000 | xp_eventos, recrutas | não diretamente consumida (ranking desativado) | Não |
| `v_ranking_force` | 20260503001000 | xp_eventos, recrutas | não diretamente consumida | Não |
| `v_recruta_patente_atual` | 20260202183000 | recruta_patentes, patentes_catalogo | v_identidade_recruta | Sim (indireta) |
| `v_historico_patentes` | 20260202183000 | recruta_patentes, patentes_catalogo | não identificado no frontend | Baixo |
| `v_recruta_medalhas` | 20260202123000 | recruta_medalhas, medalhas | não identificado (v_medals_status é preferida) | Baixo |
| `public_recrutas_padrao` | 20260120220000 | profiles | chat-central (legado) | Médio |
| `v_audit_eventos` | 20260120220000 | chat_audit_log | chat-central (write via trigger) | Alto |

### Views sem DDL local (existem no remoto)

| View | Consumidor | Evidência |
|------|------------|-----------|
| `vw_rdm_lessons_v2` | useModuleLessons | código fonte |
| `vw_recruta_module_progress_v2` | useModulesProgress | código fonte |
| `v_billing_status_recruta_v2` | billingService | código fonte |
| `v_iea_atual_v2` | ieaService | código fonte |
| `v_elegibilidade_elite_v2` | eliteService | código fonte |
| `v_classificacao_final_ciclo_v2` | eliteService | código fonte |
| `v_app_bootstrap_institucional_rcc` | bootstrapService | código fonte |
| `v_chat_conversas_recruta` | chatService.loadConversas | código fonte |
| `v_chat_mensagens_recruta` | chatService.loadMensagens | código fonte |
| `v_chat_unread_status` | chatService.loadUnreadStatus | código fonte |
| `v_instrutores_app` | chatService.loadInstructors, rpc_update_instructor_profile | migrations + código fonte |

---

### Materialized Views

| MV | Migration | Fonte | REFRESH Agendado? |
|----|-----------|-------|-------------------|
| `mv_xp_mensal_recruta` | 20260503001000 (recriada) | xp_eventos, recrutas | **NÃO** |
| `mv_ranking_mensal` | 20260503001000 (recriada) | mv_xp_mensal_recruta | **NÃO** |
| `mv_campeao_mensal` | 20260503001000 (recriada) | mv_ranking_mensal | **NÃO** |

---

### Funções / RPCs

| Função | Migration | SECURITY | search_path | Idempotente | Notas |
|--------|-----------|----------|-------------|-------------|-------|
| `check_total_release()` | 20240114185500 | DEFINER | **NÃO** | Sim | Legada, verifica 7 dias |
| `verificar_liberacao_total()` | 20240114214500 | DEFINER | **NÃO** | Não | Legada, usa IDs de exemplo |
| `registrar_xp(amount, desc, source)` | 20240114220000 | DEFINER | **NÃO** | **NÃO** | Crítico: não idempotente |
| `module_progress(recruta_id, modulo_id)` | 20240116140000 | INVOKER | N/A | Sim | Usa tabelas legadas (licoes, recruta_licoes) |
| `recruta_progresso_geral(recruta_id)` | 20240116145000 | INVOKER | N/A | Sim | Usa recruta_modulos |
| `get_student_next_lesson(user_id)` | 20260503012000 (fix) | DEFINER | **NÃO** | Sim | Migrada para schema canônico |
| `fn_insert_audit_evento()` | 20260120220000 | INVOKER | N/A | — | Obsoleta, substituída pela `_smart` |
| `fn_insert_audit_evento_smart()` | 20260120220000 | **INVOKER** | N/A | — | **BUG:** não SECURITY DEFINER, falha ao inserir em chat_audit_log |
| `grant_medal(recruta_id, codigo)` | 20260202123000 | DEFINER | **NÃO** | Sim | Engine de validação com regras dinâmicas |
| `promover_recruta(recruta_id, codigo, motivo)` | 20260202183000 | DEFINER | **NÃO** | Sim | Valida hierarquia de nível |
| `complete_lesson(p_recruta_id, p_lesson_id)` | 20260201221400 | DEFINER | **NÃO** | Sim | **RISCO:** aceita recruta_id externo |
| `rpc_auth_claim_active_client_session(id)` | 20260503003000 | DEFINER | **NÃO** | Sim | Heartbeat de sessão |
| `rpc_auth_resolve_session_state(id)` | 20260503003000 | DEFINER | **NÃO** | Sim (leitura) | Estado institucional |
| `rpc_auth_revoke_client_session(session_id)` | 20260503003000 | DEFINER | **NÃO** | Sim | Revogação de sessão |
| `rpc_complete_onboarding(forca, nome_guerra)` | 20260509001000 | DEFINER | **NÃO** | Sim (UPSERT) | Suporte a Google OAuth; cria row em recrutas |
| `rpc_set_instructor_profile(instructor_id)` | 20260503011000 | DEFINER | **NÃO** | Sim | Aceita codigo (objetivo/estrategico/didatico) |
| `rpc_update_instructor_profile(slug)` | 20260513002000 | DEFINER | **NÃO** | Sim | Aceita slug (ramos/rocha/sara), resolve para codigo |
| `rpc_start_module(modulo_id)` | 20260503011000 | DEFINER | **NÃO** | Sim | ON CONFLICT DO NOTHING |
| `rpc_complete_module(modulo_id)` | 20260503011000 | DEFINER | **NÃO** | Sim | WHERE status != 'completed' |
| `rpc_mark_notice_read(notice_id)` | 20260503006000 | DEFINER | **NÃO** | Sim | ON CONFLICT DO NOTHING |
| `rpc_mark_instructor_message_read(msg_id)` | 20260503006000 | DEFINER | **NÃO** | Sim | ON CONFLICT DO NOTHING |
| `consumir_evento_c5(evento_id)` | 20260503008000 | DEFINER | **NÃO** | Sim | Verifica ownership antes de processar |
| `c9_update_updated_at_column()` | 20260427214001 | INVOKER | N/A | — | Trigger de updated_at para c9_* |
| `fn_auth_session_updated_at()` | 20260503003000 | INVOKER | N/A | — | Trigger updated_at para auth_client_sessions |
| `fn_billing_updated_at()` | 20260503007000 | INVOKER | N/A | — | Trigger updated_at para recruta_billing |
| `fn_sync_xp_evento_aliases()` | 20260503001000 | INVOKER | N/A | — | Trigger de sync recruta_id/xp ↔ user_id/amount |

### RPCs sem DDL local (existem no remoto)

| RPC | Consumidor | Evidência |
|-----|------------|-----------|
| `rpc_chat_open_conversation(p_instrutor_slug)` | chatService | código fonte |
| `rpc_chat_send_message(p_instrutor_slug, p_client_message_id, p_user_text, p_assistant_text, p_correlation_id, p_metadata)` | instrutor-send Edge Function | código fonte |
| `rpc_chat_mark_read(p_conversa_id)` | chatService | código fonte |

---

### Triggers

| Trigger | Tabela | Evento | Timing | Função | Risco |
|---------|--------|--------|--------|--------|-------|
| `trg_insert_audit` | `v_audit_eventos` (view) | INSERT | INSTEAD OF | `fn_insert_audit_evento_smart` | **ALTO:** função não é SECURITY DEFINER — falha silenciosa |
| `trg_sync_xp_evento_aliases` | `xp_eventos` | INSERT/UPDATE | BEFORE | `fn_sync_xp_evento_aliases` | Baixo — manutenção de aliases |
| `trg_auth_session_updated_at` | `auth_client_sessions` | UPDATE | BEFORE | `fn_auth_session_updated_at` | Baixo |
| `trg_billing_updated_at` | `recruta_billing` | UPDATE | BEFORE | `fn_billing_updated_at` | Baixo |
| `set_c9_aula_conteudos_updated_at` | `c9_aula_conteudos` | UPDATE | BEFORE | `c9_update_updated_at_column` | Baixo |
| `set_c9_aula_quizzes_updated_at` | `c9_aula_quizzes` | UPDATE | BEFORE | `c9_update_updated_at_column` | Baixo |

---

### Extensões

| Extensão | Migration | Uso |
|----------|-----------|-----|
| `uuid-ossp` | 20260427214001 | uuid_generate_v4() em tabelas c9_* |
| `pgcrypto` (presumida) | — | gen_random_uuid() usado em várias tabelas |

---

### Storage (Buckets identificados)

| Bucket | DDL Local | Público | Policies | Uso |
|--------|-----------|---------|----------|-----|
| `avatars` | Sim (20240114221000) | Sim | SELECT (todos), INSERT/UPDATE (owner por pasta) | Avatares dos recrutas |
| `institutional-assets` | **NÃO** | Sim (URLs públicas) | Referenciado via GRANTs e INSERT | Assets dos instrutores (avatares, cards, chat icons) |

---

## 3. Mapa de Dependências

### Tabelas Core → Views/RPCs Dependentes

```
recrutas
  ├── v_identidade_recruta (JOIN profiles, v_recruta_patente_atual)
  ├── v_onboarding_status
  ├── v_billing_status_recruta (JOIN recruta_billing)
  ├── v_ranking_global, v_ranking_force (JOIN xp_eventos)
  ├── mv_xp_mensal_recruta, mv_ranking_mensal, mv_campeao_mensal (via xp_eventos)
  ├── v_historico_atividade_recruta (via recruta_progresso, xp_eventos, medalhas, patentes)
  └── rpc_complete_onboarding (UPSERT)

aulas
  ├── v_lessons_panel (JOIN modulos)
  ├── vw_rdm_lessons (JOIN recruta_progresso)
  ├── vw_recruta_module_progress (JOIN modulos, recruta_progresso)
  ├── v_available_reviews (JOIN aula_midias, recruta_progresso)
  ├── recruta_progresso (FK)
  ├── c9_aula_conteudos, c9_aula_flashcards, c9_aula_quizzes (FK)
  └── complete_lesson (lê xp da aula)

xp_eventos
  ├── v_ranking_global, v_ranking_force
  ├── mv_xp_mensal_recruta → mv_ranking_mensal → mv_campeao_mensal
  ├── v_historico_atividade_recruta, v_historico_progresso_recruta
  └── trg_sync_xp_evento_aliases (aliases recruta_id/xp)

auth_client_sessions
  ├── v_auth_session
  ├── v_auth_active_sessions
  ├── rpc_auth_claim_active_client_session
  ├── rpc_auth_resolve_session_state
  └── rpc_auth_revoke_client_session
```

### App/Frontend → Objetos Supabase

```
AuthContext
  ├── v_auth_app_config (versão do contrato)
  ├── v_identidade_recruta (loadProfile)
  ├── rpc_auth_claim_active_client_session (SIGNED_IN)
  └── rpc_auth_resolve_session_state (heartbeat)

bootstrapService
  └── v_app_bootstrap_institucional_rcc  ← NOME NÃO EXISTE em migrations

billingService
  └── v_billing_status_recruta_v2  ← NOME NÃO EXISTE em migrations

ieaService
  ├── v_iea_atual_v2  ← NOME NÃO EXISTE em migrations
  └── v_iea_audit

eliteService
  ├── v_elegibilidade_elite_v2  ← NOME NÃO EXISTE em migrations
  └── v_classificacao_final_ciclo_v2  ← NOME NÃO EXISTE em migrations

useModuleLessons
  └── vw_rdm_lessons_v2  ← NOME NÃO EXISTE em migrations

useModulesProgress
  └── vw_recruta_module_progress_v2  ← NOME NÃO EXISTE em migrations

chatService
  ├── v_chat_conversas_recruta  ← SEM DDL LOCAL
  ├── v_chat_mensagens_recruta  ← SEM DDL LOCAL
  ├── v_chat_unread_status  ← SEM DDL LOCAL
  ├── v_instrutores_app  ← SEM DDL LOCAL (DDL de create)
  ├── rpc_chat_open_conversation  ← SEM DDL LOCAL
  └── rpc_chat_mark_read  ← SEM DDL LOCAL

instrutor-send Edge Function
  ├── v_identidade_recruta (autenticação)
  └── rpc_chat_send_message  ← SEM DDL LOCAL

stripe-create-checkout-session Edge Function
  └── v_identidade_recruta

progressService
  ├── complete_lesson (p_recruta_id, p_lesson_id)
  ├── rpc_start_module
  └── rpc_complete_module

xpService
  └── registrar_xp (não idempotente)

onboardingService
  ├── v_onboarding_status
  └── rpc_complete_onboarding

profileService
  └── rpc_update_instructor_profile (aceita slug)

c5EventsService
  ├── v_eventos_pendentes
  └── consumir_evento_c5
```

---

## 4. Contratos Canônicos do App

| Objeto | Tipo | Consumidor | Campos Críticos | Risco de Breaking Change | Observação |
|--------|------|------------|-----------------|--------------------------|------------|
| `v_identidade_recruta` | VIEW | AuthContext, instrutor-send, stripe | id, auth_id, nome, nome_guerra, patente, forca, nivel_atual, xp, avatar_url, instructor_profile_id, tipo_acesso, onboarding_concluido, ativo | **MÁXIMO** | View mais crítica do sistema |
| `v_auth_app_config` | VIEW | AuthContext | auth_contract_version | Alto | Versão do contrato RCC |
| `v_auth_session` | VIEW | sessionGuardian | session_id, is_active, session_revoked_reason | Alto | Proteção de sessão |
| `v_onboarding_status` | VIEW | onboardingService | recruta_id, onboarding_concluido, forca_definida, nome_guerra_definido | Alto | Pré-onboarding |
| `v_app_bootstrap_institucional_rcc` | VIEW | bootstrapService | qualquer (health check) | Alto | **Nome diverge da migration** |
| `rpc_complete_onboarding` | RPC | onboardingService | p_forca, p_nome_guerra | Alto | UPSERT — cria recruta se não existe |
| `rpc_update_instructor_profile` | RPC | profileService | p_instructor_profile_id (slug) | Alto | Traduz slug → codigo |
| `complete_lesson` | RPC | progressService | p_recruta_id, p_lesson_id | Alto | **RISCO de bypass** |
| `rpc_start_module` | RPC | progressService | p_modulo_id | Médio | Idempotente |
| `rpc_complete_module` | RPC | progressService | p_modulo_id | Médio | Idempotente |
| `rpc_chat_send_message` | RPC | instrutor-send | p_instrutor_slug, p_client_message_id, p_user_text, p_assistant_text, p_correlation_id, p_metadata | **MÁXIMO** | **Sem DDL local** |
| `v_chat_conversas_recruta` | VIEW | chatService | conversa_id, recruta_id, instrutor_slug, unread_count | **MÁXIMO** | **Sem DDL local** |
| `v_chat_mensagens_recruta` | VIEW | chatService | mensagem_id, conversa_id, role, conteudo | **MÁXIMO** | **Sem DDL local** |
| `v_instrutores_app` | VIEW | chatService, useInstructors | slug, codigo, nome, titulo, avatar_url | Alto | Sem DDL de create local |
| `v_billing_status_recruta_v2` | VIEW | billingService | acesso_liberado, plano_atual, status_assinatura | Alto | **Nome diverge da migration** |
| `consumir_evento_c5` | RPC | c5EventsService | p_evento_id | Alto | Idempotente, verifica ownership |
| `v_eventos_pendentes` | VIEW | c5EventsService | id, tipo, titulo, descricao, prioridade | Alto | Filtrada por auth.uid() |

---

## 5. Segurança e RLS

| Tabela/View | RLS Ativo | Policies | Risco | Recomendação |
|-------------|-----------|----------|-------|--------------|
| `recrutas` | Sim | SELECT(authenticated), UPDATE(uid=id) | **ALTO:** sem INSERT policy — quem cria rows? Apenas `rpc_complete_onboarding` (DEFINER) e triggers implícitos | Auditar se INSERT direto é possível via API |
| `profiles` | Sim | UPDATE(uid=id) | **ALTO:** sem SELECT policy documentada localmente — pode estar exposta sem filtro | Verificar policy SELECT no remoto |
| `xp_eventos` | Sim | SELECT(uid=user_id), INSERT(uid=user_id) | **MÉDIO:** INSERT direto permitido para authenticated além da RPC | Remover política INSERT direto; usar apenas DEFINER RPC |
| `aulas` | Sim | SELECT(authenticated) | Baixo | OK para conteúdo público autenticado |
| `modulos` | Sim | SELECT(authenticated) | Baixo | OK |
| `recruta_progresso` | Sim | SELECT(uid=recruta_id) | **MÉDIO:** sem INSERT/UPDATE policy — escrita apenas via `complete_lesson` DEFINER | Verificar se INSERT direto é possível |
| `recruta_medalhas` | Sim | SELECT(uid=recruta_id) | Baixo | Concessão apenas via `grant_medal` DEFINER |
| `recruta_patentes` | Sim | SELECT(uid=recruta_id) | Baixo | Concessão apenas via `promover_recruta` DEFINER |
| `auth_client_sessions` | Sim | SELECT(uid=user_id), ALL(service_role) | Baixo | OK |
| `chat_audit_log` | Sim | ALL(service_role) | **ALTO:** trigger `fn_insert_audit_evento_smart` não é SECURITY DEFINER — inserções via `v_audit_eventos` falham silenciosamente | Tornar função SECURITY DEFINER |
| `recruta_billing` | Sim | SELECT(uid=recruta_id), ALL(service_role) | Baixo | Escrita apenas por Stripe webhook via service_role |
| `c5_eventos` | Sim | SELECT(uid=recruta_id, processado=false), ALL(service_role) | Baixo | Correto |
| `c9_aula_quiz_tentativas` | Sim | SELECT(uid=recruta_id), INSERT(uid=recruta_id), ALL(service_role) | **MÉDIO:** recruta_id referencia auth.users, não recrutas — inconsistência | Normalizar FK para recrutas(id) |
| `institutional_notices` | Sim | SELECT(authenticated, ativo=true), ALL(service_role) | Baixo | OK |
| `mv_xp_mensal_recruta` | Desconhecido | Não identificada em migrations | **MÉDIO:** MV sem RLS pode expor dados de todos os recrutas | Verificar e adicionar RLS ou restringir via view |
| `mv_ranking_mensal` | Desconhecido | Não identificada | **MÉDIO** | Idem |
| `instrutores` | Desconhecido | GRANT SELECT TO authenticated, anon | Baixo — dados públicos de catálogo | OK |
| `institutional_assets` | Desconhecido | GRANT SELECT TO authenticated, anon | Baixo — dados públicos | OK |

### Funções SECURITY DEFINER sem SET search_path (risco de schema injection)

Todas as funções SECURITY DEFINER do projeto não possuem `SET search_path = public, pg_catalog` declarado. Em ambientes com schemas customizados, isso é vetor para substituição de funções por versões maliciosas de outros schemas.

**Afetadas:** `check_total_release`, `verificar_liberacao_total`, `registrar_xp`, `get_student_next_lesson`, `complete_lesson`, `grant_medal`, `promover_recruta`, `rpc_auth_claim_active_client_session`, `rpc_auth_resolve_session_state`, `rpc_auth_revoke_client_session`, `rpc_complete_onboarding`, `rpc_set_instructor_profile`, `rpc_update_instructor_profile`, `rpc_start_module`, `rpc_complete_module`, `rpc_mark_notice_read`, `rpc_mark_instructor_message_read`, `consumir_evento_c5`.

---

## 6. Mérito, XP, Medalhas, Patentes e Rankings

### Fluxo Atual Identificado

```
Ação do Recruta (aula concluída)
  → Frontend: progressService.completeLesson(lessonId, userId)
    → RPC: complete_lesson(p_recruta_id, p_lesson_id)
      → INSERT recruta_progresso ON CONFLICT DO NOTHING  [idempotente]
      → UPDATE recrutas SET xp = xp + aulas.xp  [não idempotente para retries manuais]
      → NÃO emite c5_evento automaticamente
      → NÃO concede medalha automaticamente

Ação do Recruta (módulo concluído)
  → Frontend: progressService.completeModule(moduloId, userId)
    → RPC: rpc_complete_module(p_modulo_id)
      → UPDATE recruta_modulos SET status='completed'  [idempotente]
    → xpService.registerXp(500, desc, moduloId)  [NÃO IDEMPOTENTE]
      → RPC: registrar_xp(500, desc, moduloId)
        → INSERT xp_eventos (ledger)
        → UPDATE recrutas SET xp_total = xp_total + 500

Médio prazo: ranking
  → mv_xp_mensal_recruta: sem REFRESH
  → useRankingList: DESATIVADO no código (retorna lista vazia)
```

### Pontos de Entrada de XP

| Ponto | Idempotente | Fonte | Risco de Bypass |
|-------|-------------|-------|-----------------|
| `complete_lesson` | **Sim** (ON CONFLICT DO NOTHING em recruta_progresso) | aulas.xp | **ALTO:** aceita p_recruta_id externo — qualquer usuário pode completar aulas de outro |
| `registrar_xp` | **NÃO** | chamada direta | **ALTO:** pode ser chamado múltiplas vezes com mesmo source_id |
| `grant_medal` | Sim | medalha_regras engine | Baixo |
| `promover_recruta` | Sim | patente_regras engine + hierarquia de nível | Baixo |

### Lacunas Anti-Fraude

1. **`complete_lesson` aceita `p_recruta_id` externo** — deveria usar `auth.uid()` internamente.
2. **`registrar_xp` não verifica source_id único** — permite replay de bônus de módulo.
3. **Sem trigger de limite de XP diário/por sessão**.
4. **Sem validação cruzada** entre `recrutas.xp` (complete_lesson) e `recrutas.xp_total` (registrar_xp) — dois campos paralelos sem normalização.
5. **`v_ranking_global` e `v_ranking_force` usam `xp_eventos.xp` (ledger completo)** enquanto `v_identidade_recruta` expõe `recrutas.xp` (complete_lesson) — recruta pode ter XP visual diferente do XP do ranking.

### Recomendações

1. Corrigir `complete_lesson` para usar `auth.uid()` como `p_recruta_id`.
2. Adicionar UNIQUE constraint em `xp_eventos(user_id, source_id)` com ON CONFLICT DO NOTHING para tornar `registrar_xp` idempotente.
3. Mover bônus de módulo para dentro de `rpc_complete_module` (SECURITY DEFINER) em vez de chamar `registrar_xp` pelo cliente.
4. Implementar REFRESH da materialized view via pg_cron ou Edge Function agendada.
5. Decidir e normalizar `recrutas.xp` vs `recrutas.xp_total`.

---

## 7. Integrações Detectadas

### Frontend (React Native / Expo)
- **Supabase JS Client:** `src/lib/supabase.ts` — usa `EXPO_PUBLIC_SUPABASE_URL` + `EXPO_PUBLIC_SUPABASE_ANON_KEY`
- **Objetos consumidos:** ~25 views + ~15 RPCs + 3 Edge Functions
- **Auth:** Supabase Auth com onAuthStateChange, SecureStore para client_instance_id, Google OAuth suportado

### Edge Functions
| Função | JWT | Chamador | Propósito |
|--------|-----|----------|-----------|
| `instrutor-send` | verify_jwt=true | App (supabase.functions.invoke) | Orquestra chat: autentica via v_identidade_recruta, chama chat-central, persiste via rpc_chat_send_message |
| `chat-central` | verify_jwt=false (HMAC próprio) | instrutor-send | Chama OpenAI Assistants API. HMAC com QD_HMAC_SECRET |
| `stripe-create-checkout-session` | verify_jwt=true | App (billingService) | Cria Checkout Session na Stripe com metadata institucional |

### OpenAI Integration
- **3 Assistants configurados** (hardcoded em chat-central): marinha, exército, aeronáutica
- `OPENAI_API_KEY` como env var da Edge Function
- Threads OpenAI são efêmeros (criados por request, sem persistência no banco)

### Stripe
- `STRIPE_SECRET_KEY`, `STRIPE_PRICE_ID_MENSAL`, `STRIPE_PRICE_ID_ANUAL` como env vars
- Sem webhook de retorno documentado localmente — `recruta_billing` é atualizado externamente (presumivelmente por webhook Stripe via service_role)

### Jobs / Agendamentos
- **Nenhum pg_cron ou job agendado** identificado nas migrations locais
- Materialized views precisam de REFRESH manual ou externo
- `verificar_liberacao_total()` foi criada para ser chamada via Cron mas sem configuração

---

## 8. Lacunas e Pendências

### Crítico

| # | Evidência | Impacto | Recomendação | Objeto Sugerido |
|---|-----------|---------|--------------|-----------------|
| C1 | `complete_lesson` aceita `p_recruta_id` externo | Qualquer usuário pode completar aulas de outro recruta, ganhando XP indevido | Refatorar para usar `auth.uid()` internamente | Migration: fix_complete_lesson_use_uid |
| C2 | ~12 objetos sem DDL local (chat views/RPCs, _v2 views) | Rollback/migrate destrói o histórico; impossível auditar ou reproduzir o schema | Reverse-engineer via pg_dump remoto e criar migrations de captura | Migrations: capture_remote_objects_* |
| C3 | Tabelas core (`recrutas`, `profiles`, `recruta_modulos`, `instrutores`, `institutional_assets`) sem DDL local | Impossível recriar o banco do zero com as migrations locais | Exportar DDL do remoto e criar migration inicial | Migration: 00000000000000_baseline_schema |
| C4 | `fn_insert_audit_evento_smart` não é SECURITY DEFINER | Inserções via `v_audit_eventos` falham silenciosamente — histórico de chat não é auditado | Adicionar SECURITY DEFINER ou remover dependência da view writable | Migration: fix_audit_trigger_security_definer |
| C5 | `bootstrapService.ts` usa `v_app_bootstrap_institucional_rcc` mas migration cria `v_app_bootstrap_institucional` | App falha silenciosamente no bootstrap check | Criar view com nome canônico ou renomear no app | Migration: create_v_app_bootstrap_institucional_rcc |

### Alto

| # | Evidência | Impacto | Recomendação | Objeto Sugerido |
|---|-----------|---------|--------------|-----------------|
| A1 | `registrar_xp` não é idempotente | Bônus de módulo pode ser duplicado via retry | Tornar idempotente via UNIQUE(user_id, source_id) ON CONFLICT DO NOTHING | Migration: make_registrar_xp_idempotent |
| A2 | Materialized views sem REFRESH agendado | Ranking sempre desatualizado | Configurar pg_cron para REFRESH periódico | Migration: schedule_mv_refresh |
| A3 | Todas as funções SECURITY DEFINER sem `SET search_path` | Vetor de schema injection | Adicionar `SET search_path = public, pg_catalog` | Migration: fix_definer_functions_search_path |
| A4 | `xp_eventos` tem política INSERT para authenticated | Usuários podem inserir eventos XP diretamente | Remover política INSERT; usar apenas DEFINER RPC | Migration: fix_xp_eventos_rls |
| A5 | `allowed_modules` em `public_recrutas_padrao` sempre retorna array vazio | Controle de acesso de chat por módulo não funciona | Popular com lógica real ou documentar como intencionalmente vazio | Migration: fix_allowed_modules_logic |
| A6 | `c9_aula_quiz_tentativas.recruta_id` referencia `auth.users` (não `recrutas`) | Inconsistência com o padrão do projeto | Migrar FK para `recrutas(id)` | Migration: fix_c9_tentativas_fk |

### Médio

| # | Evidência | Impacto | Recomendação |
|---|-----------|---------|--------------|
| M1 | `vw_rdm_lessons`, `vw_recruta_module_progress` existem localmente mas app usa `_v2` | Views corretas são ignoradas | Verificar se _v2 é superset e unificar |
| M2 | `recrutas.xp` vs `recrutas.xp_total` — dois campos paralelos | XP inconsistente entre ranking e identidade | Decisão institucional de normalização |
| M3 | `module_progress()` e `recruta_progresso_geral()` usam tabelas legadas (licoes, recruta_licoes) | Funções quebradas para schema atual | Deprecar ou migrar para schema canônico |
| M4 | `check_total_release()` usa lógica de 7 dias em `recrutas.created_at` | Lógica de acesso legada, possivelmente substituída por `recruta_billing` | Avaliar deprecação |
| M5 | `instrutor-send` acessa `identidade.thread_id` que não existe em `v_identidade_recruta` | Sempre null — sem impacto funcional mas lógica morta | Remover referência |
| M6 | Sem DDL local para `storage.institutional-assets` bucket | Bucket não versionado | Adicionar criação do bucket às migrations |
| M7 | `v_historico_patentes` e `v_recruta_medalhas` existem mas não são consumidas pelo frontend | Views órfãs | Documentar ou deprecar |
| M8 | `v_iea_audit` referenciada por `ieaService` como HEAD check mas não tem RLS explícita | Pode expor dados de outros recrutas | Verificar filtro por auth.uid() |

### Baixo

| # | Evidência | Impacto | Recomendação |
|---|-----------|---------|--------------|
| B1 | `verificar_liberacao_total()` usa IDs de exemplo hardcoded | Função não funcional para produção | Deprecar ou implementar |
| B2 | `RP Page` na pasta migrations (arquivo vazio/inválido) | Arquivo inválido na pasta de migrations | Remover |
| B3 | `useRankingList` desabilitado no código (retorna lista vazia) | Ranking não exibido | Aguardar decisão institucional |
| B4 | OpenAI thread IDs não persistidos | Sem histórico de thread por conversa (novo thread a cada mensagem) | Avaliar persistência de thread_id por conversa |
| B5 | `modo=payment` no Stripe (não `subscription`) | Não suporta cobrança recorrente | Avaliar mudança para `subscription` |

---

## 9. Backlog Técnico Recomendado

### Correções de Segurança (Prioridade 1)
1. Corrigir `complete_lesson` para usar `auth.uid()` internamente
2. Adicionar `SET search_path = public, pg_catalog` a todas as funções SECURITY DEFINER
3. Tornar `fn_insert_audit_evento_smart` SECURITY DEFINER
4. Remover policy INSERT direto em `xp_eventos` para `authenticated`
5. Tornar `registrar_xp` idempotente

### Correções de Integridade (Prioridade 2)
1. Criar migration baseline com DDL de `recrutas`, `profiles`, `recruta_modulos`, `instrutores`, `institutional_assets`
2. Capturar DDL de todos os objetos `_v2` e chat do remoto
3. Criar migration para storage bucket `institutional-assets`
4. Corrigir FK de `c9_aula_quiz_tentativas.recruta_id` para `recrutas(id)`
5. Normalizar `aulas.module_id` vs `aulas.modulo_id`

### Views Canônicas (Prioridade 3)
1. Criar `v_app_bootstrap_institucional_rcc` (ou alias) para alinhar com bootstrapService
2. Criar DDL local de `v_instrutores_app`
3. Documentar divergências `_v2` — unificar ou versionar explicitamente

### RPCs Institucionais (Prioridade 3)
1. Mover bônus XP de módulo para dentro de `rpc_complete_module`
2. Criar DDL local de `rpc_chat_send_message`, `rpc_chat_open_conversation`, `rpc_chat_mark_read`
3. Deprecar `module_progress()` e `recruta_progresso_geral()` (tabelas legadas)

### Índices / Performance (Prioridade 4)
1. Índice em `recruta_progresso(recruta_id, lesson_id)` já existe (UNIQUE)
2. Índice em `aulas(modulo_id)` — verificar se existe no remoto
3. Índice em `modulos(forca, order)` para queries de currículo

### Auditoria / Logs (Prioridade 4)
1. Configurar REFRESH periódico das materialized views via pg_cron
2. Adicionar audit log para `grant_medal` e `promover_recruta` (quem chamou, quando)
3. Verificar se `chat_audit_log` está de fato sendo populado

### Rollbacks / Migrations (Prioridade 2)
1. Todas as migrations futuras devem incluir seção `ROLLBACK` como as mais recentes já fazem
2. Migrations de captura do remoto devem ser marcadas como `[CAPTURE]` para rastreabilidade

---

## 10. Próximas Migrations Sugeridas

| # | Nome Sugerido | Objetivo | Objetos Afetados | Risco | Dependências |
|---|---------------|----------|-----------------|-------|--------------|
| 1 | `20260516001000_fix_complete_lesson_use_auth_uid` | Corrigir bypass de XP — usar auth.uid() interno | `complete_lesson` | **Alto** — breaking change de assinatura | recrutas, recruta_progresso |
| 2 | `20260516002000_fix_search_path_definer_functions` | Blindar contra schema injection | Todas as SECURITY DEFINER funcs | Médio | — |
| 3 | `20260516003000_fix_audit_trigger_security_definer` | Corrigir inserção em chat_audit_log | `fn_insert_audit_evento_smart` | Baixo | chat_audit_log |
| 4 | `20260516004000_make_xp_eventos_unique_source` | Tornar registrar_xp idempotente | `xp_eventos`, `registrar_xp` | Médio — backfill necessário | xp_eventos |
| 5 | `20260516005000_create_v_app_bootstrap_institucional_rcc` | Alinhar nome com bootstrapService | Nova view alias | Baixo | v_app_bootstrap_institucional |
| 6 | `20260516006000_schedule_mv_refresh_pg_cron` | Agendar REFRESH das MVs | pg_cron, mv_xp_mensal_recruta | Médio — requer extensão pg_cron | mv_* |
| 7 | `20260516007000_capture_baseline_schema` | Capturar DDL de tabelas sem migration local | recrutas, profiles, recruta_modulos, instrutores, institutional_assets | Alto — auditar remoto antes | — |
| 8 | `20260516008000_capture_chat_objects` | Capturar DDL de chat (conversas, mensagens, unread, RPCs) | v_chat_*, rpc_chat_*, tabelas de chat | Alto | instrutor-send |
| 9 | `20260516009000_capture_v2_views` | Capturar DDL das views _v2 | 7 views _v2 | Médio | tabelas base |
| 10 | `20260516010000_move_module_xp_bonus_to_rpc` | Mover bônus XP para rpc_complete_module | rpc_complete_module, progressService | Médio | registrar_xp |

---

## 11. Anexos Técnicos

### Queries de Auditoria Utilizadas (Somente Leitura)

Todas as informações foram obtidas via leitura de arquivos locais do repositório — sem execução de queries no banco remoto.

```sql
-- Queries equivalentes que podem ser executadas no banco remoto para validação:

-- 1. Schemas e tabelas
SELECT schemaname, tablename, tableowner
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, tablename;

-- 2. Views
SELECT schemaname, viewname, definition
FROM pg_views
WHERE schemaname = 'public'
ORDER BY viewname;

-- 3. Materialized Views
SELECT schemaname, matviewname, hasindexes, ispopulated
FROM pg_matviews
WHERE schemaname = 'public';

-- 4. Funções SECURITY DEFINER
SELECT n.nspname, p.proname, pg_get_functiondef(p.oid) as def,
       p.prosecdef as security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
ORDER BY p.proname;

-- 5. Políticas RLS
SELECT schemaname, tablename, policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- 6. Índices
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- 7. Triggers
SELECT trigger_name, event_object_table, event_manipulation, action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- 8. Verificar objetos sem DDL local (objetos presentes no remoto mas ausentes das migrations)
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_type = 'FUNCTION'
ORDER BY routine_name;

-- 9. Storage buckets
SELECT id, name, public, created_at
FROM storage.buckets
ORDER BY created_at;

-- 10. Verificar pg_cron jobs
SELECT jobname, schedule, command, active
FROM cron.job
ORDER BY jobname;
```

### Objetos Remotos Sem DDL Local — Lista Consolidada

```
TABELAS:
  - public.recrutas
  - public.profiles
  - public.recruta_modulos
  - public.instrutores
  - public.institutional_assets
  - public.chat_conversas (presumida — base de v_chat_conversas_recruta)
  - public.chat_mensagens (presumida — base de v_chat_mensagens_recruta)
  - public.chat_unread (presumida — base de v_chat_unread_status)

VIEWS:
  - public.v_app_bootstrap_institucional_rcc
  - public.v_billing_status_recruta_v2
  - public.vw_rdm_lessons_v2
  - public.vw_recruta_module_progress_v2
  - public.v_iea_atual_v2
  - public.v_elegibilidade_elite_v2
  - public.v_classificacao_final_ciclo_v2
  - public.v_instrutores_app
  - public.v_chat_conversas_recruta
  - public.v_chat_mensagens_recruta
  - public.v_chat_unread_status

FUNÇÕES:
  - public.rpc_chat_open_conversation
  - public.rpc_chat_send_message
  - public.rpc_chat_mark_read

STORAGE:
  - institutional-assets (bucket)
```
