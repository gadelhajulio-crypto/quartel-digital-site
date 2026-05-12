import { ScrollView, StyleSheet } from 'react-native';
import { MARINHA_CURRICULUM } from '../../src/constants/marinhaCurriculum';
import { ModuleAccordion } from '../../src/components/modules/ModuleAccordion';
import { TacticalScreen } from '../../src/design/layout/TacticalScreen';
import { InstitutionalHeader } from '../../src/design/components/InstitutionalHeader';
import { tatico } from '../../src/design/themes/tatico';

export default function ModulosScreen() {
  return (
    <TacticalScreen>
      <InstitutionalHeader title="Módulos do curso" theme={tatico} />

      <ScrollView
        contentContainerStyle={styles.list}
        showsVerticalScrollIndicator={false}
      >
        {MARINHA_CURRICULUM.map((module, index) => (
          <ModuleAccordion
            key={module.id}
            title={module.title}
            lessons={module.lessons}
            moduleIndex={index}
          />
        ))}
      </ScrollView>
    </TacticalScreen>
  );
}

const styles = StyleSheet.create({
  list: {
    padding: 16,
    paddingBottom: 120,
    gap: 8,
  },
});
