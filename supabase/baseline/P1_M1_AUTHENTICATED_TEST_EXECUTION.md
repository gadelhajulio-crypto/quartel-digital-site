# P1-M1 Authenticated Test Execution — `rpc_complete_lesson` (T-08 → T-12)

**Sprint:** 2 / Fase 1B
**Status:** AGUARDANDO EXECUCAO PELO OPERADOR
**Data:** 2026-05-17
**Referencia:** `supabase/baseline/P1_M1_FUNCTIONAL_TESTS.md`

> **Pre-requisitos confirmados:**
> - T-01 a T-06: APROVADOS em 2026-05-17
> - T-07: APROVADO — retornou ERROR 42501 conforme esperado (modo service_role sem JWT)
> - Snapshot pre-teste coletado: `total_progresso = 0`, `xp_total_ledger = 0`, `xp_profile = 0`

---

## DADOS DE TESTE PREENCHIDOS

```
RECRUTA_ID_TESTE  = 0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673   (GADELHA)
LESSON_ID_XP_POS  = aff99e81-afd5-46c0-bcc6-c9dda47af687   (xp_valor = 50)
XP_ESPERADO       = 50
LESSON_ID_XP_ZERO = 22222222-2222-2222-2222-222222222222   (xp_valor = 0)
LESSON_ID_FAKE    = ffffffff-ffff-ffff-ffff-ffffffffffff   (nao existe)
```

---

## 1. Diagnostico do Erro Atual (T-08 sem JWT)

### Por que T-08 falhou com 42501

Quando T-08 foi executado no SQL Editor do Supabase no modo padrao (sem "Run as authenticated user"),
a sessao roda como `service_role` sem nenhum JWT de usuario associado. Nesse contexto:

- `auth.uid()` retorna `NULL`
- A **Guarda 1** da funcao dispara imediatamente:
  ```sql
  IF auth.uid() IS NULL THEN
      RAISE EXCEPTION
          'Authentication required: rpc_complete_lesson requires a valid JWT session'
          USING ERRCODE = '42501';
  END IF;
  ```
- Nenhum DML e executado — zero efeito colateral
- O erro `42501` (insufficient_privilege) e retornado antes de qualquer leitura de tabela

### Confirmacoes

| Afirmacao | Status |
|-----------|--------|
| T-07/T-08 sem JWT retornando 42501 e o comportamento CORRETO | CONFIRMADO |
| A Guarda 1 funciona como defesa de perimetro | CONFIRMADO |
| Zero registros foram inseridos na tentativa sem JWT | CONFIRMADO |
| A falha reforça que a funcao e server-authoritative | CONFIRMADO |

> **Conclusao:** T-07 (bloqueio sem JWT) esta **APROVADO**. O erro 42501 observado em T-08
> (antes do JWT) nao e falha — e confirmacao de que a Guarda 1 opera corretamente.
> T-08 precisa ser reexecutado **com JWT de GADELHA** para validar o fluxo legitimo.

---

## 2. Modos Possiveis de Executar com JWT

### Opcao A — Supabase SQL Editor com "Run as authenticated user" (RECOMENDADO)

Este e o modo mais direto. O SQL Editor do Supabase Dashboard possui um seletor de usuario
que injeta o JWT do usuario escolhido antes de executar a query.

**Passo a passo:**

1. Acessar o **Supabase Dashboard** do projeto
2. Navegar para **SQL Editor** (menu lateral esquerdo)
3. Criar um novo snippet (botao `+ New query`)
4. Localizar o seletor de usuario — aparece como icone de pessoa / dropdown acima do editor,
   rotulado `"Run as"` ou `"Impersonate user"`
5. No campo de busca do seletor, digitar:
   - Email do usuario GADELHA, OU
   - UUID: `0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673`
6. Selecionar o usuario GADELHA na lista
7. Confirmar que o seletor exibe o nome/email de GADELHA (nao `service_role`)
8. Colar e executar o SQL de cada teste (ver Secao 3)
9. **Manter o mesmo usuario selecionado para T-08, T-09, T-10, T-11 e T-12**

> **Atencao:** o seletor deve permanecer em GADELHA durante toda a sequencia T-08 → T-12.
> Trocar para `service_role` entre testes invalidara os resultados de idempotencia (T-09).

