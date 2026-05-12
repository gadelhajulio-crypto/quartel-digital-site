// RCC-0.5 — Border Radius Tokens
export const radius = {
  none: 0,
  xs: 4,
  s: 8,
  m: 12,
  l: 16,
  xl: 24,
  full: 9999,
} as const;

export type RadiusKey = keyof typeof radius;
