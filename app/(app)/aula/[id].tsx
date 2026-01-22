import { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, ActivityIndicator, TouchableOpacity, Alert } from 'react-native'
import { useLocalSearchParams, Stack, useRouter } from 'expo-router'
import { supabase } from '../../../src/lib/supabase'
import { useLessonData } from '../../../src/hooks/useLessonData'
import { isLessonBlocked } from '../../../src/lib/lessonAccess'
import { VideoCard } from '../../../src/components/cards/VideoCard'
import { PdfCard } from '../../../src/components/cards/PdfCard'
import { useAuth } from '../../../src/context/AuthContext'
import { useForceTheme } from '../../../src/context/ForceThemeContext' // Corrected context
import { Header } from '../../../src/components/Header'

export default function LessonScreen() {
    // Standardize param name to 'id' for the new route /aula/[id]
    const { id } = useLocalSearchParams()
    const { session } = useAuth();
    const { theme } = useForceTheme(); // Use Theme
    const userId = session?.user?.id;

    // Use id param
    const { data, loading } = useLessonData(String(id), userId)

    // State for local UI feeling (optimistic or synced)
    // Actually data.lesson_progress is fetched, but we might want to manually mark it if user clicks.
    const [saving, setSaving] = useState(false);

    const router = useRouter();

    if (loading || !data) {
        return (
            <View style={[styles.container, styles.center, { backgroundColor: theme.background }]}>
                <ActivityIndicator size="large" color={theme.accent || '#FFD166'} />
            </View>
        )
    }

    const blocked = isLessonBlocked(data)
    const isCompleted = !!data.lesson_progress?.completed_at;

    // Find video media
    const videoMedia = data.lesson_media?.find(m => m.type === 'video');
    const pdfMedia = data.lesson_media?.find(m => m.type === 'pdf');

    async function handleConcluir() {
        if (!userId || !id || isCompleted) return;
        setSaving(true);

        const { error } = await supabase
            .from('progresso_aulas')
            .insert({ user_id: userId, aula_id: id });

        if (error && error.code !== '23505') {
            Alert.alert('Erro', 'Não foi possível concluir a aula.');
            setSaving(false);
            return;
        }

        Alert.alert('Sucesso', 'Aula concluída! +XP', [{ text: 'OK', onPress: () => router.back() }]);
        setSaving(false);
        // In a perfect world, we'd refetch or update cache, but for now router.back is safe per legacy behavior.
    }

    return (
        <ScrollView style={[styles.container, { backgroundColor: theme.background }]}>
            <Stack.Screen options={{ headerShown: false }} />
            <View style={{ padding: 16 }}>
                <Header title={data.module.toUpperCase()} />

                <Text style={[styles.lessonTitle, { color: theme.textPrimary }]}>{data.title}</Text>

                <VideoCard
                    uri={videoMedia?.url}
                    blocked={blocked}
                />

                <PdfCard uri={pdfMedia?.url} blocked={blocked} />

                {blocked ? (
                    <Text style={[styles.blockedText, { color: theme.textSecondary }]}>
                        Conteúdo disponível após progressão no curso.
                    </Text>
                ) : (
                    <TouchableOpacity
                        style={[
                            styles.concluirButton,
                            { backgroundColor: isCompleted ? theme.card : theme.accent, marginTop: 24 }
                        ]}
                        disabled={isCompleted || saving}
                        onPress={handleConcluir}
                    >
                        <Text style={{
                            color: isCompleted ? theme.textSecondary : theme.background,
                            fontWeight: 'bold'
                        }}>
                            {isCompleted ? 'AULA CONCLUÍDA' : 'MARCAR COMO CONCLUÍDA'}
                        </Text>
                    </TouchableOpacity>
                )}
            </View>
        </ScrollView>
    )
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
    },
    center: {
        justifyContent: 'center',
        alignItems: 'center',
    },
    lessonTitle: {
        fontSize: 20,
        fontWeight: 'bold',
        marginBottom: 20,
        marginTop: 10,
    },
    blockedText: {
        textAlign: 'center',
        marginTop: 20,
    },
    concluirButton: {
        padding: 16,
        borderRadius: 12,
        alignItems: 'center',
        justifyContent: 'center'
    }
});
