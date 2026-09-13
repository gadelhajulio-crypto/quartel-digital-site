-- ==============================================================================
-- P1 — Correção de IDOR em views canônicas de frontend (RCC)
-- ==============================================================================
-- Achado: v_lesson_progress_panel, v_medals_status_v3 e
-- v_historico_atividade_recruta_v3 são OWNER postgres, sem security_invoker e
-- sem filtro por dono no corpo da view. Qualquer authenticated com GRANT SELECT
-- na view lê linhas de qualquer recruta, porque a RLS das tabelas-base
-- (recruta_progresso, xp_eventos, medalhas_concedidas) não se aplica a uma view
-- executada como owner. Confirmado por leitura de schema (dump
-- 2026-09-12, SHA-256 2a471d0e41e1c73bc967a80e873b87638c0e6c7258487c93f3a31b8fe88b1701),
-- sem consulta a dados reais.
--
-- Estratégia: manter a view owner-executed (não usar security_invoker=true),
-- e adicionar filtro EXISTS correlacionado por recrutas.auth_id = auth.uid()
-- dentro do próprio corpo da view. Nenhuma tabela-base recebe grant novo —
-- continuam acessíveis só por service_role, exatamente como hoje.
--
-- v_recruta_xp_total NÃO é alterada nesta migration: v_ranking_force_v2 e
-- v_ranking_global_v2 dependem dela via JOIN, e um filtro por auth.uid()
-- quebraria essas duas views (viram single-row por chamador em vez de ranking).
-- Confirmado no dump: v_ranking_force_v2 e v_ranking_global_v2 NÃO têm nenhum
-- GRANT explícito para nenhum papel (nem anon, nem authenticated, nem
-- service_role) — são estruturalmente inalcançáveis via API hoje, então a
-- única ação segura e suficiente é revogar o SELECT direto de `authenticated`
-- em v_recruta_xp_total; o JOIN interno das views de ranking (executadas como
-- owner postgres) continua funcionando de qualquer forma.
--
-- Colunas, ordem, tipos, owner e comentários das três views corrigidas são
-- preservados exatamente como no schema atual — só a cláusula WHERE muda.
-- ==============================================================================

-- ── 1. v_lesson_progress_panel ────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
SELECT
    rp.recruta_id AS user_id,
    rp.lesson_id,
    rp.completed_at,
    rp.recruta_id,
    rp.xp_granted,
    rp.source
FROM public.recruta_progresso rp
WHERE rp.status = 'completed'
  AND rp.completed_at IS NOT NULL
  AND (
    EXISTS (
      SELECT 1
      FROM public.recrutas r
      WHERE r.id = rp.recruta_id
        AND r.auth_id = auth.uid()
    )
    OR auth.role() = 'service_role'
  );

COMMENT ON VIEW public.v_lesson_progress_panel IS
  'CANONICAL RCC FRONTEND VIEW. Lesson progress projection, scoped to caller recruta (fix P1-IDOR-01, 2026-09-13). Frontend may SELECT through authenticated role.';

-- Grants preservados como estavam (nenhuma alteração necessária):
--   GRANT ALL ON TABLE public.v_lesson_progress_panel TO service_role;
--   GRANT SELECT ON TABLE public.v_lesson_progress_panel TO authenticated;

-- ── 2. v_medals_status_v3 ─────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_medals_status_v3 AS
SELECT
    mc.recruta_id,
    mc.medalha_id,
    cat.slug AS medalha_slug,
    cat.titulo AS medal_name,
    cat.descricao AS medal_description,
    cat.categoria,
    cat.icon_url,
    cat.active AS ativo,
    mc.granted_at AS conquistada_em,
    true AS conquistada
FROM public.medalhas_concedidas mc
JOIN public.medalhas_catalogo cat ON cat.id = mc.medalha_id
WHERE (
    EXISTS (
      SELECT 1
      FROM public.recrutas r
      WHERE r.id = mc.recruta_id
        AND r.auth_id = auth.uid()
    )
    OR auth.role() = 'service_role'
  );

COMMENT ON VIEW public.v_medals_status_v3 IS
  'CANONICAL RCC FRONTEND VIEW. Medal status projection, scoped to caller recruta (fix P1-IDOR-02, 2026-09-13). Frontend may SELECT through authenticated role.';

-- Grant preservado como estava: GRANT SELECT ON TABLE public.v_medals_status_v3 TO authenticated;

-- ── 3. v_historico_atividade_recruta_v3 ──────────────────────────────────────

