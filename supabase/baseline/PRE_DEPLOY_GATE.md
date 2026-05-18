# PRE_DEPLOY_GATE — Pacote P0 (M1–M6)
**Data da revisão:** 2026-05-17
**Escopo:** Migrations P0-M1 a P0-M6 para apply em staging
**Revisor:** Claude Code — análise estática completa
**Fontes lidas:** migrations (×5), handoffs (×6), P0_DECISION_PACKET.md, NEXT_SAFE_MIGRATIONS.md, P0_M6_PRE_AUDIT.md

---

## VEREDICTO EXECUTIVO

| Status | Detalhe |
|--------|---------|
| **✅ LIBERADO PARA STAGING** | 5 migrations passaram em todos os checks |
| **⚠ P0-M4 — PRÉ-CONDIÇÃO PENDENTE** | Verificação manual de dashboards externos obrigatória antes do apply |
| **📝 3 OBSERVAÇÕES** | Não bloqueantes — documentadas em §8 |

---

## CHECK 1 — Ordem de Execução

### 1.1 Timestamps

| Posição | Migration | Timestamp | Arquivo |
|---------|-----------|-----------|---------|
| 1 | P0-M1 | `20260516001000` | `..._p0_m1_fix_buscar_revisoes_whatsapp_search_path.sql` |
| 2 | P0-M2 | `20260516002000` | `..._p0_m2_register_baseline_audit.sql` |
| 3 | P0-M3 | `20260516003000` | **VOID — arquivo não existe — correto** |
| 4 | P0-M4 | `20260516004000` | `..._p0_m4_block_xp_events_legacy_insert.sql` |
| 5 | P0-M5 | `20260516005000` | `..._p0_m5_register_contract_registry.sql` |
| 6 | P0-M6 | `20260516006000` | `..._p0_m6_fix_complete_lesson_auth_guard.sql` |

Os timestamps são sequenciais, sem lacunas conflitantes e sem sobreposição. Supabase aplica migrations em ordem crescente de timestamp — a sequência está correta.

A ausência de arquivo físico para `20260516003000` é intencional (VOID). O Supabase CLI aplica apenas arquivos existentes na pasta migrations; o "slot" 003000 é simplesmente pulado. Nenhum problema.

### 1.2 Consistência com Decision Packet §1

O Decision Packet §1 define a ordem: M1 → M2 → ~~M3~~ → M4 → M5 → M6. Os arquivos de migration existentes seguem exatamente esta ordem.

**RESULTADO: ✅ PASS**

---

## CHECK 2 — Dependências Cruzadas

### 2.1 Dependência técnica entre migrations

| Migration | Depende de | Objeto existente antes? | Status |
|-----------|-----------|------------------------|--------|
| P0-M1 | `buscar_revisoes_whatsapp()` | ✓ dump ln 833 | ✓ OK |
| P0-M2 | `_qd_migration_snapshots` | ✓ dump ln 9018 | ✓ OK |
| P0-M4 | `xp_events` (tabela) | ✓ dump ln 14497 | ✓ OK |
| P0-M5 | `c6_contract_registry` | ✓ dump ln 9765 | ✓ OK |
| P0-M6 | `complete_lesson()` | ✓ dump ln 1182 | ✓ OK |

Nenhuma migration cria um objeto que outra migration posterior depende. Todas operam sobre objetos **já existentes no dump remoto**.

### 2.2 Dependência lógica (P0-M5 após P0-M2)

NEXT_SAFE_MIGRATIONS.md recomenda P0-M5 "após P0-M2". Esta dependência é **lógica** (garante que o baseline esteja registrado antes do registry de contratos), não técnica. As tabelas são independentes. Ambas podem ser aplicadas em qualquer ordem sem erro — mas a ordem M2→M5 é preservada pelos timestamps. ✓

### 2.3 Rollback cruzado — nenhum rollback quebra migration anterior

| Rollback de | Afeta M1? | Afeta M2? | Afeta M4? | Afeta M5? | Afeta M6? |
|-------------|-----------|-----------|-----------|-----------|-----------|
| P0-M1 rollback | — | ✗ | ✗ | ✗ | ✗ |
| P0-M2 rollback | ✗ | — | ✗ | ✗ | ✗ |
| P0-M4 rollback | ✗ | ✗ | — | ✗ | ✗ |
| P0-M5 rollback | ✗ | ✗ | ✗ | — | ✗ |
| P0-M6 rollback | ✗ | ✗ | ✗ | ✗ | — |

