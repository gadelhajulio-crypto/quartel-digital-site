create or replace function recruta_progresso_geral(
  p_recruta_id uuid
)
returns table (
  completed bigint,
  total bigint
)
language sql
stable
as $$
  select
    count(*) filter (where rm.completed_at is not null) as completed,
    count(*) as total
  from recruta_modulos rm
  where rm.recruta_id = p_recruta_id;
$$;
