# Next Safe Migrations Plan — Quartel Digital Supabase

**Data:** 2026-05-16
**IMPORTANTE:** Este documento é apenas um PLANO. Nenhuma migration executável foi criada.
**Regras:**
- NÃO executar SQL diretamente no banco
- NÃO usar `db push`, `db reset` ou `migration repair`
- Toda migration deve ser revisada e aprovada antes de execução
- Toda migration deve ser idempotente (`CREATE OR REPLACE`, `IF NOT EXISTS`, `ON CONFLICT DO NOTHING`)

---

## Nota de Revisão — 2026-05-16

| Migration | Status |
|-----------|--------|
| P0-M1 (`buscar_revisoes_whatsapp` search_path) | GERADA — aguardando execução |
| P0-M2 (baseline audit registration) | GERADA — aguardando execução |
| **P0-M3** (fn_insert_audit_evento_smart INVOKER→DEFINER) | **CANCELADA — FALSO POSITIVO CONFIRMADO PELO DUMP REMOTO** |
| P0-M4 (xp_events INSERT block) | Planejada — requer grep prévio |
| P0-M5 (contract registry) | Planejada — requer P0-M2 primeiro |
| P0-M6 (complete_lesson auth.uid()) | Planejada — alto risco, última |

> **P0-M3 VOID:** `fn_insert_audit_evento_smart` não existe no dump. `v_audit_eventos` é
> read-only (sem trigger INSTEAD OF). Auditoria de chat opera via Edge Functions — por design.
> Ver: `supabase/baseline/P0_M3_VOID_HANDOFF.md`

---

## P0 — Crítico (Segurança / Estabilidade)

### P0.1 — Adicionar search_path a `buscar_revisoes_whatsapp`

**Objetivo:** Corrigir vulnerabilidade SECURITY DEFINER sem search_path
**Objetos afetados:** `buscar_revisoes_whatsapp()`
**Pré-requisitos:** Nenhum
**Risco:** BAIXO — apenas alteração de atributo de função, sem mudança de comportamento
**Testes necessários:**
- Verificar que a função continua retornando os mesmos resultados
- Confirmar que grants service_role são preservados

**Rollback:** `CREATE OR REPLACE FUNCTION` sem `SET search_path`

**SQL Planejado (NÃO EXECUTAR):**
```sql
-- Migration: 20260516_P0_fix_buscar_revisoes_whatsapp_search_path.sql
CREATE OR REPLACE FUNCTION public.buscar_revisoes_whatsapp()
RETURNS TABLE(revisao_id uuid, recruta_id uuid, missao_id uuid, forca text)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'  -- ADIÇÃO CRÍTICA
AS $$
  -- corpo original preservado
$$;
```

---

### P0.2 — Bloquear INSERT direto em `xp_events` (tabela legada)

**Objetivo:** Impedir manipulação de XP via tabela legada
**Objetos afetados:** `xp_events` (RLS policy)
**Pré-requisitos:** Confirmar que nenhum código de produção usa INSERT em `xp_events`
**Risco:** MÉDIO — pode quebrar código legado que ainda insere em `xp_events`
**Testes necessários:**
- Busca no frontend por `.from('xp_events').insert`
- Verificar se alguma função ou trigger insere em `xp_events`

**SQL Planejado (NÃO EXECUTAR):**
```sql
-- Migration: 20260516_P0_block_xp_events_insert.sql
DROP POLICY IF EXISTS "Usuário cria XP events" ON public.xp_events;
CREATE POLICY "xp_events_insert_block" ON public.xp_events
  FOR INSERT WITH CHECK (false);
```

---

### P0.3 — Baseline Institucional Versionado

**Objetivo:** Registrar no banco que o baseline foi criado e auditado
**Objetos afetados:** `_qd_migration_snapshots` (tabela já existente no dump)
**Pré-requisitos:** Baseline files criados e aprovados
**Risco:** MÍNIMO — apenas INSERT de registro

**SQL Planejado (NÃO EXECUTAR):**
```sql
-- Migration: 20260516_P0_register_baseline_audit.sql
INSERT INTO public._qd_migration_snapshots (
  snapshot_key,
  snapshot_data,
  created_at
) VALUES (
  'baseline_2026_05_16',
  jsonb_build_object(
    'total_tables', 85,
    'total_views', 116,
    'total_functions', 84,
    'audit_completed_at', now(),
    'auditor', 'claude-code-institutional-auditor'
  ),
  now()
) ON CONFLICT (snapshot_key) DO NOTHING;
```

