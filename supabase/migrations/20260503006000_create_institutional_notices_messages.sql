-- ==============================================================================
-- AVISOS INSTITUCIONAIS E MENSAGENS DO INSTRUTOR
-- ==============================================================================
-- Cria:
--   - institutional_notices          (tabela de avisos)
--   - institutional_notice_reads     (ledger de leituras)
--   - v_institutional_notices        (view por recruta atual)
--   - instructor_messages            (tabela de mensagens)
--   - instructor_message_reads       (ledger de leituras)
--   - v_instructor_messages          (view por recruta atual)
--   - rpc_mark_notice_read           (substitui INSERT direto)
--   - rpc_mark_instructor_message_read (substitui INSERT direto)
-- Data: 03/05/2026
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. AVISOS INSTITUCIONAIS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.institutional_notices (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    title         TEXT        NOT NULL,
    body          TEXT        NOT NULL DEFAULT '',
    priority      INTEGER     NOT NULL DEFAULT 0,
    deep_link     TEXT,
    target_forca  TEXT[],               -- NULL = todas as forças
    ativo         BOOLEAN     NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ            -- NULL = sem expiração
);

CREATE INDEX IF NOT EXISTS idx_institutional_notices_ativo
    ON public.institutional_notices (ativo) WHERE ativo = true;

ALTER TABLE public.institutional_notices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read notices" ON public.institutional_notices;
CREATE POLICY "Authenticated read notices"
    ON public.institutional_notices FOR SELECT TO authenticated
    USING (
        ativo = true
        AND (expires_at IS NULL OR expires_at > now())
    );

DROP POLICY IF EXISTS "Service role full notices" ON public.institutional_notices;
CREATE POLICY "Service role full notices"
    ON public.institutional_notices FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Ledger de leituras
CREATE TABLE IF NOT EXISTS public.institutional_notice_reads (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    notice_id  UUID        NOT NULL REFERENCES public.institutional_notices(id) ON DELETE CASCADE,
    recruta_id UUID        NOT NULL REFERENCES public.recrutas(id) ON DELETE CASCADE,
    read_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (notice_id, recruta_id)
);

CREATE INDEX IF NOT EXISTS idx_notice_reads_recruta
    ON public.institutional_notice_reads (recruta_id);

ALTER TABLE public.institutional_notice_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User read own notice reads" ON public.institutional_notice_reads;
CREATE POLICY "User read own notice reads"
    ON public.institutional_notice_reads FOR SELECT TO authenticated
    USING (recruta_id = auth.uid());

DROP POLICY IF EXISTS "Service role full notice reads" ON public.institutional_notice_reads;
CREATE POLICY "Service role full notice reads"
    ON public.institutional_notice_reads FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- VIEW: v_institutional_notices
-- Frontend: .from('v_institutional_notices').select('*').order('priority').order('created_at')
-- Campos: notice_id, title, body, created_at, priority, deep_link, is_read
CREATE OR REPLACE VIEW public.v_institutional_notices AS
SELECT
    n.id                                           AS notice_id,
    n.title,
    n.body,
    n.created_at,
    n.priority,
    n.deep_link,
    CASE WHEN r.notice_id IS NOT NULL THEN true ELSE false END AS is_read
FROM public.institutional_notices n
LEFT JOIN public.institutional_notice_reads r
    ON  r.notice_id  = n.id
    AND r.recruta_id = auth.uid()
WHERE n.ativo = true
  AND (n.expires_at IS NULL OR n.expires_at > now())
  AND (n.target_forca IS NULL
       OR auth.uid() IN (
           SELECT id FROM public.recrutas
           WHERE forca = ANY(n.target_forca)
             AND id = auth.uid()
       ));

