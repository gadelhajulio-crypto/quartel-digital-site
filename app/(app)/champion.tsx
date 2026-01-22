import React from 'react';
import { View, Text, StyleSheet, ActivityIndicator } from 'react-native';
import { useMonthlyChampion } from '../../src/hooks/useMonthlyChampion';
import { useAuth } from '../../src/context/AuthContext';
import { useForceTheme } from '../../src/context/ForceThemeContext';
import { Header } from '../../src/components/Header';
import { Ionicons } from '@expo/vector-icons';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';

export default function ChampionScreen() {
    const { session, profile } = useAuth();
    const userForce = profile?.forca || 'marinha';

    const { theme } = useForceTheme(); // Dynamic Theme
    const styles = getStyles(theme);

    const { champion, loading } = useMonthlyChampion(userForce);

    if (loading) {
        return (
            <View style={[styles.container, styles.center]}>
                <ActivityIndicator size="large" color={theme.accent || '#FFD166'} />
            </View>
        );
    }

    const currentMonthName = format(new Date(), 'MMMM', { locale: ptBR }).toUpperCase();
    const name = champion?.profiles?.war_name || champion?.profiles?.full_name || champion?.profiles?.name || 'Recruta';

    return (
        <View style={styles.container}>
            <Header title="CAMPEÃO MENSAL" />

            <View style={styles.content}>
                <View style={styles.trophyContainer}>
                    <Ionicons name="trophy" size={80} color={theme.accent || '#FFD166'} />
                </View>

                <Text style={styles.monthText}>{currentMonthName}</Text>

                {champion ? (
                    <View style={styles.card}>
                        <Text style={styles.rank}>#1</Text>
                        <Text style={styles.name}>{name}</Text>
                        <View style={styles.divider} />
                        <Text style={styles.force}>{userForce.toUpperCase()}</Text>
                    </View>
                ) : (
                    <Text style={styles.emptyText}>
                        Ainda não há um campeão definido para este mês.
                    </Text>
                )}
            </View>
        </View>
    );
}

const getStyles = (theme: any) => StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: theme.background,
    },
    center: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
    },
    content: {
        flex: 1,
        alignItems: 'center',
        padding: 32,
        marginTop: 40,
    },
    trophyContainer: {
        marginBottom: 24,
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 4 },
        shadowOpacity: 0.3,
        shadowRadius: 4,
        elevation: 8,
    },
    monthText: {
        color: theme.textSecondary,
        fontSize: 14,
        letterSpacing: 2,
        marginBottom: 32,
        fontWeight: 'bold',
    },
    card: {
        backgroundColor: theme.card,
        width: '100%',
        padding: 32,
        borderRadius: 16,
        alignItems: 'center',
        borderWidth: 1,
        borderColor: 'rgba(255, 215, 0, 0.2)',
    },
    rank: {
        fontSize: 48,
        fontWeight: 'bold',
        color: theme.accent || '#FFD166',
        marginBottom: 8,
    },
    name: {
        fontSize: 20,
        color: theme.textPrimary,
        fontWeight: 'bold',
        textAlign: 'center',
        marginBottom: 16,
    },
    divider: {
        width: 40,
        height: 2,
        backgroundColor: 'rgba(255,255,255,0.1)',
        marginBottom: 16,
    },
    force: {
        color: theme.textSecondary,
        fontSize: 12,
        letterSpacing: 2,
        fontWeight: 'bold',
    },
    emptyText: {
        color: theme.textSecondary,
        textAlign: 'center',
        marginTop: 20,
        fontSize: 16,
    }
});
