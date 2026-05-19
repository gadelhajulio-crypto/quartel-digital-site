-- =============================================================================
-- P1-M1 QA — Conteúdo de Teste para Validação via Expo Go
-- =============================================================================
-- Classificação : QA / Dados de teste — NÃO é migration
-- Data          : 2026-05-18
-- Autor         : institutional-qa-2026-05-18
-- Sprint        : 2 / Fase 2 — QA pós-migração frontend
--
-- OBJETIVO
-- --------
-- Criar um módulo e uma aula de teste com UUIDs fixos, visíveis no app via
-- Expo Go, para validar o fluxo real de rpc_complete_lesson sem tocar em
-- conteúdo real.
--
-- REGRAS
-- ------
-- - NÃO executar automaticamente. Executar no SQL Editor do Supabase.
-- - NÃO alterar aulas reais, RPCs ou frontend.
-- - UUIDs fixos garantem rollback cirúrgico sem lookup de id.
-- - Executar SEMPRE como service_role (bypassa RLS).
-- - Executar os STEPs em ordem: STEP-00 → STEP-01 → STEP-02 → STEP-03.
-- - Após QA concluído (aprovado ou reprovado): executar STEP-06 (rollback).
--
-- CONTEXTO
-- --------
-- Usuário de teste : GADELHA
-- auth.users.id    : 918c08f3-8e08-4dc7-a102-da5c729a6ead
-- recrutas.id      : cc41fc7e-ce7d-405d-9178-c14b39e1a017
-- recrutas.auth_id : 918c08f3-8e08-4dc7-a102-da5c729a6ead
-- forca            : marinha
--
-- UUIDs FIXOS DE TESTE
-- --------------------
-- MÓDULO_TESTE_ID : 00000000-0000-0000-0000-000000010001
-- AULA_TESTE_ID   : 00000000-0000-0000-0000-000000010002
--
-- SCHEMA CANÔNICO CONFIRMADO (remote schema dump)
-- -----------------------------------------------
-- modulos (ln 10607):
--   id uuid, forca text NOT NULL CHECK(marinha|exercito|aeronautica),
--   titulo text NOT NULL, descricao text, ordem integer NOT NULL,
--   ativo boolean DEFAULT true, is_degustacao boolean DEFAULT false
--
-- aulas (ln 9075):
--   id uuid, modulo_id uuid NOT NULL, titulo text NOT NULL,
--   ordem integer NOT NULL, xp_valor integer DEFAULT 0 NOT NULL,
--   video_url text, pdf_url text
--
-- VIEWS CONSUMIDAS PELO APP (fluxo de aulas)
-- ------------------------------------------
-- vw_rdm_lessons_v2        : lista aulas — filtra ativo=true E is_degustacao=true
-- vw_recruta_module_progress_v2 : progresso por recruta — filtra m.forca = r.forca
-- v_lessons_panel          : detalhe da aula — sem filtros adicionais
--
-- REFERÊNCIAS
-- -----------
-- Plano QA       : supabase/baseline/P1_M1_QA_TEST_LESSON_PLAN.md
-- RPC canônica   : supabase/migrations/20260517002000_p1_m1_1_fix_rpc_complete_lesson_auth_id_resolution.sql
-- Schema remoto  : supabase/remote/supabase_remote_schema.sql (ln 9075, 10607, 14177, 14314)
-- =============================================================================


-- =============================================================================
-- STEP-00 — Verificar que os UUIDs de teste estão livres
-- =============================================================================
-- Executar ANTES de STEP-01 e STEP-02.
-- Resultado esperado: 0 linhas.
-- Se retornar linhas: este script já foi executado antes.
--   → Ir direto para STEP-03 para confirmar visibilidade.
--   → Ou executar STEP-06 para rollback antes de reinserir.
-- =============================================================================

SELECT
    'modulo' AS tipo,
    id,
    titulo
FROM public.modulos
WHERE id = '00000000-0000-0000-0000-000000010001'

UNION ALL

SELECT
    'aula',
    id,
    titulo
FROM public.aulas
WHERE id = '00000000-0000-0000-0000-000000010002';

-- Esperado: 0 linhas
-- Se retornar 1 ou 2 linhas: dados de teste já existem — NÃO executar STEP-01/02.


