// =============================================================================
// test_rpc_complete_lesson.js
// Sprint 2 / Fase 1B — validação funcional de rpc_complete_lesson (T-08 a T-12)
//
// PRE-REQUISITOS
// --------------
// 1. Migration aplicada:
//    20260517002000_p1_m1_1_fix_rpc_complete_lesson_auth_id_resolution.sql
//
// 2. Criar .env.test.local na raiz do projeto (NUNCA commitar):
//    TEST_USER_EMAIL=userc@email.com
//    TEST_USER_PASSWORD=<senha real — preencher localmente>
//
// 3. node_modules instalados:
//    npm install   (ou yarn / bun install)
//
// EXECUCAO
// --------
//    node scripts/test_rpc_complete_lesson.js
//
// IMPORTANTE
// ----------
// - Este script gera dados reais em recruta_progresso e xp_eventos.
// - Execute o ROLLBACK SQL impresso ao final se precisar limpar os dados.
// - Nao commitar .env.test.local.
// =============================================================================

'use strict';

const fs   = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');

// -----------------------------------------------------------------------------
// UUIDs de teste (fixos — confirmados na Fase 1B)
// -----------------------------------------------------------------------------
const AUTH_UID_GADELHA    = '918c08f3-8e08-4dc7-a102-da5c729a6ead'; // auth.users.id
const RECRUTA_ID_CANONICO = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017'; // recrutas.id
const LESSON_ID_XP_POS    = 'aff99e81-afd5-46c0-bcc6-c9dda47af687'; // xp_valor = 50
const LESSON_ID_XP_ZERO   = '22222222-2222-2222-2222-222222222222'; // xp_valor = 0
const LESSON_ID_FAKE      = 'ffffffff-ffff-ffff-ffff-ffffffffffff'; // nao existe
const XP_ESPERADO         = 50;

// -----------------------------------------------------------------------------
// Utilitários
// -----------------------------------------------------------------------------

/** Parseia um arquivo .env simples (KEY=VALUE, ignora # e linhas vazias). */
function parseEnvFile(filePath) {
    if (!fs.existsSync(filePath)) return null;
    const lines = fs.readFileSync(filePath, 'utf8').split('\n');
    const result = {};
    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx < 1) continue;
        const key = trimmed.slice(0, eqIdx).trim();
        const val = trimmed.slice(eqIdx + 1).trim();
        result[key] = val;
    }
    return result;
}

/** Formata resultado de teste no terminal. */
function reportTest(id, descricao, passou, detalhe) {
    const icon = passou ? 'PASSOU' : 'FALHOU';
    const sep  = passou ? '  ' : '  ';
    console.log(`\n[${icon}] ${id} — ${descricao}${detalhe ? `\n${sep}  ${detalhe}` : ''}`);
}

/** Imprime um bloco SQL formatado. */
function printSqlBlock(titulo, sql) {
    console.log(`\n${'─'.repeat(70)}`);
    console.log(`SQL: ${titulo}`);
    console.log('─'.repeat(70));
    console.log(sql.trim());
    console.log('─'.repeat(70));
}

// -----------------------------------------------------------------------------
// Carregamento de variáveis de ambiente
// -----------------------------------------------------------------------------

const ROOT       = path.resolve(__dirname, '..');
const envMain    = parseEnvFile(path.join(ROOT, '.env'));
const envTest    = parseEnvFile(path.join(ROOT, '.env.test.local'));

if (!envMain) {
    console.error('[ERRO] Arquivo .env nao encontrado na raiz do projeto.');
    process.exit(1);
}
if (!envTest) {
    console.error('[ERRO] Arquivo .env.test.local nao encontrado.');
    console.error('       Crie o arquivo na raiz do projeto com:');
    console.error('         TEST_USER_EMAIL=userc@email.com');
    console.error('         TEST_USER_PASSWORD=<senha>');
    console.error('       NUNCA commitar este arquivo.');
    process.exit(1);
}

