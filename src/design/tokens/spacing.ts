// RCC-0.5 — Spacing Tokens
export const spacing = {
  xs: 4,
  s: 8,
  m: 16,
  l: 24,
  xl: 32,
  xxl: 48,
  xxxl: 64,
} as const;

export type SpacingKey = keyof typeof spacing;
