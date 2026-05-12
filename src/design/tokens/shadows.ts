// RCC-0.5 — Shadow Tokens
import { ViewStyle } from 'react-native';
import { Platform } from 'react-native';

const ios = (color: string, opacity: number, radius: number, y: number): ViewStyle =>
  Platform.OS === 'ios'
    ? { shadowColor: color, shadowOpacity: opacity, shadowRadius: radius, shadowOffset: { width: 0, height: y } }
    : {};

const android = (elevation: number): ViewStyle =>
  Platform.OS === 'android' ? { elevation } : {};

function shadow(color: string, opacity: number, radius: number, y: number, elevation: number): ViewStyle {
  return { ...ios(color, opacity, radius, y), ...android(elevation) };
}

export const shadows = {
  none: {} as ViewStyle,
  s: shadow('#000000', 0.18, 4, 2, 2),
  m: shadow('#000000', 0.25, 8, 4, 6),
  l: shadow('#000000', 0.35, 16, 8, 12),
  accent: (accentColor: string): ViewStyle => shadow(accentColor, 0.4, 12, 4, 8),
} as const;