// O .env do Expo usa prefixo EXPO_PUBLIC_
const SUPABASE_URL      = envMain['EXPO_PUBLIC_SUPABASE_URL'];
const SUPABASE_ANON_KEY = envMain['EXPO_PUBLIC_SUPABASE_ANON_KEY'];
const TEST_EMAIL        = envTest['TEST_USER_EMAIL'];
const TEST_PASSWORD     = envTest['TEST_USER_PASSWORD'];

const missingVars = [];
if (!SUPABASE_URL)      missingVars.push('EXPO_PUBLIC_SUPABASE_URL (.env)');
if (!SUPABASE_ANON_KEY) missingVars.push('EXPO_PUBLIC_SUPABASE_ANON_KEY (.env)');
if (!TEST_EMAIL)        missingVars.push('TEST_USER_EMAIL (.env.test.local)');
if (!TEST_PASSWORD)     missingVars.push('TEST_USER_PASSWORD (.env.test.local)');

if (missingVars.length > 0) {
    console.error('[ERRO] Variaveis de ambiente ausentes:');
    missingVars.forEach(v => console.error('  - ' + v));
    process.exit(1);
}

// Senha nunca impressa — apenas confirmamos que foi carregada
console.log('[ENV] SUPABASE_URL      :', SUPABASE_URL);
console.log('[ENV] SUPABASE_ANON_KEY : ****** (carregada)');
console.log('[ENV] TEST_USER_EMAIL   :', TEST_EMAIL);
console.log('[ENV] TEST_USER_PASSWORD: ****** (carregada, nao sera impressa)');

// -----------------------------------------------------------------------------
// Resultado acumulado dos testes
// -----------------------------------------------------------------------------
const resultados = {};
function registrar(id, passou) { resultados[id] = passou; }

