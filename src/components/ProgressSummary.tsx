import { View, Text, StyleSheet } from 'react-native';
import { useForceTheme } from '../context/ForceThemeContext';

interface ProgressSummaryProps {
    progressPercent: number; // valor pronto (0–100)
    label?: string; // opcional: ex. "Progresso do Curso"
}

export function ProgressSummary({
    progressPercent,
    label = 'Progresso do Curso',
}: ProgressSummaryProps) {
    const { theme } = useForceTheme();

    return (
        <View
            style={[
                styles.container,
                {
                    backgroundColor: theme.card,
                    borderColor: theme.border,
                },
            ]}
        >
            <Text style={[styles.label, { color: theme.muted }]}>
                {label}
            </Text>

            <View
                style={[
                    styles.progressTrack,
                    { backgroundColor: theme.border },
                ]}
            >
                <View
                    style={[
                        styles.progressFill,
                        {
                            width: `${progressPercent}%`,
                            backgroundColor: theme.primary,
                        },
                    ]}
                />
            </View>

            <Text style={[styles.percent, { color: theme.text }]}>
                {progressPercent}% concluído
            </Text>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        padding: 16,
        borderRadius: 8,
        borderWidth: 1,
    },
    label: {
        fontSize: 13,
        marginBottom: 8,
    },
    progressTrack: {
        height: 8,
        borderRadius: 4,
        overflow: 'hidden',
        marginBottom: 8,
    },
    progressFill: {
        height: 8,
        borderRadius: 4,
    },
    percent: {
        fontSize: 14,
        fontWeight: '500',
        textAlign: 'right',
    },
});
