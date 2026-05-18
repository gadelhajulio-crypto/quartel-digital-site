# P0-M2 Handoff — Registrar Baseline Auditado em `_qd_migration_snapshots`
**Status:** AGUARDANDO EXECUÇÃO
**Data de geração:** 2026-05-16
**Classificação:** P0-M2 — Rastreabilidade
**Arquivo de migration:** `supabase/migrations/20260516002000_p0_m2_register_baseline_audit.sql`

---

## Objetivo

Versionar no banco que o baseline remoto de 2026-05-16 foi auditado, revisado e aprovado
institucionalmente. O registro serve como âncora de rastreabilidade para auditorias futuras:
qualquer engenheiro pode consultar `_qd_migration_snapshots` para saber qual era o estado
documentado do schema na data de execução desta migration.

---

## Escopo

| O que muda | O que NÃO muda |
|-----------|----------------|
| 1 linha inserida em `public._qd_migration_snapshots` | Nenhuma tabela funcional do app |
| | Nenhum dado de recruta, sessão, XP, chat ou billing |
| | Nenhuma view, RPC, trigger, policy ou grant |
| | Estrutura de qualquer tabela |

Esta migration é **puramente append-only em tabela interna de rastreabilidade**.

---

## Risco

| Dimensão | Avaliação |
|----------|-----------|
| Impacto no frontend | **ZERO** — tabela interna, nunca consumida pelo app |
| Impacto em dados funcionais | **ZERO** — apenas metadados de auditoria |
| Reversibilidade | **IMEDIATA** — um `DELETE` de uma linha restaura o estado original |
| Risco da migration em si | **MÍNIMO** — INSERT idempotente com ON CONFLICT DO NOTHING |
| Risco se aplicada duas vezes | **ZERO** — segunda execução é no-op silencioso |

---

## Impacto

Nenhum impacto operacional. A tabela `_qd_migration_snapshots` não é consumida por
nenhum hook, tela, view, RPC ou Edge Function do app mobile.

Após a execução, a linha pode ser consultada por qualquer ferramenta com acesso ao banco
(Supabase Studio, psql, ferramentas de auditoria interna).

---

## Nota: Correção de Coluna em Relação ao Decision Packet

O rascunho em `P0_DECISION_PACKET.md §2` usou nomes de coluna incorretos:

| Rascunho (incorreto) | Dump real (ln 9018–9022) |
|----------------------|--------------------------|
| `snapshot_key` | `migration_id` |
| `snapshot_data` | `snapshot` |
| `created_at` | `applied_at` |

Esta migration usa os nomes **reais** confirmados diretamente no dump remoto.
O `ON CONFLICT` também usa `(migration_id)`, que é a PK real da tabela.

---

## Estrutura da Tabela (dump ln 9018–9022)

```sql
CREATE TABLE IF NOT EXISTS "public"."_qd_migration_snapshots" (
    "migration_id" text        NOT NULL,          -- PK
    "applied_at"   timestamptz DEFAULT now(),
    "snapshot"     jsonb       NOT NULL
);
-- PK: _qd_migration_snapshots_pkey ON (migration_id)
-- RLS: não habilitado no dump
-- Grants explícitos: nenhum visível no dump (owner = postgres)
```

---

## SQL Exato da Migration

```sql
INSERT INTO public._qd_migration_snapshots (
    migration_id,
    applied_at,
    snapshot
)
VALUES (
    'baseline_audit_2026_05_16',
    now(),
    jsonb_build_object(

        'baseline_date',             '2026-05-16',
        'auditor',                   'institutional-audit-2026-05-16',
        'dump_source',               'supabase/remote/supabase_remote_schema.sql',
        'audit_documents',           jsonb_build_array( ... ),  -- 16 documentos

        'schema_counts',             jsonb_build_object(
            'tables', 85, 'views', 110, 'materialized_views', 6,
            'functions', 80, 'triggers', 15, 'rls_policies', 130, 'indexes', 120
        ),

        'security_issues_confirmed', jsonb_build_array(
            -- SEC-01: buscar_revisoes_whatsapp DEFINER sem search_path → P0-M1
            -- SEC-02: xp_events INSERT aberto → P0-M4
            -- SEC-03: complete_lesson p_recruta_id externo → P0-M6
            -- SEC-04: emitir_evento_c5 exposta a authenticated → Sprint 2
            -- SEC-05: MVs sem REFRESH → Sprint 2
            -- SEC-06: rpc_complete_onboarding duas sobrecargas → Sprint 3
        ),  -- 6 itens

        'false_positives_found',     jsonb_build_array(
            -- FP-01: fn_insert_audit_evento_smart — não existe no dump → P0-M3 VOID
        ),  -- 1 item

        'critical_contracts_confirmed', jsonb_build_array( ... ),  -- 25 contratos

        'contracts_missing',         jsonb_build_array(
            -- v_completed_lessons_count — ausente no dump, usada em useRecruitPanel.ts:62
        ),  -- 1 item

        'p0_migrations',             jsonb_build_object(
            'P0-M1', 'GERADA_AGUARDANDO_EXECUCAO',
            'P0-M2', 'ESTA_MIGRATION',
            'P0-M3', 'CANCELADA — falso positivo',
            'P0-M4', 'GERADA_AGUARDANDO_EXECUCAO',
            'P0-M5', 'PLANEJADA',
            'P0-M6', 'PLANEJADA_ALTO_RISCO'
        )
    )
)
ON CONFLICT (migration_id) DO NOTHING;
```