**Verificar que o JWT esta ativo:**

```sql
-- Executar com usuario GADELHA selecionado — deve retornar o UUID de GADELHA
SELECT auth.uid();
-- Esperado: 0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673
-- Se retornar NULL: JWT nao esta sendo injetado — verificar seletor de usuario
```

---

### Opcao B — Testar pelo app logado como GADELHA

Este modo usa o app mobile em execucao real. Requer que `progressService.ts` ainda chame
`complete_lesson` (status atual), entao servira apenas para validacao indireta. Para validar
`rpc_complete_lesson` diretamente, use a Opcao A ou C.

**Uso adequado da Opcao B (validacao indireta de ambiente):**

1. Fazer login no app como GADELHA (email/senha da conta de teste)
2. Navegar ate uma aula que usa a licao `aff99e81-afd5-46c0-bcc6-c9dda47af687`
3. Concluir a aula normalmente pelo app
4. Validar no banco com as queries da Secao 3 (substituindo a funcao para `complete_lesson`)

**Como validar no banco apos execucao pelo app:**

```sql
-- Verificar se progresso foi inserido (funciona para complete_lesson ou rpc_complete_lesson)
SELECT
    rp.lesson_id,
    rp.status,
    rp.xp_granted,
    rp.source,
    rp.completed_at
FROM public.recruta_progresso rp
WHERE rp.recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND rp.lesson_id  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';
```

> **Nota:** A Opcao B nao valida `rpc_complete_lesson` diretamente enquanto o frontend ainda
> usa `complete_lesson`. Usar Opcao A ou C para validacao da nova RPC.

---

### Opcao C — Script Node.js com Supabase JS (login real do usuario de teste)

Use esta opcao se o SQL Editor nao oferecer o seletor "Run as user" na versao atual do projeto.

**Pre-requisito:** criar o arquivo `.env.test.local` na raiz do projeto (NUNCA commitar este arquivo).

**Arquivo `.env.test.local` (preencher localmente — nao commitar):**

```env
# .env.test.local — NUNCA commitar. Adicionar ao .gitignore se ausente.
SUPABASE_URL=https://<seu-projeto>.supabase.co
SUPABASE_ANON_KEY=<sua-anon-key-publica>
TEST_USER_EMAIL=<email-de-GADELHA>
TEST_USER_PASSWORD=<senha-de-GADELHA>
```

**Script `scripts/test_rpc_complete_lesson.mjs`:**

