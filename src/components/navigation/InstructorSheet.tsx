// RCC-0.5 / Wave 1 — InstructorSheet backend-driven
// Recebe InstructorApp diretamente da view. Sem hardcode local.

import React, { useEffect, useRef } from 'react';
import {
  Animated,
  Image,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import type { InstructorApp } from '../../services/chatService';
import { obsidiana } from '../../design/themes/obsidiana';
import { typographyPresets } from '../../design/tokens/typography';
import { spacing } from '../../design/tokens/spacing';
import { radius } from '../../design/tokens/radius';

type Props = {
  visible: boolean;
  instructor: InstructorApp;
  glowColor: string;
  onDismiss: () => void;
  onChatPress: () => void;
  onChangePress: () => void;
};

const SHEET_HEIGHT = 460;

export function InstructorSheet({
  visible,
  instructor,
  glowColor,
  onDismiss,
  onChatPress,
  onChangePress,
}: Props) {
  const translateY = useRef(new Animated.Value(SHEET_HEIGHT)).current;
  const backdropOpacity = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (visible) {
      Animated.parallel([
        Animated.spring(translateY, {
          toValue: 0,
          useNativeDriver: true,
          damping: 22,
          stiffness: 200,
          mass: 0.9,
        }),
        Animated.timing(backdropOpacity, {
          toValue: 1,
          duration: 250,
          useNativeDriver: true,
        }),
      ]).start();
    } else {
      Animated.parallel([
        Animated.timing(translateY, {
          toValue: SHEET_HEIGHT,
          duration: 220,
          useNativeDriver: true,
        }),
        Animated.timing(backdropOpacity, {
          toValue: 0,
          duration: 180,
          useNativeDriver: true,
        }),
      ]).start();
    }
  }, [visible]);

  const imageSource = instructor.avatar_url
    ? { uri: instructor.avatar_url }
    : null;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="none"
      onRequestClose={onDismiss}
      statusBarTranslucent
    >
      {/* Backdrop */}
      <Animated.View style={[styles.backdrop, { opacity: backdropOpacity }]}>
        <Pressable style={StyleSheet.absoluteFill} onPress={onDismiss} />
      </Animated.View>

      {/* Sheet */}
      <Animated.View
        style={[
          styles.sheet,
          {
            backgroundColor: obsidiana.colors.card,
            borderColor: obsidiana.colors.border,
            transform: [{ translateY }],
          },
        ]}
      >
        {/* Handle */}
        <View style={[styles.handle, { backgroundColor: obsidiana.colors.border }]} />

        {/* Conteúdo */}
        <View style={styles.body}>
          {/* Avatar de apresentação */}
          <View style={[styles.avatarWrap, { borderColor: glowColor }]}>
            {imageSource ? (
              <Image source={imageSource} style={styles.selecaoImage} resizeMode="cover" />
            ) : (
              <View style={[styles.selecaoImage, { backgroundColor: obsidiana.colors.surface }]} />
            )}
            <View style={[styles.glowOverlay, { backgroundColor: glowColor + '18' }]} />
          </View>

          {/* Identificação */}
          <View style={styles.idBlock}>
            <Text style={[typographyPresets.label, { color: glowColor }]}>
              {instructor.titulo}
            </Text>
            <Text
              style={[
                typographyPresets.sectionTitle,
                { color: obsidiana.colors.text, marginTop: 2 },
              ]}
            >
              {instructor.nome}
            </Text>
            {instructor.descricao ? (
              <Text
                style={[
                  typographyPresets.bodySmall,
                  { color: obsidiana.colors.textSecondary, marginTop: 4, fontStyle: 'italic' },
                ]}
                numberOfLines={2}
              >
                "{instructor.descricao}"
              </Text>
            ) : null}
          </View>

          {/* Linha divisória */}
          <View style={[styles.divider, { backgroundColor: obsidiana.colors.border }]} />

          {/* CTAs */}
          <View style={styles.actions}>
            <TouchableOpacity
              style={[styles.btnPrimary, { backgroundColor: glowColor }]}
              onPress={onChatPress}
              activeOpacity={0.82}
            >
              <Text style={[typographyPresets.button, { color: obsidiana.colors.background }]}>
                Conversar com instrutor
              </Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.btnGhost, { borderColor: obsidiana.colors.border }]}
              onPress={onChangePress}
              activeOpacity={0.75}
            >
              <Text
                style={[typographyPresets.label, { color: obsidiana.colors.textSecondary }]}
              >
                Trocar instrutor
              </Text>
            </TouchableOpacity>

            <TouchableOpacity style={styles.btnClose} onPress={onDismiss} activeOpacity={0.7}>
              <Text style={[typographyPresets.label, { color: obsidiana.colors.muted }]}>
                Fechar
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      </Animated.View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.65)',
  },
  sheet: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: SHEET_HEIGHT,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    borderTopWidth: 1,
    borderLeftWidth: 1,
    borderRightWidth: 1,
    overflow: 'hidden',
    paddingBottom: Platform.OS === 'ios' ? 24 : 16,
  },
  handle: {
    alignSelf: 'center',
    width: 40,
    height: 3,
    borderRadius: 2,
    marginTop: 10,
    marginBottom: 8,
  },
  body: {
    flex: 1,
    alignItems: 'center',
    paddingHorizontal: spacing.l,
    paddingTop: spacing.s,
    gap: spacing.m,
  },
  avatarWrap: {
    width: 108,
    height: 108,
    borderRadius: 54,
    borderWidth: 1.5,
    overflow: 'hidden',
    position: 'relative',
  },
  selecaoImage: {
    width: '100%',
    height: '100%',
  },
  glowOverlay: {
    ...StyleSheet.absoluteFillObject,
  },
  idBlock: {
    alignItems: 'center',
    gap: 0,
  },
  divider: {
    width: '40%',
    height: 1,
  },
  actions: {
    width: '100%',
    gap: spacing.s,
    marginTop: spacing.xs,
  },
  btnPrimary: {
    height: 52,
    borderRadius: radius.s,
    alignItems: 'center',
    justifyContent: 'center',
  },
  btnGhost: {
    height: 44,
    borderRadius: radius.s,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  btnClose: {
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
