# Matriz de Risco — Auditoria Supabase Quartel Digital
**Data:** 2026-05-16

---

## Legenda de Severidade

| Nível | Cor | Critério |
|-------|-----|---------|
| CRÍTICO | 🔴 | Risco ativo de segurança, corrupção de dados ou indisponibilidade do app |
| ALTO | 🟠 | Risco funcional grave ou vulnerabilidade explorável |
| MÉDIO | 🟡 | Degradação silenciosa ou inconsistência estrutural |
| BAIXO | 🟢 | Dívida técnica ou melhoria de qualidade |

---

## Riscos de Segurança

| ID | Severidade | Objeto | Descrição | Exploitabilidade | Impacto | Recomendação |
|----|-----------|--------|-----------|-----------------|---------|--------------|
| SEC-01 | 🔴 CRÍTICO | `complete_lesson(p_recruta_id, p_lesson_id)` | Qualquer usuário autenticado pode passar o UUID de outro recruta como `p_recruta_id`. A função é SECURITY DEFINER e não verifica `auth.uid() = p_recruta_id`. | Alta — basta conhecer o UUID de outro recruta (visível em `v_ranking_global`) | Qualquer recruta ganha XP de qualquer aula em nome de qualquer outro usuário | Reescrever para usar `auth.uid()` internamente. Remover parâmetro `p_recruta_id` ou adicionar `IF p_recruta_id != auth.uid() THEN RAISE EXCEPTION`. |
| SEC-02 | 🟠 ALTO | `registrar_xp(amount, description, source_id)` | Função não idempotente chamada diretamente pelo cliente após `rpc_complete_module`. Retry ou replay do cliente duplica o bônus de 500 XP. | Média — requer retry de rede ou chamada manual via RPC | XP infinito por módulo; ranking inflado | Mover lógica de bônus para `rpc_complete_module` (SECURITY DEFINER) ou adicionar UNIQUE(user_id, source_id) |
| SEC-03 | 🟠 ALTO | Todas as SECURITY DEFINER sem `SET search_path` | Se um schema atacante for inserido no `search_path` da sessão, as funções podem ser redirecionadas para objetos maliciosos. | Baixa em Supabase gerenciado, mas não zero | Escalada de privilégio ou execução de código não autorizado | `ALTER FUNCTION nome SET search_path = public, pg_catalog;` para todas as ~19 funções DEFINER |
| SEC-04 | 🟠 ALTO | `xp_eventos` — policy INSERT para `authenticated` | Usuários podem inserir eventos XP diretamente via API (sem passar pela RPC `registrar_xp`). Embora `user_id` seja limitado pelo `WITH CHECK (auth.uid() = user_id)`, o `amount` não tem validação — valores negativos ou absurdamente altos são possíveis. | Média | Manipulação direta do ledger de XP | `DROP POLICY "Recruta pode inserir eventos para si mesmo" ON xp_eventos;` — escrita apenas via DEFINER RPC |
| SEC-05 | 🟠 ALTO | `fn_insert_audit_evento_smart` — INVOKER sem DEFINER | O trigger na view `v_audit_eventos` executa como o usuário chamador (role `authenticated`), mas `chat_audit_log` só permite `service_role`. Toda inserção via `v_audit_eventos` falha silenciosamente com permission denied. | Impacto no usuário: nenhum (falha oculta). Impacto na auditoria: log de chat corrompido. | Auditoria de interações de chat inoperante | `CREATE OR REPLACE FUNCTION fn_insert_audit_evento_smart() ... SECURITY DEFINER` |
| SEC-06 | 🟡 MÉDIO | `recruta_progresso` — sem policy INSERT/UPDATE explícita | Escrita depende exclusivamente de `complete_lesson` (DEFINER). Se DEFINER falhar, usuário não tem fallback direto. Mas sem policy explícita de BLOCK, inserts diretos podem ser possíveis dependendo do default do Supabase com RLS. | Baixa se RLS está ativo (default deny) | Progresso fraudulento se INSERT direto for possível | Verificar comportamento padrão; adicionar policy explícita `FOR INSERT USING (false)` se necessário |

---

## Riscos de Integridade de Dados

