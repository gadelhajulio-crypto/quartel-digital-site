# P0-M5 Handoff — Registrar Contratos Canônicos em `public.c6_contract_registry`
**Status:** AGUARDANDO EXECUÇÃO
**Data de geração:** 2026-05-16
**Classificação:** P0-M5 — Rastreabilidade de Contratos
**Arquivo de migration:** `supabase/migrations/20260516005000_p0_m5_register_contract_registry.sql`

---

## Objetivo

Registrar os 38 contratos canônicos ativos do RCC-0.5 na tabela `public.c6_contract_registry`,
fornecendo um catálogo consultável de todos os objetos SQL consumidos pelo app mobile em produção.

Após a execução, qualquer auditoria pode executar:

```sql
SELECT * FROM public.v_c6_contracts_validos;
```

e obter a lista completa de contratos ativos sem precisar fazer grep no codebase.

---

## Escopo

| O que muda | O que NÃO muda |
|-----------|----------------|
| 38 linhas inseridas em `public.c6_contract_registry` | Nenhuma view ou RPC é alterada |
| | Nenhuma RLS policy é criada ou alterada |
| | Nenhum dado funcional do app é tocado |
| | Estrutura de qualquer tabela |
| | Nenhum grant ou permissão |

Esta migration é **puramente append-only em tabela interna de registry**.

---

## Risco

| Dimensão | Avaliação |
|----------|-----------|
| Impacto no frontend | **ZERO** — tabela interna de metadados, nunca consumida diretamente pelo app |
| Impacto em dados funcionais | **ZERO** — apenas registros de catálogo |
| Reversibilidade | **IMEDIATA** — `DELETE WHERE registered_at >= '<timestamp>'` |
| Risco da migration em si | **MÍNIMO** — INSERT com ON CONFLICT DO NOTHING |
| Risco se aplicada duas vezes | **ZERO** — segunda execução é no-op silencioso |

---

## Nota Crítica: Correção de Coluna em Relação ao Decision Packet

O rascunho em `P0_DECISION_PACKET.md §2` usou nomes de coluna e valores **INCORRETOS**:

| Rascunho (incorreto) | Dump real (ln 9765–9775) |
|----------------------|--------------------------|
| `object_name` | `contract_name` |
| `object_type` | `contract_type` |
| `domain` | *(coluna não existe)* |
| `status = 'ACTIVE'` | `status = 'canonical'` (CHECK constraint) |
| `status = 'ACTIVE_RISK'` | `status = 'canonical'` + campo `notes` para risco |
| `validated_at` | *(coluna não existe — usa `registered_at`)* |

Esta migration usa **exclusivamente** os nomes e valores reais confirmados no dump remoto.
O uso dos valores do rascunho teria causado falha por violação de CHECK constraint.

---

## Estrutura Real da Tabela (dump ln 9765–9775)

```sql
CREATE TABLE IF NOT EXISTS "public"."c6_contract_registry" (
    "contract_name"  text        NOT NULL,          -- PK
    "contract_type"  text        NOT NULL,          -- CHECK: 'view','materialized_view','rpc'
    "status"         text        NOT NULL,          -- CHECK: 'canonical','system','legacy','admin_audit','blocked'
    "frontend_scope" text,                          -- nullable
    "notes"          text,                          -- nullable
    "registered_at"  timestamptz DEFAULT now(),
    "updated_at"     timestamptz DEFAULT now()
);
-- PK: c6_contract_registry_pkey ON (contract_name)
-- RLS: ENABLED — sem policies → deny-by-default para authenticated/anon
-- GRANT: apenas owner (postgres) e service_role têm acesso
```

---

## Verificação dos 7 Contratos Condicionais

Grep realizado diretamente em `supabase/remote/supabase_remote_schema.sql` em 2026-05-16:

| Contrato | Resultado | Linha no Dump | Decisão |
|----------|-----------|---------------|---------|
| `v_institutional_notices` | CONFIRMADO | ln 13098 | Incluído |
| `v_instructor_messages` | CONFIRMADO | ln 13112 | Incluído |
| `v_modulos_catalogo` | CONFIRMADO | ln 13436 | Incluído |
| `v_available_reviews` | NÃO ENCONTRADO | — | **Excluído** |
| `v_review_content` | NÃO ENCONTRADO | — | **Excluído** |
| `rpc_mark_instructor_message_read` | NÃO ENCONTRADO | — | **Excluído** |
| `rpc_complete_module` | NÃO ENCONTRADO | — | **Excluído** |

**Resultado:** 3 confirmados (incluídos) + 4 ausentes (excluídos) = total final de 38 contratos.

### Observações sobre os 4 ausentes

| Contrato ausente | Observação |
|------------------|------------|
| `v_available_reviews` | Consumida em `useAvailableReviews.ts:22` — investigar se foi dropada ou renomeada |
| `v_review_content` | Consumida em `useReviewContent.ts:22` — investigar se foi dropada ou renomeada |
| `rpc_mark_instructor_message_read` | Tabela `instructor_message_reads` existe (ln 10263), mas a RPC não está no dump |
| `rpc_complete_module` | Referenciada em `progressService.ts:20` — investigar se existe com nome diferente |

Estes 4 itens requerem investigação separada. **Não bloqueiam P0-M5.**

---

## Totais Registrados

