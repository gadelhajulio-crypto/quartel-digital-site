import React, { useCallback, useEffect, useRef } from 'react';
import { Animated, StyleSheet } from 'react-native';
import { Video, ResizeMode } from 'expo-av';

const FALLBACK_TIMEOUT_MS = 25000;
const FADE_OUT_DURATION_MS = 300;

interface Props {
  onFinish: () => void;
  // Quando true, fecha o splash imediatamente (usuário já autenticado)
  forceFinish?: boolean;
}

export function SplashCinematic({ onFinish, forceFinish }: Props) {
  const finished = useRef(false);
  const opacity = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    return () => {
      console.log('[SPLASH] unmounted');
    };
  }, []);

  const finish = useCallback(() => {
    if (finished.current) return;
    finished.current = true;

    Animated.timing(opacity, {
      toValue: 0,
      duration: FADE_OUT_DURATION_MS,
      useNativeDriver: true,
    }).start(() => {
      console.log('[SPLASH] overlay_hidden');
      onFinish();
    });
  }, [onFinish, opacity]);

  // Saída rápida: usuário autenticado — pula o cinematic
  useEffect(() => {
    if (forceFinish) {
      console.log('[SPLASH] force_finish — usuário autenticado, skip cinematic');
      finish();
    }
  }, [forceFinish, finish]);

  // Fallback: dispara se o vídeo falhar completamente e não emitir evento
  useEffect(() => {
    const timeout = setTimeout(() => {
      console.log('[SPLASH] fallback_error — timeout atingido sem fim real do vídeo');
      finish();
    }, FALLBACK_TIMEOUT_MS);
    return () => clearTimeout(timeout);
  }, [finish]);

  return (
    // Sem pointerEvents="box-none": o overlay bloqueia todas as interações abaixo
    <Animated.View style={[styles.container, { opacity }]}>
      <Video
        source={require('../../../assets/splash/splash.mp4')}
        style={StyleSheet.absoluteFill}
        resizeMode={ResizeMode.COVER}
        shouldPlay
        isLooping={false}
        isMuted={false}
        volume={1}
        onPlaybackStatusUpdate={(status) => {
          if (!status.isLoaded) {
            if ('error' in status) {
              console.log('[SPLASH] fallback_error — status.error:', (status as any).error);
              finish();
            }
            return;
          }
          if (status.durationMillis != null) {
            console.log('[SPLASH] loaded duration:', status.durationMillis, 'ms');
          }
          if (status.positionMillis != null && status.durationMillis != null) {
            console.log('[SPLASH] progress:', status.positionMillis, '/', status.durationMillis);
          }
          if (status.didJustFinish) {
            console.log('[SPLASH] finished — didJustFinish=true');
            finish();
          }
        }}
        onError={(error) => {
          console.log('[SPLASH] fallback_error — onError:', error);
          finish();
        }}
      />
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  container: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: '#0F0F13',
    zIndex: 999,
  },
});
