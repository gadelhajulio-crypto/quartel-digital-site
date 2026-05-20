-- RCC Wave 1 — Chat Institucional: Schema Completo
-- Tabelas: chat_conversas, chat_mensagens, chat_unread_status
-- Views:   v_chat_conversas_recruta, v_chat_mensagens_recruta, v_chat_unread_status
-- RPCs:    rpc_chat_open_conversation, rpc_chat_send_message, rpc_chat_mark_read
--
-- Contrato de identidade: recruta resolvido via WHERE auth_id = auth.uid()
-- (nunca WHERE id = auth.uid() — id é UUID próprio, auth_id é o vínculo com auth)
-- RPCs: SECURITY DEFINER para bypass de RLS em escrita.
-- Views:  filtram por recruta_id derivado de auth.uid() — sem SECURITY DEFINER.

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. DROP PREVENTIVO (caso existam versões legadas com schema diferente)
-- ─────────────────────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS public.v_chat_conversas_recruta  CASCADE;
DROP VIEW IF EXISTS public.v_chat_mensagens_recruta  CASCADE;
DROP VIEW IF EXISTS public.v_chat_unread_status      CASCADE;

DROP TABLE IF EXISTS public.chat_unread_status CASCADE;
DROP TABLE IF EXISTS public.chat_mensagens     CASCADE;
DROP TABLE IF EXISTS public.chat_conversas     CASCADE;

DROP FUNCTION IF EXISTS public.rpc_chat_open_conversation(TEXT)                            CASCADE;
DROP FUNCTION IF EXISTS public.rpc_chat_send_message(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB)  CASCADE;
DROP FUNCTION IF EXISTS public.rpc_chat_mark_read(UUID)                                    CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TABELAS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE public.chat_conversas (
  conversa_id     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  recruta_id      UUID        NOT NULL REFERENCES public.recrutas(id) ON DELETE CASCADE,
  instrutor_slug  TEXT        NOT NULL,         -- codigo do instrutor: objetivo/estrategico/didatico
  status          TEXT        NOT NULL DEFAULT 'ativa',
  opened_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_message_at TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_chat_conversas_recruta_instrutor UNIQUE (recruta_id, instrutor_slug)
);