```javascript
// scripts/test_rpc_complete_lesson.mjs
// Executar: node scripts/test_rpc_complete_lesson.mjs
// Pre-requisito: .env.test.local preenchido com credenciais de GADELHA
// NUNCA expor email/senha no codigo — usar apenas variaveis de ambiente

import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'fs';

// Carregar variaveis de .env.test.local manualmente (sem dependencia de dotenv)
const envRaw = readFileSync('.env.test.local', 'utf8');
const env = Object.fromEntries(
    envRaw.split('\n')
        .filter(l => l.includes('=') && !l.startsWith('#'))
        .map(l => l.split('=').map(s => s.trim()))
);

const SUPABASE_URL      = env['SUPABASE_URL'];
const SUPABASE_ANON_KEY = env['SUPABASE_ANON_KEY'];
const EMAIL             = env['TEST_USER_EMAIL'];
const PASSWORD          = env['TEST_USER_PASSWORD'];

// UUIDs de teste (preenchidos — nao alterar)
const LESSON_ID_XP_POS  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';
const LESSON_ID_XP_ZERO = '22222222-2222-2222-2222-222222222222';
const LESSON_ID_FAKE    = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
const RECRUTA_ID_TESTE  = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673';
const XP_ESPERADO       = 50;

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function main() {
    console.log('=== rpc_complete_lesson — Teste Autenticado ===\n');

    // --- Login ---
    console.log('[AUTH] Fazendo login como GADELHA...');
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
        email: EMAIL,
        password: PASSWORD,
    });
    if (authError) {
        console.error('[AUTH] FALHOU:', authError.message);
        process.exit(1);
    }
    const uid = authData.user?.id;
    console.log('[AUTH] Login OK. uid =', uid);
    if (uid !== RECRUTA_ID_TESTE) {
        console.warn('[AUTH] AVISO: uid nao corresponde a RECRUTA_ID_TESTE esperado!');
        console.warn('  uid obtido:   ', uid);
        console.warn('  uid esperado: ', RECRUTA_ID_TESTE);
    }

    // --- T-08: Fluxo legitimo ---
    console.log('\n[T-08] Chamando rpc_complete_lesson com LESSON_ID_XP_POS...');
    const { data: t08, error: e08 } = await supabase.rpc('rpc_complete_lesson', {
        p_lesson_id: LESSON_ID_XP_POS,
    });
    if (e08) {
        console.error('[T-08] ERRO:', e08.message, '| code:', e08.code);
    } else {
        console.log('[T-08] Retorno:', JSON.stringify(t08));
        const ok08 =
            t08?.status === 'ok' &&
            t08?.xp_granted === true &&
            t08?.xp_added  === XP_ESPERADO;
        console.log('[T-08] STATUS:', ok08 ? 'PASSOU' : 'FALHOU (verificar retorno)');
    }

    // --- T-09: Idempotencia (segunda chamada) ---
    console.log('\n[T-09] Segunda chamada (idempotencia)...');
    const { data: t09, error: e09 } = await supabase.rpc('rpc_complete_lesson', {
        p_lesson_id: LESSON_ID_XP_POS,
    });
    if (e09) {
        console.error('[T-09] ERRO:', e09.message);
    } else {
        console.log('[T-09] Retorno:', JSON.stringify(t09));
        const ok09 =
            t09?.status     === 'ok'   &&
            t09?.xp_granted === false  &&
            t09?.xp_added   === 0      &&
            typeof t09?.message === 'string';
        console.log('[T-09] STATUS:', ok09 ? 'PASSOU' : 'FALHOU (verificar retorno)');
    }

    // --- T-10: xp_valor = 0 ---
    console.log('\n[T-10] Chamando rpc_complete_lesson com LESSON_ID_XP_ZERO...');
    const { data: t10, error: e10 } = await supabase.rpc('rpc_complete_lesson', {
        p_lesson_id: LESSON_ID_XP_ZERO,
    });
    if (e10) {
        // Se a aula nao existe no banco, erro 22023 sera retornado
        console.warn('[T-10] ERRO (pode ser BLOQUEADO se aula nao existir):', e10.message, '| code:', e10.code);
    } else {
        console.log('[T-10] Retorno:', JSON.stringify(t10));
        const ok10 =
            t10?.status     === 'ok'  &&
            t10?.xp_granted === false &&
            t10?.xp_added   === 0     &&
            !t10?.message; // sem campo message (diferente de idempotencia)
        console.log('[T-10] STATUS:', ok10 ? 'PASSOU' : 'FALHOU ou BLOQUEADO (verificar retorno)');
    }

    // --- T-11: Aula inexistente ---
    console.log('\n[T-11] Chamando rpc_complete_lesson com UUID fake...');
    const { data: t11, error: e11 } = await supabase.rpc('rpc_complete_lesson', {
        p_lesson_id: LESSON_ID_FAKE,
    });
    if (e11) {
        const ok11 = e11.code === 'PGRST202' || e11.code === '22023' ||
                     (e11.message && e11.message.includes('Lesson not found'));
        console.log('[T-11] Erro recebido:', e11.message, '| code:', e11.code);
        console.log('[T-11] STATUS:', ok11 ? 'PASSOU (erro esperado)' : 'FALHOU (erro diferente do esperado)');
    } else {
        console.error('[T-11] FALHOU: retornou JSON em vez de erro:', JSON.stringify(t11));
    }

    // --- T-12 deve ser validado via SQL Editor pos-execucao (ver Secao 3) ---
    console.log('\n[T-12] Validar source via SQL Editor (ver Secao 3 — T-12)');
    console.log('  Query T-12 deve ser executada no SQL Editor com service_role.');

    console.log('\n=== Execucao concluida. Executar queries de validacao da Secao 3. ===');

    await supabase.auth.signOut();
}

main().catch(console.error);
```

> **Como executar:**
> ```bash
> node scripts/test_rpc_complete_lesson.mjs
> ```
> Requer Node.js >= 18 e `@supabase/supabase-js` instalado no projeto.

---

## 3. Queries Prontas para Execucao