-- RPC: rpc_mark_notice_read — substitui INSERT direto em institutional_notice_reads
CREATE OR REPLACE FUNCTION public.rpc_mark_notice_read(
    p_notice_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.institutional_notice_reads (notice_id, recruta_id)
    VALUES (p_notice_id, auth.uid())
    ON CONFLICT (notice_id, recruta_id) DO NOTHING;
END;
$$;

-- ------------------------------------------------------------------------------
-- 2. MENSAGENS DO INSTRUTOR
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.instructor_messages (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    recruta_id           UUID        NOT NULL REFERENCES public.recrutas(id) ON DELETE CASCADE,
    instructor_profile_id TEXT       NOT NULL
                         CHECK (instructor_profile_id IN ('objetivo','estrategico','didatico')),
    title                TEXT        NOT NULL,
    body                 TEXT        NOT NULL DEFAULT '',
    deep_link            TEXT,
    ativo                BOOLEAN     NOT NULL DEFAULT true,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_instructor_messages_recruta
    ON public.instructor_messages (recruta_id);

ALTER TABLE public.instructor_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User read own messages" ON public.instructor_messages;
CREATE POLICY "User read own messages"
    ON public.instructor_messages FOR SELECT TO authenticated
    USING (recruta_id = auth.uid() AND ativo = true);

DROP POLICY IF EXISTS "Service role full messages" ON public.instructor_messages;
CREATE POLICY "Service role full messages"
    ON public.instructor_messages FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Ledger de leituras
CREATE TABLE IF NOT EXISTS public.instructor_message_reads (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID        NOT NULL REFERENCES public.instructor_messages(id) ON DELETE CASCADE,
    recruta_id UUID        NOT NULL REFERENCES public.recrutas(id) ON DELETE CASCADE,
    read_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (message_id, recruta_id)
);

ALTER TABLE public.instructor_message_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User read own message reads" ON public.instructor_message_reads;
CREATE POLICY "User read own message reads"
    ON public.instructor_message_reads FOR SELECT TO authenticated
    USING (recruta_id = auth.uid());

DROP POLICY IF EXISTS "Service role full message reads" ON public.instructor_message_reads;
CREATE POLICY "Service role full message reads"
    ON public.instructor_message_reads FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- VIEW: v_instructor_messages
-- Frontend: .from('v_instructor_messages').select('*').order('created_at', {ascending: false})
-- Campos: message_id, title, body, created_at, deep_link, is_read
CREATE OR REPLACE VIEW public.v_instructor_messages AS
SELECT
    m.id                                           AS message_id,
    m.title,
    m.body,
    m.created_at,
    m.deep_link,
    CASE WHEN r.message_id IS NOT NULL THEN true ELSE false END AS is_read
FROM public.instructor_messages m
LEFT JOIN public.instructor_message_reads r
    ON  r.message_id = m.id
    AND r.recruta_id = auth.uid()
WHERE m.recruta_id = auth.uid()
  AND m.ativo = true;

-- RPC: rpc_mark_instructor_message_read — substitui INSERT direto
CREATE OR REPLACE FUNCTION public.rpc_mark_instructor_message_read(
    p_message_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.instructor_message_reads (message_id, recruta_id)
    VALUES (p_message_id, auth.uid())
    ON CONFLICT (message_id, recruta_id) DO NOTHING;
END;
$$;

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.v_institutional_notices;
-- SELECT * FROM public.v_instructor_messages;
-- SELECT public.rpc_mark_notice_read('<uuid>');
-- SELECT public.rpc_mark_instructor_message_read('<uuid>');

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_instructor_messages;
-- DROP VIEW IF EXISTS public.v_institutional_notices;
-- DROP FUNCTION IF EXISTS public.rpc_mark_instructor_message_read(UUID);
-- DROP FUNCTION IF EXISTS public.rpc_mark_notice_read(UUID);
-- DROP TABLE IF EXISTS public.instructor_message_reads;
-- DROP TABLE IF EXISTS public.instructor_messages;
-- DROP TABLE IF EXISTS public.institutional_notice_reads;
-- DROP TABLE IF EXISTS public.institutional_notices;
