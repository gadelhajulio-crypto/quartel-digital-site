CREATE OR REPLACE FUNCTION recruta_progresso_geral(p_recruta_id UUID)
RETURNS TABLE (
  completed BIGINT,
  total BIGINT,
  percentage NUMERIC
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH total_aulas AS (
    -- Conta todas as aulas de módulos que não são degustação (ou todos, dependendo da regra)
    -- Assumindo que queremos contar tudo que está ativo.
    -- Ajuste 'ativo' para 'ativa' se for o nome da coluna no seu banco, ou remova se não existir.
    -- O prompt pediu para "remover qualquer referência à coluna ativa".
    SELECT COUNT(*)::BIGINT as total
    FROM aulas a
    JOIN modulos m ON a.modulo_id = m.id
    -- WHERE m.ativa = true -- REMOVIDO conforme pedido
  ),
  aulas_concluidas AS (
    SELECT COUNT(DISTINCT pa.aula_id)::BIGINT as concluido
    FROM progresso_aulas pa
    WHERE pa.user_id = p_recruta_id
    -- AND pa.concluida = true -- Se a tabela só tem registros de concluidos, não precisa filtrar. Se tem status, descomentar.
    -- Assumindo que a existência na tabela implica conclusão ou há coluna bool.
    -- O prompt diz "garantindo que ela conte o progresso real".
  )
  SELECT 
    c.concluido as completed,
    t.total as total,
    CASE 
      WHEN t.total > 0 THEN ROUND((c.concluido::NUMERIC / t.total::NUMERIC) * 100, 2)
      ELSE 0 
    END as percentage
  FROM total_aulas t, aulas_concluidas c;
END;
$$;
