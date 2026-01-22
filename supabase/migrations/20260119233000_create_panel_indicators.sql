-- 1. MATERIALIZED VIEW: XP MENSAL DO RECRUTA
-- Calculates total XP per user per month
create materialized view mv_xp_mensal_recruta as
select
    user_id,
    force,
    date_trunc('month', created_at)::date as month_ref,
    sum(quantidade) as xp_mensal
from xp_eventos
group by user_id, force, date_trunc('month', created_at);

create unique index idx_mv_xp_mensal_recruta on mv_xp_mensal_recruta (user_id, force, month_ref);

-- 2. MATERIALIZED VIEW: RANKING MENSAL
-- Calculates rank position based on XP
create materialized view mv_ranking_mensal as
select
    user_id,
    force,
    month_ref,
    xp_mensal,
    rank() over (partition by force, month_ref order by xp_mensal desc) as rank_position
from mv_xp_mensal_recruta;

create unique index idx_mv_ranking_mensal on mv_ranking_mensal (user_id, force, month_ref);

-- 3. MATERIALIZED VIEW: CAMPEÃO MENSAL
-- Identifies the top rank for each force/month
create materialized view mv_campeao_mensal as
select
    user_id,
    force,
    month_ref
from mv_ranking_mensal
where rank_position = 1;

create unique index idx_mv_campeao_mensal on mv_campeao_mensal (force, month_ref);

-- 4. VIEW: CONTAGEM DE AULAS CONCLUÍDAS
-- Aggregate view for simple read
create or replace view v_completed_lessons_count as
select
    user_id,
    count(*) as completed_count
from lesson_progress
where completed_at is not null
group by user_id;
