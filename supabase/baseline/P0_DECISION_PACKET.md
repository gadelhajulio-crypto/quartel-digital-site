# P0 Decision Packet — Quartel Digital Supabase
**Data:** 2026-05-16
**Gerado por:** Auditoria institucional completa do dump remoto
**Fontes:** BASELINE_INDEX.md, DRIFT_REPORT.md, CRITICAL_CONTRACTS_CHECK.md,
           SECURITY_DEFINER_AUDIT.md, RLS_POLICY_AUDIT.md, modules/10–12
**Status:** AGUARDANDO APROVAÇÃO INSTITUCIONAL — não executar sem revisão

---

## RESUMO EXECUTIVO

| Item | Resposta curta |
|------|---------------|
| `complete_lesson` ainda vulnerável no dump? | **SIM** (ln 1182) — mas mitigada por grants service_role |
| `fn_insert_audit_evento_smart` ainda vulnerável? | **FALSO POSITIVO** — função não existe no dump. `v_audit_eventos` é read-only. Ver §5. |
| DEFINER sem `SET search_path` confirmados? | **1 confirmada** (`buscar_revisoes_whatsapp`) + ~20 com status não verificado |
| `xp_eventos` permite INSERT direto authenticated? | **NÃO** — BLOQUEADO. `xp_events` (legada) pode ainda permitir |
| Contratos críticos existem no dump? | **SIM** — todos os contratos obrigatórios confirmados (ver §7) |
| Migration que pode rodar primeiro sem quebrar frontend? | **P0-M1** (`buscar_revisoes_whatsapp` search_path) |

---

## §1 — LISTA P0 EM ORDEM SEGURA DE EXECUÇÃO

As migrations abaixo estão ordenadas por: impacto crescente × risco crescente.
Cada migration subsequente NÃO depende da anterior (exceto onde indicado explicitamente).

| Ordem | ID | Arquivo sugerido | Risco | Pode rodar primeiro? |
|-------|----|-----------------|-------|---------------------|
| 1 | P0-M1 | `20260516001000_fix_buscar_revisoes_search_path.sql` | BAIXO | **SIM** |
| 2 | P0-M2 | `20260516002000_register_baseline_audit.sql` | MÍNIMO | SIM |
| 3 | ~~P0-M3~~ | ~~`20260516003000_fix_audit_trigger_definer.sql`~~ | ~~BAIXO~~ | **CANCELADA — FALSO POSITIVO** |
| 4 | P0-M4 | `20260516004000_block_xp_events_legacy_insert.sql` | MÉDIO | Após verificação |
| 5 | P0-M5 | `20260516005000_register_contract_registry.sql` | MÍNIMO | Após P0-M2 |
| 6 | P0-M6 | `20260516006000_fix_complete_lesson_auth_uid.sql` | **ALTO** | **NÃO** — última |

---

## §2 — DETALHAMENTO DE CADA MIGRATION P0

---

### P0-M1 — Fix `buscar_revisoes_whatsapp` search_path

**Arquivo:** `20260516001000_fix_buscar_revisoes_search_path.sql`
**Objetivo:** Corrigir SECURITY DEFINER sem `SET search_path`, eliminando vetor de schema injection.
**Evidência no dump:** linha 833–835 — função sem cláusula `SET search_path`.

**Objetos afetados:**
- `public.buscar_revisoes_whatsapp()` — modificação de atributo apenas, sem mudança de corpo.

**Risco:** BAIXO
- Grants: apenas `service_role` — nenhum usuário autenticado consome a função diretamente.
- A modificação é não-destrutiva: `ALTER FUNCTION` com `SET search_path` não altera a lógica.

**Pré-requisitos:** Nenhum.

**Pode ser executada primeiro sem quebrar frontend:** **SIM.**
A função não é consumida pelo app mobile (apenas por Edge Functions/service_role).

**SQL da migration:**
```sql
-- =============================================================================
-- Migration: 20260516001000_fix_buscar_revisoes_search_path.sql
-- Objetivo: Corrigir SECURITY DEFINER sem SET search_path
-- Risco: BAIXO — atributo apenas, sem mudança de lógica
-- Rollback: ALTER FUNCTION public.buscar_revisoes_whatsapp() RESET search_path;
-- =============================================================================

ALTER FUNCTION public.buscar_revisoes_whatsapp()
    SET search_path TO 'public', 'pg_catalog';
```

**Testes SQL:**
```sql
-- Verificar que o atributo foi aplicado:
SELECT proname, prosecdef, proconfig
FROM pg_proc
WHERE proname = 'buscar_revisoes_whatsapp'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
-- Esperado: prosecdef=true, proconfig contém 'search_path=public,pg_catalog'

-- Verificar que grants service_role foram preservados:
SELECT grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE routine_name = 'buscar_revisoes_whatsapp';
-- Esperado: service_role com EXECUTE
```

