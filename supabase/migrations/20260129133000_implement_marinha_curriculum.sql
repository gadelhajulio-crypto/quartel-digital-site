-- ==============================================================================
-- MIGRAÇÃO OFICIAL: CURRÍCULO MARINHA DO BRASIL
-- ==============================================================================
-- Implementa a estrutura curricular definitiva (Regulamento, IMN, HPS, etc.)
-- Remove conteúdo legado/genérico apenas da força 'navy'.
-- DATA: 29/01/2026
-- ==============================================================================

DO $$
DECLARE
    v_mod0_id uuid;
    v_mod1_id uuid;
    v_mod2_id uuid;
    v_mod3_id uuid;
    v_mod4_id uuid;
    v_mod5_id uuid;
    v_mod6_id uuid;
    v_mod7_id uuid;
    v_mod8_id uuid;
    v_mod9_id uuid;
BEGIN
    -- 1. LIMPEZA DE DADOS ANTIGOS (SCOPE: NAVY)
    -- Remove aulas e módulos da Marinha para garantir 'fonte única da verdade'
    -- DELETE CASCADE já deve limpar as aulas, mas forçamos por segurança se FK permitir.
    
    DELETE FROM public.aulas 
    WHERE module_id IN (SELECT id FROM public.modulos WHERE forca = 'navy');

    DELETE FROM public.modulos 
    WHERE forca = 'navy';

    -- 2. INSERÇÃO DO CURRÍCULO

    -- ==============================================================================
    -- MÓDULO 0: REGULAMENTO DISCIPLINAR (ORDEM 0)
    -- ==============================================================================
    INSERT INTO public.modulos (title, description, "order", forca)
    VALUES ('Regulamento Disciplinar', 'Fundamentos e normas disciplinares da Marinha.', 0, 'navy')
    RETURNING id INTO v_mod0_id;

    -- Aulas M0
    INSERT INTO public.aulas (module_id, title, "order", type, url, xp) VALUES
    (v_mod0_id, 'Fundamentos do Regulamento Disciplinar para a Marinha (RDM)', 1, 'video', NULL, 100), -- Desbloqueada
    (v_mod0_id, 'Contravenção Disciplinar: Conceito e Rol Normativo', 2, 'video', NULL, 100),       -- Desbloqueada
    (v_mod0_id, 'Natureza e Circunstâncias das Contravenções Disciplinares', 3, 'video', NULL, 100),    -- Desbloqueada
    (v_mod0_id, 'Sistema de Penas Disciplinares', 4, 'video', NULL, 100),
    (v_mod0_id, 'Competência e Jurisdição Disciplinar', 5, 'video', NULL, 100),
    (v_mod0_id, 'Procedimento de Apuração e Imposição da Pena', 6, 'video', NULL, 100),
    (v_mod0_id, 'Cumprimento e Contagem da Pena', 7, 'video', NULL, 100),
    (v_mod0_id, 'Registro, Transcrição e Efeitos Funcionais', 8, 'video', NULL, 100),
    (v_mod0_id, 'Revisão, Relevamento e Cancelamento de Punições', 9, 'video', NULL, 100),
    (v_mod0_id, 'Parte, Prisão Imediata e Recursos', 10, 'video', NULL, 100),
    (v_mod0_id, 'Disposições Gerais e Limites do Regulamento Disciplinar', 11, 'video', NULL, 100);

    -- ==============================================================================
    -- MÓDULO 1: INSTRUÇÃO MILITAR NAVAL (ORDEM 1)
    -- ==============================================================================
    INSERT INTO public.modulos (title, description, "order", forca)
    VALUES ('Instrução Militar Naval', 'Normas, cerimonial e ordenança da Armada.', 1, 'navy')
    RETURNING id INTO v_mod1_id;

    INSERT INTO public.aulas (module_id, title, "order", type, url, xp) VALUES
    (v_mod1_id, 'Estatuto dos Militares', 1, 'video', NULL, 100),
    (v_mod1_id, 'Regulamento de Continência, Honras e Sinais de Respeito e Cerimonial Militar das Forças Armadas', 2, 'video', NULL, 100),
    (v_mod1_id, 'Regulamento de Uniformes da Marinha', 3, 'video', NULL, 100),
    (v_mod1_id, 'Regulamento Disciplinar para a Marinha, Código de Processo Penal Militar e Código Penal Militar', 4, 'video', NULL, 100),
    (v_mod1_id, 'Ordenança Geral para o Serviço da Armada', 5, 'video', NULL, 100);

    -- ==============================================================================
    -- MÓDULO 2: HIGIENE E PRIMEIROS SOCORROS (ORDEM 2)
    -- ==============================================================================
    INSERT INTO public.modulos (title, description, "order", forca)
    VALUES ('Higiene e Primeiros Socorros', 'Cuidados básicos de saúde e emergências.', 2, 'navy')
    RETURNING id INTO v_mod2_id;

    INSERT INTO public.aulas (module_id, title, "order", type, url, xp) VALUES
    (v_mod2_id, 'Higiene', 1, 'video', NULL, 100),
    (v_mod2_id, 'Prevenção à Dependência Química', 2, 'video', NULL, 100),
    (v_mod2_id, 'Primeiros Socorros em Hemorragias e Asfixias', 3, 'video', NULL, 100),
    (v_mod2_id, 'Primeiros Socorros em Choque Elétrico, Queimaduras, Intermações e Insolações', 4, 'video', NULL, 100),
    (v_mod2_id, 'Primeiros Socorros em Fraturas, Entorses e Luxações', 5, 'video', NULL, 100);

    -- ==============================================================================
    -- MÓDULO 3: NOÇÕES DE ARMAMENTO (ORDEM 3)
    -- ==============================================================================
    INSERT INTO public.modulos (title, description, "order", forca)
    VALUES ('Noções de Armamento', 'Conhecimento de armamento leve e munição.', 3, 'navy')
    RETURNING id INTO v_mod3_id;

    INSERT INTO public.aulas (module_id, title, "order", type, url, xp) VALUES
    (v_mod3_id, 'Armamento Leve', 1, 'video', NULL, 100),
    (v_mod3_id, 'Munição Naval', 2, 'video', NULL, 100),
    (v_mod3_id, 'Instrução e Adestramento Preparatórios para o Tiro', 3, 'video', NULL, 100);

    -- ==============================================================================
    -- MÓDULO 4: NOÇÕES DE COMBATE A INCÊNDIO (ORDEM 4)
    -- ==============================================================================
    INSERT INTO public.modulos (title, description, "order", forca)
    VALUES ('Noções de Combate a Incêndio', 'Técnicas e equipamentos de combate a incêndio a bordo.', 4, 'navy')
    RETURNING id INTO v_mod4_id;

    INSERT INTO public.aulas (module_id, title, "order", type, url, xp) VALUES
    (v_mod4_id, 'Combate a Incêndio', 1, 'video', NULL, 100),
    (v_mod4_id, 'Classificação dos Incêndios', 2, 'video', NULL, 100),
    (v_mod4_id, 'Agentes Extintores', 3, 'video', NULL, 100),
    (v_mod4_id, 'Equipamentos e Acessórios', 4, 'video', NULL, 100),
    (v_mod4_id, 'Equipamento de Proteção e Segurança', 5, 'video', NULL, 100),
    (v_mod4_id, 'Composição do Grupo de Reparo', 6, 'video', NULL, 100),
    (v_mod4_id, 'Procedimentos para Combate a Incêndio', 7, 'video', NULL, 100);

    -- ==============================================================================
    -- MÓDULO 5: ORGANIZAÇÃO BÁSICA DA MARINHA DO BRASIL (ORDEM 5)
    -- ==============================================================================
    INSERT INTO public.modulos (title, description, "order", forca)
    VALUES ('Organização Básica da Marinha do Brasil', 'Estrutura organizacional e meios navais.', 5, 'navy')
    RETURNING id INTO v_mod5_id;

    INSERT INTO public.aulas (module_id, title, "order", type, url, xp) VALUES
    (v_mod5_id, 'Organização Básica', 1, 'video', NULL, 100),
    (v_mod5_id, 'Meios Navais', 2, 'video', NULL, 100);

    -- ==============================================================================
    -- MÓDULO 6: COMUNICAÇÕES (ORDEM 6)
    -- ==============================================================================
    INSERT INTO public.modulos (title, description, "order", forca)
    VALUES ('Comunicações', 'Sistemas e procedimentos de comunicações navais.', 6, 'navy')
    RETURNING id INTO v_mod6_id;

    INSERT INTO public.aulas (module_id, title, "order", type, url, xp) VALUES
    (v_mod6_id, 'Generalidades sobre Comunicações Navais', 1, 'video', NULL, 100),
    (v_mod6_id, 'Meios de Comunicações e Respectivos Canais', 2, 'video', NULL, 100),
    (v_mod6_id, 'Classificação e Composição das Mensagens', 3, 'video', NULL, 100),
    (v_mod6_id, 'Serviço Postal da Marinha', 4, 'video', NULL, 100);

    -- ==============================================================================
    -- MÓDULO 7: FATOS E TRADIÇÕES DA MARINHA DO BRASIL (ORDEM 7)
    -- ==============================================================================
    INSERT INTO public.modulos (title, description, "order", forca)
    VALUES ('Fatos e Tradições da Marinha do Brasil', 'História, tradições e costumes navais.', 7, 'navy')
    RETURNING id INTO v_mod7_id;

    INSERT INTO public.aulas (module_id, title, "order", type, url, xp) VALUES
    (v_mod7_id, 'Tradições e Uso do Mar', 1, 'video', NULL, 100),
    (v_mod7_id, 'A Marinha do Brasil', 2, 'video', NULL, 100),
    (v_mod7_id, 'Arte Marinheira', 3, 'video', NULL, 100),
    (v_mod7_id, 'Principais Toques de Apitos', 4, 'video', NULL, 100);

    -- ==============================================================================
    -- MÓDULO 8: NOÇÕES DO SERVIÇO GERAL DE TAIFA (ORDEM 8)
    -- ==============================================================================
    INSERT INTO public.modulos (title, description, "order", forca)
    VALUES ('Noções do Serviço Geral de Taifa', 'Serviços de copa, cozinha e arrumação.', 8, 'navy')
    RETURNING id INTO v_mod8_id;

    INSERT INTO public.aulas (module_id, title, "order", type, url, xp) VALUES
    (v_mod8_id, 'Controle Higiênico e Sanitário', 1, 'video', NULL, 100),
    (v_mod8_id, 'Conhecimento e Utilização do Material', 2, 'video', NULL, 100),
    (v_mod8_id, 'Rouparia', 3, 'video', NULL, 100),
    (v_mod8_id, 'Serviços de Despenseiro', 4, 'video', NULL, 100),
    (v_mod8_id, 'Arrumação e Serviço de Mesa', 5, 'video', NULL, 100);

    -- ==============================================================================
    -- MÓDULO 9: DOCUMENTOS ADMINISTRATIVOS (ORDEM 9)
    -- ==============================================================================
    INSERT INTO public.modulos (title, description, "order", forca)
    VALUES ('Documentos Administrativos', 'Introdução à documentação e informática.', 9, 'navy')
    RETURNING id INTO v_mod9_id;

    INSERT INTO public.aulas (module_id, title, "order", type, url, xp) VALUES
    (v_mod9_id, 'Documentos Administrativos', 1, 'video', NULL, 100),
    (v_mod9_id, 'Informática', 2, 'video', NULL, 100);

END $$;

-- 4. VALIDAÇÃO DOS DADOS (OUTPUT DE CONFERÊNCIA)
SELECT '--- MÓDULOS NAVY ---' as check_title;
SELECT "order", title, forca FROM public.modulos WHERE forca = 'navy' ORDER BY "order";

SELECT '--- AULAS DO MÓDULO 0 ---' as check_title;
SELECT l.lesson_order as "ordem", l.title, l.module_id 
FROM public.aulas l
JOIN public.modulos m ON m.id = l.module_id
WHERE m.forca = 'navy' AND m."order" = 0
ORDER BY l.lesson_order;

