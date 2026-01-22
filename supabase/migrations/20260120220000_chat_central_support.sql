-- Support Views for Chat Central

-- 1. VIEW public_recrutas_padrao
-- Maps 'profiles' to the strict contract required by Chat Central
CREATE OR REPLACE VIEW public.public_recrutas_padrao AS
SELECT 
    p.id AS recruta_id,
    p.forca,
    CASE WHEN p.ativo THEN 'ativo' ELSE 'inativo' END AS status,
    COALESCE(p.instructor_profile_id, 'objetivo') AS instrutor_id,
    CASE 
        WHEN p.tipo_acesso = 'completo' THEN 'full' 
        ELSE 'free' 
    END AS access_mode,
    -- Mocking allowed_modules for now, or joining modules/progress if needed.
    -- Prompt implies this view should solve it. 
    -- For base implementation, we return empty array or 'all' logic handled by app?
    -- Chat Central code uses it to filter 'pedagogica'.
    -- If free -> limited modules?
    ARRAY[]::text[] AS allowed_modules
FROM public.profiles p;

-- 2. VIEW v_audit_eventos
-- Allows Chat Central to insert logs blindly
CREATE OR REPLACE VIEW public.v_audit_eventos AS
SELECT 
    audit_id,
    session_id,
    timestamp_utc,
    recruta_id,
    source,
    response_category AS categoria
FROM public.chat_audit_log;

-- Trigger to handle INSERT on v_audit_eventos
CREATE OR REPLACE FUNCTION public.fn_insert_audit_evento()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.chat_audit_log (
        session_id,
        timestamp_utc,
        user_id, -- We map recruta_id to user_id (same)
        recruta_id,
        source,
        response_category,
        -- Defaults for required cols in underlying table if missing in view insert
        force, 
        access_mode
    ) VALUES (
        NEW.session_id,
        NEW.timestamp_utc,
        NEW.recruta_id,
        NEW.recruta_id,
        NEW.source,
        NEW.categoria,
        'unknown', -- Chat Central logic handles force/access logic internally, 
                   -- but audit log table expects non-null. 
                   -- We might need to fetch it or relax constraint in audit table.
                   -- OR better: Chat Central *calculates* Force/Access. 
                   -- Ideally Chat Central should write to chat_audit_log directly 
                   -- if strictly following schema. 
                   -- BUT user code writes to `v_audit_eventos` with minimal fields.
                   -- We must support that.
        'unknown'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- TRIGGER
DROP TRIGGER IF EXISTS trg_insert_audit ON public.v_audit_eventos;
CREATE TRIGGER trg_insert_audit
    INSTEAD OF INSERT ON public.v_audit_eventos
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_insert_audit_evento();

-- NOTE: The underlying chat_audit_log table has NOT NULL on force/access_mode.
-- We must alter strictness or fetch them in trigger.
-- Fetching in trigger is best for consistency.
CREATE OR REPLACE FUNCTION public.fn_insert_audit_evento_smart()
RETURNS TRIGGER AS $$
DECLARE
    v_forca text;
    v_access text;
BEGIN
    SELECT forca, tipo_acesso INTO v_forca, v_access FROM public.profiles WHERE id = NEW.recruta_id;
    
    INSERT INTO public.chat_audit_log (
        session_id,
        timestamp_utc,
        user_id,
        recruta_id,
        source,
        response_category,
        force,
        access_mode
    ) VALUES (
        NEW.session_id,
        NEW.timestamp_utc,
        NEW.recruta_id,
        NEW.recruta_id,
        NEW.source,
        NEW.categoria,
        COALESCE(v_forca, 'unknown'),
        CASE WHEN v_access='completo' THEN 'full' ELSE 'free' END
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_insert_audit
    INSTEAD OF INSERT ON public.v_audit_eventos
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_insert_audit_evento_smart();
