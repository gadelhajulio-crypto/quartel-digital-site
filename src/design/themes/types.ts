// RCC-0.5 — Tipo base compartilhado do design system institucional
// Usado por todos os componentes Institutional* para aceitar qualquer tema.
// Todos os temas (obsidiana, tatico, dossie) satisfazem esta estrutura.

import type { spacing } from '../tokens/spacing';
import type { radius } from '../tokens/radius';

export type InstitutionalTheme = {
  id: string;
  colors: {
    background: string;
    card: string;
    accent: string;
    accentSoft: string;
    text: string;
    textSecondary: string;
    muted: string;
    border: string;
    surface: string;
    success: string;
    warning: string;
    error: string;
    locked: string;
  };
  spacing: typeof spacing;
  radius: typeof radius;
  button: {
    primary: { background: string; text: string };
    secondary: { background: string; text: string; border: string };
    ghost: { background: string; text: string };
  };
};
