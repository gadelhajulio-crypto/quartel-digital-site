import React from 'react';
import { View, Text, StyleSheet, ViewStyle } from 'react-native';
import { obsidiana } from '../themes/obsidiana';
import type { InstitutionalTheme } from '../themes/types';
import { typographyPresets } from '../tokens/typography';

type BadgeVariant = 'accent' | 'success' | 'warning' | 'error' | 'muted';

type Props = {
  label: string;
  theme?: InstitutionalTheme;
  variant?: BadgeVariant;
  style?: ViewStyle;
};

const variantColor = (theme: InstitutionalTheme, variant: BadgeVariant) => {
  switch (variant) {
    case 'accent':
      return { bg: theme.colors.accentSoft, text: theme.colors.accent };
    case 'success':
      return { bg: 'rgba(45,106,79,0.2)', text: theme.colors.success };
    case 'warning':
      return { bg: 'rgba(183,149,11,0.2)', text: theme.colors.warning };
    case 'error':
      return { bg: 'rgba(201,74,74,0.2)', text: theme.colors.error };
    case 'muted':
      return { bg: 'rgba(90,86,96,0.2)', text: theme.colors.muted };
  }
};

export function InstitutionalBadge({
  label,
  theme = obsidiana,
  variant = 'accent',
  style,
}: Props) {
  const { bg, text } = variantColor(theme, variant);

  return (
    <View
      style={[
        styles.badge,
        {
          backgroundColor: bg,
          borderRadius: theme.radius.full,
          paddingHorizontal: theme.spacing.s,
        },
        style,
      ]}
    >
      <Text style={[typographyPresets.label, { color: text }]}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  badge: {
    paddingVertical: 3,
    alignSelf: 'flex-start',
  },
});