// -----------------------------------------------------------------------------
// Programa principal
// -----------------------------------------------------------------------------
async function main() {
    console.log('\n' + '='.repeat(70));
    console.log('  rpc_complete_lesson — Testes Funcionais T-08 a T-12');
    console.log('  Sprint 2 / Fase 1B — P1-M1.1');
    console.log('='.repeat(70));

    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

    // ─── PRE: Login ──────────────────────────────────────────────────────────
    console.log('\n[AUTH] Fazendo login como ' + TEST_EMAIL + '...');
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
        email:    TEST_EMAIL,
        password: TEST_PASSWORD,
    });

    if (authError || !authData?.session) {
        console.error('[AUTH] FALHOU:', authError?.message ?? 'sem sessao retornada');
        console.error('       Verificar email/senha em .env.test.local');
        process.exit(1);
    }

    const sessionUserId = authData.session.user.id;
    console.log('[AUTH] Login OK. session.user.id =', sessionUserId);

    // ─── PRE: Confirmar identidade ───────────────────────────────────────────
    const identidadeCorreta = sessionUserId === AUTH_UID_GADELHA;
    reportTest(
        'PRE-ID',
        'session.user.id corresponde a AUTH_UID_GADELHA',
        identidadeCorreta,
        identidadeCorreta
            ? 'uid = ' + sessionUserId
            : 'ESPERADO: ' + AUTH_UID_GADELHA + '\nOBTIDO  : ' + sessionUserId
    );
    if (!identidadeCorreta) {
        console.error('\n[BLOQUEIO] Conta autenticada nao e GADELHA. Abortando testes.');
        console.error('           Verificar TEST_USER_EMAIL em .env.test.local.');
        await supabase.auth.signOut();
        process.exit(1);
    }
    registrar('PRE-ID', true);

    // ─── T-08: Fluxo legítimo ────────────────────────────────────────────────
    console.log('\n[T-08] Chamando rpc_complete_lesson com LESSON_ID_XP_POS...');
    console.log('       lesson_id =', LESSON_ID_XP_POS, '(xp_valor esperado = ' + XP_ESPERADO + ')');

    const { data: t08, error: e08 } = await supabase
        .rpc('rpc_complete_lesson', { p_lesson_id: LESSON_ID_XP_POS });

    if (e08) {
        reportTest('T-08', 'Fluxo legitimo', false,
            'ERRO: ' + e08.message + ' | code: ' + (e08.code ?? 'n/a'));
        registrar('T-08', false);
    } else {
        const ok08 =
            t08?.status     === 'ok'   &&
            t08?.xp_granted === true   &&
            t08?.xp_added   === XP_ESPERADO &&
            !t08?.message;  // primeira chamada nao tem campo message
        reportTest('T-08', 'Fluxo legitimo', ok08,
            'Retorno: ' + JSON.stringify(t08));
        registrar('T-08', ok08);
        if (!ok08) {
            console.log('       Esperado: {"status":"ok","xp_granted":true,"xp_added":' + XP_ESPERADO + '}');
        }
    }

    // ─── T-09: Idempotência ──────────────────────────────────────────────────
    console.log('\n[T-09] Segunda chamada (idempotencia)...');

    const { data: t09, error: e09 } = await supabase
        .rpc('rpc_complete_lesson', { p_lesson_id: LESSON_ID_XP_POS });

    if (e09) {
        reportTest('T-09', 'Idempotencia — segunda chamada nao duplica', false,
            'ERRO inesperado: ' + e09.message);
        registrar('T-09', false);
    } else {
        const ok09 =
            t09?.status     === 'ok'  &&
            t09?.xp_granted === false &&
            t09?.xp_added   === 0     &&
            typeof t09?.message === 'string' && t09.message.length > 0;
        reportTest('T-09', 'Idempotencia — segunda chamada nao duplica', ok09,
            'Retorno: ' + JSON.stringify(t09));
        registrar('T-09', ok09);
        if (!ok09) {
            console.log('       Esperado: {"status":"ok","xp_granted":false,"xp_added":0,"message":"..."}');
        }
    }

    // ─── T-10: xp_valor = 0 ──────────────────────────────────────────────────
    console.log('\n[T-10] Chamando rpc_complete_lesson com LESSON_ID_XP_ZERO...');
    console.log('       lesson_id =', LESSON_ID_XP_ZERO, '(xp_valor esperado = 0)');

    const { data: t10, error: e10 } = await supabase
        .rpc('rpc_complete_lesson', { p_lesson_id: LESSON_ID_XP_ZERO });

    if (e10) {
        // BLOQUEADO é aceitavel se a aula nao existir no banco
        const bloqueado = e10.message?.includes('Lesson not found') ||
                          e10.code === '22023';
        if (bloqueado) {
            reportTest('T-10', 'xp_valor=0 (progresso sem XP)', null,
                'BLOQUEADO — aula ' + LESSON_ID_XP_ZERO + ' nao existe no banco.\n' +
                '         Criar aula de teste com xp_valor=0 ou usar outro lesson_id.');
            registrar('T-10', null); // null = bloqueado (nao falhou, nao passou)
        } else {
            reportTest('T-10', 'xp_valor=0 (progresso sem XP)', false,
                'ERRO inesperado: ' + e10.message + ' | code: ' + (e10.code ?? 'n/a'));
            registrar('T-10', false);
        }
    } else {
        // Sem campo "message": distingue de idempotencia (T-09)
        const ok10 =
            t10?.status     === 'ok'  &&
            t10?.xp_granted === false &&
            t10?.xp_added   === 0     &&
            !t10?.message;
        reportTest('T-10', 'xp_valor=0 (progresso sem XP)', ok10,
            'Retorno: ' + JSON.stringify(t10));
        registrar('T-10', ok10);
        if (!ok10) {
            console.log('       Esperado: {"status":"ok","xp_granted":false,"xp_added":0}  (sem campo "message")');
        }
    }

    // ─── T-11: Aula inexistente ───────────────────────────────────────────────
    console.log('\n[T-11] Chamando rpc_complete_lesson com UUID fake (Guarda 3)...');
    console.log('       lesson_id =', LESSON_ID_FAKE);

    const { data: t11, error: e11 } = await supabase
        .rpc('rpc_complete_lesson', { p_lesson_id: LESSON_ID_FAKE });

    if (e11) {
        // Supabase JS retorna o SQLSTATE em e11.code (formato PostgREST: 'PXXXXX')
        // ou em e11.details. Buscamos '22023' ou a mensagem 'Lesson not found'.
        const ok11 =
            (e11.code === '22023' || e11.message?.includes('Lesson not found'));
        reportTest('T-11', 'Aula inexistente → erro 22023', ok11,
            'code: ' + (e11.code ?? 'n/a') + ' | mensagem: ' + e11.message);
        registrar('T-11', ok11);
        if (!ok11) {
            console.log('       Esperado: code=22023, mensagem contendo "Lesson not found"');
        }
    } else {
        reportTest('T-11', 'Aula inexistente → erro 22023', false,
            'FALHOU: retornou JSON em vez de erro: ' + JSON.stringify(t11));
        registrar('T-11', false);
    }

    // ─── T-12: source rastreável ──────────────────────────────────────────────
    // T-12 valida recruta_progresso.source via SELECT.
    // O cliente autenticado pode ler suas proprias linhas se RLS permitir.
    // Caso RLS bloqueie (0 linhas retornadas), o operador deve executar a
    // query SQL de validacao impressa abaixo como service_role no SQL Editor.
    console.log('\n[T-12] Verificando source em recruta_progresso...');
    console.log('       (requer RLS permissao de leitura — ver SQL de validacao abaixo)');

    const { data: t12Rows, error: e12 } = await supabase
        .from('recruta_progresso')
        .select('recruta_id, lesson_id, status, xp_granted, source, completed_at')
        .eq('lesson_id',  LESSON_ID_XP_POS)
        .eq('recruta_id', RECRUTA_ID_CANONICO);

    if (e12) {
        reportTest('T-12', 'source = rpc_complete_lesson (via JS client)', false,
            'ERRO ao consultar recruta_progresso: ' + e12.message);
        registrar('T-12', false);
    } else if (!t12Rows || t12Rows.length === 0) {
        reportTest('T-12', 'source = rpc_complete_lesson (via JS client)', false,
            'ZERO linhas retornadas.\n' +
            '       Causas possiveis:\n' +
            '         1. T-08 nao foi executado com sucesso\n' +
            '         2. RLS bloqueia leitura por esta sessao\n' +
            '         3. recruta_id errado na query\n' +
            '       Executar query SQL de validacao abaixo como service_role.');
        registrar('T-12', false);
    } else {
        const row   = t12Rows[0];
        const ok12  =
            row.source      === 'rpc_complete_lesson' &&
            row.recruta_id  === RECRUTA_ID_CANONICO &&
            row.xp_granted  === XP_ESPERADO;
        reportTest('T-12', 'source = rpc_complete_lesson (via JS client)', ok12,
            'Row: ' + JSON.stringify(row));
        if (!ok12) {
            if (row.source !== 'rpc_complete_lesson')
                console.log('       source incorreto: ' + row.source + ' (esperado: rpc_complete_lesson)');
            if (row.recruta_id !== RECRUTA_ID_CANONICO)
                console.log('       recruta_id incorreto: ' + row.recruta_id + ' (esperado: ' + RECRUTA_ID_CANONICO + ')');
        }
        registrar('T-12', ok12);
    }

    // ─── Logout ───────────────────────────────────────────────────────────────
    await supabase.auth.signOut();
    console.log('\n[AUTH] Sessao encerrada.');

    // ─── Sumario final ────────────────────────────────────────────────────────
    console.log('\n' + '='.repeat(70));
    console.log('  SUMARIO — T-08 a T-12');
    console.log('='.repeat(70));

    const TESTES = ['PRE-ID', 'T-08', 'T-09', 'T-10', 'T-11', 'T-12'];
    let totalPassou  = 0;
    let totalFalhou  = 0;
    let totalBloq    = 0;

    for (const id of TESTES) {
        const r = resultados[id];
        let status;
        if (r === true)  { status = 'PASSOU  '; totalPassou++; }
        else if (r === false) { status = 'FALHOU  '; totalFalhou++; }
        else             { status = 'BLOQUEADO'; totalBloq++; }
        console.log(`  ${status}  ${id}`);
    }

    console.log('─'.repeat(70));
    console.log(`  Passou: ${totalPassou}  Falhou: ${totalFalhou}  Bloqueado: ${totalBloq}`);

    const faseAprovada = totalFalhou === 0 && totalPassou >= 5; // T-10 pode ser BLOQUEADO
    console.log('\n  VEREDICTO:', faseAprovada
        ? 'FASE 1B APROVADA — gate de Fase 2 desbloqueado'
        : 'FASE 1B REPROVADA — investigar falhas antes de migrar progressService.ts');
    console.log('='.repeat(70));

    // ─── SQL de validação (para executar como service_role no SQL Editor) ──────
    printSqlBlock('Validacao completa pos-testes (service_role)', `
-- Validacao T-08/T-09: recruta_progresso
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
        ELSE 'DESCONHECIDO: ' || rp.source
    END AS source_audit
FROM public.recruta_progresso rp
WHERE rp.recruta_id = '${RECRUTA_ID_CANONICO}'
  AND rp.lesson_id  = '${LESSON_ID_XP_POS}';
-- Esperado: 1 linha, source='rpc_complete_lesson', xp_granted=${XP_ESPERADO}

-- Validacao T-08: xp_eventos
SELECT
    xe.recruta_id,
    xe.forca,
    xe.quantidade,
    xe.origem,
    xe.referencia_id,
    xe.created_at
FROM public.xp_eventos xe
WHERE xe.recruta_id    = '${RECRUTA_ID_CANONICO}'
  AND xe.referencia_id = '${LESSON_ID_XP_POS}'
  AND xe.origem        = 'lesson_complete';
-- Esperado: 1 linha, quantidade=${XP_ESPERADO}, forca IN ('marinha','exercito','aeronautica')

-- Validacao T-09: COUNT nao duplicou
SELECT COUNT(*) AS contagem_progresso FROM public.recruta_progresso
WHERE recruta_id = '${RECRUTA_ID_CANONICO}' AND lesson_id = '${LESSON_ID_XP_POS}';
-- Esperado: 1

SELECT COUNT(*) AS contagem_xp_eventos FROM public.xp_eventos
WHERE recruta_id = '${RECRUTA_ID_CANONICO}' AND referencia_id = '${LESSON_ID_XP_POS}'
  AND origem = 'lesson_complete';
-- Esperado: 1

-- Validacao T-10 (se PASSOU): recruta_progresso inserido, xp_eventos ausente
SELECT COUNT(*) AS progresso_xp_zero FROM public.recruta_progresso
WHERE recruta_id = '${RECRUTA_ID_CANONICO}' AND lesson_id = '${LESSON_ID_XP_ZERO}';
-- Esperado: 1 (ou 0 se T-10 foi BLOQUEADO)

SELECT COUNT(*) AS xp_eventos_xp_zero FROM public.xp_eventos
WHERE recruta_id = '${RECRUTA_ID_CANONICO}' AND referencia_id = '${LESSON_ID_XP_ZERO}'
  AND origem = 'lesson_complete';
-- Esperado: 0 (CHECK quantidade>0 impede insercao)

-- Validacao T-12: consistencia cruzada
SELECT
    rp.source         AS progresso_source,
    xe.origem         AS xp_origem,
    rp.xp_granted     AS progresso_xp,
    xe.quantidade     AS xp_ledger,
    rp.xp_granted = xe.quantidade AS xp_consistente,
    rp.recruta_id = '${RECRUTA_ID_CANONICO}' AS recruta_id_correto,
    rp.recruta_id = '${AUTH_UID_GADELHA}'    AS recruta_id_errado_auth_uid
FROM public.recruta_progresso rp
JOIN public.xp_eventos xe
  ON xe.recruta_id    = rp.recruta_id
 AND xe.referencia_id = rp.lesson_id
 AND xe.origem        = 'lesson_complete'
WHERE rp.recruta_id = '${RECRUTA_ID_CANONICO}'
  AND rp.lesson_id  = '${LESSON_ID_XP_POS}';
-- Esperado: xp_consistente=true, recruta_id_correto=true, recruta_id_errado_auth_uid=false
`);

    // ─── SQL de rollback cirúrgico ────────────────────────────────────────────
    printSqlBlock('ROLLBACK cirurgico (service_role — executar APENAS apos os testes)', `
-- R-01: remover progresso de T-08 (aula XP > 0)
DELETE FROM public.recruta_progresso
WHERE recruta_id = '${RECRUTA_ID_CANONICO}'
  AND lesson_id  = '${LESSON_ID_XP_POS}'
  AND source     = 'rpc_complete_lesson';

-- Verificacao R-01:
SELECT COUNT(*) AS deve_ser_zero FROM public.recruta_progresso
WHERE recruta_id = '${RECRUTA_ID_CANONICO}' AND lesson_id = '${LESSON_ID_XP_POS}';

-- R-02: remover XP de T-08 do ledger
DELETE FROM public.xp_eventos
WHERE recruta_id    = '${RECRUTA_ID_CANONICO}'
  AND referencia_id = '${LESSON_ID_XP_POS}'
  AND origem        = 'lesson_complete';

-- Verificacao R-02:
SELECT COUNT(*) AS deve_ser_zero FROM public.xp_eventos
WHERE recruta_id = '${RECRUTA_ID_CANONICO}' AND referencia_id = '${LESSON_ID_XP_POS}'
  AND origem = 'lesson_complete';

-- R-03: remover progresso de T-10 (aula XP = 0, se T-10 foi executado)
DELETE FROM public.recruta_progresso
WHERE recruta_id = '${RECRUTA_ID_CANONICO}'
  AND lesson_id  = '${LESSON_ID_XP_ZERO}'
  AND source     = 'rpc_complete_lesson';

-- Verificacao R-03:
SELECT COUNT(*) AS deve_ser_zero FROM public.recruta_progresso
WHERE recruta_id = '${RECRUTA_ID_CANONICO}' AND lesson_id = '${LESSON_ID_XP_ZERO}';

-- R-04: confirmar estado limpo (comparar com snapshot pre-teste)
SELECT
    (SELECT COUNT(*) FROM public.recruta_progresso
     WHERE recruta_id = '${RECRUTA_ID_CANONICO}') AS total_progresso,
    (SELECT COALESCE(SUM(quantidade), 0) FROM public.xp_eventos
     WHERE recruta_id = '${RECRUTA_ID_CANONICO}') AS xp_total_ledger,
    (SELECT xp FROM public.recrutas
     WHERE id = '${RECRUTA_ID_CANONICO}')          AS xp_recruta;
-- Esperado: total_progresso=0, xp_total_ledger=0, xp_recruta=0
-- Se xp_recruta != 0: trigger de sync atualizou recrutas.xp — corrigir com:
--   UPDATE public.recrutas SET xp = 0 WHERE id = '${RECRUTA_ID_CANONICO}';
`);
}

// Ponto de entrada — captura erros nao tratados
main().catch(err => {
    console.error('\n[ERRO FATAL]', err.message ?? err);
    process.exit(1);
});
