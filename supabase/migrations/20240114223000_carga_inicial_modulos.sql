-- ==============================================================================
-- CARGA DE DADOS ESTRUTURAL FINAL - QUARTEL DIGITAL
-- ==============================================================================
-- Este script limpa a base e insere a estrutura completa de módulos e aulas.
-- DATA: 14/01/2026
---------------------------------------------------------------------------------

-- 1. LIMPEZA TOTAL (RESET)
-- Remove pontuações, progressos e conteúdo antigo para evitar duplicidade.
DELETE FROM public.xp_eventos;
DELETE FROM public.recruta_modulos;
DELETE FROM public.aulas;
DELETE FROM public.modulos;

-- 2. GARANTIA DE ESTRUTURA (DDL)
-- Recria tabelas caso não existam (Segurança).

CREATE TABLE IF NOT EXISTS public.modulos (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    "order" INTEGER NOT NULL,
    forca TEXT NOT NULL CHECK (forca IN ('navy', 'army', 'airforce')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.aulas (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    module_id UUID NOT NULL REFERENCES public.modulos(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('video', 'pdf', 'quiz')),
    url TEXT,
    xp INTEGER DEFAULT 0,
    "order" INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. INSERÇÃO DE CONTEÚDO (DADOS)

DO $$
DECLARE
    v_force text;
    v_mod0_id uuid;
    v_mod1_id uuid;
    v_mod2_id uuid;
BEGIN
    -- [LOOP DE FORÇAS]
    -- Cria a estrutura idêntica para Marinha, Exército e Aeronáutica.
    FOREACH v_force IN ARRAY ARRAY['navy', 'army', 'airforce']
    LOOP
        
        -----------------------------------------------------------------------
        -- MÓDULO 0: BATISMO DE FOGO (DEGUSTAÇÃO)
        -----------------------------------------------------------------------
        INSERT INTO public.modulos (title, description, "order", forca)
        VALUES ('Batismo de Fogo', 'O início da sua jornada. Prove seu valor.', 0, v_force)
        RETURNING id INTO v_mod0_id;

        -- Aula 0.1 (Vídeo)
        INSERT INTO public.aulas (module_id, title, type, url, xp, "order")
        VALUES (
            v_mod0_id, 
            'Apresentação do Comando', -- Título Militar
            'video', 
            'https://vimeo.com/placeholder_aula_01', -- [EDITAR AQUI] Link do Vídeo
            50, -- XP do Vídeo
            1
        );

        -- Aula 0.2 (PDF)
        INSERT INTO public.aulas (module_id, title, type, url, xp, "order")
        VALUES (
            v_mod0_id, 
            'Código de Honra e Conduta', 
            'pdf', 
            'https://example.com/placeholder_manual.pdf', -- [EDITAR AQUI] Link do PDF
            20, -- XP do PDF
            2
        );

        -- Aula 0.3 (Vídeo)
        INSERT INTO public.aulas (module_id, title, type, url, xp, "order")
        VALUES (
            v_mod0_id, 
            'Primeira Ordem do Dia', 
            'video', 
            'https://vimeo.com/placeholder_aula_02', 
            50, 
            3
        );

        -----------------------------------------------------------------------
        -- MÓDULO 1: MENTALIDADE DE ELITE
        -----------------------------------------------------------------------
        INSERT INTO public.modulos (title, description, "order", forca)
        VALUES ('Mentalidade de Elite', 'Forje sua mente para a guerra diária.', 1, v_force)
        RETURNING id INTO v_mod1_id;

        -- Aula 1.1
        INSERT INTO public.aulas (module_id, title, type, url, xp, "order")
        VALUES (v_mod1_id, 'Disciplina Inabalável', 'video', 'https://vimeo.com/placeholder_aula_03', 50, 1);

        -- Aula 1.2
        INSERT INTO public.aulas (module_id, title, type, url, xp, "order")
        VALUES (v_mod1_id, 'Hierarquia e Lealdade', 'pdf', 'https://example.com/placeholder_hierarquia.pdf', 20, 2);

        -----------------------------------------------------------------------
        -- MÓDULO 2: ESTRATÉGIA OPERACIONAL
        -----------------------------------------------------------------------
        INSERT INTO public.modulos (title, description, "order", forca)
        VALUES ('Estratégia Operacional', 'Organização é a chave da vitória.', 2, v_force)
        RETURNING id INTO v_mod2_id;

        -- Aula 2.1
        INSERT INTO public.aulas (module_id, title, type, url, xp, "order")
        VALUES (v_mod2_id, 'Gestão do Tempo de Combate', 'video', 'https://vimeo.com/placeholder_aula_04', 50, 1);

    END LOOP;
END $$;

-- 4. VERIFICAÇÃO FINAL
-- Exibe quantos registros foram criados para conferência.
SELECT 
    (SELECT count(*) FROM public.modulos) as total_modulos,
    (SELECT count(*) FROM public.aulas) as total_aulas;