-- =============================================================================
-- STEP-01 — Inserir módulo de teste
-- =============================================================================
-- Executar APENAS se STEP-00 retornou 0 linhas.
--
-- Requisitos de visibilidade em vw_rdm_lessons_v2:
--   COALESCE(m.ativo, true) = true        → ativo = true  (DEFAULT=true, mas setar explicitamente)
--   COALESCE(m.is_degustacao, false) = true → is_degustacao = true  (DEFAULT=false — OBRIGATÓRIO)
--
-- Requisitos de visibilidade em vw_recruta_module_progress_v2:
--   m.forca = r.forca                     → forca = 'marinha' (força de GADELHA)
--   forca NOT NULL + CHECK(marinha|exercito|aeronautica) → valor confirmado.
--
-- ordem = 9999: aparece no final da lista, sem interferir com módulos reais.
-- =============================================================================

INSERT INTO public.modulos (
    id,
    forca,
    titulo,
    descricao,
    ordem,
    ativo,
    is_degustacao,
    created_at
)
VALUES (
    '00000000-0000-0000-0000-000000010001',
    'marinha',
    '[QA] Módulo Teste rpc_complete_lesson',
    'Módulo de teste QA P1-M1. Remover após Fase 2 (STEP-06).',
    9999,
    true,
    true,      -- OBRIGATÓRIO: false tornaria o módulo invisível em vw_rdm_lessons_v2
    now()
);

-- Verificação STEP-01:
SELECT
    id,
    titulo,
    forca,
    ativo,
    is_degustacao,
    ordem
FROM public.modulos
WHERE id = '00000000-0000-0000-0000-000000010001';
-- Esperado: 1 linha
--   forca         = 'marinha'
--   ativo         = true
--   is_degustacao = true
--   ordem         = 9999


-- =============================================================================
-- STEP-02 — Inserir aula de teste
-- =============================================================================
-- Executar APENAS após STEP-01 bem-sucedido.
--
-- xp_valor = 50:
--   - rpc_complete_lesson lerá aulas.xp_valor como única fonte de XP
--   - xp_valor > 0 garante inserção em xp_eventos (CHECK quantidade > 0)
--   - valor 50 é rastreável nas queries de validação (STEP-05)
--
-- video_url = NULL, pdf_url = NULL:
--   - Tela exibe placeholder "Conteúdo Institucional" (comportamento esperado)
--   - C9 (aula_conteudos/flashcards/quizzes) não é necessário para este QA
--
-- FK: modulo_id → modulos.id (CASCADE DELETE — rollback de módulo remove aula automaticamente)
-- =============================================================================

INSERT INTO public.aulas (
    id,
    modulo_id,
    titulo,
    ordem,
    xp_valor,
    video_url,
    pdf_url,
    created_at
)
VALUES (
    '00000000-0000-0000-0000-000000010002',
    '00000000-0000-0000-0000-000000010001',
    '[QA] Aula Teste rpc_complete_lesson',
    1,
    50,
    NULL,
    NULL,
    now()
);

-- Verificação STEP-02:
SELECT
    id,
    titulo,
    modulo_id,
    ordem,
    xp_valor,
    video_url,
    pdf_url
FROM public.aulas
WHERE id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 1 linha
--   modulo_id = 00000000-0000-0000-0000-000000010001
--   xp_valor  = 50
--   video_url = NULL
--   pdf_url   = NULL


-- =============================================================================
-- STEP-03 — Validar visibilidade nas views consumidas pelo app
-- =============================================================================
-- Executar após STEP-01 e STEP-02.
-- Todas as queries devem ser executadas como service_role.
--
-- V-01 e V-02 não dependem de auth.uid() — retornam os mesmos dados para qualquer role.
-- V-03 não usa auth.uid() — filtra por recruta_id explícito (GADELHA: cc41fc7e).
-- =============================================================================

-- V-01 — Aula visível em vw_rdm_lessons_v2 (lista de aulas do módulo)?
-- Hook: useModuleLessons
-- Filtro da view: ativo=true E is_degustacao=true (ambos setados em STEP-01)
SELECT
    lesson_id,
    lesson_order,
    lesson_title,
    status,
    module_id,
    forca,
    is_degustacao
