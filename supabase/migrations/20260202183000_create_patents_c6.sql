-- ==============================================================================
-- AUDITORIA C6 - INFRAESTRUTURA DE PATENTES (MEMORIAL HIERÁRQUICO)
-- ==============================================================================
-- Motivo: Progressão simbólica institucional (Rank System).
-- Diferença: Possui Hierarquia (Nível) e Histórico Obrigatório.
-- Data: 02/02/2026
-- ==============================================================================

-- 1. TABELA: CATÁLOGO DE PATENTES
CREATE TABLE IF NOT EXISTS public.patentes_catalogo (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo text NOT NULL UNIQUE,  -- 'recruta', 'soldado', 'cabo'
    titulo text NOT NULL,
    nivel integer NOT NULL,       -- 1, 2, 3... (Define a hierarquia)
    descricao text,
    icone_url text,
    ativo boolean DEFAULT true,
    created_at timestamptz DEFAULT now(),
    
    CONSTRAINT unique_nivel_ativo UNIQUE (nivel, codigo) -- Evita duplicidade lógica
);

-- RLS: Leitura pública
ALTER TABLE public.patentes_catalogo ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read patentes" ON public.patentes_catalogo FOR SELECT USING (true);


-- 2. TABELA: REGRAS DE PROMOÇÃO
-- Similar à C5, mas aplicada a Patentes.
CREATE TABLE IF NOT EXISTS public.patente_regras (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patente_id uuid NOT NULL REFERENCES public.patentes_catalogo(id) ON DELETE CASCADE,
    metrica text NOT NULL, -- 'xp_total', 'dias_servico', 'modulos_concluidos'
    operador text NOT NULL DEFAULT '>=',
    valor integer NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- RLS
ALTER TABLE public.patente_regras ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read regras patente" ON public.patente_regras FOR SELECT USING (true);


-- 3. TABELA: HISTÓRICO DE PATENTES (Recruta Patentes)
CREATE TABLE IF NOT EXISTS public.recruta_patentes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    recruta_id uuid NOT NULL REFERENCES public.recrutas(id) ON DELETE CASCADE,
    patente_id uuid NOT NULL REFERENCES public.patentes_catalogo(id) ON DELETE CASCADE,
    promovido_em timestamptz DEFAULT now(),
    motivo text NOT NULL DEFAULT 'promocao_automatica', -- 'merito', 'admin', 'inicial'
    
    -- Diferente de medalhas, aqui permitimos que o usuário tenha patentes antigas.
    -- O 'current' é definido pelo nível mais alto ou data mais recente.
    created_at timestamptz DEFAULT now()
);

-- RLS
ALTER TABLE public.recruta_patentes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "User read own career" ON public.recruta_patentes 
    FOR SELECT USING (auth.uid() = recruta_id);


-- 4. VIEW: PATENTE ATUAL (Latest State)
-- Retorna a patente de maior NÍVEL que o usuário possui.
CREATE OR REPLACE VIEW public.v_recruta_patente_atual AS
SELECT DISTINCT ON (rp.recruta_id)
    rp.recruta_id,
    p.codigo,
    p.titulo,
    p.nivel,
    p.icone_url,
    rp.promovido_em
FROM public.recruta_patentes rp
JOIN public.patentes_catalogo p ON p.id = rp.patente_id
WHERE p.ativo = true
ORDER BY rp.recruta_id, p.nivel DESC, rp.promovido_em DESC;


-- 5. VIEW: HISTÓRICO COMPLETO (Timeline)
CREATE OR REPLACE VIEW public.v_historico_patentes AS
SELECT 
    rp.recruta_id,
    p.titulo,
    p.nivel,
    rp.promovido_em,
    rp.motivo
FROM public.recruta_patentes rp
JOIN public.patentes_catalogo p ON p.id = rp.patente_id
ORDER BY rp.promovido_em DESC;


-- 6. RPC: PROMOVER RECRUTA (Engine Hierárquica)
CREATE OR REPLACE FUNCTION public.promover_recruta(
    p_recruta_id uuid,
    p_patente_codigo text,
    p_motivo text DEFAULT 'merito'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_nova_patente_id uuid;
    v_novo_nivel integer;
    v_nivel_atual integer;
    v_recruta_xp int;
    v_ativo boolean;
    r_regra RECORD;
    v_passou boolean := true;
BEGIN
    -- A. Busca Patente Alvo
    SELECT id, nivel, ativo INTO v_nova_patente_id, v_novo_nivel, v_ativo
    FROM public.patentes_catalogo
    WHERE codigo = p_patente_codigo;

    IF v_nova_patente_id IS NULL OR v_ativo = false THEN
        RETURN false; -- Patente invalida
    END IF;

    -- B. Busca Nível Atual do Recruta (Max Level)
    SELECT MAX(p.nivel) INTO v_nivel_atual
    FROM public.recruta_patentes rp
    JOIN public.patentes_catalogo p ON p.id = rp.patente_id
    WHERE rp.recruta_id = p_recruta_id;

    v_nivel_atual := COALESCE(v_nivel_atual, 0); -- Se 0, é Recruta Nível 0 (sem patente)

    -- C. Validação Hierárquica: Só promove para cima
    -- (Opcional: permitir 'rebaixamento' se p_motivo = 'punicao', mas aqui seguimos regra padrão)
    IF v_novo_nivel <= v_nivel_atual THEN
        RETURN false; -- Já possui patente igual ou superior
    END IF;

    -- D. Check de Já Possui (Idempotência temporal)
    -- Se já tem esse registro exato, ignora? Na verdade o check de nível acima já filtra.
    -- Mas garantimos não duplicar o exato mesmo registro.
    IF EXISTS (SELECT 1 FROM public.recruta_patentes WHERE recruta_id = p_recruta_id AND patente_id = v_nova_patente_id) THEN
        RETURN true; 
    END IF;

    -- E. Engine de Regras (Ex: XP Mínimo)
    SELECT COALESCE(xp, 0) INTO v_recruta_xp FROM public.recrutas WHERE id = p_recruta_id;

    FOR r_regra IN SELECT * FROM public.patente_regras WHERE patente_id = v_nova_patente_id LOOP
        
        -- Regra: XP Total
        IF r_regra.metrica = 'xp_total' THEN
            IF r_regra.operador = '>=' THEN
                IF v_recruta_xp < r_regra.valor THEN v_passou := false; END IF;
            END IF;
        END IF;

        IF v_passou = false THEN EXIT; END IF;
    END LOOP;

    -- F. Concessão
    IF v_passou THEN
        INSERT INTO public.recruta_patentes (recruta_id, patente_id, motivo)
        VALUES (p_recruta_id, v_nova_patente_id, p_motivo);
        RETURN true;
    ELSE
        RETURN false;
    END IF;
END;
$$;
