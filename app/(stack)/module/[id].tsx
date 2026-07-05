import { View, Text, FlatList, StyleSheet, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useModuleLessons } from '../../../src/hooks/useModuleLessons';
import { useModuleSimulado } from '../../../src/hooks/useQuizExecucao';
import { useAuth } from '../../../src/context/AuthContext';
import { LessonRow } from '../../../src/components/rows/LessonRow';
import { InstitutionalEmpty } from '../../../src/components/InstitutionalEmpty';
import { InstitutionalLoading } from '../../../src/components/InstitutionalLoading';
import { InstitutionalHeader } from '../../../src/design/components/InstitutionalHeader';
import { TacticalScreen } from '../../../src/design/layout/TacticalScreen';
import { tatico } from '../../../src/design/themes/tatico';
import { spacing } from '../../../src/design/tokens/spacing';

export default function ModuloAulasScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();

  const { lessons, loading } = useModuleLessons(id);
  // Simulado do módulo (CTA opcional). null quando o módulo não tem simulado.
  const { simulado } = useModuleSimulado(id);
  // Força do recruta (fonte A-16) + força do módulo (das próprias lições) — filtra CTA.
  const { profile } = useAuth();
  const moduleForca = lessons[0]?.forca;

  if (loading) {
    return <InstitutionalLoading />;
  }

  return (
    <TacticalScreen scrollable={false}>
      <InstitutionalHeader
        theme={tatico}
        title="Detalhes do módulo"
        onBack={() => router.back()}
        style={styles.header}
      />

      <FlatList
        data={lessons}
        keyExtractor={(item) => item.lesson_id}
        contentContainerStyle={styles.list}
        showsVerticalScrollIndicator={false}
        ListHeaderComponent={
          simulado && moduleForca === profile?.forca ? (
            <TouchableOpacity
              style={styles.simuladoBtn}
              onPress={() => router.push(`/(stack)/simulado/${id}` as any)}
              activeOpacity={0.85}
            >
              <Ionicons name="clipboard-outline" size={18} color={tatico.colors.accent} style={{ marginRight: 8 }} />
              <Text style={styles.simuladoBtnText}>Fazer simulado do módulo (+XP)</Text>
            </TouchableOpacity>
          ) : null
        }
        ListEmptyComponent={
          <View style={styles.emptyWrapper}>
            <InstitutionalEmpty text="Nenhuma aula disponível neste módulo." />
          </View>
        }
        renderItem={({ item }) => (
          <LessonRow
            order={item.lesson_order}
            title={item.lesson_title}
            status={item.status}
            onPress={() => {
              if (item.status !== 'blocked') {
                router.push(`/(stack)/lesson/${item.lesson_id}`);
              }
            }}
          />
        )}
      />
    </TacticalScreen>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingTop: 16,
  },
  list: {
    paddingHorizontal: spacing.m,
    paddingTop: spacing.s,
    paddingBottom: 120,
    gap: spacing.s,
  },
  emptyWrapper: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingTop: 64,
  },
  simuladoBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 14,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: tatico.colors.accent,
    marginBottom: spacing.s,
  },
  simuladoBtnText: {
    color: tatico.colors.accent,
    fontWeight: '700',
    fontSize: 14,
  },
});
