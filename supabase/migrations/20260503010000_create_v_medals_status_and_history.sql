-- ==============================================================================
-- v_medals_status E v_historico_atividade_recruta
-- ==============================================================================
-- Cria:
--   - v_medals_status                  (useMedals — status de medalhas com nível)
--   - v_historico_atividade_recruta    (nova view READ-ONLY para useStudentHistory)
--   - v_historico_progresso_recruta    (useHistory — timeline de progresso)
-- Data: 03/05/2026
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. v_medals_status
-- useMedals: .from('v_medals_status').select('*').order('name')
-- Frontend espera: medal_id, name, description, level ('none'|'bronze'|'silver'|'gold'), achieved
--
-- NOTA: Sistema de medalhas (C5) define only bronze/silver/gold.
--       O campo 'level' é derivado do campo 'codigo' da medalha (convenção do catálogo).
--       Medalhas com código contendo '-bronze'/'-silver'/'-gold' são identificadas.
--       Medalhas sem sufixo de nível retornam 'bronze' como fallback.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_medals_status AS
SELECT
    m.id                                            AS medal_id,
    m.nome                                          AS name,
    m.descricao                                     AS description,
    -- Nível derivado do sufixo do código da medalha (convenção do catálogo)
    CASE
        WHEN m.codigo ILIKE '%-gold'   THEN 'gold'
        WHEN m.codigo ILIKE '%-silver' THEN 'silver'
        WHEN m.codigo ILIKE '%-bronze' THEN 'bronze'
        ELSE 'bronze'                               -- fallback: bronze para medalhas simples
    END                                             AS level,
    CASE WHEN rm.medalha_id IS NOT NULL THEN true ELSE false END AS achieved
FROM public.medalhas m
LEFT JOIN public.recruta_medalhas rm
    ON  rm.medalha_id = m.id
    AND rm.recruta_id = auth.uid()
WHERE m.ativo = true;

-- ------------------------------------------------------------------------------
-- 2. v_historico_atividade_recruta
-- NOVA VIEW READ-ONLY criada para substituir v_audit_eventos no useStudentHistory.
-- v_audit_eventos é uma writeable view com trigger — mantida intacta.
-- Esta view expõe o histórico de atividade do recruta com os campos que o
-- frontend espera: id, event_type, title, description, created_at
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_historico_atividade_recruta AS

-- Aulas concluídas
SELECT
    rp.id::text                         AS id,
    'lesson'::text                      AS event_type,
    a.title                             AS title,
    'Aula concluída'::text              AS description,
    rp.created_at
FROM public.recruta_progresso rp
JOIN public.aulas a ON a.id = rp.lesson_id
WHERE rp.recruta_id = auth.uid()

UNION ALL

-- XP recebidos
SELECT
    xe.id::text                         AS id,
    'xp'::text                          AS event_type,
    xe.description                      AS title,
    ('+ ' || xe.amount::text || ' XP')  AS description,
    xe.created_at
FROM public.xp_eventos xe
WHERE xe.recruta_id = auth.uid()

UNION ALL

-- Medalhas conquistadas
SELECT
    rm.id::text                         AS id,
    'medal'::text                       AS event_type,
    m.nome                              AS title,
    COALESCE(m.descricao, 'Medalha conquistada') AS description,
    rm.concedido_em                     AS created_at
FROM public.recruta_medalhas rm
JOIN public.medalhas m ON m.id = rm.medalha_id
WHERE rm.recruta_id = auth.uid()

UNION ALL

-- Promoções de patente
SELECT
    rp.id::text                         AS id,
    'system'::text                      AS event_type,
    ('Promovido: ' || pc.titulo)        AS title,
    ('Patente nível ' || pc.nivel::text) AS description,
    rp.promovido_em                     AS created_at
FROM public.recruta_patentes rp
JOIN public.patentes_catalogo pc ON pc.id = rp.patente_id
WHERE rp.recruta_id = auth.uid()

ORDER BY created_at DESC;

-- ------------------------------------------------------------------------------
-- 3. v_historico_progresso_recruta
-- useHistory: .from('v_historico_progresso_recruta').select('*')
-- Frontend espera: id, created_at, description, impacto, referencia, source_id
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_historico_progresso_recruta AS

-- Aulas concluídas
SELECT
    rp.id::text                         AS id,
    rp.created_at,
    ('Aula concluída: ' || a.title)     AS description,
    rp.xp_granted                       AS impacto,
    'aula'::text                        AS referencia,
    rp.lesson_id::text                  AS source_id
FROM public.recruta_progresso rp
JOIN public.aulas a ON a.id = rp.lesson_id
WHERE rp.recruta_id = auth.uid()

UNION ALL

-- Eventos XP (bonus, módulos, etc.)
SELECT
    xe.id::text                         AS id,
    xe.created_at,
    xe.description,
    xe.amount                           AS impacto,
    'xp'::text                          AS referencia,
    xe.source_id
FROM public.xp_eventos xe
WHERE xe.recruta_id = auth.uid()

UNION ALL

-- Medalhas
SELECT
    rm.id::text                         AS id,
    rm.concedido_em                     AS created_at,
    ('Medalha: ' || m.nome)             AS description,
    NULL                                AS impacto,
    'medalha'::text                     AS referencia,
    m.codigo                            AS source_id
FROM public.recruta_medalhas rm
JOIN public.medalhas m ON m.id = rm.medalha_id
WHERE rm.recruta_id = auth.uid()

ORDER BY created_at DESC;

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.v_medals_status LIMIT 10;
-- SELECT * FROM public.v_historico_atividade_recruta LIMIT 10;
-- SELECT * FROM public.v_historico_progresso_recruta LIMIT 10;

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_historico_progresso_recruta;
-- DROP VIEW IF EXISTS public.v_historico_atividade_recruta;
-- DROP VIEW IF EXISTS public.v_medals_status;
