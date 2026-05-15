-- RCC-0.5 — rpc_update_instructor_profile
--
-- Aceita o SLUG do instrutor (ramos|rocha|sara) como parâmetro público.
-- Resolve internamente para o CODIGO (objetivo|estrategico|didatico) e persiste
-- em profiles.instructor_profile_id, mantendo o contrato de storage existente.
--
-- Motivo: o frontend trabalha com slug como identificador canônico (carregado via
-- v_instrutores_app), enquanto a constraint em profiles armazena o codigo.
-- A tradução fica no banco, não no frontend.
--
-- Chamada esperada:
--   SELECT public.rpc_update_instructor_profile('ramos');
--   SELECT public.rpc_update_instructor_profile('rocha');
--   SELECT public.rpc_update_instructor_profile('sara');

-- DROP garante que não há conflito de assinatura/return type com versão anterior
DROP FUNCTION IF EXISTS public.rpc_update_instructor_profile(TEXT);

CREATE OR REPLACE FUNCTION public.rpc_update_instructor_profile(
  p_instructor_profile_id TEXT   -- slug canônico: ramos | rocha | sara
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_codigo TEXT;
BEGIN
  -- Resolve slug → codigo via tabela canônica
  SELECT codigo
  INTO   v_codigo
  FROM   public.instrutores
  WHERE  slug  = p_instructor_profile_id
  AND    ativo = true
  LIMIT  1;

  IF v_codigo IS NULL THEN
    RAISE EXCEPTION 'INVALID_INSTRUCTOR_SLUG: %', p_instructor_profile_id;
  END IF;

  UPDATE public.profiles
  SET    instructor_profile_id = v_codigo
  WHERE  id = auth.uid();
END;
$$;

-- Permissões
GRANT EXECUTE ON FUNCTION public.rpc_update_instructor_profile(TEXT) TO authenticated;

-- Rollback:
-- DROP FUNCTION IF EXISTS public.rpc_update_instructor_profile(TEXT);
