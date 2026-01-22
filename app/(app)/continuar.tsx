import React, { useEffect } from 'react';
import { View, ActivityIndicator } from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '../../src/context/AuthContext';
import { useForceTheme } from '../../src/context/ForceThemeContext';
import { useNextLesson } from '../../src/hooks/useNextLesson';

export default function ContinuarScreen() {
    const router = useRouter();
    const { session } = useAuth();
    const { theme } = useForceTheme();
    const { nextLesson, loading } = useNextLesson(session?.user?.id);

    useEffect(() => {
        if (loading) return;

        if (nextLesson && nextLesson.lesson_id) {
            console.log('[CONTINUAR] Redirecionando para próxima aula:', nextLesson.lesson_id);
            router.replace({
                pathname: "/aula/[id]",
                params: { id: nextLesson.lesson_id }
            });
        } else {
            console.log('[CONTINUAR] Nenhuma próxima aula encontrada ou curso concluído. Voltando ao painel.');
            router.replace('/');
        }
    }, [nextLesson, loading]);

    return (
        <View style={{ flex: 1, backgroundColor: theme.background, justifyContent: 'center', alignItems: 'center' }}>
            <ActivityIndicator size="large" color={theme.primary || '#FFD166'} />
        </View>
    );
}
