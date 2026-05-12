import React, { useEffect, useState } from 'react';
import {
    View,
    Text,
    StyleSheet,
    FlatList,
    ActivityIndicator,
    TouchableOpacity,
    Alert,
    SafeAreaView
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useForceTheme } from '../../src/context/ForceThemeContext';
import { ActiveSession, getActiveSessions, revokeSession } from '../../src/services/sessionManagementService';

export default function ActiveSessionsScreen() {
    const { theme } = useForceTheme();
    const [sessions, setSessions] = useState<ActiveSession[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [revokingId, setRevokingId] = useState<string | null>(null);

    useEffect(() => {
        loadSessions();
    }, []);

    async function loadSessions() {
        setLoading(true);
        setError(null);
        try {
            const data = await getActiveSessions();
            setSessions(data);
        } catch (err: any) {
            console.error('Falha ao carregar sessões ativas:', err);
            setError('Não foi possível carregar as sessões ativas.');
        } finally {
            setLoading(false);
        }
    }

    function handleRevoke(sessionId: string, isCurrent: boolean) {
        Alert.alert(
            'Encerrar sessão',
            'Deseja encerrar a sessão deste dispositivo?',
            [
                { text: 'Cancelar', style: 'cancel' },
                {
                    text: 'Encerrar',
                    style: 'destructive',
                    onPress: async () => {
                        try {
                            setRevokingId(sessionId);
                            await revokeSession(sessionId);
                            // Se revogar o atual, o SessionGuardian/listener do supabase faz logout automático
                            if (!isCurrent) {
                                await loadSessions();
                            }
                        } catch (err: any) {
                            console.error('Falha ao revogar sessão:', err);
                            Alert.alert('Erro', 'Não foi possível encerrar a sessão remota.');
                        } finally {
                            setRevokingId(null);
                        }
                    },
                },
            ]
        );
    }

    const renderItem = ({ item }: { item: ActiveSession }) => {
        const isRevoking = revokingId === item.session_id;
        return (
            <View style={[styles.card, { backgroundColor: theme.card, borderColor: theme.border }]}>
                <View style={styles.cardHeader}>
                    <View style={styles.deviceInfo}>
                        <Ionicons
                            name={item.device_name?.toLowerCase().includes('iphone') || item.device_name?.toLowerCase().includes('android') ? 'phone-portrait-outline' : 'desktop-outline'}
                            size={24}
                            color={theme.textPrimary}
                        />
                        <View style={styles.deviceText}>
                            <Text style={[styles.deviceName, { color: theme.textPrimary }]}>
                                {item.device_name || 'Dispositivo desconhecido'}
                            </Text>
                            <Text style={[styles.lastSeen, { color: theme.textSecondary }]}>
                                Último acesso: {new Date(item.last_seen_at).toLocaleString('pt-BR')}
                            </Text>
                        </View>
                    </View>
                    {item.is_current && (
                        <View style={[styles.badge, { backgroundColor: theme.primary + '20' }]}>
                            <Text style={[styles.badgeText, { color: theme.primary }]}>Este dispositivo</Text>
                        </View>
                    )}
                </View>

                {/* Apenas mostra revoke se NAO for o atual, pelas regras da task, ou se mostrar o atual, tratamos explícito. Task pede "apenas remotas" mas também cita "atual sem confirmação". Vamos mostrar em todas, mas só se formos permitir. Task diz: "Ação 'Encerrar sessão' apenas para sessões remotas". Ok, ocultaremos no atual para obedecer à regra estrita 3. */}
                {!item.is_current && (
                    <TouchableOpacity
                        style={[styles.revokeButton, { borderColor: theme.error }]}
                        onPress={() => handleRevoke(item.session_id, item.is_current)}
                        disabled={isRevoking}
                    >
                        {isRevoking ? (
                            <ActivityIndicator size="small" color={theme.error} />
                        ) : (
                            <Text style={[styles.revokeText, { color: theme.error }]}>Encerrar sessão</Text>
                        )}
                    </TouchableOpacity>
                )}
            </View>
        );
    };

    if (loading && sessions.length === 0) {
        return (
            <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
                <View style={styles.center}>
                    <ActivityIndicator size="large" color={theme.primary} />
                    <Text style={[styles.loadingText, { color: theme.textSecondary }]}>Carregando dispositivos...</Text>
                </View>
            </SafeAreaView>
        );
    }

    if (error && sessions.length === 0) {
        return (
            <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
                <View style={styles.center}>
                    <Ionicons name="alert-circle-outline" size={48} color={theme.error} />
                    <Text style={[styles.errorText, { color: theme.error }]}>{error}</Text>
                    <TouchableOpacity style={[styles.retryButton, { backgroundColor: theme.primary }]} onPress={loadSessions}>
                        <Text style={[styles.retryText, { color: theme.background }]}>Tentar novamente</Text>
                    </TouchableOpacity>
                </View>
            </SafeAreaView>
        );
    }

    return (
        <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
            <FlatList
                data={sessions}
                keyExtractor={(item) => item.session_id}
                renderItem={renderItem}
                contentContainerStyle={styles.listContent}
                ListHeaderComponent={() => (
                    <View style={styles.header}>
                        <Text style={[styles.title, { color: theme.textPrimary }]}>Sessões ativas</Text>
                        <Text style={[styles.subtitle, { color: theme.textSecondary }]}>
                            Gerencie os dispositivos com acesso à sua conta
                        </Text>
                    </View>
                )}
                ListEmptyComponent={() => (
                    <View style={styles.emptyContainer}>
                        <Ionicons name="shield-checkmark-outline" size={48} color={theme.textMuted} />
                        <Text style={[styles.emptyText, { color: theme.textSecondary }]}>
                            Nenhuma sessão ativa encontrada.
                        </Text>
                    </View>
                )}
            />
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
    },
    listContent: {
        padding: 20,
    },
    header: {
        marginBottom: 24,
    },
    title: {
        fontSize: 24,
        fontWeight: 'bold',
        marginBottom: 8,
    },
    subtitle: {
        fontSize: 14,
        lineHeight: 20,
    },
    center: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        padding: 24,
    },
    loadingText: {
        marginTop: 16,
        fontSize: 16,
    },
    errorText: {
        marginTop: 16,
        fontSize: 16,
        textAlign: 'center',
        marginBottom: 24,
    },
    retryButton: {
        paddingHorizontal: 24,
        paddingVertical: 12,
        borderRadius: 8,
    },
    retryText: {
        fontWeight: 'bold',
        fontSize: 16,
    },
    card: {
        borderRadius: 12,
        borderWidth: 1,
        padding: 16,
        marginBottom: 16,
    },
    cardHeader: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'flex-start',
    },
    deviceInfo: {
        flexDirection: 'row',
        flex: 1,
        gap: 12,
    },
    deviceText: {
        flex: 1,
    },
    deviceName: {
        fontSize: 16,
        fontWeight: '600',
        marginBottom: 4,
    },
    lastSeen: {
        fontSize: 12,
    },
    badge: {
        paddingHorizontal: 8,
        paddingVertical: 4,
        borderRadius: 4,
        marginLeft: 12,
    },
    badgeText: {
        fontSize: 10,
        fontWeight: 'bold',
        textTransform: 'uppercase',
    },
    revokeButton: {
        marginTop: 16,
        borderWidth: 1,
        borderRadius: 8,
        paddingVertical: 10,
        alignItems: 'center',
        justifyContent: 'center',
    },
    revokeText: {
        fontSize: 14,
        fontWeight: 'bold',
    },
    emptyContainer: {
        alignItems: 'center',
        marginTop: 48,
        gap: 16,
    },
    emptyText: {
        fontSize: 16,
    }
});
