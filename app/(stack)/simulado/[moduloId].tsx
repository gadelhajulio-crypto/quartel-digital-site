import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, SafeAreaView } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useModuleSimulado } from '../../../src/hooks/useQuizExecucao';
import { QuizRunner } from '../../../src/components/quiz/QuizRunner';
import { theme } from '../../../src/theme';

export default function SimuladoScreen() {
  const { moduloId } = useLocalSearchParams<{ moduloId: string }>();
  const router = useRouter();
  const { simulado, loading } = useModuleSimulado(moduloId);

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <Ionicons name="arrow-back" size={24} color={theme.colors.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.headerTitle} numberOfLines={1}>Simulado do módulo</Text>
      </View>

      {loading ? (
        <View style={styles.center}><ActivityIndicator size="large" color={theme.colors.gold} /></View>
      ) : !simulado ? (
        <View style={styles.center}>
          <Ionicons name="clipboard-outline" size={56} color={theme.colors.textSecondary} />
          <Text style={styles.empty}>Este módulo ainda não tem simulado.</Text>
        </View>
      ) : (
        <QuizRunner quiz={simulado} onDone={() => router.back()} />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: theme.colors?.background || '#000' },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', gap: 12, padding: 32 },
  empty: { color: theme.colors.textSecondary, fontSize: 15, textAlign: 'center' },
  header: {
    height: 60, flexDirection: 'row', alignItems: 'center',
    paddingHorizontal: 16, borderBottomWidth: 1, borderBottomColor: '#333',
  },
  backBtn: { padding: 8, marginRight: 8 },
  headerTitle: { fontSize: 18, fontWeight: 'bold', color: theme.colors.textPrimary, flex: 1 },
});
