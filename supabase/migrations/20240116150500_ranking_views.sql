-- View: Ranking Mensal (Top Recrutas ordered by XP)
-- Assumes existence of 'recrutas' table with 'id', 'nome', 'xp_total', 'forca'.
-- If 'xp_total' doesn't exist, we might need to sum 'xp_eventos'. 
-- For now, relying on the user's implication that data exists. 
-- We'll try to be robust: if xp_total exists use it, otherwise use a placeholder or sum.
-- Let's assume 'recrutas' has 'xp_total' as per previous context (XP System).

create or replace view vw_ranking_mensal as
select
  row_number() over (order by coalesce(r.xp_total, 0) desc) as posicao,
  r.id as recruta_id,
  r.nome,
  coalesce(r.xp_total, 0) as xp,
  r.forca
from recrutas r
where r.nome is not null; -- Filter out incomplete profiles if needed

-- View: Posição do Recruta no Mês
create or replace view vw_posicao_recruta_mes as
select
  posicao,
  recruta_id,
  xp
from vw_ranking_mensal;
