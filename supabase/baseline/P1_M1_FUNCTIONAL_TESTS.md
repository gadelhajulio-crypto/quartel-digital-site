# P1-M1 Functional Tests — `rpc_complete_lesson` (T-07 → T-12)

**Sprint:** 2 / Fase 1B
**Referência:** `supabase/baseline/P1_M1_HANDOFF.md`
**Migration:** `20260517001000_p1_m1_create_rpc_complete_lesson.sql`
**Status:** FASE 1B — ATIVO — aguardando execução pelo operador
**Data:** 2026-05-17

> **Pré-requisito:** T-01 a T-06 — **APROVADOS em 2026-05-17**. Esta série pode ser executada.

---

## 1. Estratégia de Teste

### 1.1 Classificação por Ambiente e Risco

| Teste | Descrição curta | Seguro produção? | Precisa transação? | Precisa rollback? | Gera XP real? |
|-------|----------------|:-:|:-:|:-:|:-:|
| T-07 | Sem JWT → 42501 | SIM | Não | Não | Não |
| T-08 | Fluxo legítimo completo | CONDICIONAL* | Sim (recomendado) | Sim | **SIM** |
| T-09 | Idempotência (2ª chamada) | CONDICIONAL* | Sim (recomendado) | Sim | Não |
| T-10 | `xp_valor = 0` | CONDICIONAL* | Sim (recomendado) | Sim | Não |
| T-11 | Aula inexistente → 22023 | SIM | Não | Não | Não |
| T-12 | `source` rastreável (SELECT) | SIM** | Não | Não | Não |

> \* **CONDICIONAL:** seguro em produção apenas com conta de teste dedicada + rollback SQL preparado.
> Preferência: staging. Se não houver staging, usar conta de teste que não seja recruta real.
>
> \*\* T-12 é SELECT puro, mas depende de T-08 ter sido executado primeiro.

### 1.2 Ordem de Execução Obrigatória

```
T-07 → T-11 (independentes, sem estado)
         ↓
T-08 (gera estado: recruta_progresso + xp_eventos)
         ↓
T-09 (depende do estado de T-08)
         ↓
T-10 (independente, usa aula diferente com xp_valor=0)
         ↓
T-12 (SELECT pós T-08, independente de T-09/T-10)
         ↓
[ROLLBACK cirúrgico — ver Seção 10]
```

### 1.3 Categorias de Segurança

**Categoria A — Seguro em qualquer ambiente (zero DML):**
T-07, T-11

**Categoria B — Seguro em produção com conta de teste + rollback preparado:**
T-08, T-09, T-10, T-12

**Categoria C — Staging apenas (sem rollback necessário, dado descartável):**
T-08, T-09, T-10 quando a conta de teste não pode ser removida de produção.

---

## 2. Descoberta de Dados de Teste

> Todas as queries abaixo são **READ ONLY** (SELECT). Nenhum INSERT/UPDATE/DELETE.
> Executar no SQL Editor do Supabase como `service_role` para bypass de RLS.

### Q-D1 — Encontrar uma aula válida com `xp_valor > 0`

```sql
-- Retorna até 5 aulas com xp_valor positivo para uso em T-08/T-09
SELECT
    a.id          AS lesson_id,
    a.titulo,
    a.xp_valor,
    m.titulo      AS modulo_titulo,
    m.forca
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id
WHERE a.xp_valor > 0
ORDER BY a.xp_valor ASC   -- menor XP primeiro — minimiza impacto se não houver rollback
LIMIT 5;
-- Anotar: lesson_id e xp_valor para usar em T-08
-- Se retornar 0 linhas: ver Q-D5 (auditoria de xp_valor) antes de prosseguir
```

### Q-D2 — Encontrar uma aula válida com `xp_valor = 0`

```sql
-- Retorna até 5 aulas sem XP para uso em T-10
SELECT
    a.id      AS lesson_id,
    a.titulo,
    a.xp_valor,
    m.titulo  AS modulo_titulo
FROM public.aulas a
JOIN public.modulos m ON m.id = a.modulo_id
WHERE a.xp_valor = 0
ORDER BY a.created_at ASC
LIMIT 5;
-- Anotar: lesson_id para usar em T-10
-- Se retornar 0 linhas: T-10 não pode ser executado. Documentar como BLOQUEADO.
```

### Q-D3 — Encontrar recruta de teste seguro

