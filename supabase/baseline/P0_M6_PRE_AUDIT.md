# P0-M6 Pre-Audit — Auditoria Completa de `public.complete_lesson`
**Status:** AUDITORIA CONCLUÍDA — AGUARDANDO DECISÃO INSTITUCIONAL
**Data:** 2026-05-16
**Classificação:** P0-M6 — Segurança / SEC-03
**Próximo passo:** Aprovação de opção de correção antes de gerar migration

---

## 1. Assinatura Real da Função (dump ln 1182–1246)

```sql
CREATE OR REPLACE FUNCTION "public"."complete_lesson"(
    "p_recruta_id" "uuid",
    "p_lesson_id"  "uuid",
    "p_xp"         integer DEFAULT 50
)
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
SET "search_path" TO 'public'
```

**Owner:** `postgres`
**Tipo:** SECURITY DEFINER com `SET search_path` — sem vulnerabilidade SEC-01 (search_path correto)

---

## 2. Corpo Completo da Função (dump ln 1185–1246)

```sql
DECLARE
  v_ja_concluida boolean;
BEGIN
  -- PASSO 1 — verificação de idempotência
  SELECT EXISTS (
    SELECT 1
    FROM public.recruta_progresso
    WHERE recruta_id = p_recruta_id
      AND lesson_id  = p_lesson_id
      AND completed_at IS NOT NULL
  ) INTO v_ja_concluida;

  IF v_ja_concluida THEN
    RETURN json_build_object(
      'status', 'ok',
      'xp_granted', false,
      'message', 'Aula já concluída anteriormente'
    );
  END IF;

  -- PASSO 2 — registrar conclusão
  INSERT INTO public.recruta_progresso (
    recruta_id, lesson_id, status, completed_at, xp_granted, source
  )
  VALUES (
    p_recruta_id, p_lesson_id, 'completed', now(), p_xp, 'lesson_complete'
  )
  ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

  -- PASSO 3 — conceder XP canônico
  INSERT INTO public.xp_eventos (
    recruta_id, forca, quantidade, origem, referencia_id
  )
  SELECT r.id, r.forca, p_xp, 'lesson_complete', p_lesson_id
  FROM public.recrutas r
  WHERE r.id = p_recruta_id
  ON CONFLICT DO NOTHING;

  RETURN json_build_object(
    'status', 'ok',
    'xp_granted', true,
    'xp_added', p_xp
  );
END;
```

---

## 3. Grants Reais (dump ln 18633–18634)

```sql
REVOKE ALL ON FUNCTION "public"."complete_lesson"(uuid, uuid, integer) FROM PUBLIC;
GRANT  ALL ON FUNCTION "public"."complete_lesson"(uuid, uuid, integer) TO "service_role";
```

**Análise:**

| Role | Privilégio EXECUTE |
|------|--------------------|
| `PUBLIC` (e consequentemente `anon`, `authenticated`) | **REVOGADO** |
| `service_role` | GRANT ALL (= EXECUTE) |
| `postgres` (owner) | Implícito (owner sempre pode executar) |

> **ACHADO CRÍTICO (GRANT-01):** Não existe `GRANT EXECUTE ON FUNCTION complete_lesson TO authenticated`
> no dump. Com RLS habilitado e REVOKE FROM PUBLIC, usuários `authenticated` não possuem
> privilégio de execução visível. Isso significa que as chamadas do frontend via `supabase.rpc()`
> (que usam o JWT do usuário → role `authenticated` no PostgREST) **ou estão falhando com
> "permission denied for function" ou há um grant implícito não capturado pelo dump.**
>
> **Verificação manual obrigatória antes de P0-M6:**
> ```sql
> SELECT has_function_privilege('authenticated',
>     'public.complete_lesson(uuid, uuid, integer)', 'EXECUTE');
> -- TRUE → grant implícito existe (dump incompleto)
> -- FALSE → frontend está quebrado — qualquer tentativa de concluir aula falha
> ```

---

## 4. Frontend — Callers e Parâmetros

### Caller 1: `src/services/progressService.ts:50`

```typescript
export const completeLesson = async (lessonId: string, userId: string) => {
    const { error } = await supabase.rpc('complete_lesson', {
        p_recruta_id: userId,    // ← recebido do chamador
        p_lesson_id:  lessonId
        // p_xp não enviado → usa DEFAULT 50
    });
    if (error) throw error;
};
```

