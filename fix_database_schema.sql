-- 1. TABELA AULAS (Se não existir)
CREATE TABLE IF NOT EXISTS public.aulas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    titulo TEXT NOT NULL,
    descricao TEXT,
    video_url TEXT,
    modulo_id UUID, -- Caso haja tabela de módulos
    ordem INTEGER DEFAULT 0,
    xp_recompensa INTEGER DEFAULT 10,
    ativa BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. TABELA PROGRESSO_AULAS (Dependência da RPC)
CREATE TABLE IF NOT EXISTS public.progresso_aulas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    aula_id UUID REFERENCES public.aulas(id) ON DELETE CASCADE,
    concluida BOOLEAN DEFAULT false,
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, aula_id)
);

-- 3. FUNÇÃO DE PROGESSO (RPC)
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
  -- Total de aulas ativas no sistema
  SELECT count(*) INTO v_total
  FROM aulas
  WHERE ativa = true;

  -- Total de aulas concluídas pelo recruta
  SELECT count(*) INTO v_completed
  FROM progresso_aulas
  WHERE user_id = p_recruta_id
  AND concluida = true;

  -- Retorno dos dados
  RETURN QUERY
  SELECT 
    COALESCE(v_completed, 0),
    CASE WHEN COALESCE(v_total, 0) = 0 THEN 1 ELSE v_total END; 
END;
$$;

-- 4. VIEW DE RANKING (vw_ranking_mensal)
-- Assume que profiles tem uma coluna de 'pontos' ou calcula baseado em progresso
-- Aqui vamos criar uma view que expõe 'pontos' como 'xp'
CREATE OR REPLACE VIEW public.vw_ranking_mensal AS
SELECT
    ROW_NUMBER() OVER (ORDER BY p.pontos DESC, p.nome ASC) as posicao,
    p.id as recruta_id,
    p.nome,
    COALESCE(p.pontos, 0) as xp, -- Mapeia 'pontos' para 'xp'
    p.forca,
    p.patente
FROM
    public.profiles p
WHERE
    p.ativo = true;

-- 5. VIEW DE POSIÇÃO INDIVIDUAL (vw_posicao_recruta_mes)
CREATE OR REPLACE VIEW public.vw_posicao_recruta_mes AS
SELECT
    r.posicao,
    r.recruta_id,
    r.nome,
    r.xp
FROM
    public.vw_ranking_mensal r;