```sql
-- Identificar conta de teste: onboarding concluído, forca canônica, pouco XP
-- forca canônica = 'marinha' | 'exercito' | 'aeronautica' (CHECK constraint em xp_eventos)
SELECT
    r.id          AS recruta_id,
    r.nome_guerra,
    r.forca,
    r.xp,
    r.xp_total,
    p.ativo
FROM public.recrutas r
JOIN public.profiles p ON p.id = r.id
WHERE r.forca IN ('marinha', 'exercito', 'aeronautica')   -- forca canônica obrigatória
  AND r.onboarding_concluido = true
ORDER BY r.xp ASC   -- menor XP = conta com menos dados reais = teste mais seguro
LIMIT 10;
-- IMPORTANTE: NÃO usar conta de recruta real ativo.
-- Criar conta de teste dedicada se necessário (ver Q-D3b).
```

### Q-D3b — Verificar se recruta de teste já tem progresso nas aulas-alvo

```sql
-- Substituir os UUIDs pelos valores anotados em Q-D1 e Q-D2
-- Substituir '<recruta_id_teste>' pelo recruta escolhido em Q-D3
SELECT
    rp.lesson_id,
    rp.status,
    rp.xp_granted,
    rp.source,
    rp.completed_at
FROM public.recruta_progresso rp
WHERE rp.recruta_id = '<recruta_id_teste>'
  AND rp.lesson_id IN (
      '<lesson_id_xp_positivo>',   -- da Q-D1
      '<lesson_id_xp_zero>'        -- da Q-D2
  );
-- Esperado: 0 linhas (recruta não concluiu essas aulas ainda)
-- Se retornar linhas: escolher outro recruta OU outra aula.
-- NÃO executar T-08 em aula já concluída pelo recruta de teste.
```

### Q-D4 — Verificar usuário sem onboarding (para T-07 variante)

```sql
-- Identifica recrutas sem forca definida (onboarding incompleto)
-- Útil para validar Guarda 2 manualmente se necessário
SELECT
    r.id          AS recruta_id,
    r.forca,
    r.onboarding_concluido
FROM public.recrutas r
WHERE r.forca IS NULL
   OR r.onboarding_concluido = false
LIMIT 3;
-- Uso: apenas referência — T-07 usa ausência de JWT, não recruta sem onboarding
```

### Q-D5 — UUID fake garantido inexistente

```sql
-- UUID canônico de "null device" — nunca será um registro real
-- Usar este valor fixo para T-11:
SELECT 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid AS fake_lesson_id;
-- Confirmar que não existe:
SELECT COUNT(*) FROM public.aulas WHERE id = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
-- Esperado: 0
```

### Q-D6 — Estado inicial do ledger (snapshot pré-teste)

```sql
-- Executar ANTES de T-08 para ter baseline de comparação
-- Substituir '<recruta_id_teste>'
SELECT
    (SELECT COUNT(*) FROM public.recruta_progresso
     WHERE recruta_id = '<recruta_id_teste>') AS total_progresso,
    (SELECT COALESCE(SUM(quantidade), 0) FROM public.xp_eventos
     WHERE recruta_id = '<recruta_id_teste>') AS xp_total_ledger,
    (SELECT xp FROM public.recrutas
     WHERE id = '<recruta_id_teste>') AS xp_recruta,
    now() AS snapshot_at;
-- Guardar este resultado para comparar após T-08 e após rollback.
```

---

## 3. Preparação de Ambiente

### Checklist pré-execução

- [ ] **T-01 a T-06 aprovados** — função existe com SECURITY DEFINER, grants corretos
- [ ] **Ambiente identificado:** `[ ] Staging` `[ ] Produção com conta de teste`
- [ ] **Se produção:** conta de teste criada e verificada em Q-D3 (sem recruta real)
- [ ] **Rollback SQL preparado** (Seção 10) — com UUIDs preenchidos ANTES de executar T-08
- [ ] **Snapshot pré-teste executado** (Q-D6) — resultado anotado
- [ ] **lesson_id com xp > 0 anotado** (Q-D1) — para T-08/T-09
- [ ] **lesson_id com xp = 0 anotado** (Q-D2) — para T-10 (ou marcado BLOQUEADO)
- [ ] **recruta_id de teste confirmado** (Q-D3 + Q-D3b) — zero progresso nas aulas-alvo
- [ ] **Operador ciente:** T-08 gera progresso real em `recruta_progresso` e XP em `xp_eventos`
- [ ] **Operador ciente:** rollback requer DELETE cirúrgico pós-teste (ver Seção 10)
- [ ] **JWT de usuário disponível** para T-07 a T-12 (SQL Editor → "Run as user" ou client SDK)

