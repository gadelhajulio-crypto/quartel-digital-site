-- Function to get the OFFICIAL next lesson for a student
-- Strictly server-side decision making.

CREATE OR REPLACE FUNCTION get_student_next_lesson(p_user_id UUID)
RETURNS TABLE (
  lesson_id UUID,
  title TEXT,
  module TEXT,
  lesson_order INTEGER,
  status TEXT -- 'available' | 'completed' | 'blocked' (future expansion)
) AS $$
DECLARE
  v_force TEXT;
BEGIN
  -- 1. Get User Force
  SELECT forca INTO v_force
  FROM profiles
  WHERE id = p_user_id;

  IF v_force IS NULL THEN
    RETURN; -- No profile/force found
  END IF;

  -- 2. Find first uncompleted lesson
  RETURN QUERY
  SELECT 
    l.id as lesson_id,
    l.title,
    m.title as module,
    l.lesson_order,
    'available'::text as status
  FROM lessons l
  JOIN modules m ON l.module_id = m.id
  LEFT JOIN lesson_progress lp ON l.id = lp.lesson_id AND lp.user_id = p_user_id
  WHERE 
    l.force = v_force
    AND lp.completed_at IS NULL
  ORDER BY 
    m.module_order ASC,
    l.lesson_order ASC
  LIMIT 1;
  
  -- If no rows returned (Course Completed), we might want to return the LAST lesson as "completed" or empty.
  -- For now, the app handles empty as "Completed".
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
