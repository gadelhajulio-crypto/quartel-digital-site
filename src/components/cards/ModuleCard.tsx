import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useForceTheme } from '../../context/ForceThemeContext';

interface ModuleCardProps {
    moduleName: string;
    totalLessons: number;
    completedLessons: number;
    progressPercent: number;
    onPress: () => void;
}

export function ModuleCard({
    moduleName,
    totalLessons,
    completedLessons,
    progressPercent,
    onPress,
}: ModuleCardProps) {
    const { theme } = useForceTheme();

    return (
        <TouchableOpacity
            onPress={onPress}
            style={[
                styles.card,
                {
                    backgroundColor: theme.card,
                    borderColor: theme.border,
                },
            ]}
        >
            <Text style={[styles.title, { color: theme.text }]}>
                {moduleName}
            </Text>

            <Text style={[styles.subtitle, { color: theme.muted }]}>
                {completedLessons} de {totalLessons} aulas concluídas
            </Text>

            {/* Barra de progresso simples */}
            <View style={[styles.progressTrack, { backgroundColor: theme.border }]}>
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

            <Text style={[styles.percent, { color: theme.muted }]}>
                {progressPercent}%
            </Text>
        </TouchableOpacity>
    );
}

const styles = StyleSheet.create({
    card: {
        padding: 16,
        borderRadius: 8,
        borderWidth: 1,
    },
    title: {
        fontSize: 16,
        fontWeight: '600',
        marginBottom: 4,
    },
    subtitle: {
        fontSize: 13,
        marginBottom: 8,
    },
    progressTrack: {
        height: 6,
        borderRadius: 3,
        overflow: 'hidden',
        marginBottom: 6,
    },
    progressFill: {
        height: 6,
        borderRadius: 3,
    },
    percent: {
        fontSize: 12,
        textAlign: 'right',
    },
});