> **Nota sobre JWT no SQL Editor do Supabase:**
> O SQL Editor executa por padrão como `service_role` (sem JWT de usuário).
> Para T-08 a T-12, usar o recurso "Run as authenticated user" disponível no
> SQL Editor (ícone de usuário), ou usar o Supabase JS client com sessão autenticada.
> T-07 usa exatamente o modo padrão (service_role sem JWT) para verificar o bloqueio.

---

## 4. T-07 — Bloqueio Sem JWT

**Objetivo:** confirmar que `rpc_complete_lesson` bloqueia chamadas sem JWT com `ERRCODE 42501`.

**Por que é seguro:** a Guarda 1 dispara antes de qualquer DML. Zero efeito colateral.

**Ambiente:** qualquer (produção ou staging).

### Query

```sql
-- Executar no SQL Editor como service_role (modo padrão — SEM "Run as user")
-- Usa UUID fake: não chega ao ponto de verificar a aula (Guarda 1 dispara antes)
SELECT public.rpc_complete_lesson('ffffffff-ffff-ffff-ffff-ffffffffffff');
```

### Resultado Esperado

```
ERROR:  Authentication required: rpc_complete_lesson requires a valid JWT session
DETAIL:  ...
HINT:   ...
SQLSTATE: 42501
```

### Como Validar

```sql
-- Confirmar o SQLSTATE no painel de erro do SQL Editor.
-- Alternativa: envolver em bloco anônimo para capturar o código:
DO $$
BEGIN
    PERFORM public.rpc_complete_lesson('ffffffff-ffff-ffff-ffff-ffffffffffff');
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE NOTICE 'T-07 PASSOU: SQLSTATE 42501 capturado corretamente';
    WHEN OTHERS THEN
        RAISE NOTICE 'T-07 FALHOU: SQLSTATE % — %', SQLSTATE, SQLERRM;
END;
$$;
-- Esperado: NOTICE "T-07 PASSOU: SQLSTATE 42501 capturado corretamente"
```

### Critério de Aprovação

| Condição | Status |
|----------|--------|
| Retorna ERRO (não retorna JSON) | obrigatório |
| SQLSTATE = `42501` | obrigatório |
| Mensagem contém "Authentication required" | desejável |
| Nenhum registro inserido em qualquer tabela | obrigatório |

---

## 5. T-08 — Fluxo Legítimo

**Objetivo:** confirmar que um recruta autenticado com onboarding completo consegue concluir uma aula e receber XP correto.

**ATENÇÃO:** esta execução gera progresso real em `recruta_progresso` e XP real em `xp_eventos`. Preparar rollback (Seção 10) antes de executar.

**Ambiente:** staging (preferido) ou produção com conta de teste.

### Variáveis de Preenchimento

```
RECRUTA_ID_TESTE  = <recruta_id da Q-D3>
LESSON_ID_XP_POS  = <lesson_id da Q-D1, com xp_valor > 0>
XP_ESPERADO       = <xp_valor anotado da Q-D1>
```

### Query

```sql
-- Executar como usuário autenticado (Run as user: RECRUTA_ID_TESTE)
SELECT public.rpc_complete_lesson('<LESSON_ID_XP_POS>');
```

### Resultado Esperado

```json
{
  "status": "ok",
  "xp_granted": true,
  "xp_added": <XP_ESPERADO>
}
```

### Validação Pós-Execução

