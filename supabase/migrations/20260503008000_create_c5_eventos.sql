-- ==============================================================================
-- EVENTOS INSTITUCIONAIS C5: c5_eventos + v_eventos_pendentes + consumir_evento_c5
-- ==============================================================================
-- Frontend: c5EventsService.ts
--   - .from('v_eventos_pendentes').select('*')
--   - .rpc('consumir_evento_c5', { p_evento_id })
-- Data: 03/05/2026
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.c5_eventos (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    recruta_id    UUID        REFERENCES public.recrutas(id) ON DELETE CASCADE,
                                -- NULL = evento global (para todas as forças)
    tipo          TEXT        NOT NULL,
                                -- 'medalha' | 'patente' | 'security_logout' | etc.
    referencia_id TEXT,         -- ID do recurso associado (medalha_codigo, patente_codigo)
    titulo        TEXT        NOT NULL,
    descricao     TEXT        NOT NULL DEFAULT '',
    prioridade    INTEGER     NOT NULL DEFAULT 3,
                                -- 1=patente_nivel6, 2=patente, 3=medalha, 4=outros
    cycle_id      TEXT,         -- ciclo associado (opcional)

    processado    BOOLEAN     NOT NULL DEFAULT false,
    emitido_em    TIMESTAMPTZ NOT NULL DEFAULT now(),
    processado_em TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_c5_eventos_recruta
    ON public.c5_eventos (recruta_id, processado);
CREATE INDEX IF NOT EXISTS idx_c5_eventos_pendentes
    ON public.c5_eventos (processado) WHERE processado = false;

ALTER TABLE public.c5_eventos ENABLE ROW LEVEL SECURITY;

-- Recruta vê apenas seus próprios eventos não processados
DROP POLICY IF EXISTS "User read own c5 events" ON public.c5_eventos;
CREATE POLICY "User read own c5 events"
    ON public.c5_eventos FOR SELECT TO authenticated
    USING (recruta_id = auth.uid() AND processado = false);

DROP POLICY IF EXISTS "Service role full c5 events" ON public.c5_eventos;
CREATE POLICY "Service role full c5 events"
    ON public.c5_eventos FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- VIEW: v_eventos_pendentes
-- c5EventsService espera: id, recruta_id, tipo, referencia_id, titulo,
--                         descricao, prioridade, cycle_id, emitido_em, processado
CREATE OR REPLACE VIEW public.v_eventos_pendentes AS
SELECT
    e.id,
    e.recruta_id,
    e.tipo,
    e.referencia_id,
    e.titulo,
    e.descricao,
    e.prioridade,
    e.cycle_id,
    e.emitido_em,
    e.processado
FROM public.c5_eventos e
WHERE e.recruta_id = auth.uid()
  AND e.processado = false
ORDER BY e.prioridade ASC, e.emitido_em ASC;

-- RPC: consumir_evento_c5
-- Marca o evento como processado. Idempotente: retorna true se já processado.
-- SECURITY DEFINER: garante que o recruta só consuma seus próprios eventos.
CREATE OR REPLACE FUNCTION public.consumir_evento_c5(
    p_evento_id UUID
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_recruta_id UUID;
BEGIN
    -- Verifica existência e ownership
    SELECT recruta_id INTO v_recruta_id
    FROM public.c5_eventos
    WHERE id = p_evento_id;

    IF v_recruta_id IS NULL THEN
        RETURN false;  -- Evento não existe
    END IF;

    IF v_recruta_id != auth.uid() THEN
        RETURN false;  -- Não pertence ao recruta atual
    END IF;

    -- Idempotente: se já processado, retorna true sem erro
    UPDATE public.c5_eventos
    SET processado = true, processado_em = now()
    WHERE id = p_evento_id
      AND processado = false;

    RETURN true;
END;
$$;

-- ==============================================================================
-- TESTES
-- ==============================================================================
-- SELECT * FROM public.v_eventos_pendentes;
-- SELECT public.consumir_evento_c5('<uuid>');

-- ==============================================================================
-- ROLLBACK
-- ==============================================================================
-- DROP VIEW IF EXISTS public.v_eventos_pendentes;
-- DROP FUNCTION IF EXISTS public.consumir_evento_c5(UUID);
-- DROP TABLE IF EXISTS public.c5_eventos;
