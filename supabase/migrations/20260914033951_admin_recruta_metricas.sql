CREATE VIEW public.v_admin_recruta_metricas
WITH (security_invoker = true, security_barrier = true)
AS
SELECT
  COUNT(*)::bigint AS recrutas_total,
  COUNT(*) FILTER (
    WHERE lower(coalesce(status, '')) = 'ativo'
  )::bigint AS recrutas_ativos
FROM public.recrutas;

REVOKE ALL ON TABLE public.v_admin_recruta_metricas
  FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.v_admin_recruta_metricas
  TO service_role;
