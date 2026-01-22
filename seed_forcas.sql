-- CRIAÇÃO DA TABELA FORCAS
CREATE TABLE IF NOT EXISTS public.forcas (
    id TEXT PRIMARY KEY, -- 'marinha', 'exercito', 'aeronautica'
    nome TEXT NOT NULL,
    cor_primaria TEXT NOT NULL,
    cor_secundaria TEXT NOT NULL,
    cor_fundo TEXT NOT NULL,
    icone TEXT
);

-- Ativa RLS (opcional, mas boa prática - definindo política de leitura pública)
ALTER TABLE public.forcas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Leitura pública de forças" 
ON public.forcas FOR SELECT 
TO authenticated, anon 
USING (true);

-- SEED DOS DADOS (Cores tiradas do forceThemes.ts)
INSERT INTO public.forcas (id, nome, cor_primaria, cor_secundaria, cor_fundo, icone)
VALUES
('marinha', 'Marinha do Brasil', '#0A2A43', '#C9A24D', '#060F18', '⚓'),
('exercito', 'Exército Brasileiro', '#2F3E1E', '#A3B18A', '#141A10', '🪖'),
('aeronautica', 'Força Aérea Brasileira', '#1C2B3A', '#5DA9E9', '#0B1620', '✈️')
ON CONFLICT (id) DO UPDATE SET
    cor_primaria = EXCLUDED.cor_primaria,
    cor_secundaria = EXCLUDED.cor_secundaria,
    cor_fundo = EXCLUDED.cor_fundo,
    icone = EXCLUDED.icone;