---

### P0.4 — Contract Registry — Validação de Contratos Críticos

**Objetivo:** Registrar contratos críticos verificados na tabela c6_contract_registry
**Objetos afetados:** `c6_contract_registry`
**Pré-requisitos:** Tabela c6_contract_registry existente (confirmada no dump linha 9765)
**Risco:** MÍNIMO — apenas INSERTs de metadados

**SQL Planejado (NÃO EXECUTAR):**
```sql
-- Inserir contratos canônicos do RCC-0.5 para rastreabilidade
INSERT INTO public.c6_contract_registry (object_name, object_type, domain, status, validated_at)
VALUES
  ('v_identidade_recruta', 'VIEW', 'auth', 'ACTIVE', now()),
  ('v_app_bootstrap_institucional_rcc', 'VIEW', 'auth', 'ACTIVE', now()),
  ('rpc_complete_onboarding', 'FUNCTION', 'auth', 'ACTIVE', now()),
  ('v_chat_conversas_recruta', 'VIEW', 'chat', 'ACTIVE', now()),
  ('rpc_chat_open_conversation', 'FUNCTION', 'chat', 'ACTIVE', now()),
  ('rpc_chat_send_message', 'FUNCTION', 'chat', 'ACTIVE', now()),
  ('vw_rdm_lessons_v2', 'VIEW', 'learning', 'ACTIVE', now()),
  ('vw_recruta_module_progress_v2', 'VIEW', 'learning', 'ACTIVE', now()),
  ('complete_lesson', 'FUNCTION', 'learning', 'ACTIVE', now()),
  ('v_billing_status_recruta_v2', 'VIEW', 'billing', 'ACTIVE', now()),
  ('v_ranking_mensal_rcc', 'VIEW', 'ranking', 'ACTIVE', now()),
  ('v_iea_atual_v2', 'VIEW', 'iea', 'ACTIVE', now()),
  ('v_elegibilidade_elite_v2', 'VIEW', 'elite', 'ACTIVE', now())
ON CONFLICT DO NOTHING;
```

---

## P0.5 — Corrigir `complete_lesson` — Usar auth.uid() Internamente

**Objetivo:** Eliminar p_recruta_id como parâmetro, derivar de auth.uid()
**Objetos afetados:** `complete_lesson(p_recruta_id, p_lesson_id, p_xp)`
**Pré-requisitos:**
- Confirmar todos os chamadores da função (backend, edge functions)
- Verificar se alguma chamada passa p_recruta_id diferente do usuário autenticado
**Risco:** ALTO — mudança de assinatura pode quebrar chamadores

**Design Proposto (NÃO EXECUTAR):**
```sql
-- Nova assinatura: complete_lesson(p_lesson_id uuid, p_xp integer DEFAULT 50)
-- Deriva p_recruta_id internamente:
--   SELECT id INTO v_recruta_id FROM public.recrutas WHERE auth_id = auth.uid()
-- Mantém a assinatura antiga como OVERLOAD por período de transição
```

**Pré-condição:** Só executar após confirmar que o Edge Function de chat
também migrou para a nova assinatura.

---

## P1 — Alta Prioridade

### P1.1 — Agendamento de REFRESH para Materialized Views

**Objetivo:** Garantir que rankings e métricas estejam atualizados
**Objetos afetados:** `mv_xp_mensal_recruta`, `mv_ranking_mensal`, `mv_campeao_mensal`, `mv_c7_*`
**Pré-requisitos:** pg_cron instalado (extensão Supabase disponível)
**Risco:** BAIXO — apenas adição de jobs de refresh

**Design Proposto (NÃO EXECUTAR):**
```sql
-- Refresh diário às 00:05 UTC
SELECT cron.schedule('refresh-ranking-mensal', '5 0 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_ranking_mensal'
);
SELECT cron.schedule('refresh-xp-mensal', '0 0 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_xp_mensal_recruta'
);
SELECT cron.schedule('refresh-campeao-mensal', '10 0 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_campeao_mensal'
);
```

**Nota:** Verificar se as MVs têm índice UNIQUE para suportar `CONCURRENTLY`.

---

### P1.2 — Blindar `registrar_xp` contra Chamadas Duplicadas

