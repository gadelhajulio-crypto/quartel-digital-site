-- =============================================================
-- RCC-0.5 / Wave 1 — Hotfix: GRANTs tabelas de instrutores
-- Corrige: permission denied for table instrutores
-- Corrige: permission denied for view v_instrutores_app
-- =============================================================

-- ── Tabelas base: leitura pública (catálogo de instrutores / assets públicos)
GRANT SELECT ON public.instrutores          TO authenticated, anon;
GRANT SELECT ON public.institutional_assets TO authenticated, anon;

-- ── Views RCC: leitura autenticada
GRANT SELECT ON public.v_instrutores_app        TO authenticated, anon;
GRANT SELECT ON public.v_institutional_assets   TO authenticated, anon;
