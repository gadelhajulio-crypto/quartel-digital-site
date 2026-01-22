import { View, Text, FlatList, StyleSheet, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { useAvailableReviews } from '../../../src/hooks/useAvailableReviews';
import { ReviewCard } from '../../../src/components/cards/ReviewCard';
import { useForceTheme } from '../../../src/context/ForceThemeContext';

export default function RevisoesScreen() {
    const { theme } = useForceTheme();
    const router = useRouter();
    const { reviews, loading } = useAvailableReviews();

    if (loading) {
        return (
            <View style={[styles.container, { backgroundColor: theme.background }]}>
                <Text style={{ color: theme.text }}>Carregando revisões…</Text>
            </View>
        );
    }

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Header institucional */}
            <Text style={[styles.header, { color: theme.primary }]}>
                Revisões Disponíveis
            </Text>

            <FlatList
                data={reviews}
                keyExtractor={(item) => item.review_id}
                contentContainerStyle={styles.list}
                renderItem={({ item }) => (
                    <ReviewCard
                        lessonTitle={item.lesson_title}
                        type={item.type}
                        status={item.status}
                        onPress={() => {
                            if (item.status === 'available') {
                                router.push(`/revisao/${item.review_id}`);
                            } else {
                                Alert.alert(
                                    'Revisão indisponível',
                                    'Esta revisão será liberada após os critérios pedagógicos definidos.'
                                );
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
        gap: 12,
    },
});
