-- ==============================================================================
-- CAMADA C9 - CONTEÚDO DIDÁTICO E AVALIAÇÕES (MIGRATION DE SINCRONIZAÇÃO)
-- ==============================================================================
-- Objetivo: Refletir o estado exato das tabelas c9_ do banco de dados remoto
-- para o ambiente local em um script idempotente.
-- Data: 27/04/2026
-- ==============================================================================

-- 1. EXTENSÕES & REQUISITOS OBRIGATÓRIOS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ==============================================================================
-- DDL DAS TABELAS
-- ==============================================================================

-- 1.1 Conteúdos Ricos (Texto, Markdown, HTML atrelado a uma aula)
CREATE TABLE IF NOT EXISTS public.c9_aula_conteudos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    aula_id UUID NOT NULL REFERENCES public.aulas(id) ON DELETE CASCADE,
    conteudo TEXT NOT NULL,
    ativo BOOLEAN NOT NULL DEFAULT true,
    deleted_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 1.2 Flashcards (Frente e Verso para revisão de espaço)
CREATE TABLE IF NOT EXISTS public.c9_aula_flashcards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    aula_id UUID NOT NULL REFERENCES public.aulas(id) ON DELETE CASCADE,
    frente TEXT NOT NULL,
    verso TEXT NOT NULL,
    ordem INTEGER NOT NULL DEFAULT 0,
    ativo BOOLEAN NOT NULL DEFAULT true,
    deleted_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 1.3 Quizzes / Avaliações (Cabeçalho do Quiz por Aula)
CREATE TABLE IF NOT EXISTS public.c9_aula_quizzes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    aula_id UUID NOT NULL REFERENCES public.aulas(id) ON DELETE CASCADE,
    titulo TEXT,
    descricao TEXT,
    ativo BOOLEAN NOT NULL DEFAULT true,
    deleted_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 1.4 Perguntas do Quiz
CREATE TABLE IF NOT EXISTS public.c9_aula_quiz_perguntas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    quiz_id UUID NOT NULL REFERENCES public.c9_aula_quizzes(id) ON DELETE CASCADE,
    pergunta TEXT NOT NULL,
    explicacao TEXT, -- Explicação exibida pós-resposta
    ordem INTEGER NOT NULL DEFAULT 0,
    ativo BOOLEAN NOT NULL DEFAULT true,
    deleted_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 1.5 Alternativas da Pergunta
CREATE TABLE IF NOT EXISTS public.c9_aula_quiz_alternativas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pergunta_id UUID NOT NULL REFERENCES public.c9_aula_quiz_perguntas(id) ON DELETE CASCADE,
    texto TEXT NOT NULL,
    is_correta BOOLEAN NOT NULL DEFAULT false,
    ordem INTEGER NOT NULL DEFAULT 0,
    ativo BOOLEAN NOT NULL DEFAULT true,
    deleted_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 1.6 Tentativas de Resolução (Ledger)
CREATE TABLE IF NOT EXISTS public.c9_aula_quiz_tentativas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    quiz_id UUID NOT NULL REFERENCES public.c9_aula_quizzes(id) ON DELETE CASCADE,
    recruta_id UUID NOT NULL REFERENCES auth.users(id), -- Ponto de segurança e RLS
    pontuacao NUMERIC(5,2),
    respostas_jsonb JSONB NOT NULL DEFAULT '{}'::jsonb,
    sucesso BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ==============================================================================
-- CONSTRAINTS E ÍNDICES ÚNICOS PARCIAIS (1 Versão Ativa)
-- ==============================================================================

-- Aulas só podem ter 1 conteúdo rico ativo por vez
CREATE UNIQUE INDEX IF NOT EXISTS c9_idx_unique_conteudo_ativo 
ON public.c9_aula_conteudos (aula_id) 
WHERE ativo = true AND deleted_at IS NULL;

-- Aulas só podem ter 1 quiz ativo por vez
CREATE UNIQUE INDEX IF NOT EXISTS c9_idx_unique_quiz_ativo 
ON public.c9_aula_quizzes (aula_id) 
WHERE ativo = true AND deleted_at IS NULL;

-- Índices de performance geral (Foreign keys)
CREATE INDEX IF NOT EXISTS c9_idx_conteudos_aula ON public.c9_aula_conteudos(aula_id);
CREATE INDEX IF NOT EXISTS c9_idx_flashcards_aula ON public.c9_aula_flashcards(aula_id);
CREATE INDEX IF NOT EXISTS c9_idx_quizzes_aula ON public.c9_aula_quizzes(aula_id);
CREATE INDEX IF NOT EXISTS c9_idx_perguntas_quiz ON public.c9_aula_quiz_perguntas(quiz_id);
CREATE INDEX IF NOT EXISTS c9_idx_alternativas_pergunta ON public.c9_aula_quiz_alternativas(pergunta_id);
CREATE INDEX IF NOT EXISTS c9_idx_tentativas_recruta ON public.c9_aula_quiz_tentativas(recruta_id);

-- ==============================================================================
-- ROW LEVEL SECURITY (RLS) & POLICIES
-- ==============================================================================

