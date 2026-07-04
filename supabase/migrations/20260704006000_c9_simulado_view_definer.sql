-- Quiz/Simulado — v_c9_simulado_execucao deve rodar como OWNER (security definer),
-- não security_invoker.
--
-- MOTIVO: as tabelas c9_* têm RLS para authenticated mas NÃO têm GRANT SELECT de
-- tabela para authenticated — e NÃO devem ter, porque c9_aula_quiz_alternativas
-- expõe `correta` (gabarito). Uma view security_invoker precisaria dos grants nas
-- tabelas cruas (vazando o gabarito) e ainda dependeria de `aulas` (que nega SELECT
-- a authenticated — A-19). Rodando como owner, a view acessa as tabelas como postgres
-- e projeta apenas o necessário (SEM `correta`), com GRANT só na própria view.
--
-- O RPC rpc_c9_submit_attempt já é SECURITY DEFINER (avalia o gabarito server-side),
-- então não é afetado.

ALTER VIEW public.v_c9_simulado_execucao SET (security_invoker = false);

-- GRANT na view já concedido na migration 20260704004000 (idempotente reafirmar):
GRANT SELECT ON public.v_c9_simulado_execucao TO authenticated;
