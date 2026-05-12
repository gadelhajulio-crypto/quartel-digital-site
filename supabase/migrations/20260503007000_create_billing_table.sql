-- ==============================================================================
-- BILLING: recruta_billing + v_billing_status_recruta
-- ==============================================================================
-- Frontend: billingService.ts — .from('v_billing_status_recruta')
--   .select('acesso_liberado, plano_atual, status_assinatura, validade, trial_restante')
--   .single()
-- Data: 03/05/2026
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.recruta_billing (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    recruta_id          UUID        NOT NULL REFERENCES public.recrutas(id) ON DELETE CASCADE,

    acesso_liberado     BOOLEAN     NOT NULL DEFAULT false,
    plano_atual         TEXT,                    -- 'mensal', 'anual', NULL
    status_assinatura   TEXT,                    -- 'active', 'canceled', 'expired', 'trialing', NULL
    validade            TIMESTAMPTZ,             -- data de expiração do plano ativo
    trial_restante      INTEGER     DEFAULT 0,   -- dias restantes de trial

    -- Metadata Stripe
    stripe_customer_id  TEXT,
    stripe_session_id   TEXT,

    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (recruta_id)
);

CREATE INDEX IF NOT EXISTS idx_recruta_billing_recruta
    ON public.recruta_billing (recruta_id);

ALTER TABLE public.recruta_billing ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User read own billing" ON public.recruta_billing;
CREATE POLICY "User read own billing"
    ON public.recruta_billing FOR SELECT TO authenticated
    USING (recruta_id = auth.uid());

DROP POLICY IF EXISTS "Service role full billing" ON public.recruta_billing;
CREATE POLICY "Service role full billing"
    ON public.recruta_billing FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Trigger updated_at
CREATE OR REPLACE FUNCTION public.fn_billing_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS trg_billing_updated_at ON public.recruta_billing;
CREATE TRIGGER trg_billing_updated_at
    BEFORE UPDATE ON public.recruta_billing
    FOR EACH ROW EXECUTE FUNCTION public.fn_billing_updated_at();

-- VIEW: v_billing_status_recruta
-- Retorna billing do usuário atual. Se não existir registro, retorna linha com
-- acesso_liberado = false (usa a lógica legada de tipo_acesso como fallback).
CREATE OR REPLACE VIEW public.v_billing_status_recruta AS
SELECT
    COALESCE(b.acesso_liberado,
        CASE WHEN r.tipo_acesso = 'completo' THEN true ELSE false END
    )                       AS acesso_liberado,
    b.plano_atual,
    b.status_assinatura,
    b.validade::text        AS validade,
    COALESCE(b.trial_restante, 0) AS trial_restante
FROM public.recrutas r
LEFT JOIN public.recruta_billing b
    ON b.recruta_id = r.id
WHERE r.id = auth.uid();

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.v_billing_status_recruta;

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_billing_status_recruta;
-- DROP TABLE IF EXISTS public.recruta_billing;
