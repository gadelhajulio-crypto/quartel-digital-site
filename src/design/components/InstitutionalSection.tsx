import React from 'react';
import { View, Text, StyleSheet, ViewStyle } from 'react-native';
import { obsidiana } from '../themes/obsidiana';
import type { InstitutionalTheme } from '../themes/types';
import { typographyPresets } from '../tokens/typography';

type Props = {
  title?: string;
  subtitle?: string;
  children: React.ReactNode;
  theme?: InstitutionalTheme;
  style?: ViewStyle;
  titleRight?: React.ReactNode;
};

export function InstitutionalSection({
  title,
  subtitle,
  children,
  theme = obsidiana,
  style,
  titleRight,
}: Props) {
  const hasHeader = title || titleRight;

  return (
    <View style={[{ marginBottom: theme.spacing.l }, style]}>
      {hasHeader && (
        <View style={styles.header}>
          <View style={styles.titleGroup}>
            {title && (
              <Text style={[typographyPresets.cardTitle, { color: theme.colors.accent }]}>
                {title}
              </Text>
            )}
            {subtitle && (
              <Text
                style={[
                  typographyPresets.bodySmall,
                  { color: theme.colors.muted, marginTop: 2 },
                ]}
              >
                {subtitle}
              </Text>
            )}
          </View>
          {titleRight && <View>{titleRight}</View>}
        </View>
      )}

      {hasHeader && (
        <View
          style={[
            styles.divider,
            {
              backgroundColor: theme.colors.border,
              marginBottom: theme.spacing.m,
            },
          ]}
        />
      )}

      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  titleGroup: {
    flex: 1,
  },
  divider: {
    height: 1,
  },
});
