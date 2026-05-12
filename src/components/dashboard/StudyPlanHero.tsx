import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useForceTheme } from '../../context/ForceThemeContext';
import { Ionicons } from '@expo/vector-icons';

interface StudyPlanHeroProps {
    moduleName: string;
    lessonName: string;
    onPress: () => void;
}

export function StudyPlanHero({ moduleName, lessonName, onPress }: StudyPlanHeroProps) {
    const { theme } = useForceTheme();

    return (
        <TouchableOpacity
            style={[styles.card, { backgroundColor: theme.dashboard.card, shadowColor: theme.dashboard.textPrimary }]}
            onPress={onPress}
            activeOpacity={0.9}
        >
            <View style={styles.content}>
                <View style={[styles.iconContainer, { backgroundColor: theme.dashboard.background }]}>
                    <Ionicons name="play" size={24} color={theme.dashboard.accent} />
                </View>

                <View style={styles.textContainer}>
                    <Text style={[styles.label, { color: theme.dashboard.textSecondary }]}>
                        PLANO DE ESTUDOS
                    </Text>
                    <Text style={[styles.actionText, { color: theme.dashboard.textPrimary }]}>
                        Continuar estudando
                    </Text>
                    <Text style={[styles.lessonInfo, { color: theme.dashboard.textSecondary }]}>
                        {moduleName} • {lessonName}
                    </Text>
                </View>

                <Ionicons name="chevron-forward" size={20} color={theme.dashboard.textSecondary} />
            </View>
        </TouchableOpacity>
    );
}

const styles = StyleSheet.create({
    card: {
        marginHorizontal: 20,
        padding: 20,
        borderRadius: 16,
        marginBottom: 16,
        elevation: 2, // Android shadow
        shadowOffset: { width: 0, height: 4 },
        shadowOpacity: 0.05,
        shadowRadius: 8,
    },
    content: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    iconContainer: {
        width: 48,
        height: 48,
        borderRadius: 24,
        alignItems: 'center',
        justifyContent: 'center',
        marginRight: 16,
    },
    textContainer: {
        flex: 1,
    },
    label: {
        fontSize: 12,
        fontWeight: '600',
        textTransform: 'uppercase',
        letterSpacing: 1,
        marginBottom: 4,
    },
    actionText: {
        fontSize: 18,
        fontWeight: '700',
        marginBottom: 4,
    },
    lessonInfo: {
        fontSize: 14,
    }
});
