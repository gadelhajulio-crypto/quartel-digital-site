// RCC-0.5 — Tema Dossiê
// Identidade: Paper/light, burocrático-institucional, para telas de histórico/documentos
import { palette } from '../tokens/colors';
import { radius } from '../tokens/radius';
import { spacing } from '../tokens/spacing';

export const dossie = {
  id: 'dossie' as const,

  colors: {
    background: palette.dossieBg,
    card: palette.dossieCard,
    accent: palette.dossieAccent,
    accentSoft: 'rgba(138,28,28,0.1)',
    text: palette.dossieText,
    textSecondary: '#4a5568',
    muted: palette.dossieMuted,
    border: palette.dossieBorder,
    surface: '#e8e2d6',
    success: '#276749',
    warning: '#92400e',
    error: palette.error,
    locked: 'rgba(26,31,46,0.4)',
  },

  spacing,
  radius,

  button: {
    primary: {
      background: palette.dossieAccent,
      text: '#ffffff',
    },
    secondary: {
      background: palette.dossieCard,
      text: palette.dossieAccent,
      border: 'rgba(138,28,28,0.3)',
    },
    ghost: {
      background: 'transparent',
      text: palette.dossieAccent,
    },
  },
} as const;

export type DossieTheme = typeof dossie;