| ID | Severidade | Objeto | Descrição | Impacto | Recomendação |
|----|-----------|--------|-----------|---------|--------------|
| INT-01 | 🔴 CRÍTICO | Banco remoto ahead das migrations locais | ~12 objetos ativos no app (`_v2` views, chat views/RPCs) sem DDL local. Impossível reproduzir o schema a partir do repositório. | Perda total do schema em caso de rollback ou disaster recovery | Reverse-engineer via `pg_dump --schema-only` do remoto + criar migrations de captura |
| INT-02 | 🔴 CRÍTICO | Tabelas core sem DDL local (`recrutas`, `profiles`, `recruta_modulos`, `instrutores`, `institutional_assets`) | Schema fundacional do app não versionado. | Impossível recriar banco do zero; audit trail incompleto | Exportar DDL do remoto e criar migration baseline `00000000000000_baseline_schema.sql` |
| INT-03 | 🟠 ALTO | `mv_xp_mensal_recruta`, `mv_ranking_mensal`, `mv_campeao_mensal` sem REFRESH | Dados do ranking ficam congelados no momento da última migration | Ranking exibe dados desatualizados indefinidamente | `SELECT cron.schedule('refresh-mv', '0 * * * *', 'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_xp_mensal_recruta; REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ranking_mensal; REFRESH MATERIALIZED VIEW CONCURRENTLY mv_campeao_mensal;')` |
| INT-04 | 🟠 ALTO | `recrutas.xp` vs `recrutas.xp_total` — campos paralelos desincronizados | `xp` é atualizado por `complete_lesson` (aulas). `xp_total` é atualizado por `registrar_xp` (eventos). `v_identidade_recruta` expõe `recrutas.xp`. Rankings usam `xp_eventos.xp` (ledger completo). Três fontes de verdade para XP. | Recruta vê XP diferente na identidade vs ranking vs histórico | Normalização institucional: decidir campo canônico e consolidar |
| INT-05 | 🟡 MÉDIO | `aulas.module_id` vs `aulas.modulo_id` | Migrations legadas (20240114223000, 20260129133000) inserem em `module_id`. View canônica (20260131002700) usa `modulo_id`. A coluna foi renomeada no remoto sem migration local. | JOIN incorretos em migrations legadas | Criar migration documentando a renomeação; atualizar migrations legadas com comentário |
| INT-06 | 🟡 MÉDIO | `c9_aula_quiz_tentativas.recruta_id → auth.users(id)` | Todas as outras tabelas referenciam `recrutas(id)`. Esta tabela aponta para `auth.users` diretamente. | Inconsistência; cascade delete pode ter comportamento diferente | `ALTER TABLE c9_aula_quiz_tentativas DROP CONSTRAINT ...; ADD CONSTRAINT ... FOREIGN KEY (recruta_id) REFERENCES public.recrutas(id)` |
| INT-07 | 🟡 MÉDIO | `allowed_modules` em `public_recrutas_padrao` sempre `ARRAY[]::text[]` | Campo criado para controle de acesso do chat por módulo mas nunca populado | Controle de acesso pedagógico do chat inoperante | Implementar join real com `recruta_modulos` ou deprecar o campo |
| INT-08 | 🟡 MÉDIO | `module_progress()` e `recruta_progresso_geral()` usam tabelas legadas (`licoes`, `recruta_licoes`) | Funções retornam erro ou zero para o schema atual | Funções quebradas | Deprecar ou reescrever apontando para `aulas` e `recruta_progresso` |

---

## Riscos de Disponibilidade / Operacionais

| ID | Severidade | Objeto | Descrição | Impacto | Recomendação |
|----|-----------|--------|-----------|---------|--------------|
| OPS-01 | 🔴 CRÍTICO | `bootstrapService` usa `v_app_bootstrap_institucional_rcc` | View com esse nome não existe nas migrations locais. Se o remoto também não tiver, o app falha no cold start. | App não inicializa para nenhum usuário | Criar view com nome correto ou corrigir o código do serviço |
| OPS-02 | 🟠 ALTO | `billingService` usa `v_billing_status_recruta_v2` | Tela de billing falha silenciosamente ou lança erro | Usuários não conseguem ver status de assinatura | Criar view ou alinhar nome |
| OPS-03 | 🟠 ALTO | `useModuleLessons` usa `vw_rdm_lessons_v2` | Lista de aulas vazia para todos os módulos | Usuários não conseguem ver/acessar aulas | Criar view ou alinhar nome |
| OPS-04 | 🟠 ALTO | `useModulesProgress` usa `vw_recruta_module_progress_v2` | Lista de módulos sem progresso | Dashboard de progresso vazio | Criar view ou alinhar nome |
| OPS-05 | 🟠 ALTO | `useRankingList` desabilitado no código | Tela de ranking não exibe dados | Funcionalidade de ranking inoperante | Aguardar decisão institucional para reativar |
| OPS-06 | 🟡 MÉDIO | OpenAI thread IDs não persistidos | Cada mensagem cria um novo thread. Sem contexto de conversa entre mensagens. | Instrutor "esquece" o contexto da conversa a cada pergunta | Persistir `thread_id` por conversa em tabela de chat |
| OPS-07 | 🟢 BAIXO | Stripe `mode=payment` (não `subscription`) | Pagamento único não suporta renovação automática | Usuários precisam pagar novamente para renovar | Avaliar migração para `mode=subscription` |
| OPS-08 | 🟢 BAIXO | `verificar_liberacao_total()` com IDs de exemplo hardcoded | Função inutilizável em produção | Cron/agendamento não funciona | Deprecar ou implementar com IDs reais |

---

## Resumo Executivo de Risco

| Severidade | Quantidade | Status |
|-----------|-----------|--------|
| 🔴 CRÍTICO | 5 | SEC-01, INT-01, INT-02, OPS-01 (+ complete_lesson) |
| 🟠 ALTO | 9 | SEC-02 a SEC-05, INT-03/04, OPS-02 a 05 |
| 🟡 MÉDIO | 8 | SEC-06, INT-05 a 08, OPS-06 |
| 🟢 BAIXO | 3 | OPS-07/08 + arquivo RP Page |
| **Total** | **25** | |

---

## Priorização para Sprint de Segurança

**Sprint 1 — Correções Críticas (antes do próximo deploy):**
1. `SEC-01` — Corrigir `complete_lesson` (XP bypass)
2. `INT-01/02` — Capturar DDL do remoto (chat + _v2 + tabelas core)
3. `OPS-01` — Criar `v_app_bootstrap_institucional_rcc`

**Sprint 2 — Hardening (próximas 2 semanas):**
4. `SEC-02` — Idempotência de `registrar_xp`
5. `SEC-03` — `SET search_path` em todas as DEFINER funcs
6. `SEC-04` — Remover INSERT direto em `xp_eventos`
7. `SEC-05` — `fn_insert_audit_evento_smart` → SECURITY DEFINER
8. `INT-03` — REFRESH de MVs via pg_cron

**Sprint 3 — Integridade (próximo ciclo):**
9. `INT-04` — Normalização de `recrutas.xp` vs `xp_total`
10. `INT-05/06` — FK de c9_tentativas + documentar renomeação de colunas
11. Operacionais (`OPS-02` a `OPS-06`)
