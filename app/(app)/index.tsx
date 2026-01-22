import React from 'react';
import { View, Text, StyleSheet, ScrollView, ActivityIndicator, TouchableOpacity } from 'react-native';
import { useRecruitPanel } from '../../src/hooks/useRecruitPanel';
import { useAuth } from '../../src/context/AuthContext';
import { useForceTheme } from '../../src/context/ForceThemeContext';
import { NoticeBadge } from '../../src/components/NoticeBadge';

// ...

export default function PanelScreen() {
    // ...
    const { xp, completed, nextLesson, unreadNoticesCount, loading } = useRecruitPanel(userId!, userForce);

    // ...

    return (
        <ScrollView style={styles.container}>
            <View style={styles.headerContainer}>
                <Header title="PAINEL DO RECRUTA" />
                <View style={styles.badgeContainer}>
                    <NoticeBadge unreadCount={unreadNoticesCount || 0} />
                </View>
            </View>

            <View style={styles.courseHeader}>
// ...
                // Add styles
                const styles = StyleSheet.create({
                    // ...
                    headerContainer: {
                    position: 'relative',
    },
                badgeContainer: {
                    position: 'absolute',
                top: 16, // Adjust based on Header height
                right: 20,
                zIndex: 10,
    },
                // ...

                if (loading) {
        return (
                <View style={[styles.container, styles.center]}>
                    <ActivityIndicator size="large" color={theme.accent || '#FFD166'} />
                </View>
                );
    }

    const handleContinue = () => {
        if (nextLesson?.id) {
                    router.push(`/aula/${nextLesson.id}`);
        } else {
                    router.push('/(app)/aulas'); // Fallback to list
        }
    };

                return (
                <ScrollView style={styles.container}>
                    <Header title="PAINEL DO RECRUTA" />

                    <View style={styles.courseHeader}>
                        <Text style={styles.courseTitle}>CURSO DE FORMAÇÃO DE RECRUTAS</Text>
                        <Text style={styles.forceSubtitle}>FORÇA: {userForce.toUpperCase()}</Text>
                    </View>

                    <View style={styles.content}>

                        {/* 1. Módulo Ativo / Aula Atual */}
                        <View style={styles.activeCard}>
                            <View style={styles.statusRow}>
                                <View style={styles.statusDot} />
                                <Text style={styles.statusText}>EM ANDAMENTO</Text>
                            </View>

                            <Text style={styles.moduleName}>
                                {nextLesson?.module ? nextLesson.module.toUpperCase() : "MÓDULO INTRODUTÓRIO"}
                            </Text>

                            <Text style={styles.lessonTitle}>
                                {nextLesson?.title || "Carregando próxima aula..."}
                            </Text>

                            <TouchableOpacity style={styles.ctaButton} onPress={handleContinue}>
                                <Text style={styles.ctaText}>CONTINUAR</Text>
                                <Ionicons name="arrow-forward" size={20} color={theme.background} />
                            </TouchableOpacity>
                        </View>

                        {/* 2. Indicadores Institucionais */}
                        <View style={styles.statsContainer}>
                            <View style={styles.statBox}>
                                <Text style={styles.statValue}>{xp}</Text>
                                <Text style={styles.statLabel}>XP TOTAL</Text>
                            </View>
                            <View style={styles.statBox}>
                                <Text style={styles.statValue}>{completed}</Text>
                                <Text style={styles.statLabel}>AULAS CONCLUÍDAS</Text>
                            </View>
                        </View>

                        <Text style={styles.disclaimer}>
                            Mantenha a constância para garantir sua promoção.
                        </Text>

                    </View>
                </ScrollView>
                );
}

const getStyles = (theme: any) => StyleSheet.create({
                    container: {
                    flex: 1,
                backgroundColor: theme.background,
    },
                center: {
                    justifyContent: 'center',
                alignItems: 'center',
    },
                courseHeader: {
                    paddingHorizontal: 20,
                paddingBottom: 20,
                alignItems: 'center',
    },
                courseTitle: {
                    color: theme.textPrimary,
                fontSize: 14,
                fontWeight: 'bold',
                textAlign: 'center',
                letterSpacing: 0.5,
    },
                forceSubtitle: {
                    color: theme.accent || '#FFD166',
                fontSize: 12,
                fontWeight: 'bold',
                marginTop: 4,
                letterSpacing: 1,
    },
                content: {
                    padding: 16,
    },
                activeCard: {
                    backgroundColor: theme.card,
                borderRadius: 12,
                padding: 24,
                marginBottom: 24,
                borderLeftWidth: 4,
                borderLeftColor: theme.accent || '#FFD166',
                shadowColor: "#000",
                shadowOffset: {width: 0, height: 2 },
                shadowOpacity: 0.3,
                shadowRadius: 4,
                elevation: 5,
    },
                statusRow: {
                    flexDirection: 'row',
                alignItems: 'center',
                marginBottom: 12,
    },
                statusDot: {
                    width: 8,
                height: 8,
                borderRadius: 4,
                backgroundColor: '#4CAF50', // Green for active
                marginRight: 8,
    },
                statusText: {
                    color: theme.textSecondary,
                fontSize: 12,
                fontWeight: 'bold',
                letterSpacing: 0.5,
    },
                moduleName: {
                    color: theme.textSecondary,
                fontSize: 12, // Subdued
                textTransform: 'uppercase',
                marginBottom: 4,
    },
                lessonTitle: {
                    color: theme.textPrimary,
                fontSize: 20,
                fontWeight: 'bold',
                marginBottom: 24,
    },
                ctaButton: {
                    backgroundColor: theme.accent || '#FFD166',
                flexDirection: 'row',
                alignItems: 'center',
                justifyContent: 'center',
                paddingVertical: 14,
                borderRadius: 8,
                gap: 8,
    },
                ctaText: {
                    color: theme.background,
                fontSize: 16,
                fontWeight: 'bold',
                letterSpacing: 0.5,
    },
                statsContainer: {
                    flexDirection: 'row',
                gap: 16,
                marginBottom: 24,
    },
                // ...
                instructorBlock: {
                    flexDirection: 'row',
                alignItems: 'center',
                backgroundColor: theme.card,
                marginHorizontal: 16,
                padding: 12,
                borderRadius: 50,
                gap: 12,
                alignSelf: 'center',
                marginBottom: 20,
                paddingRight: 24,
                borderWidth: 1,
                borderColor: 'rgba(255,255,255,0.05)'
    },
                instructorAvatar: {
                    width: 40,
                height: 40,
                borderRadius: 20,
                backgroundColor: '#000',
    },
                instructorLabel: {
                    color: theme.textSecondary,
                fontSize: 10,
                fontWeight: 'bold',
                textTransform: 'uppercase',
    },
                instructorName: {
                    color: theme.textPrimary,
                fontSize: 12,
                fontWeight: 'bold',
    },
                statBox: {
                    flex: 1,
                backgroundColor: theme.card,
                padding: 16,
                borderRadius: 8,
                alignItems: 'center',
    },
                statValue: {
                    color: theme.textPrimary,
                fontSize: 24,
                fontWeight: 'bold',
                marginBottom: 4,
    },
                statLabel: {
                    color: theme.textSecondary,
                fontSize: 10,
                fontWeight: 'bold',
                letterSpacing: 0.5,
    },
                disclaimer: {
                    opacity: 0.6,
                color: theme.textSecondary,
                fontSize: 12,
                textAlign: 'center',
    }
});