FROM public.vw_rdm_lessons_v2
WHERE module_id = '00000000-0000-0000-0000-000000010001';
-- Esperado: 1 linha
--   lesson_id     = 00000000-0000-0000-0000-000000010002
--   lesson_title  = '[QA] Aula Teste rpc_complete_lesson'
--   status        = 'available'  (constante nesta view — não depende de auth.uid())
--   forca         = 'marinha'
--   is_degustacao = true
-- Se 0 linhas: verificar is_degustacao=true e ativo=true do módulo (STEP-01).


-- V-02 — Aula visível em v_lessons_panel (detalhe da aula)?
-- Hook: useLessonData
-- Sem filtros adicionais além do JOIN — qualquer aula com modulo_id válido aparece.
SELECT
    lesson_id,
    title,
    module,
    lesson_order,
    force
FROM public.v_lessons_panel
WHERE lesson_id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 1 linha
--   title         = '[QA] Aula Teste rpc_complete_lesson'
--   module        = 00000000-0000-0000-0000-000000010001
--   lesson_order  = 1
--   force         = 'marinha'
-- Se 0 linhas: verificar se STEP-02 foi executado com sucesso.


-- V-03 — Módulo visível em vw_recruta_module_progress_v2 para GADELHA?
-- Hook: useModulesProgress
-- A view faz JOIN recrutas × modulos filtrando m.forca = r.forca.
-- GADELHA: recrutas.id = cc41fc7e, forca = 'marinha'.
-- Módulo de teste: forca = 'marinha' → JOIN satisfeito.
SELECT
    recruta_id,
    module_id,
    module_title,
    total_lessons,
    completed_lessons,
    progress_percentage
FROM public.vw_recruta_module_progress_v2
WHERE module_id  = '00000000-0000-0000-0000-000000010001'
  AND recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017';
-- Esperado: 1 linha (pré-QA)
--   total_lessons     = 1
--   completed_lessons = 0
--   progress_percentage = 0
-- Se 0 linhas: verificar forca='marinha' no módulo e no recruta GADELHA.


-- V-04 — rpc_complete_lesson reconhece a aula de teste?
-- Verifica que aulas.xp_valor está correto ANTES de acionar o app.
SELECT
    id,
    titulo,
    xp_valor,
    modulo_id
FROM public.aulas
WHERE id      = '00000000-0000-0000-0000-000000010002'
  AND xp_valor > 0;
-- Esperado: 1 linha, xp_valor = 50
-- Se 0 linhas: xp_valor = 0 ou aula não existe — corrigir antes de prosseguir.


-- =============================================================================
-- STEP-04 — Checklist QA Expo Go
-- =============================================================================
-- (Executar SOMENTE após STEP-03 com todas as verificações passando)
--
-- PRÉ-CONDIÇÃO
-- ------------
-- - STEP-00 a STEP-03 executados e todas as queries retornando conforme esperado.
-- - App rodando em Expo Go, login como GADELHA (userc@email.com ou conta GADELHA).
-- - Metro bundler ativo para observar logs.
--
-- PASSO A — Verificar módulo na lista
-- ------------------------------------
-- 1. Abrir o app → navegar para a lista de módulos.
-- 2. Verificar: módulo "[QA] Módulo Teste rpc_complete_lesson" aparece no final.
-- 3. Tocar no módulo.
-- 4. Verificar: aula "[QA] Aula Teste rpc_complete_lesson" aparece listada.
-- 5. Verificar: status visual = disponível (não bloqueada).
--
-- PASSO B — Detalhe da aula
-- --------------------------
-- 6. Tocar na aula.
-- 7. Verificar: tela de detalhe carrega com título "[QA] Aula Teste rpc_complete_lesson".
-- 8. Verificar: placeholder "Conteúdo Institucional" exibido (video_url = NULL esperado).
-- 9. Verificar: botão "MARCAR AULA COMO CONCLUÍDA" visível.
--
-- PASSO C — Conclusão (primeira vez)
-- -----------------------------------
-- 10. Tocar em "MARCAR AULA COMO CONCLUÍDA".
-- 11. Observar Metro log — esperado:
--       [P1-M1] rpc_complete_lesson {"status":"ok","xp_granted":true,"xp_added":50}
-- 12. Verificar: app retorna para a tela do módulo (router.back()) sem Alert de erro.
-- 13. Executar STEP-05 para validar o banco.
--
-- PASSO D — Idempotência (segunda conclusão)
-- -------------------------------------------
-- 14. Tocar na aula novamente.
-- 15. Tocar em "MARCAR AULA COMO CONCLUÍDA" de novo.
-- 16. Observar Metro log — esperado:
--       [P1-M1] rpc_complete_lesson {"status":"ok","xp_granted":false,"xp_added":0,"message":"Aula já concluída anteriormente"}
-- 17. Verificar: app retorna normalmente (sem erro, sem Alert).
--
-- NOTA — Botão não some após conclusão
-- --------------------------------------
-- Este é comportamento ESPERADO e NÃO é bug do rpc_complete_lesson.
-- v_lesson_progress_panel lê a tabela legada lesson_progress, não recruta_progresso.
-- O hook useLessonData filtra por recruta_id mas a coluna da view é user_id.
-- A validação correta é via Metro logs (PASSO C/D) + queries SQL (STEP-05).
-- =============================================================================


