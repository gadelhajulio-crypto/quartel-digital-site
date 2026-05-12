// RCC-0.5 / Wave 1 — Hook de instrutores institucional
// Fonte: v_instrutores_app (backend-driven, sem hardcode)

import { useState, useEffect } from 'react';
import { loadInstructors, type InstructorApp } from '../services/chatService';

type State = {
  instructors: InstructorApp[];
  loading: boolean;
  error: string | null;
};

// Cache de módulo: evita re-fetch em navegações dentro da sessão
let _cache: InstructorApp[] | null = null;

export function useInstructors(): State {
  const [state, setState] = useState<State>({
    instructors: _cache ?? [],
    loading: _cache === null,
    error: null,
  });

  useEffect(() => {
    if (_cache !== null) return; // já carregado nesta sessão

    console.log('[INSTRUCTOR_UX_W1] load_start');

    loadInstructors()
      .then((data) => {
        _cache = data;
        console.log('[INSTRUCTOR_UX_W1] load_success', { count: data.length });
        setState({ instructors: data, loading: false, error: null });
      })
      .catch((err) => {
        const msg = err?.message ?? 'Erro ao carregar instrutores';
        console.warn('[INSTRUCTOR_UX_W1] load_error', { msg });
        setState({ instructors: [], loading: false, error: msg });
      });
  }, []);

  return state;
}

/** Limpa o cache de sessão (chamar após logout ou troca de perfil) */
export function clearInstructorsCache() {
  _cache = null;
}