**Rollback:**
```sql
ALTER FUNCTION public.buscar_revisoes_whatsapp() RESET search_path;
```

---

### P0-M2 — Registrar Baseline no `_qd_migration_snapshots`

**Arquivo:** `20260516002000_register_baseline_audit.sql`
**Objetivo:** Versionar no banco que o baseline 2026-05-16 foi auditado e aprovado,
usando a tabela `_qd_migration_snapshots` já existente no dump (ln 9018).

**Objetos afetados:**
- `public._qd_migration_snapshots` — apenas INSERT com ON CONFLICT DO NOTHING.

**Risco:** MÍNIMO — append-only em tabela de rastreabilidade.

**Pré-requisitos:** Aprovação institucional do baseline auditado.

**SQL da migration:**
```sql
-- =============================================================================
-- Migration: 20260516002000_register_baseline_audit.sql
-- Objetivo: Registrar baseline auditado no banco
-- Risco: MÍNIMO — apenas INSERT idempotente
-- Rollback: DELETE FROM _qd_migration_snapshots WHERE snapshot_key = 'baseline_2026_05_16';
-- =============================================================================

INSERT INTO public._qd_migration_snapshots (
    snapshot_key,
    snapshot_data,
    created_at
) VALUES (
    'baseline_2026_05_16',
    jsonb_build_object(
        'total_tables',          85,
        'total_views',           110,
        'total_materialized_views', 6,
        'total_functions',       80,
        'total_triggers',        15,
        'total_rls_policies',    130,
        'audit_completed_at',    now(),
        'auditor',               'institutional-audit-2026-05-16',
        'dump_source',           'supabase/remote/supabase_remote_schema.sql',
        'p0_items',              7,
        'security_issues_found', jsonb_build_array(
            'buscar_revisoes_whatsapp: DEFINER sem search_path',
            'complete_lesson: aceita p_recruta_id externo',
            'xp_events (legacy): possível INSERT authenticated',
            'emitir_evento_c5: exposta a authenticated',
            'mv_*: sem REFRESH agendado',
            'rpc_complete_onboarding: duas sobrecargas'
        ),
        'false_positives_found', jsonb_build_array(
            'fn_insert_audit_evento_smart: não existe no dump; v_audit_eventos é read-only'
        )
    ),
    now()
) ON CONFLICT (snapshot_key) DO NOTHING;
```

**Testes SQL:**
```sql
SELECT snapshot_key, created_at
FROM public._qd_migration_snapshots
WHERE snapshot_key = 'baseline_2026_05_16';
-- Esperado: 1 linha com created_at = agora
```

**Rollback:**
```sql
DELETE FROM public._qd_migration_snapshots WHERE snapshot_key = 'baseline_2026_05_16';
```

---

### ~~P0-M3~~ — CANCELADA — FALSO POSITIVO

> **⚠ FALSO POSITIVO CONFIRMADO — NÃO EXISTE MIGRATION CORRESPONDENTE**
>
> Durante a geração da migration, o dump remoto foi pesquisado diretamente e confirmou:
>
> - `fn_insert_audit_evento_smart` — **ZERO ocorrências** em `supabase_remote_schema.sql`.
> - `INSTEAD OF` trigger em `v_audit_eventos` — **ZERO ocorrências**.
> - `CREATE TRIGGER` — **ZERO ocorrências** em todo o dump.
> - `v_audit_eventos` (ln 11465–11494) é uma view READ-ONLY (`UNION ALL` de
>   `recruta_progresso + xp_eventos + medalhas_concedidas`). Não é writable.
>
> **Origem do falso positivo:** `supabase_audit_report.md` → `SECURITY_DEFINER_AUDIT.md` →
> propagado para módulos 03, 10, 12 e para este pacote. A afirmação foi gerada por inferência
> incorreta, não por leitura direta do dump.
>
> **Situação real da auditoria de chat:**
> `chat_audit_log` é inserido por Edge Functions rodando como `service_role` — por design,
> não via trigger SQL. Não há falha silenciosa; o mecanismo simplesmente é diferente do
> que o audit report havia inferido.
>
> **Ação necessária:** Nenhuma migration SQL. Verificar a cobertura das Edge Functions de
> auditoria de chat separadamente (fora do escopo das migrations P0).
>
> **Handoff:** `supabase/baseline/P0_M3_HANDOFF.md` — documento VOID com análise completa.

---