> Todas as queries abaixo usam os UUIDs ja preenchidos.
> Para T-08 a T-11: executar com usuario **GADELHA** selecionado no SQL Editor.
> Para validacoes pos-execucao: podem ser executadas como `service_role`.

---

### T-08 — Fluxo Legitimo

**Executar como GADELHA (Run as user):**

```sql
-- T-08: primeira conclusao da aula com XP
-- Executar com usuario GADELHA selecionado no SQL Editor
SELECT public.rpc_complete_lesson('aff99e81-afd5-46c0-bcc6-c9dda47af687');
-- Esperado:
-- {"status":"ok","xp_granted":true,"xp_added":50}
```

**Validacao T-08 — recruta_progresso:**

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
WHERE rp.recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND rp.lesson_id  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';
-- Esperado: 1 linha
--   status       = 'completed'
--   xp_granted   = 50
--   source       = 'rpc_complete_lesson'
--   completed_at IS NOT NULL
```

**Validacao T-08 — xp_eventos:**

```sql
-- V-08b: XP registrado no ledger
SELECT
    xe.recruta_id,
    xe.forca,
    xe.quantidade,
    xe.origem,
    xe.referencia_id,
    xe.created_at
FROM public.xp_eventos xe
WHERE xe.recruta_id    = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND xe.referencia_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
  AND xe.origem        = 'lesson_complete';
-- Esperado: 1 linha
--   quantidade = 50
--   origem     = 'lesson_complete'
--   forca      IN ('marinha','exercito','aeronautica')
```

**Validacao T-08 — forca valida:**

```sql
-- V-08c: forca registrada satisfaz CHECK constraint
SELECT
    xe.forca,
    xe.forca IN ('marinha', 'exercito', 'aeronautica') AS forca_valida
FROM public.xp_eventos xe
WHERE xe.recruta_id    = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND xe.referencia_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
  AND xe.origem        = 'lesson_complete';
-- Esperado: forca_valida = true
```

---

### T-09 — Idempotencia (segunda chamada)

**Executar como GADELHA — apos T-08 aprovado:**

```sql
-- T-09: segunda chamada identica a T-08 (deve ser no-op)
-- Executar com mesmo usuario GADELHA selecionado
SELECT public.rpc_complete_lesson('aff99e81-afd5-46c0-bcc6-c9dda47af687');
-- Esperado:
-- {"status":"ok","xp_granted":false,"xp_added":0,"message":"Aula ja concluida anteriormente"}
```

**Validacao T-09 — contagem deve ser 1 em ambas as tabelas:**

```sql
-- V-09a: COUNT recruta_progresso = 1 (nao duplicou)
SELECT COUNT(*) AS contagem_progresso
FROM public.recruta_progresso
WHERE recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND lesson_id  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';
-- Esperado: 1

-- V-09b: COUNT xp_eventos = 1 (nao duplicou XP)
SELECT COUNT(*) AS contagem_xp_eventos
FROM public.xp_eventos
WHERE recruta_id    = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND referencia_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
  AND origem        = 'lesson_complete';
-- Esperado: 1

-- V-09c: SUM XP = 50 (nao dobrou)
SELECT COALESCE(SUM(quantidade), 0) AS xp_total_desta_aula
FROM public.xp_eventos
WHERE recruta_id    = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND referencia_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
  AND origem        = 'lesson_complete';
-- Esperado: 50 (nao 100)
```

---

### T-10 — xp_valor = 0

> **ATENCAO:** O UUID `22222222-2222-2222-2222-222222222222` e um valor de teste.
> Antes de executar, confirmar que esta aula existe no banco com a query abaixo.
> Se nao existir, T-10 esta **BLOQUEADO** — documentar e prosseguir para T-11.

**Pre-verificacao T-10 (executar como service_role antes):**

```sql
-- Verificar se a aula xp_zero existe
SELECT id, titulo, xp_valor
FROM public.aulas
WHERE id = '22222222-2222-2222-2222-222222222222';
-- Se retornar 0 linhas: T-10 BLOQUEADO — usar Q-D2 para encontrar aula alternativa com xp_valor = 0
```

**Executar como GADELHA (se aula existir):**

```sql
-- T-10: aula informacional sem XP
-- Executar com usuario GADELHA selecionado
SELECT public.rpc_complete_lesson('22222222-2222-2222-2222-222222222222');
-- Esperado:
-- {"status":"ok","xp_granted":false,"xp_added":0}
-- NOTA: ausencia de campo "message" distingue de idempotencia (T-09)
```

**Validacao T-10:**

```sql
-- V-10a: recruta_progresso inserido (aula registrada mesmo sem XP)
SELECT COUNT(*) AS contagem_progresso
FROM public.recruta_progresso
WHERE recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND lesson_id  = '22222222-2222-2222-2222-222222222222'
  AND status     = 'completed';
