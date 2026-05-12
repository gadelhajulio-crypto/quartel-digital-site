// RCC-0.5 — Color Tokens
// Paletas oficiais do design system Quartel Digital

export const palette = {
  // Obsidiana
  obsidianaBg: '#0a0a0c',
  obsidianaAccent: '#b8935a',
  obsidianaText: '#e8e4dc',
  obsidianaCard: '#131316',
  obsidianaBorder: 'rgba(184,147,90,0.2)',
  obsidianaMuted: '#5a5660',

  // Dossiê (light)
  dossieBg: '#f1ece1',
  dossieAccent: '#8a1c1c',
  dossieText: '#1a1f2e',
  dossieCard: '#ffffff',
  dossieBorder: 'rgba(26,31,46,0.12)',
  dossieMuted: '#7a7265',

  // Tático
  taticoAccent: '#5fa8d3',
  taticoBg: '#0e1419',
  taticoText: '#dde3ee',
  taticoCard: '#131c24',
  taticoBorder: 'rgba(95,168,211,0.2)',
  taticoMuted: '#4a5a6a',

  // Semânticas compartilhadas
  success: '#2d6a4f',
  warning: '#b7950b',
  error: '#c94a4a',
  locked: 'rgba(0,0,0,0.5)',

  // Neutras
  white: '#ffffff',
  black: '#000000',
  transparent: 'transparent',
} as const;

export type PaletteKey = keyof typeof palette;