```sql
-- V-08a: progresso inserido corretamente
SELECT
    rp.recruta_id,
    rp.lesson_id,
    rp.status,
    rp.xp_granted,
    rp.source,
    rp.completed_at
FROM public.recruta_progresso rp
WHERE rp.recruta_id = '<RECRUTA_ID_TESTE>'
  AND rp.lesson_id  = '<LESSON_ID_XP_POS>';
-- Esperado: 1 linha
--   status       = 'completed'
--   xp_granted   = <XP_ESPERADO>
--   source       = 'rpc_complete_lesson'
--   completed_at IS NOT NULL

-- V-08b: XP registrado no ledger
SELECT
    xe.recruta_id,
    xe.forca,
    xe.quantidade,
    xe.origem,
    xe.referencia_id,
    xe.created_at
FROM public.xp_eventos xe
WHERE xe.recruta_id    = '<RECRUTA_ID_TESTE>'
  AND xe.referencia_id = '<LESSON_ID_XP_POS>'
  AND xe.origem        = 'lesson_complete';
-- Esperado: 1 linha
--   quantidade   = <XP_ESPERADO>  (igual a rp.xp_granted)
--   forca        = forca do recruta (marinha/exercito/aeronautica)
--   origem       = 'lesson_complete'

-- V-08c: forca registrada é válida pelo CHECK constraint
SELECT
    xe.forca,
    xe.forca IN ('marinha', 'exercito', 'aeronautica') AS forca_valida
FROM public.xp_eventos xe
WHERE xe.recruta_id    = '<RECRUTA_ID_TESTE>'
  AND xe.referencia_id = '<LESSON_ID_XP_POS>'
  AND xe.origem        = 'lesson_complete';
-- Esperado: forca_valida = true
```

### Critério de Aprovação

| Condição | Status |
|----------|--------|
| Retorno JSON com `status = "ok"` | obrigatório |
| `xp_granted = true` | obrigatório |
| `xp_added = xp_valor da aula` | obrigatório |
| 1 linha em `recruta_progresso` com `source = 'rpc_complete_lesson'` | obrigatório |
| 1 linha em `xp_eventos` com `origem = 'lesson_complete'` | obrigatório |
| `quantidade = xp_valor da aula` | obrigatório |
| `forca` in `('marinha','exercito','aeronautica')` | obrigatório |

---

## 6. T-09 — Idempotência

**Objetivo:** confirmar que chamar `rpc_complete_lesson` pela segunda vez não duplica progresso nem XP.

**Pré-requisito:** T-08 executado com sucesso para o mesmo par `(RECRUTA_ID_TESTE, LESSON_ID_XP_POS)`.

**Risco:** zero — idempotência implica zero DML na segunda chamada.

### Query

```sql
-- Executar como o mesmo usuário autenticado de T-08
-- Deve retornar imediatamente (early exit na verificação de idempotência)
SELECT public.rpc_complete_lesson('<LESSON_ID_XP_POS>');
```

### Resultado Esperado

```json
{
  "status": "ok",
  "xp_granted": false,
  "xp_added": 0,
  "message": "Aula já concluída anteriormente"
}
```

### Validação Pós-Execução

```sql
-- V-09a: COUNT em recruta_progresso deve ser exatamente 1 (não duplicou)
SELECT COUNT(*) AS contagem_progresso
FROM public.recruta_progresso
WHERE recruta_id = '<RECRUTA_ID_TESTE>'
  AND lesson_id  = '<LESSON_ID_XP_POS>';
-- Esperado: 1

-- V-09b: COUNT em xp_eventos deve ser exatamente 1 (não duplicou XP)
SELECT COUNT(*) AS contagem_xp_eventos
FROM public.xp_eventos
WHERE recruta_id    = '<RECRUTA_ID_TESTE>'
  AND referencia_id = '<LESSON_ID_XP_POS>'
  AND origem        = 'lesson_complete';
-- Esperado: 1

-- V-09c: SUM de XP não cresceu além do valor original
SELECT COALESCE(SUM(quantidade), 0) AS xp_total_desta_aula
FROM public.xp_eventos
WHERE recruta_id    = '<RECRUTA_ID_TESTE>'
  AND referencia_id = '<LESSON_ID_XP_POS>'
  AND origem        = 'lesson_complete';
-- Esperado: <XP_ESPERADO> (exatamente o mesmo de T-08, não dobrado)
```

### Critério de Aprovação

| Condição | Status |
|----------|--------|
| Retorno JSON com `xp_granted = false` | obrigatório |
| Campo `message` presente com texto de conclusão prévia | obrigatório |
| `COUNT(recruta_progresso) = 1` | obrigatório |
| `COUNT(xp_eventos) = 1` | obrigatório |
| `SUM(xp_eventos.quantidade) = XP_ESPERADO` (não dobrou) | obrigatório |

---

## 7. T-10 — `xp_valor = 0`

