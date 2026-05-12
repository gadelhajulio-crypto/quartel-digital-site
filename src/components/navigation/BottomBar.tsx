import { Ionicons } from '@expo/vector-icons';
import React from 'react';
import { View, TouchableOpacity, StyleSheet, Platform } from 'react-native';
import { useRouter, usePathname } from 'expo-router';
import { useBottomBarState } from '../../hooks/useBottomBarState';
import PanelIcon from './PanelIcon';
import InstructorButton from './InstructorButton';
import { tatico } from '../../design/themes/tatico';

const BottomBar = React.memo(function BottomBar() {
  const router = useRouter();
  const pathname = usePathname();
  const { isPanel } = useBottomBarState();

  const isProfile = pathname.includes('/profile');

  return (
    <View style={styles.container}>
      {/* Borda superior com cor tática */}
      <View style={[styles.topBorder, { backgroundColor: tatico.colors.accent }]} />

      {/* PAINEL — esquerda */}
      <TouchableOpacity
        style={styles.sideButton}
        onPress={() => router.replace('/')}
      >
        <PanelIcon active={isPanel} color={isPanel ? tatico.colors.accent : tatico.colors.muted} />
      </TouchableOpacity>

      {/* INSTRUTOR — central */}
      <InstructorButton />

      {/* PERFIL — direita */}
      <TouchableOpacity
        style={styles.sideButton}
        onPress={() => router.replace('/(tabs)/profile')}
      >
        <Ionicons
          name={isProfile ? 'person' : 'person-outline'}
          size={24}
          color={isProfile ? tatico.colors.accent : tatico.colors.muted}
        />
      </TouchableOpacity>
    </View>
  );
});

export default BottomBar;

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    height: Platform.OS === 'ios' ? 75 : 66,
    alignItems: 'center',
    justifyContent: 'space-around',
    backgroundColor: tatico.colors.card,
    borderTopWidth: 1,
    borderTopColor: tatico.colors.border,
    paddingBottom: Platform.OS === 'ios' ? 20 : 0,
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    zIndex: 9999,
    elevation: 20,
  },
  topBorder: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: 1.5,
    opacity: 0.34,
  },
  sideButton: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
  },
});
