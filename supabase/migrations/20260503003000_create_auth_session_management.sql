-- ==============================================================================
-- INFRAESTRUTURA DE SESSÕES INSTITUCIONAIS (RCC v0.3)
-- ==============================================================================
-- Cria tabelas e contratos para:
--   - v_auth_app_config        (AuthContext — leitura de versão do contrato)
--   - auth_client_sessions     (tabela de sessões por dispositivo)
--   - v_auth_session           (sessionGuardian — verifica revogação)
--   - v_auth_active_sessions   (sessionManagementService — lista sessões ativas)
--   - rpc_auth_claim_active_client_session   (AuthContext — registra dispositivo)
--   - rpc_auth_resolve_session_state         (AuthContext — estado institucional)
--   - rpc_auth_revoke_client_session         (sessionManagementService)
-- Data: 03/05/2026
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. TABELA: auth_app_config (Configurações institucionais do app)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.auth_app_config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.auth_app_config ENABLE ROW LEVEL SECURITY;

-- Leitura pública para autenticados (versão do contrato deve ser visível)
DROP POLICY IF EXISTS "Authenticated read app config" ON public.auth_app_config;
CREATE POLICY "Authenticated read app config"
    ON public.auth_app_config FOR SELECT TO authenticated USING (true);

-- Seed: versão do contrato
INSERT INTO public.auth_app_config (key, value)
VALUES ('auth_contract_version', 'RCC-0.3')
ON CONFLICT (key) DO NOTHING;

-- VIEW: v_auth_app_config
-- Frontend: supabase.from('v_auth_app_config').select('auth_contract_version').single()
CREATE OR REPLACE VIEW public.v_auth_app_config AS
SELECT
    MAX(CASE WHEN key = 'auth_contract_version' THEN value END) AS auth_contract_version
FROM public.auth_app_config;

-- ------------------------------------------------------------------------------
-- 2. TABELA: auth_client_sessions (Sessões por dispositivo/instância)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.auth_client_sessions (
    id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    client_instance_id     TEXT        NOT NULL,
    device_name            TEXT        NOT NULL DEFAULT 'Dispositivo Desconhecido',

    -- Estado da sessão
    is_active              BOOLEAN     NOT NULL DEFAULT true,
    last_seen_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Motivo de revogação
    session_revoked_reason TEXT        NOT NULL DEFAULT 'none'
                           CHECK (session_revoked_reason IN ('none','user_action','session_expired','security_logout')),

    -- Flags institucionais
    requires_mfa           BOOLEAN     NOT NULL DEFAULT false,
    account_locked         BOOLEAN     NOT NULL DEFAULT false,
    inactive_user          BOOLEAN     NOT NULL DEFAULT false,
    password_expired       BOOLEAN     NOT NULL DEFAULT false,

    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (user_id, client_instance_id)
);

CREATE INDEX IF NOT EXISTS idx_auth_client_sessions_user
    ON public.auth_client_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_auth_client_sessions_instance
    ON public.auth_client_sessions (client_instance_id);

ALTER TABLE public.auth_client_sessions ENABLE ROW LEVEL SECURITY;

-- Usuário só enxerga suas próprias sessões
DROP POLICY IF EXISTS "User read own sessions" ON public.auth_client_sessions;
CREATE POLICY "User read own sessions"
    ON public.auth_client_sessions FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- Service role acesso total
DROP POLICY IF EXISTS "Service role full access sessions" ON public.auth_client_sessions;
CREATE POLICY "Service role full access sessions"
    ON public.auth_client_sessions FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Trigger updated_at
CREATE OR REPLACE FUNCTION public.fn_auth_session_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS trg_auth_session_updated_at ON public.auth_client_sessions;
CREATE TRIGGER trg_auth_session_updated_at
    BEFORE UPDATE ON public.auth_client_sessions
    FOR EACH ROW EXECUTE FUNCTION public.fn_auth_session_updated_at();

-- ------------------------------------------------------------------------------
-- 3. VIEW: v_auth_session (sessionGuardian)
-- Frontend: supabase.from('v_auth_session').select('*').single()
-- Retorna a sessão ativa do usuário atual.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_auth_session AS
SELECT
    s.id                      AS session_id,
    s.user_id,
    s.client_instance_id,
    s.is_active,
    s.session_revoked_reason,
    s.requires_mfa,
    s.account_locked,
    s.inactive_user,
    s.password_expired,
    s.last_seen_at
FROM public.auth_client_sessions s
WHERE s.user_id = auth.uid()
  AND s.is_active = true
