import { View, Text, FlatList, StyleSheet } from 'react-native';
import { useModulesProgress } from '../../../src/hooks/useModulesProgress';
import { ModuleCard } from '../../../src/components/cards/ModuleCard';
import { useForceTheme } from '../../../src/context/ForceThemeContext';

export default function ModulosScreen() {
    const { theme } = useForceTheme();
    const { modules, loading } = useModulesProgress();

    if (loading) {
        return (
            <View style={[styles.container, { backgroundColor: theme.background }]}>
                <Text style={{ color: theme.text }}>Carregando módulos…</Text>
            </View>
        );
    }

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Header institucional */}
            <Text style={[styles.header, { color: theme.primary }]}>
                Módulos do Curso
            </Text>

            <FlatList
                data={modules}
                keyExtractor={(item) => item.module_id}
                contentContainerStyle={styles.list}
                renderItem={({ item }) => (
                    <ModuleCard
                        moduleName={item.module_name}
                        totalLessons={item.total_lessons}
                        completedLessons={item.completed_lessons}
                        progressPercent={item.progress_percent}
                        onPress={() => {
                            // Navegação futura (ex: /modulos/[id])
                            // Nenhuma lógica de negócio aqui
                        }}
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
