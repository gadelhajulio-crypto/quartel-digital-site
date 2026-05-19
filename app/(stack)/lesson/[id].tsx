import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Alert, SafeAreaView, Linking } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useLessonData } from '../../../src/hooks/useLessonData';
import { useCanonicalIdentity } from '../../../src/hooks/useCanonicalIdentity';
import { completeLesson } from '../../../src/services/progressService';
import { VideoPlayer } from '../../../src/components/VideoPlayer';
import { theme } from '../../../src/theme';

export default function LessonScreen() {
    const { id } = useLocalSearchParams();
    const router = useRouter();
    // Fix-03: recruta_id (recrutas.id) é a identidade canônica para queries de domínio
    const { recruta_id } = useCanonicalIdentity();

    const { data: lesson, loading } = useLessonData(String(id), recruta_id ?? undefined);
    const [completing, setCompleting] = useState(false);
    const [justCompleted, setJustCompleted] = useState(false);

    // 1. Loading State
    if (loading) {
        return (
            <View style={[styles.container, styles.center]}>
                <ActivityIndicator size="large" color={theme.colors.gold} />
            </View>
        );
    }

    // 2. Error State
    if (!lesson) {
        return (
            <View style={[styles.container, styles.center]}>
                <Text style={styles.textSecondary}>Aula não encontrada.</Text>
                <TouchableOpacity onPress={() => router.back()} style={styles.retryBtn}>
                    <Text style={styles.textPrimary}>Voltar</Text>
                </TouchableOpacity>
            </View>
        );
    }

    const { title, video_url, pdf_url, completed_at } = lesson;
    const isCompleted = justCompleted || !!completed_at;
    const url = video_url ?? pdf_url;

    // 3. Content Renderer Logic (Strict URL Pattern Matching)
    const renderContent = () => {
        if (!url) {
            return (
                <View style={styles.placeholder}>
                    <Ionicons name="school-outline" size={64} color={theme.colors.textSecondary} />
                    <Text style={[styles.textSecondary, { marginTop: 16 }]}>Conteúdo Institucional</Text>
                </View>
            );
        }

        const lowerUrl = url.toLowerCase();

        // 3.1 Video (Cloudflare Stream)
        // Checks for 'cloudflarestream' presence or typical video extensions for safety
        if (lowerUrl.includes('cloudflarestream') || lowerUrl.includes('customer-') || lowerUrl.endsWith('.m3u8')) {
            return <VideoPlayer uri={url} />;
        }

        // 3.2 Audio
        if (lowerUrl.endsWith('.mp3') || lowerUrl.endsWith('.aac')) {
            return (
                <View style={styles.placeholder}>
                    <Ionicons name="musical-notes" size={64} color={theme.colors.gold} />
                    <Text style={styles.textPrimary}>Áudio Disponível</Text>
                    {/* Placeholder for Audio Player - Simple Implementation */}
                </View>
            );
        }

        // 3.3 PDF (Embedded Viewer)
        if (lowerUrl.endsWith('.pdf')) {
            return (
                <View style={styles.placeholder}>
                    <Ionicons name="document-text" size={64} color={theme.colors.textPrimary} />
                    <Text style={[styles.textPrimary, { marginTop: 16 }]}>Documento PDF</Text>
                    <TouchableOpacity onPress={() => Linking.openURL(url)} style={{ marginTop: 10 }}>
                        <Text style={{ color: theme.colors.gold }}>Abrir Externamente</Text>
                    </TouchableOpacity>
                </View>
            );
        }

        // Fallback
        return (
            <View style={styles.placeholder}>
                <Text style={styles.textSecondary}>Formato de mídia desconhecido.</Text>
            </View>
        );
    };

    async function handleComplete() {
        if (!recruta_id || !id || completing || isCompleted) return;
        setCompleting(true);

        try {
            // recruta_id retido na assinatura por compat — ignorado pelo backend
            // (rpc_complete_lesson usa auth.uid() internamente)
            await completeLesson(String(id), recruta_id);
            setJustCompleted(true);
            setCompleting(false);
            router.back();
        } catch (e) {
            Alert.alert('Erro', 'Tente novamente.');
            setCompleting(false);
        }
    }

    return (
        <SafeAreaView style={styles.container}>
            {/* Header Fixo */}
            <View style={styles.header}>
                <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
                    <Ionicons name="arrow-back" size={24} color={theme.colors.textPrimary} />
                </TouchableOpacity>
                <Text style={styles.headerTitle} numberOfLines={1}>{title}</Text>
            </View>

            {/* Conteúdo Central */}
            <View style={styles.content}>
                {renderContent()}
            </View>

            {/* Footer Fixo */}
            <View style={styles.footer}>
                {isCompleted ? (
                    <View style={[styles.completeBtn, styles.completedBanner]}>
                        <Ionicons name="checkmark-circle" size={18} color="#000" style={{ marginRight: 8 }} />
                        <Text style={styles.completeBtnText}>AULA CONCLUÍDA</Text>
                    </View>
                ) : (
                    <TouchableOpacity
                        style={[styles.completeBtn, completing && { opacity: 0.7 }]}
                        onPress={handleComplete}
                        disabled={completing}
                    >
                        <Text style={styles.completeBtnText}>
                            {completing ? 'REGISTRANDO...' : 'MARCAR AULA COMO CONCLUÍDA'}
                        </Text>
                    </TouchableOpacity>
                )}
            </View>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: theme.colors?.background || '#000',
    },
    center: {
        justifyContent: 'center',
        alignItems: 'center',
    },
    header: {
        height: 60,
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 16,
        borderBottomWidth: 1,
        borderBottomColor: '#333',
    },
    backBtn: {
        padding: 8,
        marginRight: 8,
    },
    headerTitle: {
        fontSize: 18,
        fontWeight: 'bold',
        color: theme.colors?.textPrimary || '#FFF',
        flex: 1,
    },
    content: {
        flex: 1,
        justifyContent: 'center', // Center media vertically
    },
    placeholder: {
        alignItems: 'center',
        justifyContent: 'center',
        padding: 24,
    },
    footer: {
        padding: 16,
        borderTopWidth: 1,
        borderTopColor: '#333',
        backgroundColor: theme.colors?.background || '#000',
    },
    completeBtn: {
        backgroundColor: theme.colors?.gold || '#FFD700',
        paddingVertical: 16,
        borderRadius: 8,
        alignItems: 'center',
    },
    completedBanner: {
        flexDirection: 'row',
        justifyContent: 'center',
        opacity: 0.85,
    },
    completeBtnText: {
        color: '#000',
        fontWeight: 'bold',
        fontSize: 14,
        textTransform: 'uppercase',
    },
    textPrimary: {
        color: theme.colors?.textPrimary || '#FFF',
    },
    textSecondary: {
        color: theme.colors?.textSecondary || '#AAA',
    },
    retryBtn: {
        marginTop: 16,
        padding: 8,
    },
});