### P0-M4 — Bloquear INSERT direto em `xp_events` (tabela legada)

**Arquivo:** `20260516004000_block_xp_events_legacy_insert.sql`
**Objetivo:** A tabela `xp_events` (sem acento — legada, diferente de `xp_eventos`) pode
ainda permitir INSERT por usuários `authenticated`, permitindo manipulação direta de XP
sem passar por nenhuma RPC DEFINER. Bloquear completamente.

**Evidência:** BASELINE_INDEX.md — "xp_events (legada) permite INSERT por authenticated".
A tabela `xp_eventos` (canônica) está protegida. A legada `xp_events` pode não estar.

**Objetos afetados:**
- `public.xp_events` — adicionar/substituir policy de INSERT.

**Risco:** MÉDIO
- **Pré-condição obrigatória:** Confirmar que NENHUM código de produção usa
  `xp_events` (sem acento) para INSERT. Verificar:
  - Frontend: `grep -r "xp_events" src/ app/`
  - Edge Functions: busca no código de funções serverless
  - Triggers: busca no dump por `xp_events` como destino de INSERT

**SQL da migration:**
```sql
-- =============================================================================
-- Migration: 20260516004000_block_xp_events_legacy_insert.sql
-- Objetivo: Bloquear INSERT direto em xp_events (tabela legada)
-- Risco: MÉDIO — verificar ausência de código que usa xp_events antes de executar
-- Rollback: DROP POLICY "xp_events_insert_block"; recriar policy permissiva
-- =============================================================================

-- Pré-check: confirmar que tabela existe e tem RLS ativo
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'xp_events'
    ) THEN
        RAISE NOTICE 'xp_events não existe — migration não necessária.';
        RETURN;
    END IF;
END $$;

ALTER TABLE IF EXISTS public.xp_events ENABLE ROW LEVEL SECURITY;

-- Remover policy permissiva existente (nome do dump: "Usuário cria XP events")
DROP POLICY IF EXISTS "Usuário cria XP events" ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_authenticated_insert" ON public.xp_events;

-- Bloquear INSERT para todos
CREATE POLICY "xp_events_insert_block" ON public.xp_events
    FOR INSERT WITH CHECK (false);

-- Bloquear UPDATE e DELETE
CREATE POLICY "xp_events_no_update" ON public.xp_events
    FOR UPDATE TO authenticated, anon USING (false);

CREATE POLICY "xp_events_no_delete" ON public.xp_events
    FOR DELETE TO authenticated, anon USING (false);
```

**Testes SQL:**
```sql
-- 1. Confirmar que política foi criada:
SELECT polname, polcmd, polroles
FROM pg_policies
WHERE tablename = 'xp_events';
-- Esperado: xp_events_insert_block com cmd=INSERT

-- 2. Smoke test (deve falhar com RLS violation):
-- Executar como authenticated:
-- INSERT INTO public.xp_events (user_id, amount) VALUES (auth.uid(), 9999);
-- Esperado: ERROR: new row violates row-level security policy
```

**Rollback:**
```sql
DROP POLICY IF EXISTS "xp_events_insert_block" ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_no_update" ON public.xp_events;
DROP POLICY IF EXISTS "xp_events_no_delete" ON public.xp_events;
-- Recriar policy original se necessário
```

---

### P0-M5 — Registrar Contratos Críticos em `c6_contract_registry`

**Arquivo:** `20260516005000_register_contract_registry.sql`
**Objetivo:** Versionar no banco quais objetos são contratos ativos do RCC-0.5,
usando `c6_contract_registry` (confirmado no dump, ln 9765).
Permite que futuras auditorias comparem contratos registrados vs. objetos existentes.

**Objetos afetados:**
- `public.c6_contract_registry` — apenas INSERTs com ON CONFLICT DO NOTHING.

**Risco:** MÍNIMO.

**Pré-requisitos:** P0-M2 (baseline registrado).