**Objetivo:** confirmar que aulas informacionais (sem XP) são registradas em `recruta_progresso`
mas NÃO geram entrada em `xp_eventos` (evitar violação do `CHECK (quantidade > 0)`).

**Pré-requisito:** `lesson_id` com `xp_valor = 0` identificado em Q-D2.

> Se Q-D2 retornar 0 linhas: **T-10 BLOQUEADO** — documentar e prosseguir para T-11.
> Não criar aulas falsas para testar. Informar ao DBA para inserir dado de teste controlado.

### Variáveis de Preenchimento

```
LESSON_ID_XP_ZERO = <lesson_id da Q-D2, com xp_valor = 0>
```

### Query

```sql
-- Executar como o mesmo usuário autenticado (RECRUTA_ID_TESTE)
SELECT public.rpc_complete_lesson('<LESSON_ID_XP_ZERO>');
```

### Resultado Esperado

```json
{
  "status": "ok",
  "xp_granted": false,
  "xp_added": 0
}
```

> **Importante:** a ausência do campo `message` distingue este resultado do "já concluída"
> de T-09. O retorno de T-10 é `xp_granted: false` SEM `message` — primeira conclusão
> de aula informacional.

### Validação Pós-Execução

```sql
-- V-10a: recruta_progresso foi inserido (aula concluída mesmo sem XP)
SELECT COUNT(*) AS contagem_progresso
FROM public.recruta_progresso
WHERE recruta_id = '<RECRUTA_ID_TESTE>'
  AND lesson_id  = '<LESSON_ID_XP_ZERO>'
  AND status     = 'completed';
-- Esperado: 1

-- V-10b: xp_eventos NÃO foi inserido (CHECK quantidade>0 seria violado)
SELECT COUNT(*) AS contagem_xp_eventos
FROM public.xp_eventos
WHERE recruta_id    = '<RECRUTA_ID_TESTE>'
  AND referencia_id = '<LESSON_ID_XP_ZERO>'
  AND origem        = 'lesson_complete';
-- Esperado: 0

-- V-10c: xp_granted em recruta_progresso = 0 (consistente com xp_valor da aula)
SELECT xp_granted
FROM public.recruta_progresso
WHERE recruta_id = '<RECRUTA_ID_TESTE>'
  AND lesson_id  = '<LESSON_ID_XP_ZERO>';
-- Esperado: 0
```

### Critério de Aprovação

| Condição | Status |
|----------|--------|
| Retorno JSON com `status = "ok"` | obrigatório |
| `xp_granted = false` e `xp_added = 0` | obrigatório |
| Sem campo `message` no retorno | obrigatório |
| `COUNT(recruta_progresso) = 1` (aula registrada) | obrigatório |
| `COUNT(xp_eventos) = 0` (sem XP inserido) | obrigatório |

---

## 8. T-11 — Aula Inexistente

**Objetivo:** confirmar que a Guarda 3 bloqueia `p_lesson_id` inválido com `ERRCODE 22023`.

**Por que é seguro:** a Guarda 3 dispara antes de qualquer DML. Zero efeito colateral.

**Ambiente:** qualquer (produção ou staging). Pode ser executado como usuário autenticado real.

### Query

```sql
-- Executar como usuário autenticado (qualquer recruta com onboarding concluído)
-- UUID inválido: nunca existirá como aula
SELECT public.rpc_complete_lesson('ffffffff-ffff-ffff-ffff-ffffffffffff');
```

### Resultado Esperado

```
ERROR:  Lesson not found: ffffffff-ffff-ffff-ffff-ffffffffffff. Verify the lesson UUID is correct.
SQLSTATE: 22023
```

### Validação com Captura de SQLSTATE

```sql
-- Executar como usuário autenticado
DO $$
BEGIN
    PERFORM public.rpc_complete_lesson('ffffffff-ffff-ffff-ffff-ffffffffffff');
EXCEPTION
    WHEN invalid_parameter_value THEN   -- SQLSTATE 22023
        RAISE NOTICE 'T-11 PASSOU: SQLSTATE 22023 capturado — %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'T-11 FALHOU: SQLSTATE % — %', SQLSTATE, SQLERRM;
END;
$$;
-- Esperado: NOTICE "T-11 PASSOU: SQLSTATE 22023 capturado — Lesson not found: ..."
```

### Critério de Aprovação