Cada rollback é isolado. Nenhum objeto criado por uma migration é consumido por outra migration.

### 2.4 P0-M6 altera contrato registrado por P0-M5?

P0-M5 registra `complete_lesson` em `c6_contract_registry` com `status='canonical'`.
P0-M6 modifica o **corpo** da função `complete_lesson`, não a entrada no registry.

O campo `contract_name` permanece `'complete_lesson'` — sem conflito com a PK de P0-M5.
O campo `notes` em P0-M5 cita o risco SEC-03; após P0-M6 este risco é mitigado.
A tabela `c6_contract_registry` não é alterada por P0-M6 (nenhum UPDATE/DELETE).

→ Ver Observação OBS-01 em §8 para recomendação de atualização pós-deploy.

**RESULTADO: ✅ PASS**

---

## CHECK 3 — Idempotência

### P0-M1

| Instrução | Idempotente? | Mecanismo |
|-----------|-------------|-----------|
| `ALTER FUNCTION ... SET search_path` | ✓ | Sobreescreve proconfig — reexecução é no-op |
| `REVOKE ALL FROM PUBLIC` | ✓ | Idempotente no PostgreSQL |
| `GRANT ALL TO service_role` | ✓ | Idempotente no PostgreSQL |

### P0-M2

| Instrução | Idempotente? | Mecanismo |
|-----------|-------------|-----------|
| `INSERT ... ON CONFLICT (migration_id) DO NOTHING` | ✓ | Conflict na PK — reexecução é no-op |

### P0-M4

| Instrução | Idempotente? | Mecanismo |
|-----------|-------------|-----------|
| `DROP POLICY IF EXISTS "Usuário cria XP events"` | ✓ | IF EXISTS |
| `DROP POLICY IF EXISTS "xp_events_insert_block"` | ✓ | IF EXISTS |
| `DROP POLICY IF EXISTS "xp_events_no_update"` | ✓ | IF EXISTS |
| `DROP POLICY IF EXISTS "xp_events_no_delete"` | ✓ | IF EXISTS |
| `CREATE POLICY "xp_events_insert_block"` | ✓ (via DROP precedente) | DROP IF EXISTS → CREATE |
| `CREATE POLICY "xp_events_no_update"` | ✓ (via DROP precedente) | DROP IF EXISTS → CREATE |
| `CREATE POLICY "xp_events_no_delete"` | ✓ (via DROP precedente) | DROP IF EXISTS → CREATE |

Padrão correto: cada `CREATE POLICY` é precedido pelo `DROP POLICY IF EXISTS` correspondente,
garantindo que reexecução em staging (comum durante testes) nunca falhe com "policy already exists".

### P0-M5

| Instrução | Idempotente? | Mecanismo |
|-----------|-------------|-----------|
| `INSERT INTO c6_contract_registry ... ON CONFLICT (contract_name) DO NOTHING` | ✓ | Conflict na PK — segunda execução insere 0 linhas |

### P0-M6

| Instrução | Idempotente? | Mecanismo |
|-----------|-------------|-----------|
| `CREATE OR REPLACE FUNCTION complete_lesson` | ✓ | OR REPLACE — sem DROP |
| `REVOKE ALL FROM PUBLIC` | ✓ | Idempotente |
| `GRANT ALL TO service_role` | ✓ | Idempotente |
| `GRANT EXECUTE TO authenticated` | ✓ | Idempotente |

**RESULTADO: ✅ PASS — todas as migrations são seguras para múltiplas execuções em staging.**

---

## CHECK 4 — Escopo

### 4.1 Tabelas modificadas por cada migration

| Migration | Tabelas com DDL | Tabelas com DML | Funções | Policies |
|-----------|----------------|-----------------|---------|----------|
| P0-M1 | Nenhuma | Nenhuma | `buscar_revisoes_whatsapp` (ALTER) | Nenhuma |
| P0-M2 | Nenhuma | `_qd_migration_snapshots` (INSERT) | Nenhuma | Nenhuma |
| P0-M4 | Nenhuma | Nenhuma | Nenhuma | `xp_events` (DROP+CREATE) |
| P0-M5 | Nenhuma | `c6_contract_registry` (INSERT) | Nenhuma | Nenhuma |
| P0-M6 | Nenhuma | Nenhuma | `complete_lesson` (REPLACE) | Nenhuma |

