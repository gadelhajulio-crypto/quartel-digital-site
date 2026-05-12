import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useForceTheme } from '../../context/ForceThemeContext';

interface DailyProgressProps {
    progress: number; // 0 to 100
}

export function DailyProgress({ progress }: DailyProgressProps) {
    const { theme } = useForceTheme();

    return (
        <View style={styles.container}>
            <View style={styles.header}>
                <Text style={[styles.label, { color: theme.dashboard.textSecondary }]}>
                    Progresso geral
                </Text>
                <Text style={[styles.percent, { color: theme.dashboard.textPrimary }]}>
                    {progress}%
                </Text>
            </View>

            <View style={[styles.track, { backgroundColor: theme.dashboard.border }]}>
                <View
                    style={[
                        styles.fill,
                        {
                            width: `${progress}%`,
                            backgroundColor: theme.dashboard.accent
                        }
                    ]}
                />
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        marginHorizontal: 20,
        marginBottom: 24,
    },
    header: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: 8,
    },
    label: {
        fontSize: 14,
        fontWeight: '500',
    },
    percent: {
        fontSize: 14,
        fontWeight: '700',
    },
    track: {
        height: 6,
        borderRadius: 3,
        overflow: 'hidden',
    },
    fill: {
        height: '100%',
        borderRadius: 3,
    }
});
