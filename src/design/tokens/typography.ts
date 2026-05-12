// RCC-0.5 — Typography Tokens
import { TextStyle } from 'react-native';

export const fontFamily = {
  regular: 'Inter_400Regular',
  medium: 'Inter_500Medium',
  semiBold: 'Inter_600SemiBold',
  bold: 'Inter_700Bold',
} as const;

export const fontSize = {
  xs: 11,
  s: 13,
  m: 15,
  base: 16,
  l: 18,
  xl: 22,
  xxl: 28,
  display: 36,
} as const;

export const lineHeight = {
  tight: 1.2,
  normal: 1.5,
  relaxed: 1.75,
} as const;

export const letterSpacing = {
  tight: -0.5,
  normal: 0,
  wide: 1,
  wider: 2,
  widest: 4,
} as const;

export const typographyPresets = {
  displayTitle: {
    fontFamily: fontFamily.bold,
    fontSize: fontSize.display,
    letterSpacing: letterSpacing.wider,
    textTransform: 'uppercase',
  } satisfies TextStyle,

  sectionTitle: {
    fontFamily: fontFamily.bold,
    fontSize: fontSize.xl,
    letterSpacing: letterSpacing.wide,
    textTransform: 'uppercase',
  } satisfies TextStyle,

  cardTitle: {
    fontFamily: fontFamily.semiBold,
    fontSize: fontSize.base,
    letterSpacing: letterSpacing.wide,
  } satisfies TextStyle,

  body: {
    fontFamily: fontFamily.regular,
    fontSize: fontSize.m,
  } satisfies TextStyle,

  bodySmall: {
    fontFamily: fontFamily.regular,
    fontSize: fontSize.s,
  } satisfies TextStyle,

  label: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.xs,
    letterSpacing: letterSpacing.wider,
    textTransform: 'uppercase',
  } satisfies TextStyle,

  button: {
    fontFamily: fontFamily.bold,
    fontSize: fontSize.m,
    letterSpacing: letterSpacing.wide,
    textTransform: 'uppercase',
  } satisfies TextStyle,
} as const;