### Caller 2: `app/(stack)/lesson/[id].tsx:101`

```typescript
const { session } = useAuth();
const userId = session?.user?.id;          // ← sempre o JWT sub do usuário logado
// ...
await completeLesson(String(id), userId);  // userId = session?.user?.id
```

**Fluxo completo:**

```
LessonScreen.handleComplete()
  → completeLesson(lessonId, session.user.id)    // progressService.ts
    → supabase.rpc('complete_lesson', {
          p_recruta_id: session.user.id,          // ← uuid do usuário autenticado
          p_lesson_id:  lessonId
      })
```

**Observação:** O `userId` enviado é **sempre** `session?.user?.id` — o UUID do usuário
autenticado obtido do JWT. Não há nenhum mecanismo no frontend para enviar um UUID diferente
*intencionalmente*. O vetor de ataque seria via cliente modificado (curl, Postman, app alterada).

**Resultado da busca por outros callers:**

| Local | Resultado |
|-------|-----------|
| `src/` | Apenas `progressService.ts:50` |
| `app/` | Apenas `[id].tsx:101` (via `completeLesson`) |
| `supabase/functions/` | Zero ocorrências |
| `supabase/migrations/` | Apenas referências em migrations de auditoria (P0-M2, P0-M5) |

**Total de callers em produção: 1 (progressService.ts)**

---

## 5. O que a Função Faz — Análise de Efeitos

### 5.1 Tabelas modificadas

| Tabela | Operação | Conflito | Efeito |
|--------|----------|----------|--------|
| `recruta_progresso` | INSERT | `ON CONFLICT (recruta_id, lesson_id) DO NOTHING` | Idempotente ✓ |
| `xp_eventos` | INSERT (via SELECT FROM recrutas) | `ON CONFLICT DO NOTHING` | Idempotente ✓ |

### 5.2 Tabelas NÃO modificadas

- `recrutas` — **não há UPDATE em recrutas.xp, recrutas.xp_total ou qualquer outro campo.**
  A tabela `recrutas` (dump ln 8365) não possui colunas `xp` ou `xp_total` no dump remoto.
  O XP é rastreado exclusivamente via `xp_eventos`.
- `xp_events` (legado) — não tocado.
- Nenhuma outra tabela.

### 5.3 XP Total — Como é calculado

O XP total não existe como coluna em `recrutas`. É calculado via:

| Objeto | Tipo | DDL |
|--------|------|-----|
| `v_recruta_xp_total` | VIEW | `SELECT SUM(quantidade) FROM xp_eventos GROUP BY recruta_id, forca` (ln 13511) |
| `mv_xp_mensal_recruta` | MATERIALIZED VIEW | `SUM(quantidade) FROM xp_eventos GROUP BY recruta_id, forca, mes_referencia` (ln 10772) |

`v_recruta_xp_total` tem GRANT SELECT para `authenticated` (ln 19760) — frontend lê XP via view.

### 5.4 Idempotência em xp_eventos

O `ON CONFLICT DO NOTHING` no INSERT de `xp_eventos` é suportado por:

```sql
CREATE UNIQUE INDEX "ux_xp_eventos_lesson_unique"
ON "public"."xp_eventos" USING btree (recruta_id, referencia_id)
WHERE (origem = 'lesson_complete');  -- ln 16464
```

- Chave de idempotência: `(recruta_id, referencia_id)` para `origem = 'lesson_complete'`
- `referencia_id` = `p_lesson_id` na chamada
- Resultado: chamar `complete_lesson(recruta_id, lesson_id)` duas vezes gera o mesmo estado → seguro

### 5.5 Trigger em xp_eventos?

Nenhum trigger que atualiza `recrutas` foi encontrado em `xp_eventos`. O único resultado do
grep `trigger.*xp_eventos` retornou apenas o GRANT de TRIGGER na tabela (infraestrutura), sem
função de trigger associada. XP é acumulado via views, não via trigger de atualização.

---

## 6. Dependências de Colunas xp_total / xp / quantidade

