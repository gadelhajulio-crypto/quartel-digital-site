import { View, StyleSheet } from 'react-native';
import { InstitutionalEmpty } from '../../src/components/InstitutionalEmpty';
import { TacticalScreen } from '../../src/design/layout/TacticalScreen';
import { InstitutionalHeader } from '../../src/design/components/InstitutionalHeader';
import { tatico } from '../../src/design/themes/tatico';

export default function RevisoesScreen() {
  return (
    <TacticalScreen>
      <InstitutionalHeader title="Revisões" theme={tatico} />

      <View style={styles.center}>
        <InstitutionalEmpty text="Nenhuma revisão disponível no momento." />
      </View>
    </TacticalScreen>
  );
}

const styles = StyleSheet.create({
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
