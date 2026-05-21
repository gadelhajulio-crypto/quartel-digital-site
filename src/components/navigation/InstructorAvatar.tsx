import React, { useEffect, useRef } from 'react';
import {
  Animated,
  Image,
  ImageSourcePropType,
  Platform,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { tatico } from '../../design/themes/tatico';

const AVATAR_SIZE = 90;            // +22%: rosto domina o círculo
const RING_SIZE = AVATAR_SIZE + 8; // halo fica atrás do rosto, não compete

type Props = {
  avatarSource: ImageSourcePropType | null; // null = sem instrutor selecionado
  glowColor: string;
  onPress: () => void;
  active?: boolean;
  unreadCount?: number; // Wave 2b: vem de useChatUnread (banco), nunca calculado local
};

export function InstructorAvatar({ avatarSource, glowColor, onPress, active = false, unreadCount = 0 }: Props) {
  // Idle ring pulse
  const pulseAnim = useRef(new Animated.Value(0)).current;
  // Press scale
  const scaleAnim = useRef(new Animated.Value(1)).current;

  // Idle loop: subtle opacity pulse on the ring
  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulseAnim, {
          toValue: 1,
          duration: 2200,
          useNativeDriver: true,
        }),
        Animated.timing(pulseAnim, {
          toValue: 0,
          duration: 2200,
          useNativeDriver: true,
        }),
      ])
    );
    loop.start();
    return () => loop.stop();
  }, [pulseAnim]);

  const ringOpacity = pulseAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [0.15, 0.47],
  });

  const ringScale = pulseAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [1.0, 1.06],
  });

  function handlePressIn() {
    Animated.spring(scaleAnim, {
      toValue: 0.93,
      useNativeDriver: true,
      speed: 50,
      bounciness: 0,
    }).start();
  }

  function handlePressOut() {
    Animated.spring(scaleAnim, {
      toValue: 1,
      useNativeDriver: true,
      speed: 30,
      bounciness: 4,
    }).start();
  }

  return (
    <TouchableOpacity
      onPress={onPress}
      onPressIn={handlePressIn}
      onPressOut={handlePressOut}
      activeOpacity={1}
      style={styles.wrapper}
    >
      {/* Animated ring */}
      <Animated.View
        style={[
          styles.ring,
          {
            borderColor: glowColor,
            opacity: ringOpacity,
            transform: [{ scale: ringScale }],
          },
        ]}
      />

      {/* Avatar circle */}
      <Animated.View
        style={[
          styles.avatarContainer,
          {
            backgroundColor: tatico.colors.card,
            borderColor: active ? glowColor : tatico.colors.border,
            transform: [{ scale: scaleAnim }],
            // Glow via shadow — sutil, não exagerado
            ...Platform.select({
              ios: {
                shadowColor: glowColor,
                shadowOpacity: active ? 0.5 : 0.25,
                shadowRadius: active ? 8 : 4,
                shadowOffset: { width: 0, height: 0 },
              },
              android: {
                elevation: active ? 8 : 4,
              },
            }),
          },
        ]}
      >
        {avatarSource && (
          <Image source={avatarSource} style={styles.avatar} resizeMode="cover" />
        )}
      </Animated.View>

      {/* Status operacional — indicador diamante */}
      <View
        style={[
          styles.statusIndicator,
          { backgroundColor: glowColor, borderColor: tatico.colors.card },
        ]}
      />

      {/* Badge de unread institucional (Wave 2b) — visível apenas quando > 0 */}
      {unreadCount > 0 && (
        <View
          style={[
            styles.unreadBadge,
            { backgroundColor: tatico.colors.accent, borderColor: tatico.colors.card },
          ]}
        >
          <Text style={styles.unreadText}>
            {unreadCount > 9 ? '9+' : String(unreadCount)}
          </Text>
        </View>
      )}
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    width: RING_SIZE,
    height: RING_SIZE,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: -14,
  },
  ring: {
    position: 'absolute',
    width: RING_SIZE,
    height: RING_SIZE,
    borderRadius: RING_SIZE / 2,
    borderWidth: 1,
  },
  avatarContainer: {
    width: AVATAR_SIZE,
    height: AVATAR_SIZE,
    borderRadius: AVATAR_SIZE / 2,
    borderWidth: 1.5,
    overflow: 'hidden',
  },
  avatar: {
    width: '100%',
    height: '100%',
  },
  statusIndicator: {
    position: 'absolute',
    bottom: 2,
    right: 2,
    width: 7,
    height: 7,
    borderRadius: 1,          // leve arredondamento — não um círculo perfeito
    transform: [{ rotate: '45deg' }], // diamante
    borderWidth: 1.5,
  },
  // Badge unread Wave 2b: top-right do avatar, discreto, institucional
  unreadBadge: {
    position: 'absolute',
    top: 4,
    right: 4,
    minWidth: 16,
    height: 16,
    borderRadius: 8,
    borderWidth: 1.5,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 3,
    zIndex: 50,
  },
  unreadText: {
    color: '#FFFFFF',
    fontSize: 9,
    fontWeight: '700',
    lineHeight: 12,
  },
});