| Coluna | Origem | Uso em complete_lesson |
|--------|--------|------------------------|
| `xp_eventos.quantidade` | Parâmetro `p_xp` (DEFAULT 50) | Inserido diretamente |
| `xp_eventos.forca` | `SELECT r.forca FROM recrutas WHERE id = p_recruta_id` | Lido da tabela |
| `recruta_progresso.xp_granted` | Parâmetro `p_xp` (DEFAULT 50) | Inserido diretamente |
| `recrutas.xp` | **Não existe no dump** | Não usada |
| `recrutas.xp_total` | **Não existe no dump** | Não usada |

**Observação:** As migrations locais legadas (anteriores ao RCC) referenciavam `recrutas.xp` e
`recrutas.xp_total`. Esses campos **não existem** no dump remoto atual. Qualquer código
que dependa dessas colunas está operando contra um schema divergente.

---

## 7. Source_id / Idempotency_key

| Campo | Existência | Função na idempotência |
|-------|-----------|------------------------|
| `recruta_progresso.source` | Existe (valor: `'lesson_complete'`) | Identificador de origem, não usado na constraint |
| `xp_eventos.referencia_id` | Existe (`uuid`, nullable) | Parte da UNIQUE INDEX de idempotência |
| `xp_eventos.origem` | Existe (valor: `'lesson_complete'`) | Parte do WHERE da UNIQUE INDEX |

Não existe campo `idempotency_key` explícito. A idempotência é garantida pelo par
`(recruta_id, referencia_id)` filtrado por `origem = 'lesson_complete'`.

---

## 8. RLS em xp_eventos (tabela canônica)

As policies já existentes em `xp_eventos` no dump (confirmado — estas são da tabela canônica,
**não** da tabela legada `xp_events`):

```sql
CREATE POLICY "xp_eventos_insert_block" ON "public"."xp_eventos"
    FOR INSERT WITH CHECK (false);                                    -- bloqueia todos

CREATE POLICY "xp_eventos_no_delete" ON "public"."xp_eventos"
    FOR DELETE TO authenticated, anon USING (false);

CREATE POLICY "xp_eventos_no_update" ON "public"."xp_eventos"
    FOR UPDATE TO authenticated, anon USING (false) WITH CHECK (false);

CREATE POLICY "xp_eventos_select_block" ON "public"."xp_eventos"
    FOR SELECT USING (false);                                         -- bloqueia todos
```

`complete_lesson` (SECURITY DEFINER, owner=`postgres`=SUPERUSER) **bypassa todas estas
policies** — o INSERT em `xp_eventos` funciona independentemente do bloqueio RLS.

---

## 9. Análise de Quebra de Contrato com o Frontend

### Cenário A — Remover `p_recruta_id` da assinatura

| Aspecto | Impacto |
|---------|---------|
| Frontend envia `{ p_recruta_id: userId, p_lesson_id: lessonId }` | PostgREST → erro 404/400: "function does not exist" |
| Exige atualização de `progressService.ts` | **SIM** — mudança obrigatória |
| Downtime durante deploy | SIM, se frontend e função não forem deployados simultaneamente |
| **Classificação** | **BREAKING CHANGE** |

### Cenário B — Manter assinatura, adicionar validação interna

| Aspecto | Impacto |
|---------|---------|
| Frontend continua enviando `{ p_recruta_id: userId, p_lesson_id: lessonId }` | Sem mudança |
| `userId` é sempre `session.user.id` → validação `p_recruta_id = auth.uid()` passa | OK |
| Atualização de frontend necessária | **NÃO** |
| **Classificação** | **NON-BREAKING CHANGE** |

### Cenário C — Nova RPC `rpc_complete_lesson(p_lesson_id)`

| Aspecto | Impacto |
|---------|---------|
| Frontend precisa trocar `complete_lesson` por `rpc_complete_lesson` | **SIM** — mudança obrigatória |
| Permite período de coexistência (nova + antiga) | SIM, se planejado |
| **Classificação** | **BREAKING CHANGE** (mas controlável com período de transição) |

### Cenário D — Manter somente service_role, bloquear authenticated

| Aspecto | Impacto |
|---------|---------|
| Status atual: authenticated já não tem EXECUTE (conforme dump) | Status quo |
| Frontend está provavelmente quebrado hoje | **VER ACHADO GRANT-01** |
| Usuários não conseguem marcar aulas como concluídas | **CRÍTICO se confirmado** |
| **Classificação** | Nenhuma mudança necessária — mas exige verificação urgente |

