-- RCC-0.5 / Wave 1 — Pré-requisito: remover CHECK constraints com valores fixos
-- institutional_assets.tipo_check e instrutores.codigo_check limitam valores
-- e precisam ser removidos para permitir os novos tipos de assets de instrutores.

ALTER TABLE public.institutional_assets
  DROP CONSTRAINT IF EXISTS institutional_assets_tipo_check;

ALTER TABLE public.instrutores
  DROP CONSTRAINT IF EXISTS instrutores_codigo_check;
