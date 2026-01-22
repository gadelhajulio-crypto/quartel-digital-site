-- 1. PADRONIZAÇÃO DE XP (PROFILES)
-- Adiciona a coluna 'xp' se não existir
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS xp INTEGER DEFAULT 0;

-- 2. TABELA DE AULAS (Necessária para o dashboard 'Módulos')
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

-- 3. TABELA PROGRESSO_AULAS (Necessária para contar 'Concluídos')
CREATE TABLE IF NOT EXISTS public.progresso_aulas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    aula_id UUID REFERENCES public.aulas(id) ON DELETE CASCADE,
    concluida BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, aula_id)
);

-- 4. VIEWS DE RANKING (Atualizadas para usar coluna 'xp')

-- View: Ranking Mensal
CREATE OR REPLACE VIEW public.vw_ranking_mensal AS
SELECT
    ROW_NUMBER() OVER (ORDER BY p.xp DESC, p.nome ASC) as posicao,
    p.id as recruta_id,
    p.nome,
    p.xp,     -- Agora usa explicitamente a coluna 'xp'
    p.forca,
    p.patente
FROM
    public.profiles p
WHERE
    p.ativo = true;

-- View: Posição do Recruta
CREATE OR REPLACE VIEW public.vw_posicao_recruta_mes AS
SELECT
    r.posicao,
    r.recruta_id,
    r.nome,
    r.xp
FROM
    public.vw_ranking_mensal r;

-- 5. RPC: PROGESSO GERAL (Para o Dashboard)
-- Mantém a lógica de contar Aulas/Módulos para preencher a barra de progresso visual
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
  -- Total de aulas ativas
  SELECT count(*) INTO v_total FROM aulas WHERE ativa = true;

  -- Aulas concluídas pelo usuário
  SELECT count(*) INTO v_completed 
  FROM progresso_aulas 
  WHERE user_id = p_recruta_id AND concluida = true;

  RETURN QUERY
  SELECT 
    COALESCE(v_completed, 0),
    CASE WHEN COALESCE(v_total, 0) = 0 THEN 1 ELSE v_total END;
END;
$$;
