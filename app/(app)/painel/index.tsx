import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Alert, Image, Platform } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { RadarLoading } from '../../../src/components/RadarLoading';

// @ts-ignore
const logoImg = require('../../../assets/logorecrutapadrao.png');

// DNA Spec:
// Header Fixo #1B2419, Title Center
// Card Tropa Base: #283618, Gold Progress
// Grid: MÓDULOS, MISSÕES, RANKING

export default function PainelScreen() {
    const router = useRouter();
    const { theme, userForce } = useTheme();
    const [loading, setLoading] = useState(true);
    const [xp, setXp] = useState(1250);
    const targetXp = 2000;
    const progress = xp / targetXp;

    useEffect(() => {
        setTimeout(() => setLoading(false), 500);
    }, []);

    if (loading) {
        return (
            <View style={[styles.container, { backgroundColor: theme.background, justifyContent: 'center', alignItems: 'center' }]}>
                <RadarLoading color={theme.primary} />
            </View>
        );
    }

    // Grid Card Component
    const GridCard = ({ title, icon, onPress, value, badge }: { title: string, icon: string, onPress: () => void, value?: string, badge?: string }) => (
        <TouchableOpacity style={[styles.gridCard, { backgroundColor: theme.surface, borderRadius: 12 }]} onPress={onPress}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                <Text style={styles.cardIcon}>{icon}</Text>
                {badge && (
                    <View style={{ backgroundColor: theme.accent || '#FFD166', borderRadius: 8, paddingHorizontal: 6, paddingVertical: 2, height: 20, justifyContent: 'center' }}>
                        <Text style={{ color: '#000', fontSize: 10, fontWeight: 'bold' }}>{badge}</Text>
                    </View>
                )}
            </View>
            <View>
                {value && <Text style={[styles.cardValue, { color: theme.text }]}>{value}</Text>}
                <Text style={[styles.cardTitle, { color: theme.secondary }]}>{title}</Text>
            </View>
        </TouchableOpacity>
    );

    return (
        <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Header Fixo */}
            <View style={[styles.header, { backgroundColor: theme.background, borderBottomColor: 'rgba(255,255,255,0.05)' }]}>
                <Image source={logoImg} style={styles.headerLogo} resizeMode="contain" />
                <Text style={[styles.headerTitle, { color: theme.text }]}>PAINEL DO RECRUTA</Text>
            </View>

            <ScrollView contentContainerStyle={styles.content}>

                {/* Main Card */}
                <View style={[styles.mainCard, { backgroundColor: theme.surface, borderRadius: 12 }]}>
                    <View style={styles.cardHeader}>
                        <Text style={styles.helmetIcon}>🪖</Text>
                        <View style={{ flex: 1 }}>
                            <Text style={[styles.rankTitle, { color: theme.text }]}>TROPA BASE</Text>
                            <Text style={[styles.xpText, { color: '#AAA' }]}>{xp} / {targetXp} XP</Text>
                        </View>
                    </View>
                    {/* Gold Progress Bar */}
                    <View style={styles.progressTrack}>
                        <View style={[styles.progressFill, { width: `${progress * 100}%`, backgroundColor: theme.secondary }]} />
                    </View>
                </View>

                {/* Grid de Navegação */}
                <View style={styles.gridContainer}>
                    <GridCard
                        title="MÓDULOS"
                        icon="📂"
                        value="03"
                        onPress={() => router.push('/(app)/modulos')}
                    />
                    <GridCard
                        title="MISSÕES"
                        icon="🎯"
                        value="ATIVAS"
                        onPress={() => router.push('/(app)/modulo/1')} // Direct to current mission
                    />
                </View>
                <View style={styles.gridContainer}>
                    <GridCard
                        title="RANKING"
                        icon="🏆"
                        value="18º"
                        onPress={() => router.push('/(app)/ranking')}
                    />
                    <GridCard
                        title="PERFIL"
                        icon="🪪"
                        onPress={() => router.push('/(app)/perfil')}
                    />
                </View>



                {/* Instructor Access Card - NEW */}
                <TouchableOpacity
                    style={[styles.instructorCard, { backgroundColor: theme.surface, borderColor: theme.secondary }]}
                    onPress={() => router.push('/(protected)/chat')}
                >
                    <View style={styles.instructorIconContainer}>
                        <Text style={{ fontSize: 28 }}>👮‍♂️</Text>
                    </View>
                    <View style={styles.instructorTextContainer}>
                        <Text style={[styles.instructorTitle, { color: theme.secondary }]}>FALAR COM INSTRUTOR</Text>
                        <Text style={[styles.instructorSubtitle, { color: '#AAA' }]}>
                            Canal Seguro &bull; {theme.forces?.navy ? 'Naval' : 'Militar'}
                        </Text>
                    </View>
                    <Text style={{ fontSize: 20, color: theme.secondary }}>›</Text>
                </TouchableOpacity>

            </ScrollView>
        </SafeAreaView >
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
    },
    header: {
        height: Platform.OS === 'ios' ? 60 : 100, // Adjust height based on OS or rely on Flex
        paddingTop: Platform.OS === 'ios' ? 0 : 40, // SafeAreaView handles iOS padding
        alignItems: 'center',
        justifyContent: 'center',
        borderBottomWidth: 1,
        flexDirection: 'row',
    },
    headerLogo: {
        width: 30,
        height: 30,
        marginRight: 10,
    },

    headerTitle: {
        fontSize: 18,
        fontWeight: '700',
        letterSpacing: 2,
        textTransform: 'uppercase',
    },
    content: {
        padding: 20,
    },
    mainCard: {
        padding: 24,
        marginBottom: 30,
        elevation: 4,
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.3,
        shadowRadius: 4,
    },
    cardHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 16,
    },
    helmetIcon: {
        fontSize: 36,
        marginRight: 16,
    },
    rankTitle: {
        fontSize: 20,
        fontWeight: '700',
        letterSpacing: 1,
        textTransform: 'uppercase',
    },
    xpText: {
        fontSize: 12,
        fontWeight: '700',
        marginTop: 4,
    },
    progressTrack: {
        height: 8,
        backgroundColor: 'rgba(0,0,0,0.3)',
        borderRadius: 4,
        overflow: 'hidden',
    },
    progressFill: {
        height: '100%',
        borderRadius: 4,
    },
    gridContainer: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        marginBottom: 16,
    },
    gridCard: {
        width: '48%', // Grid layout
        padding: 20,
        height: 140,
        justifyContent: 'space-between',
        elevation: 2,
    },
    cardIcon: {
        fontSize: 28,
        marginBottom: 10,
    },
    cardValue: {
        fontSize: 24,
        fontWeight: '700',
        marginBottom: 4,
    },
    cardTitle: {
        fontSize: 12,
        fontWeight: '700',
        letterSpacing: 1,
        textTransform: 'uppercase',
    },
    instructorCard: {
        flexDirection: 'row',
        alignItems: 'center',
        padding: 16,
        borderRadius: 12,
        borderWidth: 1,
        marginBottom: 30, // Bottom spacing for Safe Area
    },
    instructorIconContainer: {
        width: 50,
        height: 50,
        borderRadius: 25,
        backgroundColor: 'rgba(0,0,0,0.3)',
        justifyContent: 'center',
        alignItems: 'center',
        marginRight: 16,
    },
    instructorTextContainer: {
        flex: 1,
    },
    instructorTitle: {
        fontSize: 16,
        fontWeight: '700',
        letterSpacing: 1,
        marginBottom: 4,
    },
    instructorSubtitle: {
        fontSize: 12,
    }
});
