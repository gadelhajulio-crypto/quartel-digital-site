import { View, FlatList, StyleSheet } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useModuleLessons } from '../../../src/hooks/useModuleLessons';
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
});