### 4.2 Checklist de destrutividade

| Verificação | Resultado |
|-------------|-----------|
| `DROP TABLE` presente? | **NÃO** — em nenhuma migration |
| `DROP CASCADE` presente? | **NÃO** — em nenhuma migration |
| `DROP FUNCTION` (sem IF EXISTS)? | **NÃO** — P0-M6 usa CREATE OR REPLACE |
| `ALTER TABLE ... DROP COLUMN`? | **NÃO** — nenhuma coluna removida |
| `ALTER TABLE ... ADD CONSTRAINT` que pode falhar? | **NÃO** |
| CHECK constraint institucional alterada? | **NÃO** |
| Trigger adicionado ou removido? | **NÃO** |
| Index criado ou removido? | **NÃO** |
| `TRUNCATE` presente? | **NÃO** |
| `DELETE` em tabelas funcionais? | **NÃO** — apenas em rollbacks (comentados) |

### 4.3 Tabelas canônicas — intocadas

As tabelas funcionais canônicas do app mobile foram confirmadas como não modificadas:

| Tabela | Tocada? |
|--------|---------|
| `recrutas` | ✗ |
| `profiles` | ✗ |
| `aulas` | ✗ |
| `modulos` | ✗ |
| `recruta_progresso` | ✗ (apenas lida/inserida via RPC em P0-M6 — comportamento preservado) |
| `xp_eventos` | ✗ |
| `recruta_modulos` | ✗ |
| `auth_client_sessions` | ✗ |

**RESULTADO: ✅ PASS — escopo estritamente contido.**

---

## CHECK 5 — Risco Acumulado

### 5.1 Risco por migration (isolado e acumulado)

| Migration | Tipo de mudança | Risco isolado | Risco acumulado | Reversibilidade |
|-----------|----------------|---------------|-----------------|-----------------|
| P0-M1 | ALTER FUNCTION (atributo) | BAIXO | BAIXO | 1 instrução |
| P0-M2 | INSERT metadados | MÍNIMO | BAIXO | 1 DELETE |
| ~~P0-M3~~ | VOID | ZERO | BAIXO | N/A |
| P0-M4 | RLS policy em tabela legada | MÉDIO ⚠ | MÉDIO | DROP/CREATE |
| P0-M5 | INSERT metadados | MÍNIMO | MÉDIO | DELETE WHERE |
| P0-M6 | REPLACE FUNCTION + GRANT | MÉDIO | MÉDIO | CREATE OR REPLACE + REVOKE |

### 5.2 Análise do risco acumulado

O risco acumulado do pacote é **MÉDIO**, não ALTO. Justificativa:

- Nenhuma migration altera DDL de tabelas funcionais.
- O único vetor de risco operacional real é P0-M4 (bloqueio de INSERT em `xp_events`), que tem pré-condição manual pendente e afeta exclusivamente a tabela legada.
- P0-M6 modifica uma função SECURITY DEFINER em produção — risco técnico real, mas limitado ao escopo de `complete_lesson`.
- As três migrations de metadados (P0-M2, P0-M5 e parte de P0-M1) são acumulativamente seguros por design.

### 5.3 Maior risco individual: P0-M4

P0-M4 é a única migration com uma **pré-condição não verificável via dump ou codebase**:

> Confirmar manualmente que nenhum dashboard externo (Metabase, Retool, Supabase Studio
> queries salvas, scripts de ETL externos) usa INSERT em `public.xp_events`.

Esta verificação está documentada no P0_M4_HANDOFF.md. Enquanto não concluída:
- P0-M1, P0-M2, P0-M5 e P0-M6 podem ser aplicadas com segurança.
- P0-M4 deve aguardar a verificação manual.
- P0-M4 e P0-M6 são **independentes** — não há sequência obrigatória entre elas.

**RESULTADO: ✅ PASS — risco acumulado MÉDIO, controlado e reversível.**

---

## CHECK 6 — Consistência entre Migrations e Handoffs

### 6.1 SQL da migration vs. SQL documentado no handoff