ORDER BY s.last_seen_at DESC;

-- ------------------------------------------------------------------------------
-- 4. VIEW: v_auth_active_sessions (sessionManagementService)
-- Frontend: supabase.from('v_auth_active_sessions').select('*').order('last_seen_at')
-- Retorna: session_id, device_name, last_seen_at, is_current
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_auth_active_sessions AS
SELECT
    s.id                                           AS session_id,
    s.device_name,
    s.last_seen_at,
    -- is_current: verificar via client_instance_id não é possível na view sem contexto.
    -- A coluna retorna false; o frontend identifica a corrente localmente.
    false                                          AS is_current
FROM public.auth_client_sessions s
WHERE s.user_id = auth.uid()
  AND s.is_active = true
ORDER BY s.last_seen_at DESC;

-- ------------------------------------------------------------------------------
-- 5. RPC: rpc_auth_claim_active_client_session
-- Chamada em: AuthContext — evento SIGNED_IN
-- Registra/atualiza a sessão do dispositivo atual.
-- Idempotente: usa ON CONFLICT DO UPDATE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_auth_claim_active_client_session(
    p_client_instance_id TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN RETURN; END IF;

    INSERT INTO public.auth_client_sessions (
        user_id, client_instance_id, is_active, last_seen_at,
        session_revoked_reason
    )
    VALUES (
        v_user_id, p_client_instance_id, true, now(), 'none'
    )
    ON CONFLICT (user_id, client_instance_id) DO UPDATE SET
        is_active              = true,
        last_seen_at           = now(),
        session_revoked_reason = 'none',
        requires_mfa           = false,
        account_locked         = false,
        inactive_user          = false,
        password_expired       = false,
        updated_at             = now();
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. RPC: rpc_auth_resolve_session_state
-- Chamada em: AuthContext — init, SIGNED_IN, AppState 'active'
-- Retorna estado institucional da sessão para decidir fluxo de auth.
-- Idempotente: somente leitura (atualiza last_seen_at para heartbeat)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_auth_resolve_session_state(
    p_client_instance_id TEXT
)
RETURNS TABLE (
    auth_id                UUID,
    session_revoked_reason TEXT,
    requires_mfa           BOOLEAN,
    account_locked         BOOLEAN,
    inactive_user          BOOLEAN,
    password_expired       BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN RETURN; END IF;

    -- Heartbeat: atualiza last_seen_at
    UPDATE public.auth_client_sessions
    SET last_seen_at = now(), updated_at = now()
    WHERE user_id = v_user_id
      AND client_instance_id = p_client_instance_id;

    RETURN QUERY
    SELECT
        s.user_id             AS auth_id,
        s.session_revoked_reason,
        s.requires_mfa,
        s.account_locked,
        s.inactive_user,
        s.password_expired
    FROM public.auth_client_sessions s
    WHERE s.user_id = v_user_id
      AND s.client_instance_id = p_client_instance_id
    LIMIT 1;
END;
$$;

-- ------------------------------------------------------------------------------
-- 7. RPC: rpc_auth_revoke_client_session
-- Chamada em: sessionManagementService — usuário revoga sessão
-- Idempotente: UPDATE por session_id; ignora se já revogada
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_auth_revoke_client_session(
    p_session_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.auth_client_sessions
    SET
        is_active              = false,
        session_revoked_reason = 'user_action',
        updated_at             = now()
    WHERE id = p_session_id
      AND user_id = auth.uid();  -- Garante que usuário só revoga suas próprias sessões
END;
$$;

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.v_auth_app_config;
-- SELECT * FROM public.v_auth_session;
-- SELECT * FROM public.v_auth_active_sessions;
-- SELECT public.rpc_auth_claim_active_client_session('test-instance-id');
-- SELECT * FROM public.rpc_auth_resolve_session_state('test-instance-id');

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_auth_active_sessions;
-- DROP VIEW IF EXISTS public.v_auth_session;
-- DROP VIEW IF EXISTS public.v_auth_app_config;
-- DROP FUNCTION IF EXISTS public.rpc_auth_revoke_client_session(UUID);
-- DROP FUNCTION IF EXISTS public.rpc_auth_resolve_session_state(TEXT);
-- DROP FUNCTION IF EXISTS public.rpc_auth_claim_active_client_session(TEXT);
-- DROP TABLE IF EXISTS public.auth_client_sessions;
-- DROP TABLE IF EXISTS public.auth_app_config;
