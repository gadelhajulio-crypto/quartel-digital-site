// RCC-0.5 — Tema Obsidiana
// Identidade: Dark, premium, militarmente sóbrio
import { palette } from '../tokens/colors';
import { radius } from '../tokens/radius';
import { spacing } from '../tokens/spacing';

export const obsidiana = {
  id: 'obsidiana' as const,

  colors: {
    background: palette.obsidianaBg,
    card: palette.obsidianaCard,
    accent: palette.obsidianaAccent,
    accentSoft: 'rgba(184,147,90,0.15)',
    text: palette.obsidianaText,
    textSecondary: '#a09a94',
    muted: palette.obsidianaMuted,
    border: palette.obsidianaBorder,
    surface: '#1a1a1f',
    success: palette.success,
    warning: palette.warning,
    error: palette.error,
    locked: palette.locked,
  },

  spacing,
  radius,

  button: {
    primary: {
      background: palette.obsidianaAccent,
      text: '#0a0a0c',
    },
    secondary: {
      background: palette.obsidianaCard,
      text: palette.obsidianaAccent,
      border: palette.obsidianaBorder,
    },
    ghost: {
      background: 'transparent',
      text: palette.obsidianaAccent,
    },
  },
} as const;

export type ObsidianaTheme = typeof obsidiana;