---

## 10. Plano de Compatibilidade por Opção

### Opção A — Alterar assinatura (remover `p_recruta_id`)

```
Pré-requisito: coordenar deploy backend + frontend
Passos:
  1. CREATE OR REPLACE FUNCTION complete_lesson(p_lesson_id uuid, p_xp integer DEFAULT 50)
     → usar auth.uid() internamente
  2. GRANT EXECUTE ON FUNCTION complete_lesson(uuid, integer) TO authenticated
  3. Atualizar progressService.ts: remover p_recruta_id do rpc call
  4. Deploy simultâneo (ou janela de manutenção)
```

**Risco:** ALTO — deploy coordenado obrigatório. Janela de downtime potencial.

---

### Opção B — Manter assinatura, validar internamente ← RECOMENDADA

```
Passos:
  1. CREATE OR REPLACE FUNCTION (mesma assinatura):
     - Adicionar: IF p_recruta_id IS DISTINCT FROM auth.uid() THEN
                    RAISE EXCEPTION 'Unauthorized: p_recruta_id must match auth session';
                  END IF;
  2. GRANT EXECUTE ON FUNCTION complete_lesson(uuid, uuid, integer) TO authenticated
     → necessário para frontend funcionar (ou confirmar que já existe)
  3. Nenhuma mudança no frontend
```

**Notas técnicas:**
- `auth.uid()` em funções SECURITY DEFINER: retorna o UUID do **caller** (JWT do usuário
  que iniciou a request). A variável de sessão `request.jwt.claims.sub` é preservada
  mesmo quando a execução muda para o role do owner. Confirmado pelo comportamento
  padrão do PostgREST com Supabase.
- A validação `p_recruta_id IS DISTINCT FROM auth.uid()` é segura e não quebra o fluxo
  legítimo (onde userId já é sempre session.user.id).
- Caso `auth.uid()` retorne NULL (chamada de service_role sem JWT), a validação retorna
  true para IS DISTINCT → bloquearia service_role. **Ajuste necessário:**
  ```sql
  IF auth.uid() IS NOT NULL AND p_recruta_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized';
  END IF;
  ```
  Assim, chamadas de service_role (sem JWT → auth.uid()=NULL) passam sem restrição,
  e chamadas de authenticated com UUID diferente são bloqueadas.

**Risco:** MÉDIO — modifica corpo de função em produção. Não requer mudança de frontend.
Idempotente: se já tinha uma versão anterior, CREATE OR REPLACE substitui sem DROP.

---

### Opção C — Nova RPC segura, migrar frontend depois

```
Passos:
  1. Criar: rpc_complete_lesson(p_lesson_id uuid, p_xp integer DEFAULT 50)
     → usa auth.uid() internamente, sem p_recruta_id
  2. GRANT EXECUTE TO authenticated
  3. Sprint 2: atualizar progressService.ts para usar rpc_complete_lesson
  4. Sprint 3: deprecar e remover complete_lesson
```

**Risco:** BAIXO para o banco (CREATE novo, não substitui). MÉDIO para frontend (mudança necessária).
Recomendada se houver bandwidth de frontend disponível — mas não é P0 urgente.

---

### Opção D — Manter service_role only, bloquear authenticated formalmente

```
Ações:
  1. Verificar has_function_privilege('authenticated', ..., 'EXECUTE') → confirmar FALSE
  2. Se FALSE: GRANT EXECUTE TO service_role (já existe) — nenhuma mudança
  3. Frontend deve ser redesenhado para usar Edge Function como proxy
```

**Risco:** ALTO para o produto — concluir aulas estaria quebrado para usuários.
**Não recomendada como P0.** Adequada apenas se a função for inteiramente substituída por Edge Function.

---

## 11. Classificação de Risco por Opção

| Opção | Risco Técnico | Risco Produto | Requer Frontend | Recomendada |
|-------|--------------|---------------|-----------------|-------------|
| A — Remover `p_recruta_id` | MÉDIO | ALTO (deploy sync) | **SIM** | Sprint 2 |
| **B — Validar internamente** | **MÉDIO** | **BAIXO** | **NÃO** | **✓ P0-M6** |
| C — Nova RPC | BAIXO | BAIXO | SIM | Sprint 2 |
| D — Manter service_role only | BAIXO | **CRÍTICO** | SIM (redesign) | Não |

