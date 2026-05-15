-- RCC-0.5 — Remove phantom instructor rows whose slug matches a persona code
--
-- Root cause: the canonical instructor migration (20260511120000) used
-- DELETE WHERE slug IN ('ramos','rocha','sara') before re-inserting.
-- However, older migrations had previously inserted rows with
-- slug IN ('objetivo','estrategico','didatico').
-- Those rows survived and caused v_instrutores_app to return 6 rows instead of 3.
--
-- After this migration v_instrutores_app must return exactly 3 rows:
--   ramos / rocha / sara
--
-- Validation query (run after applying):
--   SELECT slug, codigo, ativo FROM public.instrutores ORDER BY ordem_exibicao;
--   -- Expected: 3 rows — (ramos, objetivo, true), (rocha, estrategico, true), (sara, didatico, true)

DELETE FROM public.instrutores
WHERE slug IN ('objetivo', 'estrategico', 'didatico');