| Condição | Status |
|----------|--------|
| Retorna ERRO (não retorna JSON) | obrigatório |
| SQLSTATE = `22023` | obrigatório |
| Mensagem contém "Lesson not found" e o UUID | obrigatório |
| Nenhum registro inserido em qualquer tabela | obrigatório |

---

## 9. T-12 — `source` Rastreável

**Objetivo:** confirmar que o campo `source` em `recruta_progresso` é `'rpc_complete_lesson'`
(diferencia registros desta RPC de `complete_lesson` e do default `'lesson_completion'`).

**Pré-requisito:** T-08 executado com sucesso.

**Tipo:** SELECT puro — zero efeito colateral.

### Query de Auditoria

```sql
-- Auditoria completa de rastreabilidade pós T-08
SELECT
    rp.recruta_id,
    rp.lesson_id,
    rp.status,
    rp.xp_granted,
    rp.source,
    rp.completed_at,
    rp.created_at,
    -- confirmar que source não é o default antigo
    CASE rp.source
        WHEN 'rpc_complete_lesson' THEN 'NOVO — correto'
        WHEN 'lesson_complete'     THEN 'LEGADO — complete_lesson'
        WHEN 'lesson_completion'   THEN 'DEFAULT — insert direto'
        ELSE                            'DESCONHECIDO: ' || rp.source
    END AS source_audit
FROM public.recruta_progresso rp
WHERE rp.recruta_id = '<RECRUTA_ID_TESTE>'
  AND rp.lesson_id  = '<LESSON_ID_XP_POS>';
-- Esperado: 1 linha
--   source       = 'rpc_complete_lesson'
--   source_audit = 'NOVO — correto'

-- Auditoria cruzada: correlacionar com xp_eventos pelo referencia_id
SELECT
    rp.source         AS progresso_source,
    xe.origem         AS xp_origem,
    rp.xp_granted     AS progresso_xp,
    xe.quantidade     AS xp_real_ledger,
    rp.xp_granted = xe.quantidade AS xp_consistente
FROM public.recruta_progresso rp
JOIN public.xp_eventos xe
  ON xe.recruta_id    = rp.recruta_id
 AND xe.referencia_id = rp.lesson_id
 AND xe.origem        = 'lesson_complete'
WHERE rp.recruta_id = '<RECRUTA_ID_TESTE>'
  AND rp.lesson_id  = '<LESSON_ID_XP_POS>';
-- Esperado: 1 linha
--   progresso_source  = 'rpc_complete_lesson'
--   xp_origem         = 'lesson_complete'
--   xp_consistente    = true  (xp_granted = quantidade)
```

### Critério de Aprovação

| Condição | Status |
|----------|--------|
| `source = 'rpc_complete_lesson'` (não `'lesson_completion'` nem `'lesson_complete'`) | obrigatório |
| `rp.xp_granted = xe.quantidade` (consistência ledger) | obrigatório |
| `xe.origem = 'lesson_complete'` (índice de idempotência correto) | obrigatório |

---

## 10. Rollback Operacional

> **Executar APENAS após aprovação ou reprovação dos testes.**
> Rollback é cirúrgico — usa `recruta_id` + `lesson_id` específicos.
> **NUNCA usar DELETE sem cláusula WHERE precisa.**

### Preencher ANTES de executar T-08

```
RECRUTA_ID_TESTE  = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
LESSON_ID_XP_POS  = yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
LESSON_ID_XP_ZERO = zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz  (ou SKIP se T-10 bloqueado)
```

### R-01 — Remover progresso de T-08 e T-09

```sql
-- Remove apenas o registro do recruta de teste para a aula-alvo de T-08
DELETE FROM public.recruta_progresso
WHERE recruta_id = '<RECRUTA_ID_TESTE>'
  AND lesson_id  = '<LESSON_ID_XP_POS>'
  AND source     = 'rpc_complete_lesson';   -- filtro extra: só remove registros desta RPC
-- Verificação:
SELECT COUNT(*) FROM public.recruta_progresso
WHERE recruta_id = '<RECRUTA_ID_TESTE>'
  AND lesson_id  = '<LESSON_ID_XP_POS>';
-- Esperado: 0
```

### R-02 — Remover XP de T-08 do ledger

