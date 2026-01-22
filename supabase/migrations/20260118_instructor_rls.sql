-- Migration: Secure Instructor Selection
-- Date: 2026-01-18
-- Reviewer: AntiGravity

-- 1. Ensure the column exists (idempotent check not strictly needed if we know schema, but good practice)
-- ALTER TABLE profiles ADD COLUMN IF NOT EXISTS instructor_profile_id text;

-- 2. Add Constraint to ensure only valid IDs are saved
ALTER TABLE profiles
  DROP CONSTRAINT IF EXISTS check_instructor_profile_id;

ALTER TABLE profiles
  ADD CONSTRAINT check_instructor_profile_id
  CHECK (instructor_profile_id IN ('objetivo', 'estrategico', 'didatico'));

-- 3. RLS Policy: Allow users to update THEIR OWN profile
-- First, ensure RLS is on
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- drop existing policy if it conflicts (optional, depending on project style)
DROP POLICY IF EXISTS "User can update own instructor" ON profiles;

CREATE POLICY "User can update own instructor"
ON profiles
FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (
  -- Ensure they are still editing their own profile (redundant but safe)
  auth.uid() = id
  -- AND ensure the value is valid (constraint handles this, but Check here prevents bad attempts early)
  AND instructor_profile_id IN ('objetivo', 'estrategico', 'didatico')
);
