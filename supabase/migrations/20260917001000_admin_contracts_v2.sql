-- Administrative read contracts. The views intentionally use PostgreSQL's
-- owner-controlled view semantics (security_invoker is not enabled): the
-- migration owner reads the protected source relations, while service_role
-- receives access only to these sanitized projections.

CREATE VIEW public.v_admin_pagamentos_confirmados
WITH (security_barrier = true)
AS
SELECT
  bp.valor_centavos AS amount_cents,
  bp.moeda AS currency,
  bp.created_at AS occurred_at
FROM public.billing_pagamentos AS bp
WHERE bp.status_pagamento = 'confirmado';

CREATE VIEW public.v_admin_alertas
WITH (security_barrier = true)
AS
SELECT
  'billing_reconciliation_issues'::text AS source,
  bri.status_execucao AS status,
  bri.created_at AS occurred_at,
  'Divergência de reconciliação'::text AS description
FROM public.billing_reconciliation_issues AS bri
WHERE bri.status_execucao IN ('erro', 'pendente')

UNION ALL

SELECT
  'billing_reconciliacao'::text AS source,
  br.status_execucao AS status,
  br.executado_em AS occurred_at,
  'Execução de reconciliação'::text AS description
FROM public.billing_reconciliacao AS br
WHERE br.status_execucao = 'erro'

UNION ALL

SELECT
  'billing_notificacoes_log'::text AS source,
  bnl.status_envio AS status,
  bnl.created_at AS occurred_at,
  'Notificação de cobrança'::text AS description
FROM public.billing_notificacoes_log AS bnl
WHERE bnl.status_envio = 'falhou'

UNION ALL

SELECT
  'eventos_institucionais'::text AS source,
  ei.status AS status,
  ei.created_at AS occurred_at,
  'Evento institucional'::text AS description
FROM public.eventos_institucionais AS ei
WHERE ei.status = 'failed';

CREATE VIEW public.v_admin_atividade_recente
WITH (security_barrier = true)
AS
SELECT
  ev.dominio_analitico AS domain,
  ev.status AS status,
  ev.timestamp_evento AS occurred_at
FROM public.v_c5_eventos_dominios_v3 AS ev;

REVOKE ALL ON TABLE
  public.v_admin_pagamentos_confirmados,
  public.v_admin_alertas,
  public.v_admin_atividade_recente
FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE
  public.v_admin_pagamentos_confirmados,
  public.v_admin_alertas,
  public.v_admin_atividade_recente
TO service_role;
