// RCC-0.5 — Instrutor Virtual Institucional
// Catálogo de personalidades, avatares e metadados por força

export type InstructorId = 'objetivo' | 'estrategico' | 'didatico';
// Alias para compatibilidade com profileService
export type InstructorProfileId = InstructorId;
export type ForcaId = 'marinha' | 'exercito' | 'aeronautica';

export type InstructorAssets = {
  avatar: ReturnType<typeof require>;   // botão circular da BottomBar
  selecao: ReturnType<typeof require>;  // imagem de apresentação no Sheet
};

export type InstructorData = {
  id: InstructorId;
  name: string;
  rank: string;        // posto/graduação exibida no sheet
  tagline: string;     // frase curta operacional
  personality: string; // descrição da personalidade para UI
};

// Metadados das personalidades (independente de força)
export const INSTRUCTOR_DATA: Record<InstructorId, InstructorData> = {
  objetivo: {
    id: 'objetivo',
    name: 'Sargento Ramos',
    rank: 'Sargento',
    tagline: 'Direto ao ponto. Missão cumprida.',
    personality: 'Focado em resultados e eficiência operacional.',
  },
  estrategico: {
    id: 'estrategico',
    name: 'Sargento Rocha',
    rank: 'Sargento',
    tagline: 'Cada decisão tem um plano.',
    personality: 'Visão analítica e planejamento de longo prazo.',
  },
  didatico: {
    id: 'didatico',
    name: 'Sargento Sara',
    rank: 'Sargento',
    tagline: 'Aprende quem treina com método.',
    personality: 'Ensino progressivo e suporte contínuo.',
  },
};

/**
 * @deprecated Wave 4c governance cleanup
 * INSTRUCTOR_ASSETS e resolveInstructorAssets sem consumers ativos.
 * FORCE_GLOW e DEFAULT_GLOW permanecem ativos (InstructorButton, ChatScreen).
 */
// Assets canônicos por personalidade (força-agnósticos — Ramos/Rocha/Sara).
export const INSTRUCTOR_ASSETS: Partial<Record<ForcaId, Record<InstructorId, InstructorAssets>>> = {
  marinha: {
    objetivo: {
      avatar: require('../../assets/instructors/chat/ramos-chat-icon.png'),
      selecao: require('../../assets/instructors/cards/ramos-card-selected.png'),
    },
    estrategico: {
      avatar: require('../../assets/instructors/chat/rocha-chat-icon.png'),
      selecao: require('../../assets/instructors/cards/rocha-card-selected.png'),
    },
    didatico: {
      avatar: require('../../assets/instructors/chat/sara-chat-icon.png'),
      selecao: require('../../assets/instructors/cards/sara-card-selected.png'),
    },
  },
  exercito: {
    objetivo: {
      avatar: require('../../assets/instructors/chat/ramos-chat-icon.png'),
      selecao: require('../../assets/instructors/cards/ramos-card-selected.png'),
    },
    estrategico: {
      avatar: require('../../assets/instructors/chat/rocha-chat-icon.png'),
      selecao: require('../../assets/instructors/cards/rocha-card-selected.png'),
    },
    didatico: {
      avatar: require('../../assets/instructors/chat/sara-chat-icon.png'),
      selecao: require('../../assets/instructors/cards/sara-card-selected.png'),
    },
  },
  aeronautica: {
    objetivo: {
      avatar: require('../../assets/instructors/chat/ramos-chat-icon.png'),
      selecao: require('../../assets/instructors/cards/ramos-card-selected.png'),
    },
    estrategico: {
      avatar: require('../../assets/instructors/chat/rocha-chat-icon.png'),
      selecao: require('../../assets/instructors/cards/rocha-card-selected.png'),
    },
    didatico: {
      avatar: require('../../assets/instructors/chat/sara-chat-icon.png'),
      selecao: require('../../assets/instructors/cards/sara-card-selected.png'),
    },
  },
};

// Fallback: qualquer força sem assets usa marinha
export function resolveInstructorAssets(
  forca: ForcaId | string,
  instructorId: InstructorId | string | null | undefined
): InstructorAssets {
  const id = (instructorId ?? 'objetivo') as InstructorId;
  const f = forca as ForcaId;
  return (
    INSTRUCTOR_ASSETS[f]?.[id] ??
    INSTRUCTOR_ASSETS.marinha![id] ??
    INSTRUCTOR_ASSETS.marinha!.objetivo
  );
}

// Glow sutil por força — tom dessaturado para não parecer gamer
export const FORCE_GLOW: Record<string, string> = {
  marinha:     '#4a8ab0',
  exercito:    '#4a7c4a',
  aeronautica: '#5570a8',
};

export const DEFAULT_GLOW = '#5a6070';
