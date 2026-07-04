import { useEffect, useState } from 'react';
import { getQuizForLesson, getSimuladoForModule, QuizExecucao } from '../services/quizService';

// Carrega o quiz de uma lição (por aula_id). quiz=null quando a lição não tem quiz.
export function useLessonQuiz(aulaId: string | undefined) {
  const [quiz, setQuiz] = useState<QuizExecucao | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    if (!aulaId) { setLoading(false); return; }
    setLoading(true);
    getQuizForLesson(aulaId)
      .then((q) => { if (active) setQuiz(q); })
      .catch(() => { if (active) setQuiz(null); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [aulaId]);

  return { quiz, loading };
}

// Carrega o simulado de um módulo (por modulo_id). null quando o módulo não tem simulado.
export function useModuleSimulado(moduloId: string | undefined) {
  const [simulado, setSimulado] = useState<QuizExecucao | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    if (!moduloId) { setLoading(false); return; }
    setLoading(true);
    getSimuladoForModule(moduloId)
      .then((s) => { if (active) setSimulado(s); })
      .catch(() => { if (active) setSimulado(null); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [moduloId]);

  return { simulado, loading };
}
