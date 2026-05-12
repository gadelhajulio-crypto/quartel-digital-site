-- ==============================================================================
-- AUDITORIA C5 - INFRAESTRUTURA DE MEDALHAS (COM REGRAS DINÂMICAS)
-- ==============================================================================
-- Motivo: Sistema de conquistas simbólicas com validação via banco.
-- Tabela de Regras permite ajustar dificuldade sem deploy de código.
-- Data: 02/02/2026
-- ==============================================================================

-- 1. TABELA DE MEDALHAS (Definição)
CREATE TABLE IF NOT EXISTS public.medalhas (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo text NOT NULL UNIQUE, -- Slug: 'primeira-vitoria', 'xp-1000'
    nome text NOT NULL,
    descricao text,
    icone_url text,
    ativo boolean DEFAULT true,
    created_at timestamptz DEFAULT now()
);

-- 2. TABELA DE REGRAS (Lógica Dinâmica)
-- Define critérios para conquistar a medalha.
-- Ex: medalha_id=X, metrica='xp_minimo', valor=1000
-- Se uma medalha tiver múltiplas regras, TODAS devem ser atendidas (AND).
CREATE TABLE IF NOT EXISTS public.medalha_regras (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    medalha_id uuid NOT NULL REFERENCES public.medalhas(id) ON DELETE CASCADE,
    metrica text NOT NULL, -- 'xp_total', 'aulas_concluidas'
    operador text NOT NULL DEFAULT '>=', -- '>=', '=', '>'
    valor integer NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- 3. TABELA DE CONCESSÕES (Ledger)
CREATE TABLE IF NOT EXISTS public.recruta_medalhas (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    recruta_id uuid NOT NULL REFERENCES public.recrutas(id) ON DELETE CASCADE,
    medalha_id uuid NOT NULL REFERENCES public.medalhas(id) ON DELETE CASCADE,
    concedido_em timestamptz DEFAULT now(),
    UNIQUE(recruta_id, medalha_id)
);

-- RLS
ALTER TABLE public.medalhas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read medalhas" ON public.medalhas FOR SELECT USING (true);

ALTER TABLE public.medalha_regras ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read regras" ON public.medalha_regras FOR SELECT USING (true);

ALTER TABLE public.recruta_medalhas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "User read own medals" ON public.recruta_medalhas FOR SELECT USING (auth.uid() = recruta_id);

-- 4. VIEW: RECRUTA MEDALHAS (Frontend)
CREATE OR REPLACE VIEW public.v_recruta_medalhas AS
SELECT 
    rm.recruta_id,
    rm.concedido_em,
    m.codigo,
    m.nome,
    m.descricao,
    m.icone_url
FROM public.recruta_medalhas rm
JOIN public.medalhas m ON m.id = rm.medalha_id
WHERE m.ativo = true;

-- 5. RPC: GRANT MEDAL (Engine de Validação)
CREATE OR REPLACE FUNCTION public.grant_medal(
    recruta_id uuid,
    medalha_codigo text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_medalha_id uuid;
    v_ativo boolean;
    r_regra RECORD;
    v_recruta_xp int;
    v_recruta_aulas int;
    v_passou boolean := true;
BEGIN
    -- 1. Busca Medalha
    SELECT id, ativo INTO v_medalha_id, v_ativo
    FROM public.medalhas
    WHERE codigo = medalha_codigo;

    IF v_medalha_id IS NULL OR v_ativo = false THEN
        RETURN false; -- Medalha não existe ou inativa
    END IF;

    -- 2. Verifica se já possui
    IF EXISTS (SELECT 1 FROM public.recruta_medalhas WHERE recruta_id = grant_medal.recruta_id AND medalha_id = v_medalha_id) THEN
        RETURN true; -- Já possui, considera sucesso (idempotente)
    END IF;

    -- 3. Engine de Regras
    -- Carrega dados do recruta para comparação
    SELECT COALESCE(xp, 0) INTO v_recruta_xp FROM public.recrutas WHERE id = recruta_id;
    
    -- (Opcional) Contar aulas concluídas se necessário
    -- SELECT COUNT(*) INTO v_recruta_aulas FROM public.recruta_progresso WHERE recruta_id = grant_medal.recruta_id;

    -- Itera sobre as regras da medalha
    FOR r_regra IN SELECT * FROM public.medalha_regras WHERE medalha_id = v_medalha_id LOOP
        
        -- Regra: XP Mínimo
        IF r_regra.metrica = 'xp_total' THEN
            IF r_regra.operador = '>=' THEN
                IF v_recruta_xp < r_regra.valor THEN v_passou := false; END IF;
            END IF;
        END IF;

        -- Regra: Manual (ex: evento específico, skip check via DB)
        -- Se metrica for 'evento_manual', supomos que a chamada RPC é a prova.

        -- Se falhar em qualquer regra, para.
        IF v_passou = false THEN EXIT; END IF;
    END LOOP;

    -- 4. Concessão
    IF v_passou THEN
        INSERT INTO public.recruta_medalhas (recruta_id, medalha_id)
        VALUES (recruta_id, v_medalha_id)
        ON CONFLICT DO NOTHING;
        RETURN true;
    ELSE
        RETURN false; -- Critérios não atendidos
    END IF;
END;
$$;
