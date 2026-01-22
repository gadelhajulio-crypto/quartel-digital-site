import { View, Text, FlatList, StyleSheet } from 'react-native';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { useMedals } from '../../../src/hooks/useMedals';
import { MedalCard } from '../../../src/components/cards/MedalCard';

export default function MedalhasScreen() {
    const { theme } = useForceTheme();
    const { medals, loading } = useMedals();

    if (loading) {
        return (
            <View style={[styles.container, { backgroundColor: theme.background }]}>
                <Text style={{ color: theme.text }}>Carregando medalhas…</Text>
            </View>
        );
    }

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Header institucional */}
            <Text style={[styles.header, { color: theme.primary }]}>
                Medalhas Institucionais
            </Text>

            <FlatList
                data={medals}
                keyExtractor={(item) => item.medal_id}
                contentContainerStyle={styles.list}
                renderItem={({ item }) => (
                    <MedalCard
                        name={item.name}
                        description={item.description}
                        level={item.level}
                        achieved={item.achieved}
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