| Migration | SQL na migration | SQL no handoff | Consistente? |
|-----------|-----------------|----------------|--------------|
| P0-M1 | `ALTER FUNCTION ... SET search_path TO 'public', 'pg_catalog'` | Idêntico | ✓ |
| P0-M2 | `INSERT ... ON CONFLICT (migration_id) DO NOTHING` | Idêntico (resumido) | ✓ |
| P0-M4 | `DROP IF EXISTS` × 4 + `CREATE POLICY` × 3 | Idêntico | ✓ |
| P0-M5 | 38 INSERTs + `ON CONFLICT (contract_name) DO NOTHING` | Resumo idêntico | ✓ |
| P0-M6 | `CREATE OR REPLACE FUNCTION` + guarda + 3 grants | Idêntico (seção SQL completo) | ✓ |

### 6.2 Nomes de arquivo

| Handoff referencia | Arquivo físico existe? | Match? |
|-------------------|----------------------|--------|
| `20260516001000_p0_m1_fix_buscar_revisoes_whatsapp_search_path.sql` | ✓ | ✓ |
| `20260516002000_p0_m2_register_baseline_audit.sql` | ✓ | ✓ |
| `20260516004000_p0_m4_block_xp_events_legacy_insert.sql` | ✓ | ✓ |
| `20260516005000_p0_m5_register_contract_registry.sql` | ✓ | ✓ |
| `20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql` | ✓ | ✓ |

**RESULTADO: ✅ PASS — migrations e handoffs são consistentes.**

---

## CHECK 7 — Consistência com Decision Packet e NEXT_SAFE_MIGRATIONS

### 7.1 P0_DECISION_PACKET.md

| Item | Situation |
|------|-----------|
| §1 — ordem de execução | Consistent com timestamps das migrations |
| §2 — P0-M3 marcada como CANCELADA | ✓ sem arquivo de migration |
| §2 — P0-M2 usa `snapshot_key/snapshot_data/created_at` no rascunho | ⚠ Rascunho tem colunas antigas — migration real usa `migration_id/applied_at/snapshot` (CORRETO) |
| §2 — P0-M6 descrito como "alto risco, mudança de assinatura" | ⚠ Desatualizado — P0-M6 manteve assinatura (Opção B). Risco real é MÉDIO |

### 7.2 NEXT_SAFE_MIGRATIONS.md

| Item | Status |
|------|--------|
| Tabela de status das migrations | ✓ Atualizada com P0-M3 VOID |
| SQL exemplo de P0-M2 (P0.3) | ⚠ Usa colunas antigas (`snapshot_key/snapshot_data/created_at`) — marcado "(NÃO EXECUTAR)" |
| SQL exemplo de P0-M5 (P0.4) | ⚠ Usa colunas antigas (`object_name/domain/status='ACTIVE'`) — marcado "(NÃO EXECUTAR)" |
| P0-M6 (P0.5) | ⚠ Descreve remoção de `p_recruta_id` (Opção A) — escolhida Opção B. Marcado como design proposto |

**CONCLUSÃO:** Os exemplos SQL nos documentos de planejamento são inconsistentes com as migrations finais, porém:
1. Todos estão marcados explicitamente como `(NÃO EXECUTAR)`.
2. Os arquivos executáveis (`.sql` em `supabase/migrations/`) são os corretos.
3. Não há risco de aplicação acidental do SQL incorreto.

Estes documentos de planejamento são referência histórica e não serão executados. As inconsistências são documentação, não bugs.

**RESULTADO: ✅ PASS — migrations executáveis são corretas. Documentos de planejamento desatualizados não bloqueiam staging.**

---

## CHECK 8 — Observações Não Bloqueantes

### OBS-01 — `c6_contract_registry.notes` para `complete_lesson` ficará desatualizado após P0-M6

**Situação:** P0-M5 registra `complete_lesson` com:
```
notes = 'RISCO ATIVO: aceita p_recruta_id como parâmetro externo. Mitigado por grants service_role only. Correção planejada em P0-M6.'
```

Após P0-M6, o risco é mitigado. A nota permanece com "RISCO ATIVO" mas a correção já foi aplicada.

**Impacto:** Documentação interna do registry — não afeta comportamento do app.

**Recomendação:** Após confirmar P0-M6 aplicado com sucesso em staging e produção, executar:
```sql
UPDATE public.c6_contract_registry
SET notes = 'RISCO MITIGADO em P0-M6 (2026-05-16): auth.uid() guard adicionado. GRANT EXECUTE TO authenticated incluído. Risco residual: p_xp externo manipulável (Sprint 2).',
    updated_at = now()
WHERE contract_name = 'complete_lesson';
```

---

