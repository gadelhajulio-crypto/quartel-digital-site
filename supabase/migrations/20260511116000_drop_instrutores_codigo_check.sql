-- RCC-0.5 / Wave 1 — Pré-requisito: remover CHECK constraint de codigo em instrutores
-- A constraint instrutores_codigo_check rejeita os novos valores de personalidade
-- (objetivo, estrategico, didatico). Removida para permitir insert dos instrutores Wave 1.

ALTER TABLE public.instrutores
  DROP CONSTRAINT IF EXISTS instrutores_codigo_check;