**Objetivo:** Tornar idempotente se função existir
**Objetos afetados:** `registrar_xp` (se existir no banco — não encontrada no dump atual)
**Pré-requisitos:** Confirmar existência da função no banco
**Risco:** MÉDIO

**Nota:** A função `registrar_xp` está documentada na MEMORY.md como "NÃO idempotente" mas não foi encontrada no dump remoto. Pode ter sido removida ou renomeada.

---

### P1.3 — Policies Explícitas para `institutional_notices` e `instructor_messages`

**Objetivo:** Garantir que apenas recrutas autenticados possam ler seus avisos
**Objetos afetados:** `institutional_notices`, `instructor_messages`
**Pré-requisitos:** Confirmar modelo de acesso esperado
**Risco:** BAIXO

**Design Proposto (NÃO EXECUTAR):**
```sql
CREATE POLICY "notices_select_authenticated"
  ON public.institutional_notices FOR SELECT TO authenticated USING (true);

CREATE POLICY "messages_select_authenticated"
  ON public.instructor_messages FOR SELECT TO authenticated USING (true);
```

---

### P1.4 — Deprecar Sobrecarga Obsoleta de `rpc_complete_onboarding`

**Objetivo:** Remover overload sem parâmetros para evitar ambiguidade
**Objetos afetados:** `rpc_complete_onboarding()` (sem params, linha 5983)
**Pré-requisitos:** Confirmar que NENHUM chamador usa a versão sem parâmetros
**Risco:** MÉDIO — pode quebrar chamadores antigos

**Design Proposto (NÃO EXECUTAR):**
```sql
-- Apenas após confirmação total de chamadores:
DROP FUNCTION IF EXISTS public.rpc_complete_onboarding();
-- Manter: rpc_complete_onboarding(p_forca text, p_nome_guerra text)
```

---

## P2 — Médio Prazo

### P2.1 — Sunset Plan para Tabelas Legadas

**Objetivo:** Documentar e planejar remoção de tabelas obsoletas
**Candidatos:** `xp_events`, `user_xp`, `aulas_concluidas`, `lessons`, `lesson_progress`,
`lesson_media`, `licoes`, `progresso_recruta`, `progresso_aulas`, `progresso_missoes`,
`missoes`, `revisoes`, `roles`, `sessions`, `users`, `usuarios`

**Processo proposto:**
1. Confirmar no frontend que nenhuma tabela é consumida diretamente
2. Criar migration que adiciona comentário `DEPRECATED` na tabela
3. Após 2 ciclos de sprint sem uso: DROP TABLE

**Risco:** ALTO se alguma tabela ainda for usada indiretamente.

---

### P2.2 — Normalizar xp vs xp_total em `recrutas`

**Objetivo:** Resolver divergência entre campos paralelos
**Objetos afetados:** `recrutas.xp` e `recrutas.xp_total`
**Pré-requisitos:** Decisão institucional sobre campo canônico
**Risco:** ALTO — impacta fórmulas de level, ranking e IEA

**Status:** BLOQUEADO aguardando decisão institucional.

---

## Ordem de Execução Recomendada

```
Sprint 1 — Zero Breaking Change (pode executar agora):
  [P0-M1] Fix buscar_revisoes_whatsapp search_path      (GERADA — baixo risco)
  [P0-M2] Register baseline audit                        (GERADA — mínimo risco)
  [P0-M3] ~~CANCELADA — falso positivo~~                 (ver P0_M3_VOID_HANDOFF.md)
  [P0-adicional] Recreate v_completed_lessons_count      (baixo risco)

Sprint 2 — Verificação Prévia Necessária:
  [P0-M4] Block xp_events INSERT                         (médio risco — grep antes)
  [P0-M5] Register contract registry                     (mínimo risco — após P0-M2)
  [P1.1]  Refresh materialized views schedule            (baixo risco)
  [P1.3]  Notices/messages policies                      (baixo risco)
  [bulk]  ALTER FUNCTION search_path para todas DEFINER  (após query de verificação)

Sprint 3 — Coordenação Total Necessária:
  [P0-M6] complete_lesson → auth.uid()                   (alto risco — janela manutenção)
  [P1.4]  Deprecar rpc_complete_onboarding() sem params  (após confirmar zero callers)

Sprint 4+:
  [P2.1]  Sunset tabelas legadas
  [P2.2]  Normalização xp/xp_total (BLOQUEADO — decisão institucional)
```
