import { View, Text, StyleSheet } from 'react-native';
import { ProgressCard } from '../../src/components/ProgressCard';
import { TacticalScreen } from '../../src/design/layout/TacticalScreen';
import { InstitutionalHeader } from '../../src/design/components/InstitutionalHeader';
import { tatico } from '../../src/design/themes/tatico';
import { typographyPresets } from '../../src/design/tokens/typography';
import { spacing } from '../../src/design/tokens/spacing';

export default function Progresso() {
  return (
    <TacticalScreen scrollable>
      <InstitutionalHeader title="Progresso" theme={tatico} />

      <View style={styles.content}>
        <ProgressCard />
        <Text
          style={[
            typographyPresets.bodySmall,
            { color: tatico.colors.muted, textAlign: 'center', marginTop: spacing.m },
          ]}
        >
          Estatísticas detalhadas em breve.
        </Text>
      </View>
    </TacticalScreen>
  );
}

const styles = StyleSheet.create({
  content: {
    padding: spacing.m,
    paddingBottom: 120,
  },
});