-- =============================================================================
-- STEP-05 — Validação pós-QA (executar após PASSO C do Expo Go)
-- =============================================================================
-- Executar como service_role no SQL Editor após clicar "MARCAR COMO CONCLUÍDA".
-- =============================================================================

-- QA-01 — Progresso registrado com recruta_id canônico e source correto
SELECT
    rp.recruta_id,
    rp.lesson_id,
    rp.status,
    rp.xp_granted,
    rp.source,
    rp.completed_at,
    rp.recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017' AS recruta_id_canonico,
    rp.recruta_id = '918c08f3-8e08-4dc7-a102-da5c729a6ead' AS recruta_id_auth_errado
FROM public.recruta_progresso rp
WHERE rp.lesson_id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 1 linha
--   status              = 'completed'
--   xp_granted          = 50
--   source              = 'rpc_complete_lesson'
--   completed_at        IS NOT NULL
--   recruta_id_canonico = true   (cc41fc7e — recrutas.id)
--   recruta_id_auth_errado = false  (se true: P1-M1.1 NÃO foi aplicada — BLOQUEANTE)


-- QA-02 — XP registrado no ledger (xp_eventos)
SELECT
    xe.recruta_id,
    xe.forca,
    xe.quantidade,
    xe.origem,
    xe.referencia_id
FROM public.xp_eventos xe
WHERE xe.referencia_id = '00000000-0000-0000-0000-000000010002'
  AND xe.origem        = 'lesson_complete';
-- Esperado: 1 linha
--   recruta_id   = cc41fc7e-ce7d-405d-9178-c14b39e1a017
--   forca        = 'marinha'
--   quantidade   = 50
--   origem       = 'lesson_complete'
--   referencia_id = 00000000-0000-0000-0000-000000010002
-- Se 0 linhas com xp_valor > 0: rpc_complete_lesson falhou no PASSO B — ver Metro logs.


-- QA-03 — Idempotência: contagens devem ser 1 mesmo após múltiplas conclusões
SELECT COUNT(*) AS contagem_progresso
FROM public.recruta_progresso
WHERE lesson_id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 1 (nunca > 1)

SELECT COUNT(*) AS contagem_xp
FROM public.xp_eventos
WHERE referencia_id = '00000000-0000-0000-0000-000000010002'
  AND origem        = 'lesson_complete';
-- Esperado: 1 (nunca > 1)
-- Se > 1: XP foi duplicado — ON CONFLICT não funcionou — BLOQUEANTE.


-- QA-04 — Progresso refletido em vw_recruta_module_progress_v2 após conclusão
SELECT
    recruta_id,
    module_id,
    module_title,
    total_lessons,
    completed_lessons,
    progress_percentage
FROM public.vw_recruta_module_progress_v2
WHERE module_id  = '00000000-0000-0000-0000-000000010001'
  AND recruta_id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017';
-- Esperado (pós-conclusão):
--   total_lessons       = 1
--   completed_lessons   = 1
--   progress_percentage = 100
-- Se completed_lessons = 0: recruta_progresso.recruta_id não bate com recrutas.id —
--   verificar QA-01 campo recruta_id_canonico.


