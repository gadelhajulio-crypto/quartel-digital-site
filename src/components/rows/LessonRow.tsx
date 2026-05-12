import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { tatico } from '../../design/themes/tatico';
import { typographyPresets } from '../../design/tokens/typography';
import { radius } from '../../design/tokens/radius';
import { spacing } from '../../design/tokens/spacing';

export type LessonStatus = 'blocked' | 'available' | 'completed';

interface LessonRowProps {
  order: number;
  title: string;
  status: LessonStatus;
  onPress: () => void;
}

const STATUS_ICON: Record<LessonStatus, keyof typeof Ionicons.glyphMap> = {
  completed: 'checkmark-circle',
  available: 'play-circle',
  blocked:   'lock-closed',
};

const STATUS_COLOR: Record<LessonStatus, string> = {
  completed: tatico.colors.success,
  available: tatico.colors.accent,
  blocked:   tatico.colors.muted,
};

export function LessonRow({ order, title, status, onPress }: LessonRowProps) {
  const isBlocked = status === 'blocked';
  const iconColor = STATUS_COLOR[status];

  return (
    <TouchableOpacity
      onPress={onPress}
      disabled={isBlocked}
      activeOpacity={0.8}
      style={[
        styles.row,
        {
          backgroundColor: tatico.colors.card,
          borderColor: tatico.colors.border,
          opacity: isBlocked ? 0.55 : 1,
        },
      ]}
    >
      <Text style={[typographyPresets.label, styles.order, { color: tatico.colors.muted }]}>
        {String(order).padStart(2, '0')}
      </Text>

      <View style={styles.content}>
        <Text
          style={[typographyPresets.body, { color: tatico.colors.text }]}
          numberOfLines={2}
        >
          {title}
        </Text>
      </View>

      <Ionicons name={STATUS_ICON[status]} size={22} color={iconColor} />
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: spacing.m,
    borderRadius: radius.s,
    borderWidth: 1,
    gap: spacing.s,
  },
  order: {
    width: 28,
    textAlign: 'right',
    color: tatico.colors.muted,
  },
  content: {
    flex: 1,
  },
});