### OBS-02 — P0_DECISION_PACKET.md e NEXT_SAFE_MIGRATIONS.md não foram atualizados para Opção B

**Situação:** P0_DECISION_PACKET.md §1 classifica P0-M6 como `ALTO` risco e o NEXT_SAFE_MIGRATIONS.md o coloca em "Sprint 3 — janela de manutenção". Após a auditoria pré-M6, a abordagem escolhida (Opção B — sem mudança de assinatura) reduz o risco para MÉDIO e elimina a necessidade de janela de manutenção.

**Impacto:** Documentação de planejamento — nenhum efeito no apply.

**Recomendação:** Após execução bem-sucedida, atualizar os documentos de planejamento para refletir o risco real executado.

---

### OBS-03 — P0-M6 não inclui UPDATE em `_qd_migration_snapshots`

**Situação:** P0-M2 registra o status de P0-M6 como `'PLANEJADA_ALTO_RISCO'`. Não há migration que atualize este registro para `'EXECUTADA'` após P0-M6.

**Impacto:** `_qd_migration_snapshots` é um ledger histórico (snapshot de momento) — não é um status tracker em tempo real. A semântica correta é preservar o registro histórico de auditoria como estava em 2026-05-16.

**Recomendação:** Não é necessário corrigir. Para rastreabilidade futura, uma nova migration de snapshot (P0-M7 ou sprint snapshot) pode registrar o estado pós-P0 se necessário.

---

## CHECK 9 — Risco Residual Pós-Deploy

Após execução completa do pacote P0 em produção:

| ID | Risco | Severidade | Já mitigado por P0? | Próxima ação |
|----|-------|-----------|---------------------|--------------|
| RR-01 | `complete_lesson`: `p_xp` ainda é parâmetro externo manipulável | MÉDIO | ✗ | Sprint 2 — Option C (nova RPC sem p_xp) |
| RR-02 | `complete_lesson`: `p_lesson_id` sem validação de existência | BAIXO | ✗ | Sprint 2 |
| RR-03 | ~20 funções SECURITY DEFINER sem `SET search_path` (além de buscar_revisoes_whatsapp) | MÉDIO | Apenas 1 corrigida (P0-M1) | Sprint 2 — ALTER FUNCTION em lote |
| RR-04 | `emitir_evento_c5` exposta a `authenticated` (SEC-04) | MÉDIO | ✗ | Sprint 2 |
| RR-05 | Materialized views sem REFRESH agendado (SEC-05) | OPERACIONAL | ✗ | Sprint 2 — pg_cron |
| RR-06 | `rpc_complete_onboarding` duas sobrecargas (SEC-06) | BAIXO | ✗ | Sprint 3 |
| RR-07 | `v_available_reviews`, `v_review_content`, `rpc_mark_instructor_message_read`, `rpc_complete_module` ausentes no dump mas consumidos no frontend | P0 PRODUTO | ✗ | Investigação urgente separada |

---

## CHECK 10 — Pré-Condições Antes do Apply em Staging

### Pré-condições automáticas (já verificadas via dump + codebase)

| Verificação | Status |
|-------------|--------|
| `buscar_revisoes_whatsapp()` existe no banco remoto (dump ln 833) | ✓ Confirmado |
| `_qd_migration_snapshots` existe (dump ln 9018) | ✓ Confirmado |
| `xp_events` existe e tem RLS ativo (dump ln 14497) | ✓ Confirmado |
| `c6_contract_registry` existe com DDL correto (dump ln 9765) | ✓ Confirmado |
| `complete_lesson()` existe (dump ln 1182) | ✓ Confirmado |
| Nenhum frontend usa `xp_events` diretamente (grep src/, app/, supabase/functions/) | ✓ Confirmado |
| `progressService.ts` é único caller de `complete_lesson` | ✓ Confirmado |
| `userId = session.user.id` (não existe UI que override o UUID) | ✓ Confirmado |

### Pré-condição manual pendente (P0-M4 apenas)

```
[ ] Confirmar que Metabase (se usado) não tem query ativa com INSERT em public.xp_events
[ ] Confirmar que Retool (se usado) não tem resource/query com INSERT em public.xp_events
[ ] Confirmar que Supabase Studio não tem query salva com INSERT em public.xp_events
[ ] Confirmar que scripts externos de ETL/analytics não inserem em public.xp_events
```

