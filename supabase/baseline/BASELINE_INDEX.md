# Baseline Index — Quartel Digital Supabase

**Data geração:** 2026-05-16
**Dump origem:** `supabase/remote/supabase_remote_schema.sql`
**Total de linhas no dump:** ~19.300

---

## Resumo Executivo de Objetos

| Tipo | Schema public | Schema auth | Schema storage | Total |
|------|:-------------:|:-----------:|:--------------:|:-----:|
| Tabelas | ~85 | ~18 | 8 | **~111** |
| Views regulares | ~110 | 0 | 0 | **~110** |
| Materialized Views | 6 | 0 | 0 | **6** |
| Funções/RPCs | ~80 | 4 | 0 | **~84** |
| Triggers | ~15 | 0 | 0 | **~15** |
| Índices | ~80 | ~35 | ~10 | **~125** |
| RLS Policies | ~130 | ~16 | 0 | **~146** |
| Tipos ENUM | 0 | 7 | 1 | **8** |

---

## Tabelas por Domínio

### Core / Identidade
- `recrutas` — perfil gamificado principal (id = auth.uid via auth_id)
- `profiles` — perfil institucional (id = auth.uid)
- `forcas` — catálogo de forças armadas
- `auth_client_revocations`, `auth_client_singleton` — gestão de sessão device
- `auth_session_revocations`, `auth_session_singleton` — gestão de sessão JWT
- `recruta_status` — status gamificado do recruta

### Chat RCC-0.5 Wave 1
- `chat_conversas` — conversas recruta↔instrutor
- `chat_mensagens` — mensagens individuais com idempotência
- `chat_reads` — marcação de leitura
- `chat_events` — eventos de chat (tracking)
- `chat_logs` — logs de operações chat
- `chat_summaries` — sumários de thread por recruta
- `chat_threads` — threads legados
- `chat_audit_log` — auditoria imutável
- `conversation_locks` — locks distribuídos de conversação
- `instrutor_threads` — threads por instrutor (legado)
- `instrutores` — catálogo de personas visuais dos instrutores

### C5 / Gamificação / Medalhas / Patentes
- `eventos_institucionais` — ledger C5 (imutável)
- `c5_audit_eventos_institucionais` — auditoria do C5
- `c5_alertas_operacionais` — alertas do motor C5
- `c5_fatos_analytics` — fatos analíticos C5
- `c5_jobs_execucao_log` — log de jobs C5
- `c5_metricas_diarias` — métricas diárias C5
- `c5_metricas_recruta` — métricas por recruta
- `c5_regras_alerta` — regras de alerta C5
- `c5_taxonomia_eventos` — taxonomia dos tipos de evento
- `medalhas_catalogo` — catálogo de medalhas
- `medalha_regras` — regras de concessão
- `medalhas_concedidas` — medalhas concedidas (append-only via service_role)
- `medalhas_concessao_log` — log de concessão
- `medalhas_eventos`, `recruta_medalhas_eventos` — eventos relacionados a medalhas
- `medalhas_obrigatorias_map` — mapeamento de medalhas obrigatórias
- `medalhas_slug_aliases`, `medalhas_catalogo_versionamento` — versionamento
- `patentes_catalogo` — catálogo de patentes
- `patente_regras` — regras de promoção
- `recruta_patentes` — patentes do recruta
- `c7_ciclos`, `c7_execucao_diaria_log`, `c7_regras_bloqueio_*` — auditoria C7

### Aprendizagem / Módulos / Aulas
- `modulos` — catálogo de módulos
- `aulas` — catálogo de aulas (coluna canônica: modulo_id)
- `recruta_modulos` — progresso por módulo
- `recruta_progresso` — progresso por aula (tabela canônica)
- `recruta_progressos_modulos` — progresso modular (legado?)
- `c9_aula_conteudos`, `c9_aula_flashcards`, `c9_aula_quizzes` — didática C9
- `c9_aula_quiz_perguntas`, `c9_aula_quiz_alternativas`, `c9_aula_quiz_tentativas` — quiz C9
- `aulas_concluidas` — (legado) marcação de conclusão
- `lessons`, `lesson_media`, `lesson_progress` — (legado) tabelas do sistema antigo
- `licoes` — (legado) conteúdo de lições antigas

### Billing
- `billing_assinaturas` — assinaturas (gateway)
- `billing_pagamentos` — pagamentos processados
- `billing_eventos` — eventos de billing
- `billing_notificacoes_log` — notificações enviadas
- `billing_reconciliacao` — reconciliações
- `billing_reconciliation_issues` — problemas de reconciliação
- `modelos_precificacao_versionada` — histórico de preços de modelos AI

