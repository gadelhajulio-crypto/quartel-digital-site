-- Adiciona o campo se não existir
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS instructor_profile_id text;

-- Cria a constraint de validação
ALTER TABLE public.profiles 
DROP CONSTRAINT IF EXISTS check_instructor_type; -- Drop if exists to avoid error on retry

ALTER TABLE public.profiles 
ADD CONSTRAINT check_instructor_type 
CHECK (instructor_profile_id IN ('objetivo', 'estrategico', 'didatico'));
