-- Função RPC para calcular progresso do recruta
-- Retorna: { completed: integer, total: integer }

create or replace function recruta_progresso_geral(p_recruta_id uuid)
returns table (
  completed bigint,
  total bigint
) 
language plpgsql
security definer
as $$
declare
  v_completed bigint;
  v_total bigint;
begin
  -- Total de aulas ativas no sistema
  select count(*) into v_total
  from aulas
  where ativa = true;

  -- Total de aulas concluídas pelo recruta
  select count(*) into v_completed
  from progresso_aulas
  where user_id = p_recruta_id
  and concluida = true;

  -- Retorno dos dados
  return query
  select 
    coalesce(v_completed, 0),
    case when coalesce(v_total, 0) = 0 then 1 else v_total end; -- Evita divisão por zero no front
end;
$$;
