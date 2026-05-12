-- ==============================================================================
-- SEED QA: DADOS DE TESTE (MANUAL QA)
-- ==============================================================================
-- Execute este script no SQL Editor do Supabase para criar o ambiente de teste.

-- 1. Criação de Módulo de Teste (Visível no Dashboard)
-- Schema corrigido: titulo, descricao, ordem, ativo, is_degustacao
INSERT INTO public.modulos (id, titulo, descricao, ordem, forca, ativo, is_degustacao, created_at)
VALUES (
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', -- ID Fixo para Teste
    'MÓDULO QA - TESTE MANUAL',
    'Módulo exclusivo para validação de fluxo de aula e player.',
    99, -- Ordem alta
    'marinha',
    true, -- Ativo
    false, -- Não é degustação
    now()
) ON CONFLICT (id) DO UPDATE SET
    titulo = EXCLUDED.titulo,
    descricao = EXCLUDED.descricao,
    ativo = true;

-- 2. Criação de Aula 01 (Vídeo Válido)
INSERT INTO public.aulas (id, modulo_id, titulo, descricao, video_url, ordem, xp_recompensa, ativa, created_at)
VALUES (
    'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22', -- ID Fixo Aula 01
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', -- Link ao Módulo QA
    'Aula Teste 01 - Big Buck Bunny',
    'Teste de playback de vídeo e persistência de progresso.',
    'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4', -- Vídeo Público Seguro
    1,
    100,
    true,
    now()
) ON CONFLICT (id) DO UPDATE SET
    video_url = EXCLUDED.video_url,
    ativa = true;

-- 3. Criação de Aula 02 (Vídeo Válido)
INSERT INTO public.aulas (id, modulo_id, titulo, descricao, video_url, ordem, xp_recompensa, ativa, created_at)
VALUES (
    'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380c33', -- ID Fixo Aula 02
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', -- Link ao Módulo QA
    'Aula Teste 02 - Jellyfish',
    'Teste de navegação entre aulas e retorno ao dashboard.',
    'https://test-videos.co.uk/vids/jellyfish/mp4/h264/360/Jellyfish_360_10s_1MB.mp4', -- Vídeo Público Seguro
    2,
    100,
    true,
    now()
) ON CONFLICT (id) DO UPDATE SET
    video_url = EXCLUDED.video_url,
    ativa = true;

-- 4. Confirmação
SELECT id, titulo, video_url FROM public.aulas WHERE module_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
