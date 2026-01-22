-- Create XP Events table
CREATE TABLE IF NOT EXISTS public.xp_eventos (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) NOT NULL,
    amount INTEGER NOT NULL,
    description TEXT NOT NULL,
    source_id TEXT, -- e.g., lesson_id
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Add xp_total to recruited (if not exists, assuming 'recrutas' or 'profiles' table exists, 
-- but based on previous context we might need to rely on the user having a table. 
-- Checking previous logs/files, we saw references to 'recrutas'.
-- Safely adding column if it doesn't exist.
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'recrutas' AND column_name = 'xp_total') THEN
        ALTER TABLE public.recrutas ADD COLUMN xp_total INTEGER DEFAULT 0;
    END IF;
END $$;

-- RPC to register XP
CREATE OR REPLACE FUNCTION public.registrar_xp(
    p_amount INTEGER,
    p_description TEXT,
    p_source_id TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_new_total INTEGER;
BEGIN
    v_user_id := auth.uid();
    
    -- Insert Event
    INSERT INTO public.xp_eventos (user_id, amount, description, source_id)
    VALUES (v_user_id, p_amount, p_description, p_source_id);
    
    -- Update Total
    UPDATE public.recrutas
    SET xp_total = COALESCE(xp_total, 0) + p_amount
    WHERE id = v_user_id
    RETURNING xp_total INTO v_new_total;
    
    RETURN v_new_total;
END;
$$;
