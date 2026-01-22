import { View, Text, FlatList, StyleSheet } from 'react-native';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { useStudentHistory } from '../../../src/hooks/useStudentHistory';
import { HistoryRow } from '../../../src/components/rows/HistoryRow';
import { InstitutionalLoading } from '../../../src/components/InstitutionalLoading';
import { InstitutionalEmpty } from '../../../src/components/InstitutionalEmpty';

export default function HistoricoScreen() {
    const { theme } = useForceTheme();
    const { history, loading } = useStudentHistory();

    if (loading) {
        return <InstitutionalLoading />;
    }

    if (!history || history.length === 0) {
        return (
            <View style={[styles.container, { backgroundColor: theme.background }]}>
                <Text style={[styles.header, { color: theme.primary }]}>
                    Histórico do Recruta
                </Text>
                <InstitutionalEmpty text="Nenhum registro disponível no momento." />
            </View>
        );
    }

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            <Text style={[styles.header, { color: theme.primary }]}>
                Histórico do Recruta
            </Text>

            <FlatList
                data={history}
                keyExtractor={(item) => item.history_id}
                contentContainerStyle={styles.list}
                renderItem={({ item }) => (
                    <HistoryRow
                        type={item.event_type}
                        title={item.title}
                        description={item.description}
                        date={item.created_at}
                    />
                )}
            />
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        padding: 16,
    },
    header: {
        fontSize: 20,
        fontWeight: '600',
        marginBottom: 16,
    },
    list: {
        gap: 12,
    },
});
