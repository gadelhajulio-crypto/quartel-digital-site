import React from 'react';
import {
  TouchableOpacity,
  Text,
  ActivityIndicator,
  StyleSheet,
  ViewStyle,
  TextStyle,
} from 'react-native';
import { obsidiana } from '../themes/obsidiana';
import type { InstitutionalTheme } from '../themes/types';
import { typographyPresets } from '../tokens/typography';
type Variant = 'primary' | 'secondary' | 'ghost';
type Size = 's' | 'm' | 'l';

type Props = {
  label: string;
  onPress: () => void;
  theme?: InstitutionalTheme;
  variant?: Variant;
  size?: Size;
  disabled?: boolean;
  loading?: boolean;
  style?: ViewStyle;
  textStyle?: TextStyle;
};

const paddingBySize: Record<Size, { vertical: number; horizontal: number }> = {
  s: { vertical: 8, horizontal: 16 },
  m: { vertical: 12, horizontal: 24 },
  l: { vertical: 16, horizontal: 32 },
};

export function InstitutionalButton({
  label,
  onPress,
  theme = obsidiana,
  variant = 'primary',
  size = 'm',
  disabled = false,
  loading = false,
  style,
  textStyle,
}: Props) {
  const btn = theme.button[variant];
  const pad = paddingBySize[size];

  const bg =
    variant === 'secondary'
      ? btn.background
      : variant === 'ghost'
      ? 'transparent'
      : btn.background;

  return (
    <TouchableOpacity
      onPress={onPress}
      disabled={disabled || loading}
      activeOpacity={0.75}
      style={[
        styles.base,
        {
          backgroundColor: disabled ? theme.colors.muted : bg,
          borderRadius: theme.radius.s,
          paddingVertical: pad.vertical,
          paddingHorizontal: pad.horizontal,
          borderWidth: variant === 'secondary' ? 1 : 0,
          borderColor:
            variant === 'secondary' && !disabled
              ? (btn as { border?: string }).border ?? theme.colors.border
              : 'transparent',
          opacity: disabled ? 0.5 : 1,
        },
        style,
      ]}
    >
      {loading ? (
        <ActivityIndicator color={btn.text} size="small" />
      ) : (
        <Text
          style={[
            typographyPresets.button,
            { color: disabled ? theme.colors.textSecondary : btn.text },
            textStyle,
          ]}
        >
          {label}
        </Text>
      )}
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  base: {
    alignItems: 'center',
    justifyContent: 'center',
  },
});
