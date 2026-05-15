-- RCC-0.5 — Atualização de microcopy dos instrutores
--
-- Atualiza titulo e descricao para os 3 instrutores canônicos.
-- v_instrutores_app já expõe esses campos; basta atualizar os dados.
--
-- Antes: titulo = 'Sargento' (genérico para todos)
-- Depois: titulo diferenciado por perfil de instrutor

UPDATE public.instrutores
SET
  titulo   = 'INSTRUTOR OBJETIVO',
  descricao = 'Direto, operacional e focado em resultado. Ideal para quem prefere orientação clara, objetiva e sem rodeios.'
WHERE slug = 'ramos';

UPDATE public.instrutores
SET
  titulo   = 'INSTRUTOR ESTRATÉGICO',
  descricao = 'Analítico, estratégico e orientado a planejamento. Ideal para quem quer entender o caminho, organizar decisões e evoluir com método.'
WHERE slug = 'rocha';

UPDATE public.instrutores
SET
  titulo   = 'INSTRUTORA DIDÁTICA',
  descricao = 'Clara, paciente e progressiva. Ideal para quem aprende melhor com explicações guiadas, exemplos práticos e suporte contínuo.'
WHERE slug = 'sara';

-- Validação:
-- SELECT slug, titulo, descricao FROM public.instrutores ORDER BY ordem_exibicao;
