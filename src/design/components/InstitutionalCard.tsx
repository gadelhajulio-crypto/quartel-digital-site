import React from 'react';
import { View, StyleSheet, ViewStyle, StyleProp } from 'react-native';
import { obsidiana } from '../themes/obsidiana';
import type { InstitutionalTheme } from '../themes/types';

type Props = {
  theme?: InstitutionalTheme;
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
  elevated?: boolean;
  accent?: boolean;
};

export function InstitutionalCard({
  theme = obsidiana,
  children,
  style,
  elevated = false,
  accent = false,
}: Props) {
  return (
    <View
      style={[
        styles.card,
        {
          backgroundColor: theme.colors.card,
          borderRadius: theme.radius.m,
          borderColor: accent ? theme.colors.accent : theme.colors.border,
          borderWidth: accent ? 1.5 : 1,
        },
        elevated && {
          shadowColor: '#000',
          shadowOpacity: 0.3,
          shadowRadius: 8,
          shadowOffset: { width: 0, height: 4 },
          elevation: 6,
        },
        style,
      ]}
    >
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    padding: 16,
    overflow: 'hidden',
  },
});
