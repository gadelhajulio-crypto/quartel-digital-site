import React, { useEffect, useState, useMemo } from 'react';
import {
    View,
    Text,
    FlatList,
    TouchableOpacity,
    StyleSheet,
    ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { useForceTheme } from '../context/ForceThemeContext';
import { useRouter, useLocalSearchParams } from 'expo-router';

type Aula = {
    id: string;
    titulo: string;
    ordem: number;
    video_url?: string;
    pdf_url?: string;
};

export default function ModuleLessonsScreen() {
    const router = useRouter();
    // Params: id comes from /modulo/[id]
    const { id, moduloTitulo: titleParam, isDegustacao: degustacaoParam, isLiberado: liberadoParam } = useLocalSearchParams();

    // Normalize params
    const moduloId = Array.isArray(id) ? id[0] : id;
    const moduloTitulo = Array.isArray(titleParam) ? titleParam[0] : titleParam;
    const isDegustacao = degustacaoParam === 'true';
    const isLiberado = liberadoParam === 'true';

    const { session } = useAuth();
    const { theme, loading: themeLoading } = useForceTheme();

    const styles = useMemo(() => getStyles(theme), [theme]);

    if (themeLoading || !theme) {
        return (
            <View style={{ flex: 1, backgroundColor: '#020B14', justifyContent: 'center', alignItems: 'center' }}>
                <ActivityIndicator size="large" color="#FFD166" />
            </View>
        );
    }

    const userId = session?.user?.id;

    const [aulas, setAulas] = useState<Aula[]>([]);
    const [concluidas, setConcluidas] = useState<string[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (userId && moduloId) {
            loadData();
        }
    }, [userId, moduloId]);

    async function loadData() {
        setLoading(true);
        await Promise.all([loadAulas(), loadConcluidas()]);
        setLoading(false);
    }

    async function loadAulas() {
        try {
            const { data, error } = await supabase
                .from('aulas')
                .select('id, titulo, ordem') // Temporarily removed video_url and pdf_url to prevent crash
                .eq('modulo_id', moduloId)
                .order('ordem');

            if (error) throw error;
            if (data) setAulas(data);
        } catch (err) {
            console.error('Error loading aulas:', err);
        }
    }

    async function loadConcluidas() {
        try {
            if (!userId) return;
            const { data, error } = await supabase
                .from('progresso_aulas')
                .select('aula_id')
                .eq('user_id', userId);
            // .eq('concluida', true); // Removed as per request

            if (error) throw error;

            if (data) {
                setConcluidas(data.map((item) => item.aula_id));
            }
        } catch (err) {
            console.error('Error loading concluidas:', err);
        }
    }

    function isAulaLiberada(aulaId: string) {
        if (isDegustacao) return true;
        if (isLiberado) return true;
        return false;
    }

    function renderItem({ item }: { item: Aula }) {
        const concluida = concluidas.includes(item.id);
        const liberada = isAulaLiberada(item.id);

        let iconName: keyof typeof Ionicons.glyphMap = 'lock-closed';
        let iconColor = theme.textSecondary;

        if (concluida) {
            iconName = 'checkmark-circle';
            iconColor = theme.accent;
        } else if (liberada) {
            iconName = 'play-circle';
            iconColor = theme.textSecondary;
        }

        return (
            <TouchableOpacity
                disabled={!liberada && !concluida}
                onPress={() =>
                    router.push({
                        pathname: `/lesson/${item.id}`,
                        params: {
                            aulaTitulo: item.titulo,
                            videoUrl: item.video_url || '',
                            pdfUrl: item.pdf_url || '',
                        }
                    })
                }
                style={[
                    styles.card,
                    {
                        backgroundColor: theme.card,
                        opacity: (liberada || concluida) ? 1 : 0.5,
                    },
                ]}
            >
                <Ionicons name={iconName} size={24} color={iconColor} style={{ marginRight: 12 }} />

                <View style={{ flex: 1 }}>
                    <Text
                        style={[
                            styles.titulo,
                            { color: theme.textPrimary },
                        ]}
                    >
                        {item.titulo}
                    </Text>

                    <Text
                        style={{
                            color: iconColor,
                            fontSize: 12,
                            marginTop: 4,
                        }}
                    >
                        {concluida
                            ? 'Concluída'
                            : liberada
                                ? 'Disponível'
                                : 'Bloqueada'}
                    </Text>
                </View>
            </TouchableOpacity>
        );
    }

    return (
        <SafeAreaView style={[styles.safe, { backgroundColor: theme.background }]}>
            <View style={styles.container}>
                <View style={styles.headerContainer}>
                    <TouchableOpacity onPress={() => router.back()} style={{ padding: 8, marginRight: 8 }}>
                        <Ionicons name="arrow-back" size={24} color={theme.textPrimary} />
                    </TouchableOpacity>
                    <Text style={[styles.header, { color: theme.textPrimary }]}>
                        {moduloTitulo || 'Aulas do Módulo'}
                    </Text>
                </View>

                {loading ? (
                    <View style={styles.loadingContainer}>
                        <ActivityIndicator size="large" color={theme.accent} />
                        <Text style={{ color: theme.textSecondary, marginTop: 10 }}>Carregando instruções...</Text>
                    </View>
                ) : (
                    <FlatList
                        data={aulas}
                        keyExtractor={(item) => item.id}
                        renderItem={renderItem}
                        contentContainerStyle={{ paddingBottom: 32 }}
                        ListEmptyComponent={
                            <Text style={{ color: theme.textSecondary, textAlign: 'center', marginTop: 20 }}>
                                Nenhuma aula encontrada neste módulo.
                            </Text>
                        }
                    />
                )}
            </View>
        </SafeAreaView>
    );
}

const getStyles = (theme: any) => StyleSheet.create({
    safe: {
        flex: 1,
    },
    container: {
        flex: 1,
        padding: 16,
    },
    headerContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 20,
    },
    header: {
        fontSize: 20,
        fontWeight: '700',
        flex: 1,
    },
    card: {
        padding: 16,
        borderRadius: 12,
        marginBottom: 12,
        flexDirection: 'row',
        alignItems: 'center',
    },
    titulo: {
        fontSize: 16,
        fontWeight: '600',
    },
    loadingContainer: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
    },
});