CREATE TABLE public.chat_mensagens (
  mensagem_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversa_id       UUID        NOT NULL REFERENCES public.chat_conversas(conversa_id) ON DELETE CASCADE,
  recruta_id        UUID        NOT NULL,
  instrutor_slug    TEXT        NOT NULL,
  role              TEXT        NOT NULL CHECK (role IN ('user', 'assistant')),
  conteudo          TEXT        NOT NULL,
  status            TEXT        NOT NULL DEFAULT 'sent',
  client_message_id TEXT,
  correlation_id    TEXT,
  origem            TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índice de idempotência: mesmo client_message_id+role não pode ser inserido duas vezes.
-- Partial (WHERE NOT NULL) porque client_message_id pode ser nulo em mensagens legadas.
CREATE UNIQUE INDEX uq_mensagens_cmi_role
  ON public.chat_mensagens(client_message_id, role)
  WHERE client_message_id IS NOT NULL;

CREATE TABLE public.chat_unread_status (
  conversa_id    UUID        PRIMARY KEY REFERENCES public.chat_conversas(conversa_id) ON DELETE CASCADE,
  recruta_id     UUID        NOT NULL,
  instrutor_slug TEXT        NOT NULL,
  unread_count   INT         NOT NULL DEFAULT 0,
  last_read_at   TIMESTAMPTZ,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. ÍNDICES DE PERFORMANCE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE INDEX idx_chat_conversas_recruta
  ON public.chat_conversas(recruta_id);

CREATE INDEX idx_chat_mensagens_conversa_created
  ON public.chat_mensagens(conversa_id, created_at);

CREATE INDEX idx_chat_mensagens_recruta
  ON public.chat_mensagens(recruta_id);

CREATE INDEX idx_chat_unread_recruta
  ON public.chat_unread_status(recruta_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RLS
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.chat_conversas     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_mensagens     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_unread_status ENABLE ROW LEVEL SECURITY;

-- Recruta lê as próprias conversas (views já filtram, mas RLS é camada extra).
DROP POLICY IF EXISTS "recruta_select_own_conversas"     ON public.chat_conversas;
DROP POLICY IF EXISTS "recruta_select_own_mensagens"     ON public.chat_mensagens;
DROP POLICY IF EXISTS "recruta_select_own_unread_status" ON public.chat_unread_status;

CREATE POLICY "recruta_select_own_conversas" ON public.chat_conversas
  FOR SELECT TO authenticated
  USING (
    recruta_id = (SELECT id FROM public.recrutas WHERE auth_id = auth.uid())
  );

CREATE POLICY "recruta_select_own_mensagens" ON public.chat_mensagens
  FOR SELECT TO authenticated
  USING (
    recruta_id = (SELECT id FROM public.recrutas WHERE auth_id = auth.uid())
  );

CREATE POLICY "recruta_select_own_unread_status" ON public.chat_unread_status
  FOR SELECT TO authenticated
  USING (
    recruta_id = (SELECT id FROM public.recrutas WHERE auth_id = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. VIEWS (contratos de leitura)
-- ─────────────────────────────────────────────────────────────────────────────

-- v_chat_conversas_recruta
-- Inclui nome/titulo do instrutor e status de unread.
-- Filtrada por auth.uid() → recruta_id.
CREATE OR REPLACE VIEW public.v_chat_conversas_recruta AS
SELECT
  cc.conversa_id,
  cc.recruta_id,
  cc.instrutor_slug,
  COALESCE(i.nome,   cc.instrutor_slug) AS instrutor_nome,
  COALESCE(i.titulo, '')               AS instrutor_titulo,
  NULL::TEXT                           AS avatar_asset_tipo,
  NULL::TEXT                           AS chat_icon_asset_tipo,
  cc.status,
  COALESCE(us.unread_count, 0)         AS unread_count,
  COALESCE(us.unread_count, 0) > 0     AS has_unread,
  cc.opened_at,
  cc.last_message_at,
  cc.updated_at
FROM public.chat_conversas cc
LEFT JOIN public.instrutores i
  ON i.codigo = cc.instrutor_slug
LEFT JOIN public.chat_unread_status us
  ON us.conversa_id = cc.conversa_id
WHERE cc.recruta_id = (
  SELECT id FROM public.recrutas WHERE auth_id = auth.uid()
);

-- v_chat_mensagens_recruta
-- Mensagens da conversa, filtradas por recruta autenticado.
CREATE OR REPLACE VIEW public.v_chat_mensagens_recruta AS
SELECT
  m.mensagem_id,
  m.conversa_id,
  m.recruta_id,
  m.instrutor_slug,
  m.role,
  m.conteudo,
  m.status,
  m.client_message_id,
  m.correlation_id,
  m.origem,
  m.created_at
FROM public.chat_mensagens m
WHERE m.recruta_id = (
  SELECT id FROM public.recrutas WHERE auth_id = auth.uid()
);

-- v_chat_unread_status
-- Status de unread por conversa, filtrado por recruta autenticado.
CREATE OR REPLACE VIEW public.v_chat_unread_status AS
SELECT
  us.conversa_id,
  us.recruta_id,
  us.instrutor_slug,
  us.unread_count,
  us.unread_count > 0 AS has_unread,
  us.last_read_at,
  us.updated_at
FROM public.chat_unread_status us
WHERE us.recruta_id = (
  SELECT id FROM public.recrutas WHERE auth_id = auth.uid()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RPCs (contratos de escrita)
-- ─────────────────────────────────────────────────────────────────────────────

-- rpc_chat_open_conversation
-- Cria ou recupera uma conversa para o recruta+instrutor.
-- Idempotente: ON CONFLICT retorna o conversa_id existente.
CREATE OR REPLACE FUNCTION public.rpc_chat_open_conversation(
  p_instrutor_slug TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recruta_id UUID;
  v_conversa_id UUID;
  v_status TEXT;
BEGIN
  -- Resolver recruta via auth_id canônico
  SELECT id INTO v_recruta_id
  FROM public.recrutas
  WHERE auth_id = auth.uid();

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'recruta_not_found';
  END IF;

  -- Upsert conversa: cria se não existe, retorna existente se já existe
  INSERT INTO public.chat_conversas(recruta_id, instrutor_slug)
  VALUES (v_recruta_id, p_instrutor_slug)
  ON CONFLICT ON CONSTRAINT uq_chat_conversas_recruta_instrutor
  DO UPDATE SET updated_at = NOW()
  RETURNING conversa_id, status INTO v_conversa_id, v_status;

  RETURN json_build_object(
    'conversa_id', v_conversa_id,
    'status',      v_status
  );
END;
$$;

-- rpc_chat_send_message
-- Persiste o par user+assistant de forma idempotente.
-- Chamada por instrutor-send após resposta do Chat Central.
-- Retorna conversa_id e mensagem_id da mensagem do assistant.
CREATE OR REPLACE FUNCTION public.rpc_chat_send_message(
  p_instrutor_slug    TEXT,
  p_client_message_id TEXT,
  p_user_text         TEXT,
  p_assistant_text    TEXT,
  p_correlation_id    TEXT,
  p_metadata          JSONB DEFAULT '{}'::JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recruta_id         UUID;
  v_conversa_id        UUID;
  v_user_mensagem_id   UUID;
  v_asst_mensagem_id   UUID;
BEGIN
  -- Resolver recruta via auth_id canônico
  SELECT id INTO v_recruta_id
  FROM public.recrutas
  WHERE auth_id = auth.uid();

  IF v_recruta_id IS NULL THEN
    RAISE EXCEPTION 'recruta_not_found';
  END IF;

  -- Upsert conversa (cria se não existe, marca last_message_at)
  INSERT INTO public.chat_conversas(recruta_id, instrutor_slug, last_message_at)
  VALUES (v_recruta_id, p_instrutor_slug, NOW())
  ON CONFLICT ON CONSTRAINT uq_chat_conversas_recruta_instrutor
  DO UPDATE SET
    last_message_at = NOW(),
    updated_at      = NOW()
  RETURNING conversa_id INTO v_conversa_id;

  -- Inserir mensagem do usuário (idempotente via partial unique index)
  INSERT INTO public.chat_mensagens(
    conversa_id, recruta_id, instrutor_slug,
    role, conteudo, client_message_id, correlation_id, origem
  )
  VALUES (
    v_conversa_id, v_recruta_id, p_instrutor_slug,
    'user', p_user_text, p_client_message_id, p_correlation_id, 'app'
  )
  ON CONFLICT (client_message_id, role)
  WHERE client_message_id IS NOT NULL
  DO NOTHING;

  -- Recuperar mensagem_id do user (inserida agora ou já existente)
  SELECT mensagem_id INTO v_user_mensagem_id
  FROM public.chat_mensagens
  WHERE conversa_id = v_conversa_id
    AND role = 'user'
    AND client_message_id = p_client_message_id;

  -- Inserir mensagem do assistant (idempotente)
  INSERT INTO public.chat_mensagens(
    conversa_id, recruta_id, instrutor_slug,
    role, conteudo, client_message_id, correlation_id, origem
  )
  VALUES (
    v_conversa_id, v_recruta_id, p_instrutor_slug,
    'assistant', p_assistant_text, p_client_message_id, p_correlation_id, 'instrutor-send'
  )
  ON CONFLICT (client_message_id, role)
  WHERE client_message_id IS NOT NULL
  DO NOTHING;

  -- Recuperar mensagem_id do assistant
  SELECT mensagem_id INTO v_asst_mensagem_id
  FROM public.chat_mensagens
  WHERE conversa_id = v_conversa_id
    AND role = 'assistant'
    AND client_message_id = p_client_message_id;

  -- Upsert unread_status: incrementa apenas se assistente ainda não foi lido
  INSERT INTO public.chat_unread_status(conversa_id, recruta_id, instrutor_slug, unread_count)
  VALUES (v_conversa_id, v_recruta_id, p_instrutor_slug, 1)
  ON CONFLICT (conversa_id)
  DO UPDATE SET
    unread_count = chat_unread_status.unread_count + 1,
    updated_at   = NOW();

  RETURN json_build_object(
    'conversa_id', v_conversa_id,
    'mensagem_id', v_asst_mensagem_id
  );
END;
$$;

-- rpc_chat_mark_read
-- Zera unread_count da conversa para o recruta autenticado.
-- Idempotente.
CREATE OR REPLACE FUNCTION public.rpc_chat_mark_read(
  p_conversa_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recruta_id UUID;
BEGIN
  SELECT id INTO v_recruta_id
  FROM public.recrutas
  WHERE auth_id = auth.uid();

  IF v_recruta_id IS NULL THEN
    RETURN; -- silencioso: sem recruta, sem-op
  END IF;

  UPDATE public.chat_unread_status
  SET
    unread_count = 0,
    last_read_at = NOW(),
    updated_at   = NOW()
  WHERE conversa_id = p_conversa_id
    AND recruta_id  = v_recruta_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. GRANTS
-- ─────────────────────────────────────────────────────────────────────────────

GRANT SELECT ON public.v_chat_conversas_recruta TO authenticated;
GRANT SELECT ON public.v_chat_mensagens_recruta  TO authenticated;
GRANT SELECT ON public.v_chat_unread_status      TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_chat_open_conversation(TEXT)                            TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_chat_send_message(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_chat_mark_read(UUID)                                    TO authenticated;
