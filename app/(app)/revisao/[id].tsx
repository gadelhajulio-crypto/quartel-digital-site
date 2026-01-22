import { View, Text, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { useReviewContent } from '../../../src/hooks/useReviewContent';
import { ReviewAudioPlayer } from '../../../src/components/players/ReviewAudioPlayer';
import { ReviewVideoPlayer } from '../../../src/components/players/ReviewVideoPlayer';

export default function RevisaoConsumoScreen() {
    const { id } = useLocalSearchParams<{ id: string }>();
    const { theme } = useForceTheme();
    const { content, loading } = useReviewContent(id);

    if (loading || !content) {
        return (
            <View style={[styles.container, { backgroundColor: theme.background }]}>
                <Text style={{ color: theme.text }}>Carregando revisão…</Text>
            </View>
        );
    }

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Contexto institucional */}
            <Text style={[styles.lessonTitle, { color: theme.muted }]}>
                Aula relacionada
            </Text>
            <Text style={[styles.lessonName, { color: theme.text }]}>
                {content.lesson_title}
            </Text>

            <View style={styles.playerContainer}>
                {content.type === 'audio' ? (
                    <ReviewAudioPlayer sourceUrl={content.media_url} />
                ) : (
                    <ReviewVideoPlayer sourceUrl={content.media_url} />
                )}
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        padding: 16,
    },
    lessonTitle: {
        fontSize: 13,
        marginBottom: 4,
    },
    lessonName: {
        fontSize: 18,
        fontWeight: '600',
        marginBottom: 16,
    },
    playerContainer: {
        flex: 1,
        justifyContent: 'center',
    },
});
