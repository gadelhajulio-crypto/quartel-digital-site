// RCC-0.5 — Tema Tático
// Identidade: Operacional, azul-aço, para telas de missão/treino
import { palette } from '../tokens/colors';
import { radius } from '../tokens/radius';
import { spacing } from '../tokens/spacing';

export const tatico = {
  id: 'tatico' as const,

  colors: {
    background: palette.taticoBg,
    card: palette.taticoCard,
    accent: palette.taticoAccent,
    accentSoft: 'rgba(95,168,211,0.15)',
    text: palette.taticoText,
    textSecondary: '#8fa8be',
    muted: palette.taticoMuted,
    border: palette.taticoBorder,
    surface: '#1a2530',
    success: palette.success,
    warning: palette.warning,
    error: palette.error,
    locked: palette.locked,
  },

  spacing,
  radius,

  button: {
    primary: {
      background: palette.taticoAccent,
      text: '#0e1419',
    },
    secondary: {
      background: palette.taticoCard,
      text: palette.taticoAccent,
      border: palette.taticoBorder,
    },
    ghost: {
      background: 'transparent',
      text: palette.taticoAccent,
    },
  },
} as const;

export type TaticoTheme = typeof tatico;
