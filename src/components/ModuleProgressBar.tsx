import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { theme } from '../theme';

type Props = {
    completed: number;
    total: number;
};

export function ModuleProgressBar({ completed, total }: Props) {
    const percentage = total === 0 ? 0 : completed / total;

    return (
        <View style={styles.container}>
            <Text style={styles.text}>
                PROGRESSO DO MÓDULO: {completed}/{total}
            </Text>

            <View style={styles.track}>
                <View
                    style={[
                        styles.fill,
                        {
                            width: `${percentage * 100}%`,
                            backgroundColor: percentage === 1 ? theme.colors.success : theme.colors.gold, // Green if done, Gold otherwise
                        },
                    ]}
                />
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        marginBottom: 16,
        paddingHorizontal: 4,
    },
    text: {
        marginBottom: 8,
        color: theme.colors.textSecondary,
        fontSize: 12,
        fontWeight: 'bold',
        textTransform: 'uppercase',
        letterSpacing: 1,
    },
    track: {
        height: 8,
        backgroundColor: '#333', // Dark track
        borderRadius: 4,
        overflow: 'hidden',
    },
    fill: {
        height: '100%',
        borderRadius: 4,
    }
});
