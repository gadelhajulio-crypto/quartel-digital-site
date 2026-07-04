// quizService — leitura de quiz/simulado (views security-definer, sem gabarito)
// e submissão via RPC rpc_c9_submit_attempt (avalia server-side + XP 1ª tentativa).
// Nunca recebe `correta` do banco — o gabarito não sai do servidor.

import { supabase } from '../lib/supabase';

export interface QuizAlternativa {
  alternativa_id: string;
  texto: string;
  ordem: number;
}

export interface QuizPergunta {
  pergunta_id: string;
  enunciado: string;
  explicacao?: string | null;
  ordem: number;
  alternativas: QuizAlternativa[];
}

export interface QuizExecucao {
  id: string; // quiz_id (quiz de lição) ou simulado_id (simulado de módulo)
  titulo: string;
  perguntas: QuizPergunta[];
  total_perguntas: number;
}

export interface QuizResposta {
  pergunta_id: string;
  alternativa_id: string;
}

export interface SubmitResult {
  ok: boolean;
  reason?: string;
  escopo?: 'quiz_aula' | 'simulado_modulo';
  total_perguntas?: number;
  total_acertos?: number;
  percentual?: number;
  primeira_tentativa?: boolean;
  xp_concedido?: number;
}

/** Quiz de uma lição (v_c9_quiz_execucao). null se a lição não tem quiz. */
export async function getQuizForLesson(aulaId: string): Promise<QuizExecucao | null> {
  const { data, error } = await supabase
    .from('v_c9_quiz_execucao')
    .select('quiz_id, titulo, perguntas, total_perguntas')
    .eq('aula_id', aulaId)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data || !data.total_perguntas) return null;
  return {
    id: data.quiz_id as string,
    titulo: (data.titulo as string) ?? 'Quiz',
    perguntas: ((data.perguntas as QuizPergunta[]) ?? []),
    total_perguntas: data.total_perguntas as number,
  };
}

/** Simulado de um módulo (v_c9_simulado_execucao, agrega perguntas das lições). */
export async function getSimuladoForModule(moduloId: string): Promise<QuizExecucao | null> {
  const { data, error } = await supabase
    .from('v_c9_simulado_execucao')
    .select('simulado_id, titulo, perguntas, total_perguntas')
    .eq('modulo_id', moduloId)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data || !data.total_perguntas) return null;
  return {
    id: data.simulado_id as string,
    titulo: (data.titulo as string) ?? 'Simulado',
    perguntas: ((data.perguntas as QuizPergunta[]) ?? []),
    total_perguntas: data.total_perguntas as number,
  };
}

/** Submete tentativa. Avaliação e XP (1ª tentativa) são server-side. */
export async function submitAttempt(
  quizId: string,
  respostas: QuizResposta[],
): Promise<SubmitResult> {
  const { data, error } = await supabase.rpc('rpc_c9_submit_attempt', {
    p_quiz_id: quizId,
    p_respostas: respostas,
  });
  if (error) throw new Error(error.message);
  return data as SubmitResult;
}
