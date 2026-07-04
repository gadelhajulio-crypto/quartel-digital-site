import { ScrollView, StyleSheet, View, Text, ActivityIndicator } from 'react-native';
import { useAuth } from '../../src/context/AuthContext';
import { useModulesCatalog } from '../../src/hooks/useModulesCatalog';
import { ModuleAccordion } from '../../src/components/modules/ModuleAccordion';
import { TacticalScreen } from '../../src/design/layout/TacticalScreen';
import { InstitutionalHeader } from '../../src/design/components/InstitutionalHeader';
import { tatico } from '../../src/design/themes/tatico';
import { typographyPresets } from '../../src/design/tokens/typography';

// Tab de módulos — DB-driven (A-15/A-16). Fonte: useModulesCatalog
// (v_modulos_catalogo + v_lessons_panel), filtrado pela força do recruta.
// Substituiu a constante hardcoded MARINHA_CURRICULUM (removida).
export default function ModulosScreen() {
  const { profile } = useAuth();
  const force = profile?.forca ?? 'marinha';
  const { modules, loading } = useModulesCatalog(force, profile);

  return (
    <TacticalScreen>
      <InstitutionalHeader title="Módulos do curso" theme={tatico} />

      {loading ? (
        <View style={styles.centered}>
          <ActivityIndicator color={tatico.colors.accent} />
        </View>
      ) : modules.length === 0 ? (
        // Força sem currículo publicado (ex.: Exército/Aeronáutica em construção):
        // estado explícito em vez de lista vazia, que pareceria bug.
        <View style={styles.centered}>
          <Text style={[typographyPresets.sectionTitle, styles.emptyTitle, { color: tatico.colors.text }]}>
            Conteúdo em desenvolvimento
          </Text>
          <Text style={[typographyPresets.body, styles.emptyBody, { color: tatico.colors.textSecondary }]}>
            O currículo desta força ainda está sendo preparado. Novos módulos serão
            liberados em breve.
          </Text>
        </View>
      ) : (
        <ScrollView
          contentContainerStyle={styles.list}
          showsVerticalScrollIndicator={false}
        >
          {modules.map((module, index) => (
            <ModuleAccordion
              key={module.id}
              title={module.title}
              lessons={module.lessons}
              moduleIndex={index}
            />
          ))}
        </ScrollView>
      )}
    </TacticalScreen>
  );
}

const styles = StyleSheet.create({
  list: {
    padding: 16,
    paddingBottom: 120,
    gap: 8,
  },
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
    gap: 12,
  },
  emptyTitle: {
    textAlign: 'center',
  },
  emptyBody: {
    textAlign: 'center',
    lineHeight: 22,
  },
});