---

## 12. RECOMENDAÇÃO FINAL

### Caminho: **Opção B** — Validar `p_recruta_id = auth.uid()` internamente

**Justificativa:**

1. **Sem breaking change** — frontend não precisa ser alterado. Único arquivo consumidor
   (`progressService.ts:50`) continua funcionando sem modificação.

2. **Elimina o vetor SEC-03** — um cliente malicioso enviando UUID de outro usuário como
   `p_recruta_id` receberá `RAISE EXCEPTION 'Unauthorized'` ao invés de gravar progresso
   e XP para o usuário alvo.

3. **Compatível com service_role** — a condição `IF auth.uid() IS NOT NULL AND ...` preserva
   chamadas server-side (Edge Functions, cron) onde `auth.uid()` retorna NULL.

4. **Corrige GRANT-01 ao mesmo tempo** — a migration P0-M6 deve incluir o
   `GRANT EXECUTE TO authenticated` ausente, garantindo que o frontend funcione
   corretamente independentemente do resultado da verificação manual.

5. **CREATE OR REPLACE é seguro** — não faz DROP da função, não quebra dependências,
   preserva o owner e os grants existentes.

### Pré-condição obrigatória antes de P0-M6:

```sql
-- Executar em produção ANTES de gerar P0-M6:
SELECT has_function_privilege(
    'authenticated',
    'public.complete_lesson(uuid, uuid, integer)',
    'EXECUTE'
);
-- TRUE  → frontend funciona (grant implícito existe)
-- FALSE → frontend está quebrado hoje (GRANT-01 confirmado como bug ativo)
```

O resultado desta verificação não muda a recomendação (Opção B inclui o GRANT),
mas determina se GRANT-01 é um bug ativo em produção que precisa de comunicação urgente.

---

## 13. Achados Consolidados

| ID | Objeto | Achado | Severidade | Ação em P0-M6 |
|----|--------|--------|------------|---------------|
| SEC-03 | `complete_lesson` | Aceita `p_recruta_id` externo — qualquer authenticated pode gravar XP e progresso para outro recruta | MÉDIO-ALTO | CORRIGIR via Opção B |
| GRANT-01 | `complete_lesson` | Sem `GRANT EXECUTE TO authenticated` visível no dump — frontend potencialmente quebrado | CRÍTICO (produto) | ADICIONAR em P0-M6 |
| INFO-01 | `recrutas` | Sem colunas `xp`/`xp_total` no dump remoto — XP é calculado via `v_recruta_xp_total` (view) | INFO | Nenhuma |
| INFO-02 | `xp_eventos` | Unique index `ux_xp_eventos_lesson_unique` garante idempotência real para `complete_lesson` | INFO | Nenhuma |
| INFO-03 | `xp_eventos` | RLS com blocking policies já existente — SECURITY DEFINER bypassa corretamente via SUPERUSER | INFO | Nenhuma |

---

## 14. Referências

| Documento | Localização |
|-----------|-------------|
| Função (ln 1182–1246) | `supabase/remote/supabase_remote_schema.sql` |
| Grants (ln 18633–18634) | `supabase/remote/supabase_remote_schema.sql` |
| Unique index (ln 16464) | `supabase/remote/supabase_remote_schema.sql` |
| RLS xp_eventos (ln 18434–18446) | `supabase/remote/supabase_remote_schema.sql` |
| `v_recruta_xp_total` (ln 13511) | `supabase/remote/supabase_remote_schema.sql` |
| Caller principal | `src/services/progressService.ts:50` |
| UI caller | `app/(stack)/lesson/[id].tsx:101` |
| SEC-03 original | `supabase/baseline/P0_DECISION_PACKET.md §5` |
| Decision Packet (P0-M6) | `supabase/baseline/P0_DECISION_PACKET.md §2` |

---

## 15. Status

```
AUDITORIA CONCLUÍDA
AGUARDANDO DECISÃO INSTITUCIONAL SOBRE OPÇÃO (A/B/C/D)
RECOMENDAÇÃO: OPÇÃO B
PRÉ-CONDIÇÃO: Executar has_function_privilege() em produção antes de gerar P0-M6
```