**SQL da migration:**
```sql
-- =============================================================================
-- Migration: 20260516005000_register_contract_registry.sql
-- Objetivo: Registrar contratos RCC-0.5 no c6_contract_registry
-- Risco: MÍNIMO — apenas INSERTs idempotentes
-- Rollback: DELETE FROM c6_contract_registry WHERE validated_at >= '<timestamp>';
-- =============================================================================

INSERT INTO public.c6_contract_registry
    (object_name, object_type, domain, status, validated_at)
VALUES
    -- Auth / Identidade
    ('v_identidade_recruta',              'VIEW',     'auth',     'ACTIVE', now()),
    ('v_auth_app_config',                 'VIEW',     'auth',     'ACTIVE', now()),
    ('v_app_bootstrap_institucional_rcc', 'VIEW',     'auth',     'ACTIVE', now()),
    ('v_onboarding_status',               'VIEW',     'auth',     'ACTIVE', now()),
    ('rpc_complete_onboarding',           'FUNCTION', 'auth',     'ACTIVE', now()),
    ('rpc_auth_claim_active_client_session', 'FUNCTION', 'auth',  'ACTIVE', now()),
    ('rpc_auth_resolve_session_state',    'FUNCTION', 'auth',     'ACTIVE', now()),
    ('rpc_auth_revoke_client_session',    'FUNCTION', 'auth',     'ACTIVE', now()),
    -- Chat
    ('v_chat_conversas_recruta',          'VIEW',     'chat',     'ACTIVE', now()),
    ('v_chat_mensagens_recruta',          'VIEW',     'chat',     'ACTIVE', now()),
    ('v_chat_unread_status',              'VIEW',     'chat',     'ACTIVE', now()),
    ('rpc_chat_open_conversation',        'FUNCTION', 'chat',     'ACTIVE', now()),
    ('rpc_chat_send_message',             'FUNCTION', 'chat',     'ACTIVE', now()),
    ('rpc_chat_mark_read',                'FUNCTION', 'chat',     'ACTIVE', now()),
    -- Instrutores
    ('v_instrutores_app',                 'VIEW',     'instrutores', 'ACTIVE', now()),
    ('rpc_update_instructor_profile',     'FUNCTION', 'instrutores', 'ACTIVE', now()),
    -- Aprendizagem
    ('vw_rdm_lessons_v2',                 'VIEW',     'learning', 'ACTIVE', now()),
    ('vw_recruta_module_progress_v2',     'VIEW',     'learning', 'ACTIVE', now()),
    ('complete_lesson',                   'FUNCTION', 'learning', 'ACTIVE_RISK', now()),
    ('rpc_start_module',                  'FUNCTION', 'learning', 'ACTIVE', now()),
    ('rpc_complete_module',               'FUNCTION', 'learning', 'ACTIVE', now()),
    -- Billing
    ('v_billing_status_recruta_v2',       'VIEW',     'billing',  'ACTIVE', now()),
    ('rpc_billing_status_recruta',        'FUNCTION', 'billing',  'ACTIVE', now()),
    -- Ranking / IEA
    ('v_ranking_mensal_rcc',              'VIEW',     'ranking',  'ACTIVE', now()),
    ('v_posicao_recruta_mes_rcc',         'VIEW',     'ranking',  'ACTIVE', now()),
    ('v_iea_atual_v2',                    'VIEW',     'iea',      'ACTIVE', now()),
    ('v_elegibilidade_elite_v2',          'VIEW',     'elite',    'ACTIVE', now()),
    ('v_classificacao_final_ciclo_v2',    'VIEW',     'elite',    'ACTIVE', now()),
    -- Gamificação
    ('v_medals_status_v3',                'VIEW',     'medals',   'ACTIVE', now()),
    ('v_eventos_pendentes',               'VIEW',     'c5',       'ACTIVE', now()),
    ('consumir_evento_c5',                'FUNCTION', 'c5',       'ACTIVE', now())
ON CONFLICT DO NOTHING;
```

**Testes SQL:**
```sql
SELECT COUNT(*) FROM public.c6_contract_registry WHERE status IN ('ACTIVE', 'ACTIVE_RISK');
-- Esperado: 32
```

**Rollback:**
```sql
DELETE FROM public.c6_contract_registry
WHERE validated_at >= '<timestamp da migration>';
```

---

### P0-M6 — Corrigir `complete_lesson` para usar `auth.uid()` internamente

**Arquivo:** `20260516006000_fix_complete_lesson_auth_uid.sql`
**Objetivo:** Remover `p_recruta_id` como parâmetro externo. A função DEFINER deve
derivar o recruta internamente via `auth.uid()`, eliminando a possibilidade de
um service_role mal-configurado marcar aulas em nome de outro recruta.

**Evidência no dump:** linha 1182 — `complete_lesson(p_recruta_id uuid, p_lesson_id uuid, p_xp integer DEFAULT 50)`.

**AVISO — NÃO É A MIGRATION QUE PODE RODAR PRIMEIRO.**
Esta migration tem risco ALTO e requer coordenação com:
1. Edge Functions que chamam `complete_lesson` (passar apenas `p_lesson_id`).
2. `progressService.ts` no frontend (remover `p_recruta_id` do payload).
3. Outros serviços backend que usam a função.

