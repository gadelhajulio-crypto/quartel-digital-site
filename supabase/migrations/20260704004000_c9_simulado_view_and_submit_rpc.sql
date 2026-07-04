-- Quiz/Simulado — view de execução do simulado (agregação) + RPC de submissão/XP.
-- Design: docs/DESIGN_QUIZ_SIMULADO.md §2/§3.

-- ── View de execução do SIMULADO (agrega perguntas dos quizzes de lição do módulo) ──
-- Espelha v_c9_quiz_execucao: expõe perguntas+alternativas SEM revelar `correta`.
-- Um simulado (escopo='simulado_modulo') não tem perguntas próprias; reúne as das
-- lições do seu módulo.
CREATE OR REPLACE VIEW public.v_c9_simulado_execucao WITH (security_invoker = true) AS
SELECT
  s.id        AS simulado_id,
  s.modulo_id,
  s.titulo,
  COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'pergunta_id', p.id,
        'aula_id',     lq.aula_id,
        'enunciado',   p.enunciado,
        'explicacao',  p.explicacao,
        'ordem',       p.ordem,
        'alternativas', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object('alternativa_id', a.id, 'texto', a.texto, 'ordem', a.ordem) ORDER BY a.ordem), '[]'::jsonb)
          FROM public.c9_aula_quiz_alternativas a
          WHERE a.pergunta_id = p.id AND a.ativo = true AND a.deleted_at IS NULL
        )
      ) ORDER BY lq.aula_id, p.ordem
    ) FILTER (WHERE p.id IS NOT NULL), '[]'::jsonb
  ) AS perguntas,
  count(p.id)::integer AS total_perguntas
FROM public.c9_aula_quizzes s
JOIN public.aulas la               ON la.modulo_id = s.modulo_id
JOIN public.c9_aula_quizzes lq     ON lq.aula_id = la.id AND lq.escopo = 'quiz_aula' AND lq.ativo = true AND lq.deleted_at IS NULL
JOIN public.c9_aula_quiz_perguntas p ON p.quiz_id = lq.id AND p.ativo = true AND p.deleted_at IS NULL
WHERE s.escopo = 'simulado_modulo' AND s.ativo = true AND s.deleted_at IS NULL
GROUP BY s.id, s.modulo_id, s.titulo;

GRANT SELECT ON public.v_c9_simulado_execucao TO authenticated;
-- garantir grant nas views de quiz existentes (padrão A-15) — idempotente
GRANT SELECT ON public.v_c9_quiz_execucao  TO authenticated;
GRANT SELECT ON public.v_c9_quiz_resultado TO authenticated;

-- ── RPC de submissão de tentativa (quiz de lição OU simulado de módulo) ──
-- Avalia server-side (gabarito nunca sai do banco), registra tentativa, e concede
-- XP em xp_eventos (ledger canônico do ranking) SÓ na 1ª tentativa (anti-farm).
CREATE OR REPLACE FUNCTION public.rpc_c9_submit_attempt(p_quiz_id uuid, p_respostas jsonb)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_auth        uuid := auth.uid();
  v_recruta_id  uuid;   -- recrutas.id (para xp_eventos + ranking)
  v_forca       text;
  v_escopo      text;
  v_modulo_id   uuid;
  v_aula_id     uuid;
  v_total       integer := 0;
  v_acertos     integer := 0;
  v_percentual  numeric(5,2) := 0;
  v_primeira    boolean := false;
  v_base        integer := 0;
  v_bonus       integer := 0;
  v_xp          integer := 0;
  v_origem      text;
