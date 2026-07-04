-- A-18 — Reconciliação de drift da camada C9 (didático/avaliações).
--
-- CONTEXTO: a migration 20260427214001_create_c9_didactic_layer.sql foi uma
-- "migration de sincronização" com CREATE TABLE IF NOT EXISTS. As tabelas c9_ já
-- existiam no remoto (criadas direto no prod), então aquela migration virou NO-OP:
-- consta como aplicada, mas descreve colunas que NUNCA vigoraram no banco real
-- (ex.: pergunta vs enunciado, is_correta vs correta, frente/verso vs pergunta/resposta,
-- pontuacao/respostas_jsonb/sucesso vs a estrutura real de tentativas). O repo, portanto,
-- documentava um schema c9 falso. Ver docs/AUDITORIA_INICIAL.md (A-18).
--
-- OBJETIVO: reconciliar o repo com o estado REAL do remoto (introspecção via
-- supabase/remote/supabase_remote_schema.sql), para que o trabalho novo de
-- quiz/simulado seja construído sobre o schema verdadeiro.
--
-- SEGURANÇA: 100% idempotente. No remoto (onde as colunas reais já existem) todo
-- ADD COLUMN IF NOT EXISTS é pulado → NO-OP. Constraints via DO-guard (pg_constraint).
-- Nenhum DROP (não remove as colunas do no-op antigo caso existam em algum ambiente
-- fresh — elas são inofensivas; o que importa é garantir as colunas REAIS).

-- ── c9_aula_conteudos ─────────────────────────────────────────────────────────
ALTER TABLE public.c9_aula_conteudos ADD COLUMN IF NOT EXISTS tipo            text;
ALTER TABLE public.c9_aula_conteudos ADD COLUMN IF NOT EXISTS titulo          text;
ALTER TABLE public.c9_aula_conteudos ADD COLUMN IF NOT EXISTS corpo_markdown  text;
ALTER TABLE public.c9_aula_conteudos ADD COLUMN IF NOT EXISTS versao          integer DEFAULT 1 NOT NULL;
ALTER TABLE public.c9_aula_conteudos ADD COLUMN IF NOT EXISTS origem          text    DEFAULT 'QD_FACTORY' NOT NULL;
ALTER TABLE public.c9_aula_conteudos ADD COLUMN IF NOT EXISTS metadata        jsonb   DEFAULT '{}'::jsonb NOT NULL;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'c9_aula_conteudos_tipo_check') THEN
    ALTER TABLE public.c9_aula_conteudos ADD CONSTRAINT c9_aula_conteudos_tipo_check
      CHECK (tipo = ANY (ARRAY['roteiro','resumo','explicacao','markdown','material_complementar']));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'c9_aula_conteudos_versao_check') THEN
    ALTER TABLE public.c9_aula_conteudos ADD CONSTRAINT c9_aula_conteudos_versao_check CHECK (versao > 0);
  END IF;
END $$;

-- ── c9_aula_flashcards ────────────────────────────────────────────────────────
ALTER TABLE public.c9_aula_flashcards ADD COLUMN IF NOT EXISTS pergunta  text;
ALTER TABLE public.c9_aula_flashcards ADD COLUMN IF NOT EXISTS resposta  text;
ALTER TABLE public.c9_aula_flashcards ADD COLUMN IF NOT EXISTS origem    text  DEFAULT 'QD_FACTORY' NOT NULL;
ALTER TABLE public.c9_aula_flashcards ADD COLUMN IF NOT EXISTS metadata  jsonb DEFAULT '{}'::jsonb NOT NULL;

-- ── c9_aula_quizzes ───────────────────────────────────────────────────────────
ALTER TABLE public.c9_aula_quizzes ADD COLUMN IF NOT EXISTS origem   text  DEFAULT 'QD_FACTORY' NOT NULL;
ALTER TABLE public.c9_aula_quizzes ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}'::jsonb NOT NULL;

-- ── c9_aula_quiz_perguntas ────────────────────────────────────────────────────
ALTER TABLE public.c9_aula_quiz_perguntas ADD COLUMN IF NOT EXISTS enunciado text;
ALTER TABLE public.c9_aula_quiz_perguntas ADD COLUMN IF NOT EXISTS metadata  jsonb DEFAULT '{}'::jsonb NOT NULL;

-- ── c9_aula_quiz_alternativas ─────────────────────────────────────────────────
ALTER TABLE public.c9_aula_quiz_alternativas ADD COLUMN IF NOT EXISTS correta  boolean DEFAULT false NOT NULL;
ALTER TABLE public.c9_aula_quiz_alternativas ADD COLUMN IF NOT EXISTS metadata jsonb   DEFAULT '{}'::jsonb NOT NULL;

-- ── c9_aula_quiz_tentativas ───────────────────────────────────────────────────
ALTER TABLE public.c9_aula_quiz_tentativas ADD COLUMN IF NOT EXISTS respostas       jsonb        DEFAULT '[]'::jsonb NOT NULL;
ALTER TABLE public.c9_aula_quiz_tentativas ADD COLUMN IF NOT EXISTS total_perguntas integer      DEFAULT 0 NOT NULL;
ALTER TABLE public.c9_aula_quiz_tentativas ADD COLUMN IF NOT EXISTS total_acertos   integer      DEFAULT 0 NOT NULL;
ALTER TABLE public.c9_aula_quiz_tentativas ADD COLUMN IF NOT EXISTS percentual      numeric(5,2) DEFAULT 0 NOT NULL;
ALTER TABLE public.c9_aula_quiz_tentativas ADD COLUMN IF NOT EXISTS finalizada      boolean      DEFAULT true NOT NULL;
ALTER TABLE public.c9_aula_quiz_tentativas ADD COLUMN IF NOT EXISTS metadata        jsonb        DEFAULT '{}'::jsonb NOT NULL;

-- NOTA: função de updated_at real é public.c9_set_updated_at (triggers c9_*_updated_at)
-- e as views v_c9_quiz_execucao / v_c9_quiz_resultado / v_c9_aula_execucao + RLS já
-- existem no remoto e referenciam as colunas reais acima — não redeclaradas aqui para
-- manter esta reconciliação mínima e no-op. O schema real de referência está em
-- supabase/remote/supabase_remote_schema.sql.
