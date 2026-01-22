-- 1. VIEW: LISTAGEM DE AULAS PARA O PAINEL
create or replace view v_lessons_panel as
select
  l.id as lesson_id,
  l.title as title,
  l.module as module,
  l.lesson_order as lesson_order,
  l.force as force,
  l.created_at as created_at
from lessons l;

-- 2. VIEW: DETALHES DA AULA (SEM MÍDIA)
create or replace view v_lesson_detail_panel as
select
  l.id as lesson_id,
  l.title as title,
  l.module as module,
  l.lesson_order as lesson_order,
  l.force as force
from lessons l;

-- 3. VIEW: EXISTÊNCIA DE MÍDIA (SEM URL)
-- Filters for strictly Lesson content (Video/PDF), excluding reviews if strictly for lesson panel. 
-- However, creating a generic view for all media allows app to filter. 
-- Given the strict breakdown in prompt, I'll allow all types or restrict? 
-- Prompt 181 implied generic media panel. Prompt 196 puts all in lesson_media.
-- I will select all types here, allowing the UI to decide what to show based on 'media_type'.
create or replace view v_lesson_media_panel as
select
  lm.lesson_id as lesson_id,
  lm.type as media_type
from lesson_media lm;

-- 4. VIEW: PROGRESSO DO ALUNO
-- FIXED: Using 'lesson_progress' table, NOT 'progresso_aulas'
create or replace view v_lesson_progress_panel as
select
  lp.user_id as user_id,
  lp.lesson_id as lesson_id,
  lp.completed_at as completed_at
from lesson_progress lp;

-- 5. VIEW: EXISTÊNCIA DE REVISÃO
-- FIXED: Sourcing from 'lesson_media' where type is review
create or replace view v_review_panel as
select
  lm.lesson_id as lesson_id,
  lm.type as review_type
from lesson_media lm
where lm.type in ('review_video', 'review_audio');
