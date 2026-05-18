# P0-M6 Handoff — Guardar `auth.uid()` em `public.complete_lesson`
**Status:** AGUARDANDO EXECUÇÃO
**Data de geração:** 2026-05-16
**Classificação:** P0-M6 — Segurança (SEC-03 + GRANT-01)
**Arquivo de migration:** `supabase/migrations/20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql`

---

## Objetivo

Corrigir dois problemas confirmados na auditoria pré-P0-M6:

**SEC-03 — Parâmetro externo sem validação:**
A função aceita `p_recruta_id` como `uuid` externo sem verificar se corresponde ao usuário
autenticado. Um cliente modificado poderia passar o UUID de outro recruta e registrar
conclusão de aula + XP em nome dele.

**GRANT-01 — EXECUTE ausente para `authenticated`:**
O dump remoto contém apenas `GRANT ALL TO service_role`. Sem `GRANT EXECUTE TO authenticated`,
chamadas via `supabase.rpc()` com JWT de usuário retornam "permission denied for function
complete_lesson". Esta migration inclui o grant faltante.

---

## Escopo

| O que muda | O que NÃO muda |
|-----------|----------------|
| Corpo da função: adicionada guarda `auth.uid()` | Assinatura: idêntica ao dump |
| `GRANT EXECUTE TO authenticated` adicionado | `SECURITY DEFINER`: mantido |
| | `SET search_path TO 'public'`: mantido |
| | Owner (`postgres`): mantido |
| | `GRANT ALL TO service_role`: mantido |
| | `REVOKE ALL FROM PUBLIC`: mantido |
| | Lógica de negócio: preservada integralmente |
| | Tabelas, colunas, constraints, indexes: intocados |
| | Dados de recrutas, progresso, XP: intocados |

Esta migration usa `CREATE OR REPLACE FUNCTION` — não executa DROP, não quebra dependências,
não invalida planos de query existentes em outros objetos.

---

## Risco

| Dimensão | Avaliação |
|----------|-----------|
| Breaking change no frontend | **NENHUM** — assinatura preservada, `progressService.ts:50` sem alteração |
| Impacto em dados existentes | **ZERO** — apenas corpo da função e grant |
| Reversibilidade | **IMEDIATA** — rollback é `CREATE OR REPLACE` com corpo original + `REVOKE EXECUTE FROM authenticated` |
| Risco da migration em si | **MÉDIO** — substitui corpo de função SECURITY DEFINER em produção |
| Chamadas legítimas do frontend | **Não afetadas** — `userId = session.user.id` sempre passa a guarda |
| Chamadas de service_role | **Não afetadas** — `auth.uid() IS NULL` → guarda não dispara |

---

## Pré-condição Recomendada

Antes de aplicar em produção, executar no banco remoto para entender o estado atual:

```sql
SELECT has_function_privilege(
    'authenticated',
    'public.complete_lesson(uuid, uuid, integer)',
    'EXECUTE'
);
```

| Resultado | Interpretação |
|-----------|---------------|
| `true` | Grant implícito existia — GRANT-01 não causou downtime visível |
| `false` | GRANT-01 era bug ativo — frontend incapaz de concluir aulas hoje |

O resultado não bloqueia a migration (ambos são corrigidos). Mas `false` indica que
a comunicação de resolução do bug deve ser feita para a equipe de produto.

---

## A Mudança — Guarda de Segurança (SEC-03)

### Código adicionado (início do corpo, antes de qualquer DML)

```sql
IF auth.uid() IS NOT NULL AND p_recruta_id IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Unauthorized: p_recruta_id must match the authenticated user session'
    USING ERRCODE = '42501';
END IF;
```

### Por que `auth.uid() IS NOT NULL`?

Em PostgreSQL/Supabase, `auth.uid()` lê `current_setting('request.jwt.claims', true)`.
Chamadas via `service_role` (Edge Functions, cron, seeds) não carregam JWT → `auth.uid()` retorna `NULL`.

A condição composta garante:

| Contexto da chamada | `auth.uid()` | Comportamento da guarda |
|---------------------|-------------|------------------------|
| Frontend (JWT de usuário) | UUID do caller | Valida `p_recruta_id = auth.uid()` |
| Frontend com UUID diferente | UUID do caller | **RAISE EXCEPTION 42501** |
| Edge Function (service_role) | NULL | Guarda ignorada — passa |
| Cron / seed (service_role) | NULL | Guarda ignorada — passa |

### Por que `IS DISTINCT FROM` e não `!=`?

`NULL != NULL` retorna NULL em SQL (não `true`), o que tornaria a guarda bypassável
se `p_recruta_id` fosse NULL. `IS DISTINCT FROM` trata NULL de forma determinística:
`NULL IS DISTINCT FROM NULL` = `false` (iguais), `NULL IS DISTINCT FROM 'uuid'` = `true`.