```sql
-- Remove apenas o evento XP gerado por esta aula para este recruta
DELETE FROM public.xp_eventos
WHERE recruta_id    = '<RECRUTA_ID_TESTE>'
  AND referencia_id = '<LESSON_ID_XP_POS>'
  AND origem        = 'lesson_complete';
-- Verificação:
SELECT COUNT(*) FROM public.xp_eventos
WHERE recruta_id    = '<RECRUTA_ID_TESTE>'
  AND referencia_id = '<LESSON_ID_XP_POS>'
  AND origem        = 'lesson_complete';
-- Esperado: 0
```

### R-03 — Remover progresso de T-10 (se executado)

```sql
-- Executar apenas se T-10 foi executado
DELETE FROM public.recruta_progresso
WHERE recruta_id = '<RECRUTA_ID_TESTE>'
  AND lesson_id  = '<LESSON_ID_XP_ZERO>'
  AND source     = 'rpc_complete_lesson';
-- Verificação:
SELECT COUNT(*) FROM public.recruta_progresso
WHERE recruta_id = '<RECRUTA_ID_TESTE>'
  AND lesson_id  = '<LESSON_ID_XP_ZERO>';
-- Esperado: 0
-- Nota: não há R-04 para xp_eventos de T-10 pois nenhum foi inserido (xp_valor=0)
```

### R-04 — Confirmar estado limpo pós-rollback (comparar com snapshot Q-D6)

```sql
-- Comparar com valores anotados em Q-D6
SELECT
    (SELECT COUNT(*) FROM public.recruta_progresso
     WHERE recruta_id = '<RECRUTA_ID_TESTE>') AS total_progresso,
    (SELECT COALESCE(SUM(quantidade), 0) FROM public.xp_eventos
     WHERE recruta_id = '<RECRUTA_ID_TESTE>') AS xp_total_ledger,
    (SELECT xp FROM public.recrutas
     WHERE id = '<RECRUTA_ID_TESTE>') AS xp_recruta,
    now() AS snapshot_at;
-- Esperado: valores idênticos ao snapshot Q-D6 (estado pré-teste restaurado)
```

> **Nota sobre `recrutas.xp`:** a coluna `recrutas.xp` pode ser atualizada por trigger
> (dependendo da configuração). Verificar se `recrutas.xp` retornou ao valor de Q-D6.
> Se não: o trigger de sync pode ter atualizado `recrutas.xp` na inserção em `xp_eventos`.
> Neste caso, fazer manualmente:
> ```sql
> UPDATE public.recrutas
> SET xp = <valor_xp_de_Q_D6>
> WHERE id = '<RECRUTA_ID_TESTE>';
> ```
> Documentar se isso foi necessário — indica comportamento de trigger a monitorar em Fase 2.

---

## 11. Critério de Aprovação Final

### APROVADO

Todos os critérios obrigatórios de T-07 a T-12 satisfeitos:

- T-07: `42501` sem JWT ✓
- T-08: retorno correto + `recruta_progresso` + `xp_eventos` corretos ✓
- T-09: idempotência confirmada (COUNT=1 em ambas as tabelas) ✓
- T-10: `xp_valor=0` → `recruta_progresso` inserido, `xp_eventos` ausente ✓ (ou BLOQUEADO documentado)
- T-11: `22023` para UUID inválido ✓
- T-12: `source = 'rpc_complete_lesson'` + consistência de XP ✓

**Consequência:** Fase 2 pode ser iniciada (migração do frontend em `progressService.ts`).

### APROVADO COM RESSALVAS

Um ou mais critérios desejáveis não satisfeitos, mas todos os obrigatórios sim. Exemplos:

- T-10 BLOQUEADO por ausência de aula com `xp_valor = 0` → documentar, criar dado de teste, reexecutar
- Mensagem de erro de T-07/T-11 diferente do esperado mas SQLSTATE correto → aceitar, documentar
- `recrutas.xp` não reverteu pelo rollback (trigger) → documentar comportamento, prosseguir

**Consequência:** Fase 2 pode ser iniciada com monitoramento adicional. Abrir issue para ressalvas.

### REPROVADO

Qualquer critério obrigatório não satisfeito. Exemplos:

