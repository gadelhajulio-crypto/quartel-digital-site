-- Quiz/Simulado — schema: is_placeholder + simulado first-class.
-- Design: docs/DESIGN_QUIZ_SIMULADO.md. Idempotente.

-- ── is_placeholder estruturado (identificação de conteúdo não-real, não prefixo) ──
ALTER TABLE public.modulos                ADD COLUMN IF NOT EXISTS is_placeholder boolean NOT NULL DEFAULT false;
ALTER TABLE public.aulas                  ADD COLUMN IF NOT EXISTS is_placeholder boolean NOT NULL DEFAULT false;
ALTER TABLE public.c9_aula_quizzes        ADD COLUMN IF NOT EXISTS is_placeholder boolean NOT NULL DEFAULT false;
ALTER TABLE public.c9_aula_quiz_perguntas ADD COLUMN IF NOT EXISTS is_placeholder boolean NOT NULL DEFAULT false;

-- ── Simulado first-class: quiz por aula OU simulado por módulo na mesma tabela ──
ALTER TABLE public.c9_aula_quizzes ALTER COLUMN aula_id DROP NOT NULL;
ALTER TABLE public.c9_aula_quizzes ADD COLUMN IF NOT EXISTS modulo_id uuid REFERENCES public.modulos(id) ON DELETE CASCADE;
ALTER TABLE public.c9_aula_quizzes ADD COLUMN IF NOT EXISTS escopo text NOT NULL DEFAULT 'quiz_aula';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'c9_quizzes_escopo_check') THEN
    ALTER TABLE public.c9_aula_quizzes ADD CONSTRAINT c9_quizzes_escopo_check
      CHECK (escopo = ANY (ARRAY['quiz_aula','simulado_modulo']));
  END IF;
  -- exatamente um alvo por escopo
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'c9_quizzes_escopo_target_check') THEN
    ALTER TABLE public.c9_aula_quizzes ADD CONSTRAINT c9_quizzes_escopo_target_check
      CHECK (
        (escopo = 'quiz_aula'       AND aula_id   IS NOT NULL AND modulo_id IS NULL) OR
        (escopo = 'simulado_modulo' AND modulo_id IS NOT NULL AND aula_id   IS NULL)
      );
  END IF;
END $$;

-- 1 simulado ativo por módulo (espelha a regra de 1 quiz ativo por aula)
CREATE UNIQUE INDEX IF NOT EXISTS c9_idx_unique_simulado_modulo_ativo
  ON public.c9_aula_quizzes (modulo_id)
  WHERE escopo = 'simulado_modulo' AND ativo = true AND deleted_at IS NULL;

-- ── Idempotência de XP p/ quiz/simulado (espelha ux_xp_eventos_lesson_unique, que
--    é parcial p/ origem='lesson_complete'). Garante 1 evento de XP por recruta+quiz. ──
CREATE UNIQUE INDEX IF NOT EXISTS ux_xp_eventos_quiz_unique
  ON public.xp_eventos (recruta_id, referencia_id)
  WHERE origem IN ('quiz_aula_concluido','simulado_modulo_concluido');