---

## Grant adicionado (GRANT-01)

```sql
GRANT EXECUTE ON FUNCTION public.complete_lesson(uuid, uuid, integer) TO authenticated;
```

Este grant permite que usuários com JWT válido chamem a função via `supabase.rpc()`.
Combinado com a guarda de `auth.uid()`, authenticated pode chamar apenas para o próprio UUID.

---

## SQL Completo da Migration

```sql
-- PASSO 1 — Substituir função com guarda
CREATE OR REPLACE FUNCTION public.complete_lesson(
    p_recruta_id uuid,
    p_lesson_id  uuid,
    p_xp         integer DEFAULT 50
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ja_concluida boolean;
BEGIN

  -- Guarda SEC-03
  IF auth.uid() IS NOT NULL AND p_recruta_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: p_recruta_id must match the authenticated user session'
      USING ERRCODE = '42501';
  END IF;

  -- idempotência
  SELECT EXISTS (
    SELECT 1 FROM public.recruta_progresso
    WHERE recruta_id = p_recruta_id AND lesson_id = p_lesson_id
      AND completed_at IS NOT NULL
  ) INTO v_ja_concluida;

  IF v_ja_concluida THEN
    RETURN json_build_object(
      'status', 'ok', 'xp_granted', false, 'message', 'Aula já concluída anteriormente'
    );
  END IF;

  -- registrar conclusão
  INSERT INTO public.recruta_progresso
    (recruta_id, lesson_id, status, completed_at, xp_granted, source)
  VALUES
    (p_recruta_id, p_lesson_id, 'completed', now(), p_xp, 'lesson_complete')
  ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

  -- conceder XP canônico
  INSERT INTO public.xp_eventos (recruta_id, forca, quantidade, origem, referencia_id)
  SELECT r.id, r.forca, p_xp, 'lesson_complete', p_lesson_id
  FROM public.recrutas r
  WHERE r.id = p_recruta_id
  ON CONFLICT DO NOTHING;

  RETURN json_build_object('status', 'ok', 'xp_granted', true, 'xp_added', p_xp);
END;
$$;

-- PASSO 2 — Ajustar grants
REVOKE ALL     ON FUNCTION public.complete_lesson(uuid, uuid, integer) FROM PUBLIC;
GRANT ALL      ON FUNCTION public.complete_lesson(uuid, uuid, integer) TO service_role;
GRANT EXECUTE  ON FUNCTION public.complete_lesson(uuid, uuid, integer) TO authenticated;
```

---

## Testes SQL Pós-Apply

### Teste 1 — Guarda SEC-03: UUID diferente do caller é bloqueado?
*(executar como usuário authenticated com JWT válido — substitua `<outro_uuid>` por um UUID válido diferente do caller)*

```sql
SELECT public.complete_lesson('<outro_uuid>', '<uuid_qualquer_aula>');
```
**Esperado:** `ERROR 42501 — "Unauthorized: p_recruta_id must match the authenticated user session"`

---

### Teste 2 — Fluxo legítimo: próprio UUID passa pela guarda?
*(executar como usuário authenticated)*

```sql
SELECT public.complete_lesson(auth.uid(), '<uuid_de_aula_valida>');
```
**Esperado:**
```json
{"status": "ok", "xp_granted": true, "xp_added": 50}
```
ou `"xp_granted": false` se a aula já havia sido concluída.

---

### Teste 3 — Idempotência: segunda chamada não duplica XP?

```sql
-- Primeira chamada
SELECT public.complete_lesson(auth.uid(), '<uuid_aula>');
-- Segunda chamada
SELECT public.complete_lesson(auth.uid(), '<uuid_aula>');
-- Esperado na 2ª: {"status":"ok","xp_granted":false,"message":"Aula já concluída anteriormente"}

SELECT COUNT(*)
FROM public.xp_eventos
WHERE recruta_id    = auth.uid()
  AND referencia_id = '<uuid_aula>'
  AND origem        = 'lesson_complete';
-- Esperado: 1
```

---

### Teste 4 — Grant para `authenticated` existe?

```sql
SELECT has_function_privilege(
    'authenticated',
    'public.complete_lesson(uuid, uuid, integer)',
    'EXECUTE'
);
-- Esperado: true
```

---

### Teste 5 — Grant para `service_role` preservado?

```sql
SELECT has_function_privilege(
    'service_role',
    'public.complete_lesson(uuid, uuid, integer)',
    'EXECUTE'
);
-- Esperado: true
```

---

### Teste 6 — Grant para `anon` revogado?

```sql
SELECT has_function_privilege(
    'anon',
    'public.complete_lesson(uuid, uuid, integer)',
    'EXECUTE'
);
-- Esperado: false
```