Se **todos** os itens acima retornarem "nenhum consumidor": **P0-M4 pode ser executada**.
Se **qualquer** item retornar consumidor ativo: **bloquear P0-M4 e tratar separadamente**.

### Pré-condição recomendada (P0-M6 — não bloqueante)

```sql
-- Executar antes de P0-M6 para entender estado atual:
SELECT has_function_privilege(
    'authenticated',
    'public.complete_lesson(uuid, uuid, integer)',
    'EXECUTE'
);
-- TRUE  → GRANT-01 não causou downtime (grant implícito existia)
-- FALSE → GRANT-01 era bug ativo (frontend incapaz de concluir aulas)
```

Este resultado não bloqueia P0-M6 (ambos os cenários são corrigidos), mas determina se uma comunicação de resolução de bug deve ser feita para a equipe de produto.

---

## Plano de Apply em Staging

### Fase 1 — Sem pré-condição manual (pode executar imediatamente)

```
1. supabase db push --include-all (ou apply por arquivo)
   → 20260516001000_p0_m1_fix_buscar_revisoes_whatsapp_search_path.sql
   → 20260516002000_p0_m2_register_baseline_audit.sql
   → (20260516003000 — VOID, arquivo não existe, pulado automaticamente)
   → 20260516005000_p0_m5_register_contract_registry.sql
   → 20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql

2. Executar testes pós-apply de cada handoff:
   [ ] P0-M1 Testes 1–4 (pg_proc.proconfig, grants, comportamento)
   [ ] P0-M2 Testes 1–4 (snapshot inserido, campos corretos, idempotência)
   [ ] P0-M5 Testes 1–6 (38 registros, v_c6_contracts_validos, CHECK constraints)
   [ ] P0-M6 Testes 1–7 (guarda 42501, fluxo legítimo, idempotência, grants)
```

### Fase 2 — Após pré-condição manual de P0-M4

```
3. Confirmar zero consumidores de xp_events em dashboards externos
4. Aplicar: 20260516004000_p0_m4_block_xp_events_legacy_insert.sql
5. Executar testes pós-apply:
   [ ] P0-M4 Testes 1–7 (policies criadas, INSERT bloqueado, service_role OK)
```

---

## Resumo Final por Migration

| Migration | Tipo | Risco | Idempotente | Pré-condição | Veredicto |
|-----------|------|-------|-------------|--------------|-----------|
| P0-M1 | ALTER FUNCTION | BAIXO | ✓ | Nenhuma | ✅ LIBERADO |
| P0-M2 | INSERT metadados | MÍNIMO | ✓ | Nenhuma | ✅ LIBERADO |
| ~~P0-M3~~ | VOID | ZERO | N/A | N/A | ✅ CORRETO (sem arquivo) |
| P0-M4 | RLS policies | MÉDIO | ✓ | ⚠ Dashboards externos | ⚠ AGUARDA PRÉ-CONDIÇÃO |
| P0-M5 | INSERT metadados | MÍNIMO | ✓ | Nenhuma | ✅ LIBERADO |
| P0-M6 | REPLACE FUNCTION | MÉDIO | ✓ | Recomendada (não bloqueante) | ✅ LIBERADO |

---

## Aprovação

```
[ ] CHECK 1 — Ordem de execução: validado
[ ] CHECK 2 — Dependências cruzadas: validado
[ ] CHECK 3 — Idempotência: validado
[ ] CHECK 4 — Escopo: validado
[ ] CHECK 5 — Risco acumulado: aceito
[ ] CHECK 6 — Consistência migrations/handoffs: validado
[ ] CHECK 7 — Consistência com Decision Packet: validado (divergências são só documentação)
[ ] OBS-01 — UPDATE em c6_contract_registry pós-P0-M6: ciente
[ ] OBS-02 — Decision Packet e NEXT_SAFE_MIGRATIONS desatualizados: ciente
[ ] OBS-03 — _qd_migration_snapshots não atualizado pós-deploy: ciente (ledger histórico)
[ ] Pré-condição manual P0-M4 executada e resultado documentado
[ ] Pré-condição recomendada P0-M6 executada (has_function_privilege)
[ ] Aprovado para staging por: ___________________________
[ ] Data de apply em staging: ___________________________
[ ] Todos os testes de staging passaram
[ ] Aprovado para produção por: _________________________
[ ] Data de apply em produção: __________________________
```

---

**Status deste documento:** PRONTO PARA APROVAÇÃO