> O SQL completo e sem abreviações está no arquivo de migration.

---

## Conteúdo do Snapshot

O campo `snapshot` (jsonb) registra os seguintes blocos:

| Campo no JSON | Conteúdo |
|---------------|----------|
| `baseline_date` | `"2026-05-16"` |
| `auditor` | `"institutional-audit-2026-05-16"` |
| `dump_source` | caminho do arquivo remoto |
| `audit_documents` | array com 16 arquivos de baseline produzidos |
| `schema_counts` | contagens do dump: 85 tabelas, 110 views, 80 funções… |
| `security_issues_confirmed` | 6 achados de segurança com ID, objeto, severidade, migration e status |
| `false_positives_found` | 1 falso positivo (FP-01: fn_insert_audit_evento_smart) |
| `critical_contracts_confirmed` | 25 contratos canônicos confirmados no dump |
| `contracts_missing` | 1 contrato ausente (v_completed_lessons_count) |
| `p0_migrations` | status de cada migration P0 no momento da execução |

---

## Testes SQL Pós-Apply

### Teste 1 — Registro foi inserido?
```sql
SELECT migration_id, applied_at
FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
```
**Esperado:** 1 linha com `applied_at` próximo de `now()`.

---

### Teste 2 — Snapshot contém os campos esperados com contagens corretas?
```sql
SELECT
    snapshot->>'baseline_date'    AS baseline_date,
    snapshot->>'auditor'          AS auditor,
    jsonb_array_length(snapshot->'security_issues_confirmed')    AS security_issues,
    jsonb_array_length(snapshot->'false_positives_found')        AS false_positives,
    jsonb_array_length(snapshot->'critical_contracts_confirmed') AS contracts_ok,
    jsonb_array_length(snapshot->'contracts_missing')            AS contracts_missing
FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
```
**Esperado:**
```
baseline_date   | 2026-05-16
auditor         | institutional-audit-2026-05-16
security_issues | 6
false_positives | 1
contracts_ok    | 25
contracts_missing | 1
```

---

### Teste 3 — Idempotência: reexecutar não gera erro nem duplicata?
```sql
-- Executar o INSERT da migration novamente (simular reexecução).
-- Esperado: nenhum erro, INSERT 0 0

SELECT COUNT(*)
FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
-- Esperado: 1 (exatamente uma linha, independente de quantas vezes foi executado)
```

---

### Teste 4 — `applied_at` não foi sobrescrito pela reexecução?
```sql
-- Antes de reexecutar, anotar o applied_at original:
SELECT applied_at FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';

-- Reexecutar o INSERT.

-- Consultar novamente — deve ser o mesmo timestamp:
SELECT applied_at FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
-- Esperado: mesmo valor (ON CONFLICT DO NOTHING não faz UPDATE)
```

---

## Rollback

```sql
DELETE FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
```

**Verificação pós-rollback:**
```sql
SELECT COUNT(*)
FROM public._qd_migration_snapshots
WHERE migration_id = 'baseline_audit_2026_05_16';
-- Esperado: 0
```

Rollback é imediato e sem efeitos colaterais — apenas remove a linha de metadados.

---

## Referências

| Documento | Localização |
|-----------|-------------|
| Arquivo da migration | `supabase/migrations/20260516002000_p0_m2_register_baseline_audit.sql` |
| Dump remoto (tabela, ln 9018) | `supabase/remote/supabase_remote_schema.sql` |
| Dump remoto (PK, ln 14831) | `supabase/remote/supabase_remote_schema.sql` |
| Decision Packet (P0-M2) | `supabase/baseline/P0_DECISION_PACKET.md §2` |
| P0-M1 Handoff | `supabase/baseline/P0_M1_HANDOFF.md` |
| P0-M3 VOID Handoff | `supabase/baseline/P0_M3_VOID_HANDOFF.md` |
| P0-M4 Handoff | `supabase/baseline/P0_M4_HANDOFF.md` |

---

## Checklist de Aprovação

```
[ ] Dump relido nas linhas 9018–9022 (schema da tabela confirmado)
[ ] Dump relido na linha 14831–14832 (PK confirmada como migration_id)
[ ] Nomes de colunas na migration conferidos contra o dump (migration_id, applied_at, snapshot)
[ ] ON CONFLICT (migration_id) DO NOTHING confirmado como idempotente
[ ] Conteúdo do snapshot revisado e aprovado institucionalmente
[ ] Migration aplicada em ambiente de staging
[ ] Teste 1 passou em staging (1 linha inserida)
[ ] Teste 2 passou em staging (campos e contagens corretos)
[ ] Teste 3 passou em staging (reexecução idempotente)
[ ] Teste 4 passou em staging (applied_at preservado na reexecução)
[ ] Aprovado por: ___________________________
[ ] Data de execução em produção: ___________
[ ] Executado por: __________________________
[ ] Testes repetidos em produção pós-apply
[ ] Status atualizado para: EXECUTADO
```

---

## Status

```
AGUARDANDO EXECUÇÃO
```
