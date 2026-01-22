create or replace function module_progress(
  p_recruta_id uuid,
  p_modulo_id uuid
)
returns table (
  completed bigint,
  total bigint
)
language sql
stable
as $$
  select
    count(*) filter (where rl.completed_at is not null) as completed,
    count(*) as total
  from licoes l
  left join recruta_licoes rl
    on rl.licao_id = l.id
   and rl.recruta_id = p_recruta_id
  where l.modulo_id = p_modulo_id;
$$;
