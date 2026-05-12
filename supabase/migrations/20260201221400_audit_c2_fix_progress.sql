-- ==============================================================================
-- AUDITORIA C2 - FIX DEFINITIVO DE PROGRESSO
-- ==============================================================================
-- Motivo: Padronizar Writes, Eliminar Tabelas Fantasmas, Centralizar XP.
-- Data: 01/02/2026
-- ==============================================================================

-- ETAPA 1: TABELA OFICIAL
CREATE TABLE IF NOT EXISTS public.recruta_progresso (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  recruta_id uuid NOT NULL
    REFERENCES public.recrutas(id) ON DELETE CASCADE,

  lesson_id uuid NOT NULL
    REFERENCES public.aulas(id) ON DELETE CASCADE,

  status text NOT NULL CHECK (status IN ('completed')),

  completed_at timestamptz NOT NULL DEFAULT now(),

  xp_granted integer NOT NULL DEFAULT 0,

  source text NOT NULL DEFAULT 'lesson_completion',

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (recruta_id, lesson_id)
);

-- Habilitar RLS na nova tabela
ALTER TABLE public.recruta_progresso ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Recrutas veem seu próprio progresso"
  ON public.recruta_progresso
  FOR SELECT
  USING (auth.uid() = recruta_id);

-- ETAPA 2: VIEW OFICIAL DE LEITURA
CREATE OR REPLACE VIEW public.v_lesson_progress_panel AS
SELECT
  rp.recruta_id,
  rp.lesson_id,
  rp.completed_at,
  rp.xp_granted
FROM public.recruta_progresso rp;

-- ETAPA 3: RPC OFICIAL DE ESCRITA
CREATE OR REPLACE FUNCTION public.complete_lesson(
  p_recruta_id uuid,
  p_lesson_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- Garante permissão para escrever e dar XP
AS $$
DECLARE
  v_xp integer;
BEGIN
  -- Buscar XP da aula
  SELECT xp INTO v_xp
  FROM public.aulas
  WHERE id = p_lesson_id;

  -- Inserir Progresso (Idempotente)
  INSERT INTO public.recruta_progresso (
    recruta_id,
    lesson_id,
    status,
    xp_granted
  )
  VALUES (
    p_recruta_id,
    p_lesson_id,
    'completed',
    COALESCE(v_xp, 0)
  )
  ON CONFLICT (recruta_id, lesson_id) DO NOTHING;

  -- Conceder XP ao Recruta
  -- (Assume que public.recrutas tem coluna xp)
  UPDATE public.recrutas
  SET xp = COALESCE(xp, 0) + COALESCE(v_xp, 0)
  WHERE id = p_recruta_id;
END;
$$;