-- Esperado: 1

-- V-10b: xp_eventos NAO inserido (CHECK quantidade>0 seria violado)
SELECT COUNT(*) AS contagem_xp_eventos
FROM public.xp_eventos
WHERE recruta_id    = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND referencia_id = '22222222-2222-2222-2222-222222222222'
  AND origem        = 'lesson_complete';
-- Esperado: 0

-- V-10c: xp_granted = 0 em recruta_progresso
SELECT xp_granted
FROM public.recruta_progresso
WHERE recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND lesson_id  = '22222222-2222-2222-2222-222222222222';
-- Esperado: 0
```

---

### T-11 — Aula Inexistente (erro 22023)

**Executar como GADELHA:**

```sql
-- T-11: UUID fake — Guarda 3 deve bloquear com 22023
-- Seguro: dispara antes de qualquer DML
SELECT public.rpc_complete_lesson('ffffffff-ffff-ffff-ffff-ffffffffffff');
-- Esperado: ERROR 22023 — "Lesson not found: ffffffff-ffff-ffff-ffff-ffffffffffff..."
```

**Alternativa com captura de SQLSTATE (executar como GADELHA):**

```sql
-- Captura explicita do SQLSTATE para registro no protocolo
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

---

### T-12 — Source Rastreavel (SELECT puro — service_role)

> T-12 e SELECT puro. Executar como `service_role` apos T-08 aprovado.

```sql
-- T-12a: auditoria de source em recruta_progresso
SELECT
    rp.recruta_id,
    rp.lesson_id,
    rp.status,
    rp.xp_granted,
    rp.source,
    rp.completed_at,
    CASE rp.source
        WHEN 'rpc_complete_lesson' THEN 'NOVO — correto'
        WHEN 'lesson_complete'     THEN 'LEGADO — complete_lesson'
        WHEN 'lesson_completion'   THEN 'DEFAULT — insert direto'
        ELSE                            'DESCONHECIDO: ' || rp.source
    END AS source_audit
FROM public.recruta_progresso rp
WHERE rp.recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND rp.lesson_id  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';
-- Esperado: source = 'rpc_complete_lesson', source_audit = 'NOVO — correto'

-- T-12b: consistencia cruzada recruta_progresso x xp_eventos
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
WHERE rp.recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND rp.lesson_id  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';
-- Esperado:
--   progresso_source = 'rpc_complete_lesson'
--   xp_origem        = 'lesson_complete'
--   xp_consistente   = true
--   progresso_xp     = 50
--   xp_real_ledger   = 50
```

---

## 4. Rollback Manual Cirurgico

> **Executar APENAS apos aprovacao ou reprovacao dos testes.**
> NUNCA usar DELETE sem clausula WHERE precisa.
> Confirmar cada passo com o SELECT de verificacao antes de prosseguir.

**UUIDs preenchidos:**

```
RECRUTA_ID_TESTE  = 0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673
LESSON_ID_XP_POS  = aff99e81-afd5-46c0-bcc6-c9dda47af687   (aula T-08)
LESSON_ID_XP_ZERO = 22222222-2222-2222-2222-222222222222   (aula T-10 — SKIP se T-10 bloqueado)
```

---

**R-01 — Remover progresso de T-08 (recruta_progresso, aula XP > 0):**

```sql
-- Remove APENAS o registro desta RPC para este recruta nesta aula
DELETE FROM public.recruta_progresso
WHERE recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND lesson_id  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
  AND source     = 'rpc_complete_lesson';   -- filtro extra: nao toca registros de complete_lesson

-- Verificacao R-01:
SELECT COUNT(*) AS deve_ser_zero
FROM public.recruta_progresso
WHERE recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND lesson_id  = 'aff99e81-afd5-46c0-bcc6-c9dda47af687';
-- Esperado: 0
```