-- Habilita proteção RLS em todas as tabelas
ALTER TABLE public.c9_aula_conteudos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.c9_aula_flashcards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.c9_aula_quizzes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.c9_aula_quiz_perguntas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.c9_aula_quiz_alternativas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.c9_aula_quiz_tentativas ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- REGRA 1: USUÁRIOS AUTENTICADOS (LEITURA DE ATIVOS)
-- "authenticated pode ler conteúdo ativo" -> WHERE ativo=true AND deleted_at is null
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "Public read active contents" ON public.c9_aula_conteudos;
CREATE POLICY "Public read active contents" ON public.c9_aula_conteudos
    FOR SELECT TO authenticated
    USING (ativo = true AND deleted_at IS NULL);

DROP POLICY IF EXISTS "Public read active flashcards" ON public.c9_aula_flashcards;
CREATE POLICY "Public read active flashcards" ON public.c9_aula_flashcards
    FOR SELECT TO authenticated
    USING (ativo = true AND deleted_at IS NULL);

DROP POLICY IF EXISTS "Public read active quizzes" ON public.c9_aula_quizzes;
CREATE POLICY "Public read active quizzes" ON public.c9_aula_quizzes
    FOR SELECT TO authenticated
    USING (ativo = true AND deleted_at IS NULL);

DROP POLICY IF EXISTS "Public read active questions" ON public.c9_aula_quiz_perguntas;
CREATE POLICY "Public read active questions" ON public.c9_aula_quiz_perguntas
    FOR SELECT TO authenticated
    USING (ativo = true AND deleted_at IS NULL);

DROP POLICY IF EXISTS "Public read active alternatives" ON public.c9_aula_quiz_alternativas;
CREATE POLICY "Public read active alternatives" ON public.c9_aula_quiz_alternativas
    FOR SELECT TO authenticated
    USING (ativo = true AND deleted_at IS NULL);

-- ------------------------------------------------------------------------------
-- REGRA 2: SERVICE ROLE (ACESSO ABSOLUTO PARA ESCRITA/ADMINISTRAÇÃO)
-- "service role controla escrita de conteúdo"
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "Service Role Absolute Access" ON public.c9_aula_conteudos;
CREATE POLICY "Service Role Absolute Access" ON public.c9_aula_conteudos FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Service Role Absolute Access" ON public.c9_aula_flashcards;
CREATE POLICY "Service Role Absolute Access" ON public.c9_aula_flashcards FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Service Role Absolute Access" ON public.c9_aula_quizzes;
CREATE POLICY "Service Role Absolute Access" ON public.c9_aula_quizzes FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Service Role Absolute Access" ON public.c9_aula_quiz_perguntas;
CREATE POLICY "Service Role Absolute Access" ON public.c9_aula_quiz_perguntas FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Service Role Absolute Access" ON public.c9_aula_quiz_alternativas;
CREATE POLICY "Service Role Absolute Access" ON public.c9_aula_quiz_alternativas FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Service Role Absolute Access" ON public.c9_aula_quiz_tentativas;
CREATE POLICY "Service Role Absolute Access" ON public.c9_aula_quiz_tentativas FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ------------------------------------------------------------------------------
-- REGRA 3: TENTATIVAS DE USUÁRIO (ISOLAMENTO DE ESCRITA/LEITURA POR UID)
-- "usuário autenticado só registra próprias tentativas protegidas via recrutas.auth_id = auth.uid()"
-- Resolvido aqui como `recruta_id = auth.uid()`
-- ------------------------------------------------------------------------------

DROP POLICY IF EXISTS "User write own attempts" ON public.c9_aula_quiz_tentativas;
CREATE POLICY "User write own attempts" ON public.c9_aula_quiz_tentativas
    FOR INSERT TO authenticated
    WITH CHECK (recruta_id = auth.uid());

DROP POLICY IF EXISTS "User read own attempts" ON public.c9_aula_quiz_tentativas;
CREATE POLICY "User read own attempts" ON public.c9_aula_quiz_tentativas
    FOR SELECT TO authenticated
    USING (recruta_id = auth.uid());

-- Trigger para automatizar o updated_at em tabelas com esse timestamp
CREATE OR REPLACE FUNCTION public.c9_update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Aplica trigger em todas as tabelas content (Idempotente ao usar DROP antes ou CREATE OR REPLACE se comportado)
DROP TRIGGER IF EXISTS set_c9_aula_conteudos_updated_at ON public.c9_aula_conteudos;
CREATE TRIGGER set_c9_aula_conteudos_updated_at
BEFORE UPDATE ON public.c9_aula_conteudos FOR EACH ROW EXECUTE FUNCTION public.c9_update_updated_at_column();

DROP TRIGGER IF EXISTS set_c9_aula_quizzes_updated_at ON public.c9_aula_quizzes;
CREATE TRIGGER set_c9_aula_quizzes_updated_at
BEFORE UPDATE ON public.c9_aula_quizzes FOR EACH ROW EXECUTE FUNCTION public.c9_update_updated_at_column();
