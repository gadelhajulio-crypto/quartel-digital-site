import { View, StyleSheet } from 'react-native';
import { useStudentHistory } from '../../src/hooks/useStudentHistory';
import { HistoryTimeline } from '../../src/components/rows/HistoryTimeline';
import { InstitutionalLoading } from '../../src/components/InstitutionalLoading';
import { InstitutionalEmpty } from '../../src/components/InstitutionalEmpty';
import { DossierScreen } from '../../src/design/layout/DossierScreen';
import { InstitutionalHeader } from '../../src/design/components/InstitutionalHeader';
import { dossie } from '../../src/design/themes/dossie';

export default function HistoricoScreen() {
  const { history, loading } = useStudentHistory();

  if (loading) {
    return <InstitutionalLoading />;
  }

  return (
    <DossierScreen scrollable={false}>
      <InstitutionalHeader title="Histórico de atividade" theme={dossie} />

      {!history || history.length === 0 ? (
        <View style={styles.empty}>
          <InstitutionalEmpty text="Nenhum registro disponível no momento." />
        </View>
      ) : (
        <HistoryTimeline items={history} />
      )}
    </DossierScreen>
  );
}

const styles = StyleSheet.create({
  empty: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