CREATE OR REPLACE VIEW public.v_historico_atividade_recruta_v3 AS
SELECT
    rp.id,
    rp.recruta_id,
    'progresso'::text AS event_type,
    'Aula concluída'::text AS title,
    ('Aula concluída em '::text || rp.lesson_id) AS description,
    rp.completed_at AS created_at
FROM public.recruta_progresso rp
WHERE rp.status = 'completed'
  AND (
    EXISTS (
      SELECT 1
      FROM public.recrutas r
      WHERE r.id = rp.recruta_id
        AND r.auth_id = auth.uid()
    )
    OR auth.role() = 'service_role'
  )
UNION ALL
SELECT
    xe.id,
    xe.recruta_id,
    'xp'::text AS event_type,
    'XP recebido'::text AS title,
    ('Ganho de XP: '::text || xe.quantidade) AS description,
    xe.created_at
FROM public.xp_eventos xe
WHERE (
    EXISTS (
      SELECT 1
      FROM public.recrutas r
      WHERE r.id = xe.recruta_id
        AND r.auth_id = auth.uid()
    )
    OR auth.role() = 'service_role'
  );

COMMENT ON VIEW public.v_historico_atividade_recruta_v3 IS
  'CANONICAL RCC FRONTEND VIEW. Activity history projection, scoped to caller recruta em ambos os braços do UNION (fix P1-IDOR-03, 2026-09-13). Frontend may SELECT through authenticated role.';

-- Grant preservado como estava: GRANT SELECT ON TABLE public.v_historico_atividade_recruta_v3 TO authenticated;

-- ── 4. v_recruta_xp_total — só revogar o SELECT direto de authenticated ────────
-- Definição da view NÃO é tocada (ver justificativa no cabeçalho).

REVOKE SELECT ON TABLE public.v_recruta_xp_total FROM authenticated;

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
--   SELECT recruta_id AS user_id, lesson_id, completed_at, recruta_id, xp_granted, source
--   FROM public.recruta_progresso
--   WHERE status = 'completed' AND completed_at IS NOT NULL;
-- COMMENT ON VIEW public.v_lesson_progress_panel IS 'CANONICAL RCC FRONTEND VIEW. Lesson progress projection. Frontend may SELECT through authenticated role.';
--
-- CREATE OR REPLACE VIEW public.v_medals_status_v3 AS
--   SELECT mc.recruta_id, mc.medalha_id, cat.slug AS medalha_slug, cat.titulo AS medal_name,
--          cat.descricao AS medal_description, cat.categoria, cat.icon_url,
--          cat.active AS ativo, mc.granted_at AS conquistada_em, true AS conquistada
--   FROM public.medalhas_concedidas mc
--   JOIN public.medalhas_catalogo cat ON cat.id = mc.medalha_id;
-- COMMENT ON VIEW public.v_medals_status_v3 IS 'CANONICAL RCC FRONTEND VIEW. Medal status projection. Frontend may SELECT through authenticated role.';
--
-- CREATE OR REPLACE VIEW public.v_historico_atividade_recruta_v3 AS
--   SELECT rp.id, rp.recruta_id, 'progresso'::text AS event_type, 'Aula concluída'::text AS title,
--          ('Aula concluída em '::text || rp.lesson_id) AS description, rp.completed_at AS created_at
--   FROM public.recruta_progresso rp WHERE rp.status = 'completed'
--   UNION ALL
--   SELECT xe.id, xe.recruta_id, 'xp'::text, 'XP recebido'::text,
--          ('Ganho de XP: '::text || xe.quantidade), xe.created_at
--   FROM public.xp_eventos xe;
-- COMMENT ON VIEW public.v_historico_atividade_recruta_v3 IS 'CANONICAL RCC FRONTEND VIEW. Activity history projection. Frontend may SELECT through authenticated role.';
--
-- GRANT SELECT ON TABLE public.v_recruta_xp_total TO authenticated;

-- ==============================================================================
-- TESTES (não executados nesta migration; ver plano de teste em anexo à PR)
-- ==============================================================================
-- Com dois usuários autenticados de Forças diferentes (ambiente de teste):
--   SELECT * FROM public.v_lesson_progress_panel;              -- só a própria linha
--   SELECT * FROM public.v_medals_status_v3;                   -- só a própria linha
--   SELECT * FROM public.v_historico_atividade_recruta_v3;     -- só a própria linha
--   SELECT * FROM public.v_recruta_xp_total;                   -- erro de permissão (grant revogado)
