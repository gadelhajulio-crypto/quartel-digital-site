import { View, Text, FlatList, StyleSheet } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useModuleLessons } from '../../../src/hooks/useModuleLessons';
import { LessonRow } from '../../../src/components/rows/LessonRow';
import { useForceTheme } from '../../../src/context/ForceThemeContext';

export default function ModuloAulasScreen() {
    const { id } = useLocalSearchParams<{ id: string }>();
    const router = useRouter();
    const { theme } = useForceTheme();

    const { lessons, loading } = useModuleLessons(id);

    if (loading) {
        return (
            <View style={[styles.container, { backgroundColor: theme.background }]}>
                <Text style={{ color: theme.text }}>Carregando aulas…</Text>
            </View>
        );
    }

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Header institucional */}
            <Text style={[styles.header, { color: theme.primary }]}>
                Aulas do Módulo
            </Text>

            <FlatList
                data={lessons}
                keyExtractor={(item) => item.lesson_id}
                contentContainerStyle={styles.list}
                renderItem={({ item }) => (
                    <LessonRow
                        order={item.lesson_order}
                        title={item.lesson_title}
                        status={item.status}
                        onPress={() => {
                            if (item.status === 'available') {
                                router.push(`/aula/${item.lesson_id}`);
                            }
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
        gap: 8,
    },
});
