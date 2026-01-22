-- 1. CORREÇÃO DA TABELA PROFILES
-- Adiciona colunas se não existirem
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS xp INTEGER DEFAULT 0;

ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS forca TEXT DEFAULT 'marinha';

-- Remove constraint antiga se existir para evitar conflito e recria
ALTER TABLE public.profiles 
DROP CONSTRAINT IF EXISTS check_forca_values;

ALTER TABLE public.profiles 
ADD CONSTRAINT check_forca_values 
CHECK (forca IN ('marinha', 'exercito', 'aeronautica'));

-- 2. TABELAS DE AULAS (Necessárias para o Dashboard e RPC)
CREATE TABLE IF NOT EXISTS public.aulas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    titulo TEXT NOT NULL,
    descricao TEXT,
    video_url TEXT,
    modulo_id UUID, 
    ordem INTEGER DEFAULT 0,
    xp_recompensa INTEGER DEFAULT 10,
    ativa BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.progresso_aulas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    aula_id UUID REFERENCES public.aulas(id) ON DELETE CASCADE,
    concluida BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, aula_id)
);

-- 3. VIEWS DE RANKING (Com XP e Força)

CREATE OR REPLACE VIEW public.vw_ranking_mensal AS
SELECT
    ROW_NUMBER() OVER (ORDER BY p.xp DESC, p.nome ASC) as posicao,
    p.id as recruta_id,
    p.nome,
    p.xp,
    p.forca, -- Adicionado para permitir exibição do ícone/tema correto no ranking
    p.patente
FROM
    public.profiles p
WHERE
    p.ativo = true;

CREATE OR REPLACE VIEW public.vw_posicao_recruta_mes AS
SELECT
    r.posicao,
    r.recruta_id,
    r.nome,
    r.xp,
    r.forca
FROM
    public.vw_ranking_mensal r;

-- 4. RPC: PROGESSO GERAL
CREATE OR REPLACE FUNCTION recruta_progresso_geral(p_recruta_id uuid)
RETURNS TABLE (
  completed bigint,
  total bigint
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_completed bigint;
  v_total bigint;
BEGIN
  SELECT count(*) INTO v_total FROM aulas WHERE ativa = true;

  SELECT count(*) INTO v_completed 
  FROM progresso_aulas 
  WHERE user_id = p_recruta_id AND concluida = true;

  RETURN QUERY
  SELECT 
    COALESCE(v_completed, 0),
    CASE WHEN COALESCE(v_total, 0) = 0 THEN 1 ELSE v_total END;
END;
$$;
