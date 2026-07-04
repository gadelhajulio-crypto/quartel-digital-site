-- A-22 (cont.) — views de quiz pré-existentes: mesmo tratamento da v_c9_simulado_execucao.
--
-- v_c9_quiz_execucao: NÃO expõe `correta` → basta rodar como owner (security definer)
--   para funcionar sem GRANT nas tabelas c9 (que não podem ser concedidas — gabarito).
-- v_c9_quiz_resultado: EXPÕE `correta` (revisão pós-resposta, ok), MAS hoje depende do
--   RLS "own attempts" para escopar ao usuário. Como definer o RLS é ignorado, então
--   ADICIONA-SE filtro explícito `recruta_id = auth.uid()` — senão exporia tentativas
--   de outros recrutas. (recruta_id na C9 = auth.uid(), por convenção da camada.)

-- ── v_c9_quiz_execucao → security definer (não expõe gabarito) ──
ALTER VIEW public.v_c9_quiz_execucao SET (security_invoker = false);
GRANT SELECT ON public.v_c9_quiz_execucao TO authenticated;

-- ── v_c9_quiz_resultado → security definer + filtro explícito por auth.uid() ──
CREATE OR REPLACE VIEW public.v_c9_quiz_resultado AS
 WITH respostas_expandidas AS (
   SELECT t_1.id AS tentativa_id,
          t_1.quiz_id,
          t_1.recruta_id,
          t_1.created_at,
          ((r.value ->> 'pergunta_id'))::uuid    AS pergunta_id,
          ((r.value ->> 'alternativa_id'))::uuid AS alternativa_id
   FROM public.c9_aula_quiz_tentativas t_1
     CROSS JOIN LATERAL jsonb_array_elements(
       CASE WHEN jsonb_typeof(t_1.respostas) = 'array' THEN t_1.respostas ELSE '[]'::jsonb END
     ) r(value)
   WHERE t_1.recruta_id = auth.uid()        -- escopo explícito (definer ignora RLS)
 ), avaliadas AS (
   SELECT re.tentativa_id, re.quiz_id, re.recruta_id, re.created_at,
          p.id AS pergunta_id, p.enunciado, p.explicacao, p.ordem,
          re.alternativa_id, a.texto AS alternativa_texto,
          COALESCE(a.correta, false) AS correta
   FROM respostas_expandidas re
     JOIN public.c9_aula_quiz_perguntas p ON p.id = re.pergunta_id
     LEFT JOIN public.c9_aula_quiz_alternativas a ON a.id = re.alternativa_id AND a.pergunta_id = p.id
 )
 SELECT t.id AS tentativa_id, t.quiz_id, t.recruta_id, t.created_at,
        t.total_perguntas, t.total_acertos, t.percentual, t.finalizada,
        COALESCE(jsonb_agg(jsonb_build_object(
          'pergunta_id', av.pergunta_id, 'enunciado', av.enunciado,
          'alternativa_id', av.alternativa_id, 'alternativa_texto', av.alternativa_texto,
          'correta', av.correta,
          'status', CASE WHEN av.correta THEN 'convergente' ELSE 'divergente' END,
          'explicacao', av.explicacao, 'ordem', av.ordem
        ) ORDER BY av.ordem) FILTER (WHERE av.pergunta_id IS NOT NULL), '[]'::jsonb) AS questoes
 FROM public.c9_aula_quiz_tentativas t
   LEFT JOIN avaliadas av ON av.tentativa_id = t.id
 WHERE t.recruta_id = auth.uid()            -- escopo explícito (definer ignora RLS)
 GROUP BY t.id, t.quiz_id, t.recruta_id, t.created_at, t.total_perguntas, t.total_acertos, t.percentual, t.finalizada;

GRANT SELECT ON public.v_c9_quiz_resultado TO authenticated;