BEGIN
  IF v_auth IS NULL THEN
    RAISE EXCEPTION 'auth required' USING ERRCODE = '42501';
  END IF;

  -- Resolução canônica de recruta (auth_id primário, id como fallback legado)
  SELECT r.id, r.forca INTO v_recruta_id, v_forca
  FROM public.recrutas r
  WHERE r.auth_id = v_auth OR r.id = v_auth
  ORDER BY (r.auth_id = v_auth) DESC
  LIMIT 1;
  IF v_recruta_id IS NULL THEN
    RETURN json_build_object('ok', false, 'reason', 'recruta_not_found');
  END IF;

  SELECT escopo, modulo_id, aula_id INTO v_escopo, v_modulo_id, v_aula_id
  FROM public.c9_aula_quizzes
  WHERE id = p_quiz_id AND ativo = true AND deleted_at IS NULL;
  IF v_escopo IS NULL THEN
    RETURN json_build_object('ok', false, 'reason', 'quiz_not_found');
  END IF;

  -- Conjunto de perguntas do "execução": próprias (quiz_aula) ou agregadas (simulado)
  IF v_escopo = 'quiz_aula' THEN
    SELECT count(*) INTO v_total
    FROM public.c9_aula_quiz_perguntas
    WHERE quiz_id = p_quiz_id AND ativo = true AND deleted_at IS NULL;
  ELSE
    SELECT count(p.id) INTO v_total
    FROM public.aulas la
    JOIN public.c9_aula_quizzes lq     ON lq.aula_id = la.id AND lq.escopo = 'quiz_aula' AND lq.ativo = true AND lq.deleted_at IS NULL
    JOIN public.c9_aula_quiz_perguntas p ON p.quiz_id = lq.id AND p.ativo = true AND p.deleted_at IS NULL
    WHERE la.modulo_id = v_modulo_id;
  END IF;

  -- Acertos: respostas cujo alternativa_id é a correta da respectiva pergunta
  SELECT count(*) INTO v_acertos
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_respostas) = 'array' THEN p_respostas ELSE '[]'::jsonb END) AS r
  JOIN public.c9_aula_quiz_alternativas a
    ON a.id = (r->>'alternativa_id')::uuid
   AND a.pergunta_id = (r->>'pergunta_id')::uuid
   AND a.correta = true AND a.ativo = true AND a.deleted_at IS NULL;

  v_percentual := CASE WHEN v_total > 0 THEN round(100.0 * v_acertos / v_total, 2) ELSE 0 END;

  -- Primeira tentativa? (antes de inserir a atual) — recruta_id na C9 = auth.uid()
  SELECT NOT EXISTS (
    SELECT 1 FROM public.c9_aula_quiz_tentativas WHERE quiz_id = p_quiz_id AND recruta_id = v_auth
  ) INTO v_primeira;

  INSERT INTO public.c9_aula_quiz_tentativas
    (quiz_id, recruta_id, respostas, total_perguntas, total_acertos, percentual, finalizada)
  VALUES
    (p_quiz_id, v_auth, COALESCE(p_respostas, '[]'::jsonb), v_total, v_acertos, v_percentual, true);

  -- XP só na 1ª tentativa (anti-farm). quiz ≤20, simulado ≤100.
  IF v_primeira THEN
    IF v_escopo = 'quiz_aula' THEN
      v_base := 0; v_origem := 'quiz_aula_concluido';
      v_bonus := CASE WHEN v_percentual >= 90 THEN 20 WHEN v_percentual >= 80 THEN 12 WHEN v_percentual >= 70 THEN 6 ELSE 0 END;
    ELSE
      v_base := 40; v_origem := 'simulado_modulo_concluido';
      v_bonus := CASE WHEN v_percentual >= 90 THEN 60 WHEN v_percentual >= 80 THEN 40 WHEN v_percentual >= 70 THEN 20 ELSE 0 END;
    END IF;
    v_xp := v_base + v_bonus;

    -- xp_eventos.quantidade tem CHECK > 0: só grava se houver XP
    IF v_xp > 0 THEN
      INSERT INTO public.xp_eventos (recruta_id, forca, quantidade, origem, referencia_id)
      VALUES (v_recruta_id, v_forca, v_xp, v_origem, p_quiz_id)
      ON CONFLICT DO NOTHING;  -- ux_xp_eventos_quiz_unique: 1 evento por recruta+quiz
    END IF;
  ELSE
    v_xp := 0;
  END IF;

  RETURN json_build_object(
    'ok', true,
    'escopo', v_escopo,
    'total_perguntas', v_total,
    'total_acertos', v_acertos,
    'percentual', v_percentual,
    'primeira_tentativa', v_primeira,
    'xp_concedido', v_xp
  );
END $$;

REVOKE ALL ON FUNCTION public.rpc_c9_submit_attempt(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_c9_submit_attempt(uuid, jsonb) TO authenticated;
