-- ==============================================================================
-- FIX: get_student_next_lesson — Migrar schema legado para canônico
-- ==============================================================================
-- Motivo: RPC original (20260122144000) usa tabelas legadas:
--   lessons → aulas
--   modules → modulos
--   lesson_progress → recruta_progresso
--   profiles.forca → recrutas.forca (com normalização)
-- Status anterior: QUEBRADA para o schema atual.
-- Data: 03/05/2026
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.get_student_next_lesson(p_user_id UUID)
RETURNS TABLE (
    lesson_id    UUID,
    title        TEXT,
    module       TEXT,   -- título do módulo (compatibilidade com uso no hook)
    lesson_order INTEGER,
    status       TEXT    -- 'available' | 'completed' | 'blocked'
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_forca TEXT;
BEGIN
    -- 1. Busca força do recruta (aceita tanto forca em português quanto inglês)
    SELECT
        CASE forca
            WHEN 'navy'     THEN 'marinha'
            WHEN 'army'     THEN 'exercito'
            WHEN 'airforce' THEN 'aeronautica'
            ELSE forca
        END
    INTO v_forca
    FROM public.recrutas
    WHERE id = p_user_id;

    IF v_forca IS NULL THEN
        RETURN;  -- Recruta sem força definida
    END IF;

    -- 2. Primeira aula não concluída da força do recruta
    RETURN QUERY
    SELECT
        a.id                    AS lesson_id,
        a.title,
        m.title                 AS module,
        a."order"               AS lesson_order,
        'available'::text       AS status
    FROM public.aulas a
    JOIN public.modulos m
        ON m.id = a.modulo_id
    LEFT JOIN public.recruta_progresso rp
        ON  rp.lesson_id  = a.id
        AND rp.recruta_id = p_user_id
        AND rp.status     = 'completed'
    WHERE
        (
            -- Aceita tanto forca em português quanto inglês no módulo
            m.forca = v_forca
            OR m.forca = CASE v_forca
                WHEN 'marinha'   THEN 'navy'
                WHEN 'exercito'  THEN 'army'
                WHEN 'aeronautica' THEN 'airforce'
                ELSE v_forca
            END
        )
        AND rp.lesson_id IS NULL     -- ainda não completada
    ORDER BY
        m."order" ASC,
        a."order" ASC
    LIMIT 1;

    -- Se não retornou linhas: curso concluído. O frontend trata null como concluído.
END;
$$;

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.get_student_next_lesson('<recruta_uuid>');

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- (Recriar versão anterior conforme 20260122144000_get_student_next_lesson.sql)