| Tipo | Quantidade |
|------|-----------|
| Views (`contract_type = 'view'`) | 25 |
| RPCs (`contract_type = 'rpc'`) | 13 |
| **Total** | **38** |

### Distribuição por Domínio

| Domínio | Contratos |
|---------|-----------|
| Auth / Identidade | 8 (4 views + 4 RPCs) |
| Chat (RCC Wave 1) | 6 (3 views + 3 RPCs) |
| Instrutores e Assets | 6 (4 views + 2 RPCs) |
| Aprendizagem | 6 (3 views + 3 RPCs) |
| Gamificação C5 | 2 (1 view + 1 RPC) |
| Gamificação (Medalhas) | 2 (2 views) |
| Ranking | 4 (4 views) |
| IEA e Elite | 3 (3 views) |
| Billing | 1 (1 view) |

---

## Contratos com Anotações de Risco

| Contrato | Campo `notes` |
|----------|--------------|
| `complete_lesson` | `RISCO ATIVO: aceita p_recruta_id como parâmetro externo. Mitigado por grants service_role only. Correção planejada em P0-M6.` |
| `rpc_complete_onboarding` | `Atenção: duas sobrecargas no dump (ln 5983 sem params — obsoleta; ln 6053 com params — esta). Sprint 3: deprecar versão sem params.` |

---

## Testes SQL Pós-Apply

### Teste 1 — Total de registros inseridos?
```sql
SELECT COUNT(*)
FROM public.c6_contract_registry
WHERE status = 'canonical';
```
**Esperado:** `38`

---

### Teste 2 — Contagem por tipo?
```sql
SELECT contract_type, COUNT(*)
FROM public.c6_contract_registry
WHERE status = 'canonical'
GROUP BY contract_type
ORDER BY contract_type;
```
**Esperado:**
```
contract_type | count
--------------+-------
rpc           |    13
view          |    25
```

---

### Teste 3 — `complete_lesson` tem nota de risco?
```sql
SELECT contract_name, notes
FROM public.c6_contract_registry
WHERE contract_name = 'complete_lesson';
```
**Esperado:** `notes` contém `'RISCO ATIVO'`.

---

### Teste 4 — `v_c6_contracts_validos` retorna os registros?
```sql
SELECT COUNT(*) FROM public.v_c6_contracts_validos;
```
**Esperado:** `38` *(esta view filtra `status IN ('canonical','system')`)*

---

### Teste 5 — Idempotência: reexecutar não gera erro nem duplicata?
```sql
-- Executar o INSERT da migration novamente (simular reexecução).
-- Esperado: INSERT 0 0 (zero linhas inseridas)
SELECT COUNT(*)
FROM public.c6_contract_registry
WHERE status = 'canonical';
-- Esperado: ainda 38
```

---

### Teste 6 — CHECK constraints respeitadas?
```sql
SELECT contract_name, contract_type, status
FROM public.c6_contract_registry
WHERE contract_type NOT IN ('view','materialized_view','rpc')
   OR status NOT IN ('canonical','system','legacy','admin_audit','blocked');
```
**Esperado:** zero linhas (nenhum valor inválido).

---

## Rollback

```sql
DELETE FROM public.c6_contract_registry
WHERE registered_at >= '<timestamp_da_migration>';
```

**Verificação pós-rollback:**
```sql
SELECT COUNT(*)
FROM public.c6_contract_registry
WHERE status = 'canonical';
-- Esperado: 0 (assumindo que a tabela estava vazia antes)
```

Rollback é imediato e sem efeitos colaterais — apenas remove os metadados inseridos.

---

## Referências

| Documento | Localização |
|-----------|-------------|
| Arquivo da migration | `supabase/migrations/20260516005000_p0_m5_register_contract_registry.sql` |
| Seleção de contratos | `supabase/baseline/P0_M5_CONTRACT_SELECTION.md` |
| Dump remoto (tabela, ln 9765) | `supabase/remote/supabase_remote_schema.sql` |
| Dump remoto (PK, ln 14961) | `supabase/remote/supabase_remote_schema.sql` |
| Dump remoto (RLS, ln 17598) | `supabase/remote/supabase_remote_schema.sql` |
| Decision Packet (P0-M5) | `supabase/baseline/P0_DECISION_PACKET.md §2` |
| P0-M4 Handoff | `supabase/baseline/P0_M4_HANDOFF.md` |

---

## Checklist de Aprovação

```
[ ] Dump relido nas linhas 9765–9775 (schema da tabela confirmado)
[ ] Dump relido na linha 14961 (PK confirmada como contract_name)
[ ] Dump relido na linha 17598 (RLS habilitado confirmado)
[ ] CHECK constraints verificadas: contract_type e status com valores corretos
[ ] Verificação dos 7 contratos condicionais confirmada (3 incluídos, 4 excluídos)
[ ] 4 contratos ausentes documentados para investigação separada
[ ] ON CONFLICT (contract_name) DO NOTHING confirmado como idempotente
[ ] Migration aplicada em ambiente de staging
[ ] Teste 1 passou em staging (38 linhas inseridas)
[ ] Teste 2 passou em staging (25 views + 13 RPCs)
[ ] Teste 3 passou em staging (complete_lesson com nota de risco)
[ ] Teste 4 passou em staging (v_c6_contracts_validos retorna 38)
[ ] Teste 5 passou em staging (reexecução idempotente)
[ ] Teste 6 passou em staging (zero violações de CHECK)
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
