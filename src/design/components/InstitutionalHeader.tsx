import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ViewStyle } from 'react-native';
import { obsidiana } from '../themes/obsidiana';
import { typographyPresets } from '../tokens/typography';

type Theme = typeof obsidiana;

type Props = {
  title: string;
  subtitle?: string;
  theme?: Theme;
  onBack?: () => void;
  rightSlot?: React.ReactNode;
  style?: ViewStyle;
};

export function InstitutionalHeader({
  title,
  subtitle,
  theme = obsidiana,
  onBack,
  rightSlot,
  style,
}: Props) {
  return (
    <View
      style={[
        styles.container,
        {
          borderBottomColor: theme.colors.border,
          paddingHorizontal: theme.spacing.m,
          paddingVertical: theme.spacing.m,
        },
        style,
      ]}
    >
      {onBack && (
        <TouchableOpacity onPress={onBack} style={styles.backBtn} hitSlop={12}>
          <Text style={[styles.backArrow, { color: theme.colors.accent }]}>{'←'}</Text>
        </TouchableOpacity>
      )}

      <View style={styles.titleBlock}>
        <Text
          style={[typographyPresets.sectionTitle, { color: theme.colors.accent }]}
          numberOfLines={1}
        >
          {title}
        </Text>
        {subtitle && (
          <Text
            style={[typographyPresets.bodySmall, { color: theme.colors.textSecondary, marginTop: 2 }]}
            numberOfLines={1}
          >
            {subtitle}
          </Text>
        )}
      </View>

      {rightSlot && <View style={styles.right}>{rightSlot}</View>}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: 1,
  },
  backBtn: {
    marginRight: 12,
  },
  backArrow: {
    fontSize: 22,
  },
  titleBlock: {
    flex: 1,
  },
  right: {
    marginLeft: 12,
  },
});
