# P0-M3 VOID Handoff — Falso Positivo: `fn_insert_audit_evento_smart`

**Status:** CANCELADA — FALSO POSITIVO CONFIRMADO PELO DUMP REMOTO
**Data:** 2026-05-16
**Migration planejada:** `20260516003000_fix_audit_trigger_definer.sql`
**Migration gerada:** NÃO — cancelada antes da geração

---

## Decisão

**Nenhuma migration necessária.**

A função `public.fn_insert_audit_evento_smart` **não existe** no banco remoto.
O objeto que o item de auditoria alegava estar vulnerável simplesmente não existe.
Não há o que corrigir.

---

## Função Analisada

| Campo | Valor |
|-------|-------|
| Nome | `public.fn_insert_audit_evento_smart` |
| Tipo declarado no audit | Trigger function |
| Status de segurança declarado | `SECURITY INVOKER` (alegado como bug) |
| Existe no dump? | **NÃO** |
| Ocorrências no dump | **0** |

---

## Status Real de SECURITY DEFINER / INVOKER

Não aplicável. A função não existe.

O dump remoto (`supabase/remote/supabase_remote_schema.sql`) foi pesquisado
diretamente com os seguintes termos:

| Termo | Ocorrências |
|-------|-------------|
| `fn_insert_audit_evento_smart` | **0** |
| `INSTEAD OF` | **0** |
| `CREATE TRIGGER` | **0** |

---

## Evidência do Dump que Desmente o Achado

### `v_audit_eventos` (dump ln 11465–11494) — view READ-ONLY

A view que supostamente recebia o trigger `INSTEAD OF INSERT` é uma
`UNION ALL` estática de três tabelas de leitura:

```
recruta_progresso  (eventos de progresso de aula)
xp_eventos         (eventos de XP)
medalhas_concedidas (eventos de medalhas)
```

Não há nenhum trigger associado. A view não aceita escrita.
Qualquer INSERT em `v_audit_eventos` retornaria erro de imediato — não falha silenciosa.

### `chat_audit_log` (dump ln 9968) — inserção via Edge Functions

A tabela existe com as colunas:
`audit_id, session_id, timestamp_utc, recruta_id, instructor_profile_id,
access_mode, interaction_type, response_category, source, agent, metadata`

RLS: `service_role` full access — por design.

Inserções são realizadas por Edge Functions rodando como `service_role`,
não por trigger SQL. Esse é o mecanismo correto e intencional.

---

## Origem do Falso Positivo

### Cadeia de propagação

```
supabase_audit_report.md
  └─ inferiu fn_insert_audit_evento_smart a partir de referências TypeScript
      │  (sem validação direta no dump)
      └─ SECURITY_DEFINER_AUDIT.md
          └─ modules/03_chat_rcc_05_wave1.sql  → cita "BUG: INVOKER em vez de DEFINER"
          └─ modules/10_functions_rpcs.sql      → lista função como INVOKER com bug
          └─ modules/12_triggers_indexes.sql    → lista o trigger como existente
              └─ P0_DECISION_PACKET.md §5       → "SIM — confirmado. Bug ativo."
                  └─ P0-M3 planejada            ← CANCELADA AQUI
```

### Raiz

`supabase_audit_report.md` fez inferência a partir de chamadas TypeScript em `src/`
que sugeriam um mecanismo de auditoria via trigger. A inferência não foi validada
por pesquisa direta no dump antes de ser propagada para os documentos de baseline.

---

## Impacto

**Nenhum.**

- Nenhuma migration foi executada.
- Nenhum objeto do banco foi alterado.
- Nenhuma tela ou hook do app mobile é afetado.
- A auditoria de chat opera normalmente via Edge Functions (mecanismo correto).

---

## Próxima Migration Recomendada

Com P0-M3 cancelada, a sequência de menor risco operacional é:

| Prioridade | Migration | Risco | Justificativa |
|-----------|-----------|-------|---------------|
| **1ª** | **P0-M2** — `20260516002000_register_baseline_audit.sql` | MÍNIMO | Apenas INSERT idempotente em `_qd_migration_snapshots`. Zero impacto no frontend. Sem pré-requisitos além de aprovação institucional do baseline. |
| 2ª | P0-M4 — `20260516004000_block_xp_events_legacy_insert.sql` | MÉDIO | Requer grep prévio no codebase e Edge Functions para confirmar zero uso de `xp_events` em INSERT. Só após confirmação. |

**P0-M2 é a próxima ação recomendada** — já tem migration gerada, é reversível em
uma linha e não requer janela de manutenção.

---

## Arquivos com Informação Desatualizada (referência)

Os arquivos abaixo ainda contêm a menção incorreta. São documentos de
referência/auditoria — não executáveis — e não foram corrigidos linha a linha
para evitar regressões em dados corretos adjacentes:

| Arquivo | Trecho incorreto |
|---------|-----------------|
| `supabase/baseline/modules/03_chat_rcc_05_wave1.sql` | `fn_insert_audit_evento_smart BUG — deve ser DEFINER` |
| `supabase/baseline/modules/10_functions_rpcs.sql` | fn_insert_audit_evento_smart listada como INVOKER com bug |
| `supabase/baseline/modules/12_triggers_indexes_constraints.sql` | trg_audit_evento_smart listado como trigger existente |
| `supabase/baseline/SECURITY_DEFINER_AUDIT.md` | fn_insert_audit_evento_smart na lista de vulnerabilidades |
| `supabase/baseline/P0_M3_HANDOFF.md` | handoff preliminar gerado antes deste documento VOID |

A nota canônica de cancelamento está em:
- `supabase/baseline/P0_DECISION_PACKET.md` §2 (P0-M3) e §5
- Este arquivo (`P0_M3_VOID_HANDOFF.md`)

---

## Checklist de Encerramento

```
[x] Pesquisa direta no dump confirmou zero ocorrências da função
[x] v_audit_eventos confirmada como read-only (sem trigger)
[x] chat_audit_log confirmado como inserido por Edge Functions (por design)
[x] P0_DECISION_PACKET.md §1, §2, §5, §9, §10 corrigidos
[x] NEXT_SAFE_MIGRATIONS.md atualizado
[x] Este handoff VOID gerado com rastreabilidade completa
[ ] Equipe notificada sobre o falso positivo no audit_report original
[ ] supabase_audit_report.md marcado como "contém inferência não validada em P0-M3"
```
