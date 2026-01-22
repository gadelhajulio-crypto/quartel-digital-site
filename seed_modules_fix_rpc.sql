-- 1. SEED MÓDULOS DE TESTE
-- Insere módulos se não existirem (evita duplicação por título)
INSERT INTO public.modulos (titulo, descricao, forca, ordem, is_degustacao)
SELECT 'BÁSICO NAVAL', 'Introdução à vida na Marinha.', 'marinha', 1, false
WHERE NOT EXISTS (SELECT 1 FROM public.modulos WHERE titulo = 'BÁSICO NAVAL');

INSERT INTO public.modulos (titulo, descricao, forca, ordem, is_degustacao)
SELECT 'INFANTARIA', 'Táticas de combate terrestre.', 'exercito', 1, false
WHERE NOT EXISTS (SELECT 1 FROM public.modulos WHERE titulo = 'INFANTARIA');

INSERT INTO public.modulos (titulo, descricao, forca, ordem, is_degustacao)
SELECT 'AERONÁUTICA BÁSICA', 'Fundamentos de voo e mecânica.', 'aeronautica', 1, false
WHERE NOT EXISTS (SELECT 1 FROM public.modulos WHERE titulo = 'AERONÁUTICA BÁSICA');

-- 2. CORREÇÃO DA RPC (ativa -> ativo)
-- Assume que a coluna na tabela aulas deve ser tratada como 'ativa' ou 'ativo'.
-- Se a tabela foi criada como 'ativa', idealmente deveríamos renomear, mas vamos ajustar a RPC para o que o usuário pediu.
-- Se a tabela 'aulas' não tiver coluna 'ativo', este script pode falhar se não alterarmos a tabela também.
-- Vamos garantir que a coluna 'ativo' exista ou renomear 'ativa' para 'ativo'.

DO $$
BEGIN
  IF EXISTS(SELECT *
    FROM information_schema.columns
    WHERE table_name='aulas' and column_name='ativa')
  THEN
      ALTER TABLE public.aulas RENAME COLUMN ativa TO ativo;
  END IF;
END $$;

-- Recria a RPC usando 'ativo'
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
  -- Total de aulas ativas (agora usando 'ativo')
  SELECT count(*) INTO v_total FROM aulas WHERE ativo = true;

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