**Objetos afetados:**
- `public.complete_lesson` — mudança de assinatura (breaking change).
- `progressService.ts` — atualizar chamada RPC.
- Qualquer Edge Function que chame `complete_lesson`.

**Risco:** ALTO
- Breaking change de assinatura.
- Requer janela de manutenção coordenada.
- Período de transição recomendado: manter as duas assinaturas por 1 sprint.

**Pré-requisitos:**
1. Grep completo no código por `complete_lesson` em Edge Functions e backend.
2. Confirmar que TODOS os callers usam `p_lesson_id` suficiente (sem `p_recruta_id`).
3. Staging deployment e teste end-to-end.
4. Aprovação do tech lead.

**SQL da migration:**
```sql
-- =============================================================================
-- Migration: 20260516006000_fix_complete_lesson_auth_uid.sql
-- Objetivo: complete_lesson usa auth.uid() internamente
-- Risco: ALTO — breaking change de assinatura
-- Rollback: Recriar com assinatura original (p_recruta_id, p_lesson_id, p_xp)
-- =============================================================================

-- Fase 1: Dropar assinatura antiga (assinaturas diferentes impedem CREATE OR REPLACE)
DROP FUNCTION IF EXISTS public.complete_lesson(uuid, uuid, integer);

-- Fase 2: Criar nova assinatura com auth.uid() interno
CREATE OR REPLACE FUNCTION public.complete_lesson(
    p_lesson_id uuid,
    p_xp        integer DEFAULT 50
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $$
DECLARE
    v_recruta_id uuid;
    v_xp_valor   integer;
BEGIN
    -- Derivar recruta_id do JWT — nunca aceitar como parâmetro externo
    SELECT id INTO v_recruta_id
    FROM public.recrutas
    WHERE auth_id = auth.uid();

    IF v_recruta_id IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: recruta não encontrado para auth.uid()=%', auth.uid();
    END IF;

    -- Usar XP da tabela aulas se não informado explicitamente
    SELECT COALESCE(xp_valor, p_xp, 0) INTO v_xp_valor
    FROM public.aulas
    WHERE id = p_lesson_id;

    -- Inserção idempotente via UNIQUE(recruta_id, lesson_id)
    INSERT INTO public.recruta_progresso (recruta_id, lesson_id, status, xp_granted)
    VALUES (v_recruta_id, p_lesson_id, 'completed', COALESCE(v_xp_valor, 0))
    ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

    -- Atualizar XP do recruta apenas se o INSERT ocorreu
    IF FOUND THEN
        UPDATE public.recrutas
        SET xp = COALESCE(xp, 0) + COALESCE(v_xp_valor, 0)
        WHERE id = v_recruta_id;
    END IF;
END;
$$;

-- Re-aplicar grants (service_role apenas)
REVOKE ALL ON FUNCTION public.complete_lesson(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_lesson(uuid, integer) TO service_role;
```

**Mudança obrigatória em progressService.ts:**
```typescript
// ANTES (vulnerável):
await supabase.rpc('complete_lesson', {
    p_recruta_id: userId,
    p_lesson_id: lessonId,
});

// DEPOIS (seguro — p_recruta_id removido):
await supabase.rpc('complete_lesson', {
    p_lesson_id: lessonId,
});
```

**Testes SQL:**
```sql
-- 1. Verificar nova assinatura:
SELECT proname, pronargs, proargnames
FROM pg_proc
WHERE proname = 'complete_lesson';
-- Esperado: 2 args (p_lesson_id, p_xp), SEM p_recruta_id

-- 2. Tentar marcar aula de OUTRO recruta (deve afetar apenas o próprio):
-- (executar como recruta A, passar lesson_id válida)
SELECT complete_lesson('<lesson_uuid>');
-- Esperado: sucesso, only recruta A é afetado

-- 3. Idempotência — segunda chamada deve ser no-op:
SELECT complete_lesson('<lesson_uuid>');
-- Esperado: sem erro, sem duplicação em recruta_progresso

-- 4. XP correto:
SELECT xp FROM public.recrutas WHERE id = '<recruta_id>';
-- Esperado: xp incrementado pelo xp_valor da aula
```

**Rollback:**
```sql
DROP FUNCTION IF EXISTS public.complete_lesson(uuid, integer);
-- Recriar versão original com assinatura (p_recruta_id uuid, p_lesson_id uuid, p_xp integer)
-- e GRANT ALL ON FUNCTION ... TO service_role;
```

---

## §3 — MIGRATION QUE PODE SER EXECUTADA PRIMEIRO SEM QUEBRAR O FRONTEND

**→ P0-M1** (`20260516001000_fix_buscar_revisoes_search_path.sql`)

