-- Create Audit Log table for Chat
CREATE TABLE IF NOT EXISTS public.chat_audit_log (
    audit_id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    session_id UUID, -- Optional, if we want to track app sessions
    timestamp_utc TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    user_id UUID NOT NULL,
    recruta_id UUID NOT NULL,
    force TEXT NOT NULL,
    instructor_profile_id TEXT,
    access_mode TEXT NOT NULL,
    
    -- Context
    interaction_type TEXT DEFAULT 'question', -- question, explanation, quiz, etc.
    response_category TEXT DEFAULT 'answered_within_scope', -- answered_within_scope, blocked, etc.
    
    -- Source
    source TEXT DEFAULT 'mobile_app',
    agent TEXT, -- e.g. instrutor_marinha
    
    -- Metadata (No content)
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Indices
CREATE INDEX IF NOT EXISTS idx_chat_audit_user ON public.chat_audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_audit_timestamp ON public.chat_audit_log(timestamp_utc);
CREATE INDEX IF NOT EXISTS idx_chat_audit_recruta ON public.chat_audit_log(recruta_id);

-- RLS (Security)
ALTER TABLE public.chat_audit_log ENABLE ROW LEVEL SECURITY;

-- Only service role can insert/select usually, or user can insert their own?
-- System/Service Role will do the insertion via Edge Function.
-- Users might want to see their audit log? Probably not.
-- Keeping it restricted.
CREATE POLICY "Service Role Full Access" ON public.chat_audit_log
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);
