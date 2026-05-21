// RCC-0.5 — Design System Quartel Digital
// Ponto único de importação

// Tokens
export * from './tokens/colors';
export * from './tokens/spacing';
export * from './tokens/typography';
export * from './tokens/radius';
export * from './tokens/shadows';

// Themes
export { obsidiana } from './themes/obsidiana';
export { tatico } from './themes/tatico';
export { dossie } from './themes/dossie';
export type { ObsidianaTheme } from './themes/obsidiana';
export type { TaticoTheme } from './themes/tatico';
export type { DossieTheme } from './themes/dossie';
export type { InstitutionalTheme } from './themes/types';

// Components
export { InstitutionalCard } from './components/InstitutionalCard';
export { InstitutionalButton } from './components/InstitutionalButton';
export { InstitutionalHeader } from './components/InstitutionalHeader';
export { InstitutionalBadge } from './components/InstitutionalBadge';
export { InstitutionalInput } from './components/InstitutionalInput';
export { InstitutionalSection } from './components/InstitutionalSection';

// Layout
export { ScreenContainer } from './layout/ScreenContainer';
export { ObsidianScreen } from './layout/ObsidianScreen';
export { TacticalScreen } from './layout/TacticalScreen';
export { DossierScreen } from './layout/DossierScreen';