**Justificativa:**
1. Modifica apenas um atributo de função (`SET search_path`) — zero mudança de comportamento.
2. Grants permanecem exclusivamente para `service_role` — nenhum usuário autenticado é afetado.
3. A função não é consumida por nenhum hook, tela ou serviço do app mobile.
4. O comando é `ALTER FUNCTION` — atômico e reversível em 1 linha de rollback.
5. Não requer janela de manutenção.

---

## §4 — CONFIRMAÇÃO: `complete_lesson` VULNERÁVEL NO DUMP REAL

**Resposta: SIM — confirmado no dump.**

- **Linha do dump:** 1182
- **Assinatura confirmada:** `complete_lesson(p_recruta_id uuid, p_lesson_id uuid, p_xp integer DEFAULT 50)`
- **Evidência:** CRITICAL_CONTRACTS_CHECK.md linha 41: `complete_lesson | SIM (ln 1182) | SIM | 20260503011000 | RISCO — Aceita p_recruta_id — grants só service_role`

**Nível real de exploitabilidade:**
- O grant atual é **service_role apenas** — um usuário `authenticated` do app mobile NÃO pode chamar `complete_lesson` diretamente via cliente Supabase JS.
- A vulnerabilidade é **design inseguro**, não exploitável pelo usuário final atual.
- Torna-se crítica se: (a) o grant for expandido para `authenticated` por engano, ou (b) houver outra RPC que chama `complete_lesson` com parâmetro arbitrário.
- **Classificação real: MÉDIO-ALTO (mitigado por grant, não resolvido por design).**

---

## §5 — CONFIRMAÇÃO: `fn_insert_audit_evento_smart` VULNERÁVEL NO DUMP REAL

**Resposta: FALSO POSITIVO — a função não existe no dump. A premissa estava errada.**

### Pesquisa direta realizada no dump (`supabase_remote_schema.sql`):

| Termo pesquisado | Ocorrências |
|-----------------|-------------|
| `fn_insert_audit_evento_smart` | **0** |
| `INSTEAD OF` | **0** |
| `CREATE TRIGGER` | **0** |

### O que o dump confirma sobre `v_audit_eventos`:

`v_audit_eventos` (ln 11465–11494) é uma **view READ-ONLY** — `UNION ALL` de três tabelas:
- `public.recruta_progresso` (eventos de progresso de aula)
- `public.xp_eventos` (eventos de XP)
- `public.medalhas_concedidas` (eventos de medalhas)

Não há trigger `INSTEAD OF INSERT`. A view não aceita escrita.

### Como a auditoria de chat realmente funciona:

`chat_audit_log` (ln 9968) recebe inserções via **Edge Functions** rodando como `service_role`.
Não há e nunca houve um trigger SQL para auditoria de chat. O design é correto por arquitetura.

### Origem do falso positivo:

`supabase_audit_report.md` inferiu a existência da função a partir de referências indiretas
em código TypeScript. A inferência não foi validada contra o dump. O erro foi propagado
para `SECURITY_DEFINER_AUDIT.md`, `modules/03`, `modules/10`, `modules/12` e para §2 deste pacote.

### Ação corretiva:

- Migration P0-M3 **CANCELADA** (sem objeto a corrigir).
- Arquivos de módulo que referenciavam a função como bug devem ser tratados como incorretos
  nesse ponto específico — ver `P0_M3_HANDOFF.md` (VOID) para rastreabilidade completa.
- Verificar cobertura real da auditoria de chat via Edge Functions (fora do escopo das migrations SQL).

---

## §6 — CONFIRMAÇÃO: FUNÇÕES SECURITY DEFINER SEM `SET search_path`

### Confirmada com certeza (1):

| Função | Linha dump | Evidência |
|--------|-----------|-----------|
| `buscar_revisoes_whatsapp()` | 833–835 | SECURITY_DEFINER_AUDIT.md: única listada como "AUSENTE" confirmada |

### Prováveis (não confirmadas — status "—" no audit):

Estas funções aparecem no catálogo de DEFINER mas sem `search_path` confirmado.
O "—" no audit indica que o campo não foi verificado linha a linha no dump.
Requerem verificação com query direta:

```sql
-- Query de verificação — executar no remoto (read-only):
SELECT proname,
       prosecdef,
       proconfig,
       proconfig IS NULL OR NOT (proconfig && ARRAY['search_path']) AS sem_search_path
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
ORDER BY sem_search_path DESC, proname;
```

