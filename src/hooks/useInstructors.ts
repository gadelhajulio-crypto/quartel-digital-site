// RCC-0.5 / Wave 1 — Hook de instrutores institucional
// Fonte: v_instrutores_app (backend-driven, sem hardcode)
//
// Subscriber pattern: quando reloadInstructors() é chamado após confirmar troca,
// TODOS os hooks montados (InstructorButton, ChatScreen, etc.) recebem os novos dados.
// Sem esse padrão, componentes já montados no tab bar ficam com estado stale.

import { useState, useEffect } from 'react';
import { loadInstructors, type InstructorApp } from '../services/chatService';

type State = {
  instructors: InstructorApp[];
  loading: boolean;
  error: string | null;
};

// Cache de módulo: evita re-fetch em navegações dentro da sessão
let _cache: InstructorApp[] | null = null;

// Listeners de hooks montados: notificados quando o cache é atualizado
const _listeners = new Set<(data: InstructorApp[]) => void>();

function notifyListeners(data: InstructorApp[]) {
  _listeners.forEach((l) => l(data));
}

export function useInstructors(): State {
  const [state, setState] = useState<State>({
    instructors: _cache ?? [],
    loading: _cache === null,
    error: null,
  });

  useEffect(() => {
    // Registrar listener para receber atualizações de reloadInstructors()
    const listener = (data: InstructorApp[]) => {
      setState({ instructors: data, loading: false, error: null });
    };
    _listeners.add(listener);

    if (_cache === null) {
      console.log('[INSTRUCTOR_UX_W1] load_start');

      loadInstructors()
        .then((data) => {
          _cache = data;
          console.log('[INSTRUCTOR_UX_W1] load_success', { count: data.length });
          console.log('[INSTRUCTOR_CANONICAL]', data.map((i) => i.slug));
          notifyListeners(data);
        })
        .catch((err) => {
          const msg = err?.message ?? 'Erro ao carregar instrutores';
          console.warn('[INSTRUCTOR_UX_W1] load_error', { msg });
          setState({ instructors: [], loading: false, error: msg });
        });
    }

    return () => {
      _listeners.delete(listener);
    };
  }, []);

  return state;
}

/**
 * Recarrega instrutores do banco e notifica TODOS os hooks montados.
 * Chamar após confirmar troca de instrutor.
 */
export async function reloadInstructors(): Promise<void> {
  _cache = null;
  console.log('[INSTRUCTOR_UX_W1] reload_start');
  try {
    const data = await loadInstructors();
    _cache = data;
    console.log('[INSTRUCTOR_UX_W1] reload_success', { count: data.length });
    notifyListeners(data);
  } catch (err: any) {
    const msg = err?.message ?? 'Erro ao recarregar instrutores';
    console.warn('[INSTRUCTOR_UX_W1] reload_error', { msg });
    // Falha não crítica: profile já foi atualizado via refetchProfile
  }
}

/** Limpa o cache de sessão (chamar após logout) */
export function clearInstructorsCache() {
  _cache = null;
}