### Ranking / IEA / Elite
- `xp_eventos` — ledger de XP (append-only via service_role)
- `ciclos_formativos` — ciclos de formação
- `iea_snapshots` — snapshots de IEA por ciclo
- `recruta_ciclo_status` — status do recruta no ciclo
- `iea_marcos_emitidos` — marcos de IEA já emitidos para C5
- `ranking_periodos`, `ranking_resultados` — ranking histórico
- `campeoes_mensais` — campeões mensais por força

### Storage / Assets
- `institutional_assets` — assets institucionais versionados
- `institutional_notices`, `institutional_notice_reads` — avisos institucionais
- `instructor_messages`, `instructor_message_reads` — mensagens do instrutor

### Legado / Misc
- `xp_events` — (legado) tabela de XP antiga
- `user_xp` — (legado) saldo de XP antigo
- `progresso_recruta`, `progresso_aulas`, `progresso_missoes` — (legado)
- `missoes`, `revisoes`, `cronograma_semanal` — gamificação legada
- `roles`, `sessions`, `users`, `usuarios` — (legado) auth antigo
- `os_tasks`, `os_task_logs` — tasks do sistema operacional
- `automacoes_execucoes` — execuções de automações

---

## Contratos Críticos por Domínio

### Chat (RCC-0.5 Wave 1)
- `v_chat_conversas_recruta` — listagem de conversas do recruta
- `v_chat_mensagens_recruta` — mensagens de uma conversa
- `v_chat_unread_status` — status de mensagens não lidas
- `rpc_chat_open_conversation` — abrir/criar conversa
- `rpc_chat_send_message` — enviar mensagem
- `rpc_chat_mark_read` — marcar como lida

### Auth / Identidade
- `v_identidade_recruta` — perfil completo (contrato de login)
- `v_auth_app_config` — versão do contrato (auth_contract_version)
- `v_app_bootstrap_institucional_rcc` — bootstrap do app
- `v_onboarding_status` — status de onboarding

### Aprendizagem
- `vw_rdm_lessons_v2` — lista de aulas do recruta
- `vw_recruta_module_progress_v2` — progresso por módulo
- `complete_lesson` — LEGACY/FALLBACK (Sprint 2 — sem callers do app; manter até Sprint 3+ com confirmação de zero tráfego)
- `rpc_complete_lesson` — CANONICAL (P1-M1 Sprint 2 FASE 2 CONCLUÍDA 2026-05-18) — server-authoritative, auth_id resolution, aulas.xp_valor

### Ranking / Gamificação
- `v_ranking_mensal_rcc` — ranking mensal RCC
- `v_posicao_recruta_mes_rcc` — posição do recruta no mês
- `v_medals_status_v2` — status de medalhas

### Billing
- `v_billing_status_recruta_v2` — status de acesso/assinatura

---

## Lista P0 — Itens Críticos Imediatos

1. **`buscar_revisoes_whatsapp` sem search_path** — SECURITY DEFINER vulnerável
2. **`complete_lesson` aceita p_recruta_id** — MITIGADO (P0-M6 auth guard + P1-M1 rpc_complete_lesson canonical em Sprint 2)
3. **`xp_events` (legada) permite INSERT por authenticated** — risco de manipulação de XP
4. **`v_medals_status` original ausente** — frontend pode estar usando v2 ou versão inexistente
5. **Refresh de materialized views não agendado** — `mv_ranking_mensal`, `mv_xp_mensal_recruta`, `mv_campeao_mensal` podem estar desatualizadas
6. **`rpc_complete_onboarding` tem 2 sobrecargas** — risco de chamada incorreta
7. **INSERT direto em `recruta_progresso` por authenticated** — bypass do contrato canônico

---

## Lista P1 — Alta Prioridade

1. Criar refresh agendado para materialized views (mv_ranking_mensal, mv_xp_mensal_recruta, mv_campeao_mensal)
2. Verificar policies de `institutional_notices` e `instructor_messages`
3. Verificar policies de `chat_conversas` para authenticated
4. Documentar e deprecar tabelas legadas: `lessons`, `lesson_progress`, `lesson_media`, `licoes`
5. Confirmar que `aulas.modulo_id` (não `module_id`) é a coluna canônica no remoto

---

## Ordem Recomendada de Remediação

1. P0.1 — Adicionar search_path a `buscar_revisoes_whatsapp`
2. P0.2 — Bloquear INSERT em `xp_events` para authenticated
3. P0.3 — Documentar acesso a `chat_conversas`
4. P0.4 — Remover sobrecarga obsoleta de `rpc_complete_onboarding` (se confirmado)
5. P1.1 — Agendamento refresh materialized views
6. P1.2 — Corrigir complete_lesson para usar auth.uid() internamente
7. P1.3 — Idempotência de `registrar_xp` (se função existir)
8. P2.1 — Deprecar/remover tabelas legadas com sunset plan