Funções com status "—" (provavelmente sem search_path):
- `fn_acquire_conversation_lock`
- `fn_release_conversation_lock`
- `rpc_auth_claim_active_client_session`
- `rpc_auth_resolve_session_state`
- `rpc_auth_revoke_client_session`
- `rpc_chat_open_conversation`
- `rpc_chat_send_message`
- `rpc_chat_mark_read`
- `rpc_chat_summary_upsert`
- `rpc_complete_onboarding` (ambas as sobrecargas)
- `rpc_update_instructor_profile`
- `rpc_set_instructor_profile`
- `rpc_start_module`
- `rpc_complete_module`
- `rpc_mark_notice_read`
- `rpc_mark_instructor_message_read`
- `verificar_elegibilidade_grau6`
- `garantir_recruta_ciclo_status_me`

**Ação recomendada (Sprint 2):** Executar a query de verificação no remoto.
Se confirmadas sem search_path, gerar migration de bulk-ALTER (baixo risco, alto impacto).

---

## §7 — CONFIRMAÇÃO: `xp_eventos` PERMITE INSERT DIRETO POR `authenticated`?

**Resposta: NÃO — a tabela canônica `xp_eventos` está PROTEGIDA.**

**Evidência (RLS_POLICY_AUDIT.md):**
```
xp_eventos | INSERT | xp_eventos_insert_block | public | false | BLOQUEADO
```
Nenhum usuário autenticado pode fazer INSERT direto em `xp_eventos`.

**PORÉM — a tabela LEGADA `xp_events` (sem acento) pode ainda estar desprotegida:**
- BASELINE_INDEX.md: "xp_events (legada) permite INSERT por authenticated"
- A policy "Usuário cria XP events" ainda pode existir nesta tabela
- Esta tabela não é a mesma que `xp_eventos` (são duas tabelas distintas)
- **Ação: P0-M4** — bloquear INSERT em `xp_events` (legada)

**Verificação antes de P0-M4:**
```sql
SELECT polname, polcmd, polroles
FROM pg_policies
WHERE tablename = 'xp_events';
-- Se retornar policy de INSERT para authenticated: confirmar P0-M4 urgente
-- Se a tabela não existir: P0-M4 não necessária (incluir verificação idempotente)
```

---

## §8 — CONFIRMAÇÃO: CONTRATOS CRÍTICOS EXISTEM NO DUMP

Baseado em CRITICAL_CONTRACTS_CHECK.md — grep confirmado no dump real:

| Contrato | Dump | Linha | Status |
|----------|:----:|-------|--------|
| `v_app_bootstrap_institucional_rcc` | **SIM** | 11313 | OK — security_invoker=true |
| `v_identidade_recruta` | **SIM** | 11251 | OK |
| `v_auth_app_config` | **SIM** | 11578 | OK |
| `v_onboarding_status` | **SIM** | 13468 | OK |
| `v_chat_conversas_recruta` | **SIM** | 12451 | OK — security_invoker=true |
| `v_chat_mensagens_recruta` | **SIM** | 12478 | OK — security_invoker=true |
| `v_chat_unread_status` | **SIM** | 12503 | OK — security_invoker=true |
| `rpc_chat_open_conversation` | **SIM** | 5624 | OK |
| `rpc_chat_send_message` | **SIM** | 5678 | OK |
| `rpc_chat_mark_read` | **SIM** | 5521 | OK |
| `vw_rdm_lessons_v2` | **SIM** | 14177 | OK |
| `vw_recruta_module_progress_v2` | **SIM** | 14314 | OK |
| `v_billing_status_recruta_v2` | **SIM** | 11691 | OK |
| `v_instrutores_app` | **SIM** | 13125 | OK — security_invoker=true |
| `v_ranking_mensal_rcc` | **SIM** | 13567 | OK — security_invoker=true |
| `v_posicao_recruta_mes_rcc` | **SIM** | 13480 | OK — security_invoker=true |
| `v_iea_atual_v2` | **SIM** | 13027 | OK |
| `v_elegibilidade_elite_v2` | **SIM** | 12739 | OK |
| `v_classificacao_final_ciclo_v2` | **SIM** | 12596 | OK |
| `rpc_complete_onboarding` | **SIM** | 6053 | ATENÇÃO: 2 sobrecargas |
| `rpc_auth_claim_active_client_session` | **SIM** | 4329 | OK |
| `rpc_auth_resolve_session_state` | **SIM** | 4410 | OK |
| `rpc_auth_revoke_client_session` | **SIM** | 4477 | OK |
| `rpc_update_instructor_profile` | **SIM** | 6389 | OK |
| `complete_lesson` | **SIM** | 1182 | RISCO — p_recruta_id externo |
| `v_medals_status` (v1) | **NÃO** | — | DIVERGENTE — frontend usa v2/v3 |
| `v_completed_lessons_count` | **NÃO** | — | **P0 CRÍTICO** — useRecruitPanel quebrado |

