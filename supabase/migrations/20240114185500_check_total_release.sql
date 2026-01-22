-- Function to check if the current user has access to all modules
-- Returns true if the user's account (created_at) is older than 7 days
create or replace function check_total_release()
returns boolean
language plpgsql
security definer -- Runs with the privileges of the creator
as $$
declare
  is_released boolean;
begin
  select (created_at < (now() - interval '7 days'))
  into is_released
  from recrutas
  where id = auth.uid(); -- Assumes 'id' in 'recrutas' is linked to auth.users

  -- If user not found or created_at is null, default to false
  return coalesce(is_released, false);
end;
$$;
