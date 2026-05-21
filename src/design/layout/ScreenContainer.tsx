import React from 'react';
import {
  View,
  ScrollView,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  ViewStyle,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { obsidiana } from '../themes/obsidiana';
import type { InstitutionalTheme } from '../themes/types';

type Props = {
  children: React.ReactNode;
  theme?: InstitutionalTheme;
  scrollable?: boolean;
  avoidKeyboard?: boolean;
  style?: ViewStyle;
  contentStyle?: ViewStyle;
};

export function ScreenContainer({
  children,
  theme = obsidiana,
  scrollable = false,
  avoidKeyboard = false,
  style,
  contentStyle,
}: Props) {
  const bg = { backgroundColor: theme.colors.background };
  const content = scrollable ? (
    <ScrollView
      style={[styles.fill, bg]}
      contentContainerStyle={[styles.content, contentStyle]}
      keyboardShouldPersistTaps="handled"
      showsVerticalScrollIndicator={false}
    >
      {children}
    </ScrollView>
  ) : (
    <View style={[styles.fill, styles.content, bg, contentStyle]}>{children}</View>
  );

  const inner = avoidKeyboard ? (
    <KeyboardAvoidingView
      style={styles.fill}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      {content}
    </KeyboardAvoidingView>
  ) : (
    content
  );

  return (
    <SafeAreaView style={[styles.fill, bg, style]} edges={['top', 'left', 'right']}>
      {inner}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  fill: {
    flex: 1,
  },
  content: {
    padding: 16,
  },
});