**R-02 — Remover XP de T-08 do ledger (xp_eventos, aula XP > 0):**

```sql
-- Remove APENAS o evento XP desta aula para este recruta
DELETE FROM public.xp_eventos
WHERE recruta_id    = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND referencia_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
  AND origem        = 'lesson_complete';

-- Verificacao R-02:
SELECT COUNT(*) AS deve_ser_zero
FROM public.xp_eventos
WHERE recruta_id    = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND referencia_id = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'
  AND origem        = 'lesson_complete';
-- Esperado: 0
```

**R-03 — Remover progresso de T-10 (EXECUTAR APENAS SE T-10 FOI EXECUTADO):**

```sql
-- Executar apenas se T-10 foi executado com sucesso
DELETE FROM public.recruta_progresso
WHERE recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND lesson_id  = '22222222-2222-2222-2222-222222222222'
  AND source     = 'rpc_complete_lesson';

-- Verificacao R-03:
SELECT COUNT(*) AS deve_ser_zero
FROM public.recruta_progresso
WHERE recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673'
  AND lesson_id  = '22222222-2222-2222-2222-222222222222';
-- Esperado: 0
-- Nota: nao ha R-04 para xp_eventos de T-10 — nenhum foi inserido (xp_valor=0)
```

**R-04 — Confirmar estado limpo (comparar com snapshot Q-D6):**

```sql
-- Comparar com snapshot pre-teste: total_progresso=0, xp_total_ledger=0, xp_profile=0
SELECT
    (SELECT COUNT(*) FROM public.recruta_progresso
     WHERE recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673') AS total_progresso,
    (SELECT COALESCE(SUM(quantidade), 0) FROM public.xp_eventos
     WHERE recruta_id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673') AS xp_total_ledger,
    (SELECT xp FROM public.recrutas
     WHERE id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673')          AS xp_recruta,
    now() AS snapshot_at;
-- Esperado: total_progresso = 0, xp_total_ledger = 0, xp_recruta = 0
-- (identico ao snapshot Q-D6 coletado antes dos testes)
```

> **ALERTA — trigger de sync em `recrutas.xp`:**
> Se `recrutas.xp` nao retornar ao valor do snapshot apos R-02, o trigger de sync
> (`20260503001000`) pode ter atualizado a coluna na insercao em `xp_eventos`.
> Neste caso, corrigir manualmente:
> ```sql
> UPDATE public.recrutas
> SET xp = 0   -- valor do snapshot Q-D6
> WHERE id = '0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673';
> ```
> Documentar se necessario — indica comportamento de trigger a monitorar em Fase 2.

---

## 5. Criterio de Aprovacao

| Teste | Condicao | Resultado Esperado | Status Operador |
|-------|----------|--------------------|-----------------|
| T-08 | Retorno JSON correto + 1 linha em recruta_progresso + 1 linha em xp_eventos com xp=50 | `{"status":"ok","xp_granted":true,"xp_added":50}` | [ ] PASSOU / [ ] FALHOU |
| T-09 | Segunda chamada nao duplica — COUNT=1 em ambas as tabelas, SUM XP=50 | `{"status":"ok","xp_granted":false,"xp_added":0,"message":"..."}` | [ ] PASSOU / [ ] FALHOU |
| T-10 | recruta_progresso inserido, xp_eventos COUNT=0, retorno sem campo `message` | `{"status":"ok","xp_granted":false,"xp_added":0}` ou BLOQUEADO | [ ] PASSOU / [ ] BLOQUEADO / [ ] FALHOU |
| T-11 | Erro 22023 com mensagem "Lesson not found" — zero DML | `ERROR 22023` | [ ] PASSOU / [ ] FALHOU |
| T-12 | source='rpc_complete_lesson', xp_consistente=true | source_audit='NOVO — correto' | [ ] PASSOU / [ ] FALHOU |

---

## 6. Veredicto Esperado

### Se todos os testes obrigatorios passarem (T-08, T-09, T-10 ou BLOQUEADO, T-11, T-12):