- T-07 retorna JSON em vez de erro → Guarda 1 não funciona, **BLOQUEANTE**
- T-08 retorna `xp_added` diferente de `xp_valor` da aula → XP não server-authoritative, **BLOQUEANTE**
- T-09 mostra `COUNT(xp_eventos) = 2` → idempotência quebrada, **BLOQUEANTE**
- T-10 gera entrada em `xp_eventos` com `quantidade = 0` → violação de constraint em produção real, **BLOQUEANTE**
- T-12 mostra `source = 'lesson_completion'` → rastreabilidade incorreta

**Consequência:** Fase 2 BLOQUEADA. Investigar, corrigir a função via `CREATE OR REPLACE`, reexecutar testes.

---

## 12. Próximo Passo Após Aprovação

### Fase 2 — Migrar `progressService.ts`

**Arquivo:** `src/services/progressService.ts`

Alteração de uma linha:

```typescript
// REMOVER:
const { data, error } = await supabase.rpc('complete_lesson', {
    p_recruta_id: userId,
    p_lesson_id: lessonId
});

// ADICIONAR:
const { data, error } = await supabase.rpc('rpc_complete_lesson', {
    p_lesson_id: lessonId   // recruta_id derivado internamente via auth.uid()
});
```

**Checklist Fase 2:**
- [ ] Verificar consumidor do `data` em `app/(stack)/lesson/[id].tsx` — novo formato: `{status, xp_granted, xp_added}`
- [ ] Verificar se `userId` ainda é necessário em outro lugar do fluxo ou pode ser removido do call
- [ ] Build de staging com nova chamada antes de deploy em produção
- [ ] Rollback imediato disponível: reverter a linha para `complete_lesson`

### Observabilidade Pós-Fase 2

Monitorar por 48h após a migração do frontend:

```sql
-- Taxa de adoção: proportion de conclusões via nova RPC vs legada
SELECT
    source,
    COUNT(*)                                          AS total,
    MIN(completed_at)                                 AS primeiro_em,
    MAX(completed_at)                                 AS ultimo_em
FROM public.recruta_progresso
WHERE completed_at >= now() - interval '48 hours'
GROUP BY source
ORDER BY total DESC;
-- Esperado após Fase 2: 'rpc_complete_lesson' como source dominante

-- Verificar anomalias de XP (xp_granted != quantidade no ledger)
SELECT
    rp.lesson_id,
    rp.xp_granted AS xp_progresso,
    xe.quantidade  AS xp_ledger,
    rp.completed_at
FROM public.recruta_progresso rp
JOIN public.xp_eventos xe
  ON xe.recruta_id    = rp.recruta_id
 AND xe.referencia_id = rp.lesson_id
 AND xe.origem        = 'lesson_complete'
WHERE rp.source      = 'rpc_complete_lesson'
  AND rp.xp_granted != xe.quantidade   -- divergência
  AND rp.completed_at >= now() - interval '48 hours';
-- Esperado: 0 linhas
```

### Deprecação de `complete_lesson` (Sprint 3)

Após migração total confirmada via observabilidade:

```sql
-- Marcar como legacy no registry (Sprint 3)
UPDATE public.c6_contract_registry
SET    status     = 'legacy',
       notes      = notes || ' | Deprecated Sprint 3: all traffic migrated to rpc_complete_lesson.',
       updated_at = now()
WHERE  contract_name = 'complete_lesson';
```

DROP de `complete_lesson` apenas após auditoria confirmando zero chamadas em logs e automações.

---

## Sumário Executivo

| Métrica | Valor |
|---------|-------|
| Total de testes (T-07 a T-12) | **6** |
| Seguros para produção sem restrição | **3** (T-07, T-11, T-12*) |
| Requerem conta de teste / staging | **3** (T-08, T-09, T-10) |
| Geram XP real (requerem rollback) | **1** (T-08) |
| Geram progresso sem XP (requerem rollback) | **1** (T-10, se aula xp=0 disponível) |
| Exigem rollback obrigatório | **2** (T-08, T-10) |
| Rollout frontend pode iniciar após aprovação? | **SIM** — Fase 2 desbloqueada |
| Risco residual após Fase 2 | **BAIXO** — `complete_lesson` permanece como fallback durante Sprint 2 |

> \* T-12 é SELECT puro mas depende de T-08 ter sido executado.

**Risco residual principal:** se `recrutas.xp` for atualizado por trigger no INSERT em `xp_eventos`,
o rollback de T-08 precisará de `UPDATE recrutas SET xp = ...` manual.
Monitorar comportamento do trigger durante os testes e documentar antes de Fase 2.
