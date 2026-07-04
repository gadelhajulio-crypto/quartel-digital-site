-- Seed do esqueleto MÍNIMO de quiz/simulado — Exército & Aeronáutica.
-- Prova o pipeline (módulo→lição→quiz→XP→simulado) para as forças sem conteúdo.
-- TUDO is_placeholder=true. Marinha fora (conteúdo real, quiz autorado depois).
--
-- Por força: 2 módulos × 2 lições; 1 quiz/lição × 2 perguntas × 4 alternativas;
-- 1 simulado/módulo (agregação — SEM perguntas próprias).
-- Total Ex+Aero: 4 módulos, 8 aulas, 8 quizzes de lição, 4 simulados,
--                16 perguntas, 64 alternativas.
-- Idempotente: guard por is_placeholder existente.

DO $$
DECLARE
  v_forca      text;
  v_forca_cap  text;
  v_mod        integer;
  v_lic        integer;
  v_p          integer;
  v_a          integer;
  v_modulo_id  uuid;
  v_aula_id    uuid;
  v_quiz_id    uuid;
  v_pergunta_id uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM public.modulos WHERE is_placeholder AND forca IN ('exercito','aeronautica')) THEN
    RAISE NOTICE 'Seed placeholder Ex/Aero já existe — pulando.';
    RETURN;
  END IF;

  FOREACH v_forca IN ARRAY ARRAY['exercito','aeronautica'] LOOP
    v_forca_cap := initcap(v_forca);

    FOR v_mod IN 1..2 LOOP
      INSERT INTO public.modulos (forca, titulo, ordem, ativo, is_degustacao, is_placeholder)
      VALUES (v_forca, format('[Placeholder] Módulo %s — %s', v_mod, v_forca_cap), v_mod, true, false, true)
      RETURNING id INTO v_modulo_id;

      -- Simulado do módulo (escopo simulado_modulo, sem perguntas próprias)
      INSERT INTO public.c9_aula_quizzes (aula_id, modulo_id, escopo, titulo, ativo, is_placeholder)
      VALUES (NULL, v_modulo_id, 'simulado_modulo',
              format('[Placeholder] Simulado — Módulo %s — %s', v_mod, v_forca_cap), true, true);

      FOR v_lic IN 1..2 LOOP
        INSERT INTO public.aulas (modulo_id, titulo, ordem, xp_valor, is_placeholder)
        VALUES (v_modulo_id, format('[Placeholder] Lição %s — Módulo %s — %s', v_lic, v_mod, v_forca_cap), v_lic, 0, true)
        RETURNING id INTO v_aula_id;

        -- Quiz da lição
        INSERT INTO public.c9_aula_quizzes (aula_id, modulo_id, escopo, titulo, ativo, is_placeholder)
        VALUES (v_aula_id, NULL, 'quiz_aula',
                format('[Placeholder] Quiz — Lição %s — Módulo %s — %s', v_lic, v_mod, v_forca_cap), true, true)
        RETURNING id INTO v_quiz_id;

        FOR v_p IN 1..2 LOOP
          INSERT INTO public.c9_aula_quiz_perguntas (quiz_id, enunciado, explicacao, ordem, is_placeholder)
          VALUES (v_quiz_id,
                  format('Pergunta de exemplo %s — [Placeholder] Lição %s — Módulo %s — %s', v_p, v_lic, v_mod, v_forca_cap),
                  'Explicação de exemplo (placeholder).', v_p, true)
          RETURNING id INTO v_pergunta_id;

          FOR v_a IN 1..4 LOOP
            INSERT INTO public.c9_aula_quiz_alternativas (pergunta_id, texto, correta, ordem)
            VALUES (v_pergunta_id, format('Alternativa %s (exemplo)', v_a), (v_a = 1), v_a);
          END LOOP;
        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Seed placeholder Ex/Aero criado.';
END $$;