```
FASE 1B — APROVADA
Gate de Fase 2 desbloqueado.
PR frontend pode ser aberto: migrar progressService.ts para rpc_complete_lesson.
NÃO remover complete_lesson — coexistencia obrigatoria durante Sprint 2.
```

**Proximo passo:** abrir PR com alteracao de uma linha em `src/services/progressService.ts`:

```typescript
// REMOVER:
const { data, error } = await supabase.rpc('complete_lesson', {
    p_recruta_id: userId,
    p_lesson_id: lessonId
});

// ADICIONAR:
const { data, error } = await supabase.rpc('rpc_complete_lesson', {
    p_lesson_id: lessonId
});
// recruta_id derivado internamente via auth.uid()
// retorno: {status, xp_granted, xp_added} — validar consumidor em app/(stack)/lesson/[id].tsx
```

---

### Se qualquer criterio obrigatorio falhar:

```
FASE 2 — BLOQUEADA
Aplicar rollback cirurgico (Secao 4).
Investigar a funcao rpc_complete_lesson via CREATE OR REPLACE.
Reexecutar testes a partir de T-08.
NÃO migrar progressService.ts.
```

**Falhas bloqueantes por categoria:**

| Falha | Causa provavel | Acao |
|-------|----------------|------|
| T-08 retorna 42501 com JWT | JWT nao esta sendo injetado no SQL Editor | Verificar seletor "Run as user" |
| T-08 retorna 22023 "Recruta profile not found" | Recruta GADELHA sem registro em `recrutas` | Verificar onboarding do recruta |
| T-08 retorna 22023 "forca is not defined" | Recruta sem `forca` definida | Executar `rpc_complete_onboarding` para GADELHA |
| T-08 retorna `xp_added` diferente de 50 | `aulas.xp_valor` com valor diferente do esperado | Confirmar xp_valor da aula `aff99e81...` |
| T-09 mostra COUNT xp_eventos = 2 | Idempotencia quebrada — ON CONFLICT nao funcionou | Investigar indice `ux_xp_eventos_lesson_unique` |
| T-10 gera entrada em xp_eventos | Condicional `IF v_xp_valor > 0` nao esta funcionando | Verificar corpo da funcao |
| T-11 retorna JSON em vez de erro | Guarda 3 nao esta operando | Verificar DDL da funcao no pg_proc |
| T-12 mostra source diferente de 'rpc_complete_lesson' | INSERT com source errado | Verificar PASSO A da funcao |

---

## 7. Saida Final Esperada

Apos execucao bem-sucedida de todos os testes e rollback, o operador deve registrar:

```
=== PROTOCOLO DE EXECUCAO P1-M1 FASE 1B ===

Data de execucao : 2026-05-17
Operador         : [PREENCHER]
Ambiente         : [ ] Staging  [ ] Producao com conta de teste
Modo de execucao : [ ] SQL Editor (Run as user)  [ ] Script Node.js  [ ] App

Recruta de teste : GADELHA (0e7b3ac0-4b84-4ce8-b2ef-8128cad6a673)
Aula XP > 0      : aff99e81-afd5-46c0-bcc6-c9dda47af687  (xp=50)
Aula XP = 0      : 22222222-2222-2222-2222-222222222222  (xp=0) | [ ] Confirmada  [ ] BLOQUEADO

RESULTADOS:
  T-08 (fluxo legitimo)     : [ ] PASSOU  [ ] FALHOU
  T-09 (idempotencia)       : [ ] PASSOU  [ ] FALHOU
  T-10 (xp_valor=0)         : [ ] PASSOU  [ ] BLOQUEADO  [ ] FALHOU
  T-11 (aula inexistente)   : [ ] PASSOU  [ ] FALHOU
  T-12 (source rastreavel)  : [ ] PASSOU  [ ] FALHOU

Rollback executado          : [ ] SIM  [ ] NAO (N/A se staging)
recurtas.xp precisou UPDATE : [ ] SIM  [ ] NAO

VEREDICTO FINAL:
  [ ] FASE 1B APROVADA — Fase 2 (PR frontend) DESBLOQUEADA
  [ ] FASE 1B APROVADA COM RESSALVAS — Fase 2 DESBLOQUEADA com monitoramento
  [ ] FASE 1B REPROVADA — Fase 2 BLOQUEADA, investigar e reexecutar

Observacoes:
[PREENCHER]
=============================================================
```