-- QA-05 — Ledger XP consistente: xp_granted em progresso = quantidade em xp_eventos
SELECT
    rp.xp_granted AS xp_progresso,
    xe.quantidade  AS xp_ledger,
    rp.xp_granted = xe.quantidade AS ledger_consistente
FROM public.recruta_progresso rp
JOIN public.xp_eventos xe
    ON  xe.referencia_id = rp.lesson_id
    AND xe.recruta_id    = rp.recruta_id
    AND xe.origem        = 'lesson_complete'
WHERE rp.lesson_id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 1 linha, ledger_consistente = true, ambos = 50


-- =============================================================================
-- STEP-06 — Rollback cirúrgico
-- =============================================================================
-- Executar SOMENTE após QA concluído (aprovado ou reprovado).
-- Executar como service_role no SQL Editor.
-- Ordem obrigatória: xp_eventos → recruta_progresso → aulas → modulos.
-- aulas deve ser removida antes de modulos (FK CASCADE, mas explicitamos por segurança).
-- =============================================================================

-- R-01 — Remover XP do ledger (xp_eventos)
DELETE FROM public.xp_eventos
WHERE referencia_id = '00000000-0000-0000-0000-000000010002'
  AND origem        = 'lesson_complete';

-- Verificação R-01:
SELECT COUNT(*) AS deve_ser_zero
FROM public.xp_eventos
WHERE referencia_id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 0


-- R-02 — Remover progresso da aula de teste (recruta_progresso)
DELETE FROM public.recruta_progresso
WHERE lesson_id = '00000000-0000-0000-0000-000000010002';

-- Verificação R-02:
SELECT COUNT(*) AS deve_ser_zero
FROM public.recruta_progresso
WHERE lesson_id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 0


-- R-03 — Remover aula de teste
DELETE FROM public.aulas
WHERE id = '00000000-0000-0000-0000-000000010002';

-- Verificação R-03:
SELECT COUNT(*) AS deve_ser_zero
FROM public.aulas
WHERE id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 0


-- R-04 — Remover módulo de teste
-- (Executar SOMENTE após R-03 — FK constraint aulas.modulo_id → modulos.id)
-- (Se FK for CASCADE DELETE, R-03 pode ser pulado, mas mantemos explicitamente)
DELETE FROM public.modulos
WHERE id = '00000000-0000-0000-0000-000000010001';

-- Verificação R-04:
SELECT COUNT(*) AS deve_ser_zero
FROM public.modulos
WHERE id = '00000000-0000-0000-0000-000000010001';
-- Esperado: 0


-- R-05 — Confirmação final: nenhum rastro dos UUIDs de teste
SELECT
    'modulo' AS tipo,
    id,
    titulo
FROM public.modulos
WHERE id = '00000000-0000-0000-0000-000000010001'

UNION ALL

SELECT 'aula', id, titulo
FROM public.aulas
WHERE id = '00000000-0000-0000-0000-000000010002'

UNION ALL

SELECT 'xp_evento', referencia_id::uuid, origem
FROM public.xp_eventos
WHERE referencia_id = '00000000-0000-0000-0000-000000010002'

UNION ALL

SELECT 'progresso', lesson_id, source
FROM public.recruta_progresso
WHERE lesson_id = '00000000-0000-0000-0000-000000010002';
-- Esperado: 0 linhas — rollback completo.


-- R-06 — (Opcional) Verificar recrutas.xp após rollback
-- Se o trigger de sync xp_eventos → recrutas.xp foi acionado durante QA,
-- o valor de recrutas.xp pode ter sido incrementado em 50.
-- Verificar o valor atual:
SELECT
    id,
    auth_id,
    nome_guerra,
    xp,
    forca
FROM public.recrutas
WHERE id = 'cc41fc7e-ce7d-405d-9178-c14b39e1a017';
-- Se xp foi incrementado indevidamente durante QA e já foi revertido pelo trigger,
-- o valor estará correto automaticamente.
-- Se necessário correção manual:
--   UPDATE public.recrutas SET xp = <valor_anterior> WHERE id = 'cc41fc7e-...';
-- Consultar o DBA antes de executar o UPDATE manual.

-- =============================================================================
-- FIM DO SCRIPT
-- =============================================================================
