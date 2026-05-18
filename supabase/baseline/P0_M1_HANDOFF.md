# P0-M1 Handoff — Fix `buscar_revisoes_whatsapp` search_path
**Status:** AGUARDANDO EXECUÇÃO
**Data de geração:** 2026-05-16
**Classificação:** P0 — Segurança

---

## Objetivo

Corrigir vulnerabilidade de *search_path hijacking* na função
`public.buscar_revisoes_whatsapp()`, que é declarada `SECURITY DEFINER`
sem `SET search_path`.

Uma função `SECURITY DEFINER` sem `search_path` fixado herda o `search_path`
da sessão do chamador. Se um schema adversário for posicionado antes de `public`
no `search_path`, a função pode resolver `public.revisoes` ou `public.missoes`
para objetos maliciosos nesse schema, executando código arbitrário com os
privilégios do owner da função (`postgres`).

---

## Risco

| Dimensão | Avaliação |
|----------|-----------|
| Severidade da vulnerabilidade | **ALTO** — padrão inseguro para SECURITY DEFINER |
| Exploitabilidade atual | **BAIXO** — grants apenas para `service_role`; nenhum usuário `authenticated` acessa a função |
| Risco da migration em si | **BAIXO** — `ALTER FUNCTION` modifica apenas atributo, sem mudança de lógica |
| Reversibilidade | **IMEDIATA** — rollback em uma linha |
| Impacto no frontend | **ZERO** — função não é consumida pelo app mobile |

---

## Impacto

**O que muda:**
- O atributo `proconfig` da função passa a incluir `search_path=public,pg_catalog`.
- A função executa com `search_path` fixado independente da sessão do chamador.
- Comportamento lógico, retorno e performance: **inalterados**.

**O que NÃO muda:**
- Corpo da função (`$$ select r.id ... $$`).
- Assinatura (sem parâmetros, retorna `TABLE(...)`).
- Grants (`service_role` apenas).
- Owner (`postgres`).

---

## Assinatura exata (dump ln 833)

```sql
public.buscar_revisoes_whatsapp()
```

Retorna: `TABLE(revisao_id uuid, recruta_id uuid, missao_id uuid, forca text)`
Linguagem: `sql`
Security: `SECURITY DEFINER` (sem `SET search_path` — este é o bug)

---

## Corpo original da função (dump ln 835–847 — reproduzido para referência)

```sql
SELECT
    r.id          AS revisao_id,
    r.recruta_id,
    r.missao_id,
    m.forca
FROM public.revisoes r
JOIN public.missoes m ON m.id = r.missao_id
WHERE r.tipo   = 'whatsapp'
  AND r.status = 'pendente'
ORDER BY r.criada_em
LIMIT 10;
```

A migration **não toca este corpo**.

---

## SQL aplicado

```sql
-- Arquivo: supabase/migrations/20260516001000_p0_m1_fix_buscar_revisoes_whatsapp_search_path.sql

ALTER FUNCTION public.buscar_revisoes_whatsapp()
    SET search_path TO 'public', 'pg_catalog';

REVOKE ALL ON FUNCTION public.buscar_revisoes_whatsapp() FROM PUBLIC;
GRANT ALL ON FUNCTION public.buscar_revisoes_whatsapp() TO service_role;
```

Três comandos:
1. `ALTER FUNCTION` — aplica `SET search_path` (o único com efeito de segurança).
2. `REVOKE ALL FROM PUBLIC` — idempotente, garante que herança pública não foi aplicada.
3. `GRANT ALL TO service_role` — idempotente, garante que grant não foi perdido.

---

## Testes pós-aplicação

### Teste 1 — search_path foi aplicado?
```sql
SELECT proname, prosecdef, proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'buscar_revisoes_whatsapp';
```
**Esperado:**
```
proname   | buscar_revisoes_whatsapp
prosecdef | true
proconfig | {search_path=public,pg_catalog}
```

### Teste 2 — Grant service_role preservado?
```sql
SELECT grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE routine_schema = 'public'
  AND routine_name   = 'buscar_revisoes_whatsapp';
```
**Esperado:**
```
grantee      | privilege_type
service_role | EXECUTE
```

### Teste 3 — Comportamento inalterado (executar como service_role)?
```sql
SELECT * FROM public.buscar_revisoes_whatsapp() LIMIT 1;
```
**Esperado:** mesmos dados de antes da migration (ou zero linhas se não houver
revisões WhatsApp pendentes). Sem erro de permissão ou schema.

### Teste 4 — PUBLIC não tem EXECUTE?
```sql
SELECT grantee
FROM information_schema.role_routine_grants
WHERE routine_name = 'buscar_revisoes_whatsapp'
  AND grantee = 'PUBLIC';
```
**Esperado:** zero linhas.

---

## Rollback

Caso a migration precise ser revertida (improvável dado o baixo risco):

```sql
ALTER FUNCTION public.buscar_revisoes_whatsapp() RESET search_path;
```

Verificação pós-rollback:
```sql
SELECT proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'buscar_revisoes_whatsapp';
-- Esperado: NULL (search_path removido)
```

---

## Referências

| Documento | Localização |
|-----------|------------|
| Arquivo da migration | `supabase/migrations/20260516001000_p0_m1_fix_buscar_revisoes_whatsapp_search_path.sql` |
| Dump remoto (função) | `supabase/remote/supabase_remote_schema.sql` ln 833–850 |
| Dump remoto (grants) | `supabase/remote/supabase_remote_schema.sql` ln 18594–18595 |
| Security Definer Audit | `supabase/baseline/SECURITY_DEFINER_AUDIT.md` |
| Risk Matrix (SEC-03) | `supabase_risk_matrix.md` |
| P0 Decision Packet | `supabase/baseline/P0_DECISION_PACKET.md` §P0-M1 |

---

## Checklist de aprovação

```
[ ] Dump relido nas linhas 833–850 (assinatura e corpo conferidos)
[ ] grep no codebase confirma que nenhum outro caller usa buscar_revisoes_whatsapp
    com search_path customizado que poderia ser afetado
[ ] Migration aplicada em ambiente de staging
[ ] Teste 1 passou em staging (proconfig contém search_path)
[ ] Teste 2 passou em staging (service_role com EXECUTE)
[ ] Teste 3 passou em staging (mesmo resultado lógico)
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