---

### Teste 7 — Chamada service_role (auth.uid()=NULL) não é bloqueada pela guarda?
*(executar como service_role, sem JWT)*

```sql
SELECT public.complete_lesson('<uuid_recruta_valido>', '<uuid_aula_valida>');
-- Esperado: sucesso ({"status":"ok","xp_granted":true,...} ou já concluída)
-- Não deve lançar exceção 42501
```

---

## Rollback

Caso a migration precise ser revertida, recriar a função exatamente como estava no dump
(ln 1182–1246) e remover o grant adicionado:

### Passo R1 — Recriar função original (dump ln 1182–1246)

```sql
CREATE OR REPLACE FUNCTION public.complete_lesson(
    p_recruta_id uuid,
    p_lesson_id  uuid,
    p_xp         integer DEFAULT 50
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ja_concluida boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.recruta_progresso
    WHERE recruta_id = p_recruta_id
      AND lesson_id  = p_lesson_id
      AND completed_at IS NOT NULL
  ) INTO v_ja_concluida;

  IF v_ja_concluida THEN
    RETURN json_build_object(
      'status',     'ok',
      'xp_granted', false,
      'message',    'Aula já concluída anteriormente'
    );
  END IF;

  INSERT INTO public.recruta_progresso (
    recruta_id, lesson_id, status, completed_at, xp_granted, source
  )
  VALUES (
    p_recruta_id, p_lesson_id, 'completed', now(), p_xp, 'lesson_complete'
  )
  ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

  INSERT INTO public.xp_eventos (
    recruta_id, forca, quantidade, origem, referencia_id
  )
  SELECT r.id, r.forca, p_xp, 'lesson_complete', p_lesson_id
  FROM public.recrutas r
  WHERE r.id = p_recruta_id
  ON CONFLICT DO NOTHING;

  RETURN json_build_object(
    'status',     'ok',
    'xp_granted', true,
    'xp_added',   p_xp
  );
END;
$$;
```

### Passo R2 — Restaurar grants ao estado original do dump

```sql
REVOKE ALL     ON FUNCTION public.complete_lesson(uuid, uuid, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.complete_lesson(uuid, uuid, integer) FROM authenticated;
GRANT ALL      ON FUNCTION public.complete_lesson(uuid, uuid, integer) TO service_role;
```

### Verificação pós-rollback

```sql
SELECT has_function_privilege('authenticated',
    'public.complete_lesson(uuid, uuid, integer)', 'EXECUTE');
-- Esperado: false

SELECT has_function_privilege('service_role',
    'public.complete_lesson(uuid, uuid, integer)', 'EXECUTE');
-- Esperado: true
```

---

## Referências

| Documento | Localização |
|-----------|-------------|
| Arquivo da migration | `supabase/migrations/20260516006000_p0_m6_fix_complete_lesson_auth_guard.sql` |
| Auditoria pré-M6 | `supabase/baseline/P0_M6_PRE_AUDIT.md` |
| Função original (ln 1182) | `supabase/remote/supabase_remote_schema.sql` |
| Grants originais (ln 18633) | `supabase/remote/supabase_remote_schema.sql` |
| Caller principal | `src/services/progressService.ts:50` |
| UI caller | `app/(stack)/lesson/[id].tsx:101` |
| SEC-03 original | `supabase/baseline/P0_DECISION_PACKET.md §5` |
| Decision Packet (P0-M6) | `supabase/baseline/P0_DECISION_PACKET.md §2` |

---

## Checklist de Aprovação

```
[ ] Pré-condição executada: has_function_privilege('authenticated',...) verificado
[ ] Resultado documentado: TRUE / FALSE (circular um)
[ ] Corpo da função relido contra dump ln 1182–1246 (lógica original preservada)
[ ] Guarda auth.uid() revisada e aprovada
[ ] Condição IS DISTINCT FROM confirmada (vs. != para segurança com NULL)
[ ] Condição IS NOT NULL para service_role confirmada
[ ] ERRCODE '42501' confirmado como adequado (insufficient_privilege)
[ ] Grants revisados: REVOKE PUBLIC + GRANT service_role + GRANT authenticated
[ ] Rollback relido e testado mentalmente contra dump
[ ] Migration aplicada em ambiente de staging
[ ] Teste 1 passou em staging (UUID diferente bloqueado — 42501)
[ ] Teste 2 passou em staging (próprio UUID aceito)
[ ] Teste 3 passou em staging (idempotência preservada)
[ ] Teste 4 passou em staging (authenticated = true)
[ ] Teste 5 passou em staging (service_role = true)
[ ] Teste 6 passou em staging (anon = false)
[ ] Teste 7 passou em staging (service_role sem JWT não bloqueado)
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