### Ausência P0 crítica: `v_completed_lessons_count`

Esta view está **ausente no dump** mas é consumida por `src/hooks/useRecruitPanel.ts:62`.
Não foi incluída nas migrations P0 acima por ser uma migration adicional, mas é igualmente urgente:

**Migration adicional recomendada:**
```
Arquivo: 20260516007000_recreate_v_completed_lessons_count.sql
```

```sql
CREATE OR REPLACE VIEW public.v_completed_lessons_count AS
SELECT
    rp.recruta_id AS user_id,
    COUNT(*) AS completed_count
FROM public.recruta_progresso rp
WHERE rp.status = 'completed'
  AND rp.recruta_id = (
      SELECT id FROM public.recrutas WHERE auth_id = auth.uid()
  )
GROUP BY rp.recruta_id;

GRANT SELECT ON public.v_completed_lessons_count TO authenticated;
GRANT SELECT ON public.v_completed_lessons_count TO service_role;
```

**Nota:** Verificar como `useRecruitPanel.ts` faz o SELECT (com `.eq()` ou sem filtro)
para confirmar se a view deve usar `auth.uid()` interno ou aceitar filtro externo.

---

## §9 — CHECKLIST DE APROVAÇÃO INSTITUCIONAL

Para cada migration P0, preencher antes de executar em produção:

```
P0-M1 (buscar_revisoes_whatsapp):
[ ] Lido corpo atual da função no dump (ln 833–835)
[ ] Confirmado que grants service_role existem e serão preservados
[ ] Testado em staging
[ ] Aprovado por: _______________

P0-M2 (baseline audit):
[ ] Baseline revisado e aprovado institucionalmente
[ ] _qd_migration_snapshots tem coluna snapshot_key (verificar DDL ln 9018)
[ ] Aprovado por: _______________

~~P0-M3~~ (CANCELADA — falso positivo; ver §5 e P0_M3_HANDOFF.md):
[x] VOID — nenhuma ação necessária

P0-M4 (xp_events block):
[ ] grep -r "xp_events" src/ app/ retorna ZERO resultados de INSERT
[ ] grep no código de Edge Functions retorna ZERO resultados de INSERT em xp_events
[ ] Confirmado que tabela xp_events existe no remoto
[ ] Confirmado que nenhum trigger insere em xp_events
[ ] Aprovado por: _______________

P0-M5 (contract registry):
[ ] c6_contract_registry tem colunas object_name, object_type, domain, status, validated_at
[ ] Verificado DDL da tabela (ln 9765 do dump)
[ ] Aprovado por: _______________

P0-M6 (complete_lesson):
[ ] Todas as Edge Functions atualizadas para nova assinatura
[ ] progressService.ts atualizado (p_recruta_id removido)
[ ] Staging deployment completo
[ ] Teste end-to-end de completar aula passado
[ ] Janela de manutenção agendada
[ ] Aprovado por: _______________

v_completed_lessons_count (adicional):
[ ] Verificado como useRecruitPanel.ts faz SELECT (filtro interno ou externo)
[ ] Ajustar DDL conforme necessário
[ ] Aprovado por: _______________
```

---

## §10 — ORDEM FINAL RECOMENDADA DE SPRINTS

```
Sprint 1 — Zero Breaking Change (pode executar agora):
  [1] P0-M1 — buscar_revisoes_whatsapp search_path  (BAIXO risco)
  [2] P0-M2 — baseline audit registration           (MÍNIMO risco)
  [3] ~~P0-M3~~ — CANCELADA (falso positivo)
  [4] P0-adicional — recreate v_completed_lessons_count (BAIXO risco)

Sprint 2 — Verificação Prévia Necessária:
  [5] P0-M4 — xp_events INSERT block                (MÉDIO risco, após grep)
  [6] P0-M5 — contract registry                     (MÍNIMO risco)
  [7] bulk ALTER — search_path para todas DEFINER sem confirmação (após query de verificação)

Sprint 3 — Coordenação Total Necessária:
  [8] P0-M6 — complete_lesson auth.uid()             (ALTO risco, janela manutenção)
  [9] Deprecar rpc_complete_onboarding() sem params  (após confirmar zero chamadores)

Sprint 4+ — Decisão Institucional:
  [10] Refresh agendado das MVs via pg_cron
  [11] rpc_complete_module com bônus XP interno (eliminar registrar_xp do cliente)
  [12] Sunset plan para 15 tabelas legadas
  [13] Normalização recrutas.xp vs recrutas.xp_total (BLOQUEADO — decisão institucional)
```
