# P0-M3 Handoff — VOID — Falso Positivo: `fn_insert_audit_evento_smart`
**Status:** CANCELADA — FALSO POSITIVO
**Data de geração:** 2026-05-16
**Classificação:** N/A — Nenhuma migration executar

---

## Resumo

A migration P0-M3 foi cancelada antes de ser gerada. A função
`public.fn_insert_audit_evento_smart` **não existe** no banco remoto.
A premissa do item de auditoria (SEC-05 / P0-M3) era incorreta.

**Nenhuma ação SQL é necessária.**

---

## Pesquisa direta no dump (`supabase/remote/supabase_remote_schema.sql`)

Executada durante a tentativa de gerar a migration:

| Termo pesquisado | Resultado |
|-----------------|-----------|
| `fn_insert_audit_evento_smart` | **0 ocorrências** |
| `INSTEAD OF` | **0 ocorrências** |
| `CREATE TRIGGER` | **0 ocorrências** |
| `v_audit_eventos` | **1 ocorrência** — view read-only (ln 11465–11494) |

---

## O que o dump confirma

### `v_audit_eventos` (ln 11465–11494) — view READ-ONLY

```sql
CREATE OR REPLACE VIEW "public"."v_audit_eventos" AS
SELECT
    rp.recruta_id,
    rp.lesson_id AS source_id,
    'lesson_progress'::text AS event_type,
    rp.completed_at AS created_at
FROM public.recruta_progresso rp
WHERE rp.recruta_id = (SELECT id FROM public.recrutas WHERE auth_id = auth.uid())
UNION ALL
SELECT
    xe.recruta_id,
    xe.id AS source_id,
    'xp_evento'::text AS event_type,
    xe.criada_em AS created_at
FROM public.xp_eventos xe
WHERE xe.recruta_id = (SELECT id FROM public.recrutas WHERE auth_id = auth.uid())
UNION ALL
SELECT
    mc.recruta_id,
    mc.medalha_id AS source_id,
    'medalha'::text AS event_type,
    mc.concedida_em AS created_at
FROM public.medalhas_concedidas mc
WHERE mc.recruta_id = (SELECT id FROM public.recrutas WHERE auth_id = auth.uid());
```

A view é **somente leitura**. Não há trigger `INSTEAD OF INSERT` associado.

### `chat_audit_log` (ln 9968)

A tabela existe com as colunas:
`audit_id, session_id, timestamp_utc, recruta_id, instructor_profile_id,
access_mode, interaction_type, response_category, source, agent, metadata`

RLS: `service_role` full access only (por design correto).

Inserções em `chat_audit_log` são realizadas por **Edge Functions** rodando como
`service_role` — não por trigger SQL. Esse é o design intencional da arquitetura.

---

## Origem do falso positivo

### Cadeia de propagação

```
supabase_audit_report.md
  └─ inferiu fn_insert_audit_evento_smart a partir de refs TypeScript
      └─ SECURITY_DEFINER_AUDIT.md
          └─ modules/03_chat_rcc_05_wave1.sql   (linha "BUG: INVOKER em vez de DEFINER")
          └─ modules/10_functions_rpcs.sql       (listou como função INVOKER com bug)
          └─ modules/12_triggers_indexes.sql     (listou o trigger como existente)
              └─ P0_DECISION_PACKET.md §5        (confirmou como "SIM — bug ativo")
                  └─ P0-M3 (migração planejada)  ← CANCELADA AQUI
```

### Raiz do problema

`supabase_audit_report.md` inferiu a existência da função a partir de chamadas
TypeScript em `src/` que pareciam sugerir um mecanismo de trigger de auditoria.
Essa inferência não foi validada por busca direta no dump antes de ser documentada.

O erro foi multiplicado ao ser copiado para 4 documentos de baseline sem verificação
independente.

---

## Arquivos com informação incorreta (referência para correção futura)

Os arquivos abaixo ainda contêm menção à `fn_insert_audit_evento_smart` como bug ativo.
Foram gerados antes da descoberta do falso positivo e não foram corrigidos linha a linha
para evitar regressões em outros dados corretos que esses arquivos contêm:

| Arquivo | Conteúdo incorreto |
|---------|-------------------|
| `supabase/baseline/modules/03_chat_rcc_05_wave1.sql` | Linha que cita "BUG: INVOKER em vez de DEFINER" |
| `supabase/baseline/modules/10_functions_rpcs.sql` | fn_insert_audit_evento_smart listada como INVOKER |
| `supabase/baseline/modules/12_triggers_indexes_constraints.sql` | trg_audit_evento_smart listado como trigger existente |
| `supabase/baseline/SECURITY_DEFINER_AUDIT.md` | fn_insert_audit_evento_smart na lista de vulnerabilidades |

**Esses arquivos são de referência/auditoria (não executáveis).** A nota corretiva
está registrada neste handoff. Corrigi-los não é P0.

---

## Situação real da auditoria de chat

A auditoria de chat via Edge Functions pode ou não estar cobrindo todos os cenários.
Isso requer investigação separada fora do escopo das migrations SQL P0:

1. Verificar quais Edge Functions inserem em `chat_audit_log`
2. Confirmar que `interaction_type`, `response_category`, `agent` são populados corretamente
3. Confirmar que há cobertura para sessões iniciadas e encerradas

**Isso é um item de Sprint 2+ — não é bloqueante para as migrations P0.**

---

## Rollback

N/A — nenhuma migration foi executada.

---

## Status

```
CANCELADA — FALSO POSITIVO
Nenhuma action pendente relacionada a esta migration.
```
