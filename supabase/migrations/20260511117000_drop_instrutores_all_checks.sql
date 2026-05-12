-- RCC-0.5 / Wave 1 — Remover todas as CHECK constraints da tabela instrutores
-- A tabela foi criada com constraints que rejeitam os novos slugs/codigos dos instrutores Wave 1.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    WHERE t.relname = 'instrutores'
      AND t.relnamespace = 'public'::regnamespace
      AND c.contype = 'c'
  LOOP
    EXECUTE format('ALTER TABLE public.instrutores DROP CONSTRAINT IF EXISTS %I', r.conname);
  END LOOP;
END;
$$;
