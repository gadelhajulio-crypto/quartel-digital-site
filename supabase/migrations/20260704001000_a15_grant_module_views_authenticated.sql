-- A-15 — GRANT SELECT ausente em views recruta-facing de módulos/lições.
--
-- Diagnóstico (auditoria 2026-07-04): estas views negavam `42501 permission denied`
-- a um usuário `authenticated`, ao contrário de peers como v_lessons_panel /
-- v_medals_status_v3 que já concedem SELECT a authenticated. Não é RLS admin-only
-- intencional — é GRANT ausente (oversight). Consumidas por código de módulos
-- (tab de módulos DB-driven, detalhe de módulo, agregados de progresso).
--
-- IDEMPOTÊNCIA: GRANT é idempotente por natureza (re-conceder é no-op).

GRANT SELECT ON public.v_modulos_catalogo            TO authenticated;
GRANT SELECT ON public.vw_recruta_module_progress_v2 TO authenticated;
GRANT SELECT ON public.vw_rdm_lessons_v2             TO authenticated;
