import { View, Text, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useForceTheme } from '../../context/ForceThemeContext';

interface HistoryRowProps {
    type: 'lesson' | 'review' | 'xp' | 'medal' | 'system';
    title: string;
    description: string;
    date: string;
}

const iconMap: Record<HistoryRowProps['type'], keyof typeof Ionicons.glyphMap> = {
    lesson: 'book-outline',
    review: 'refresh-outline',
    xp: 'stats-chart-outline',
    medal: 'ribbon-outline',
    system: 'information-circle-outline',
};

export function HistoryRow({
    type,
    title,
    description,
    date,
}: HistoryRowProps) {
    const { theme } = useForceTheme();

    return (
        <View
            style={[
                styles.row,
                {
                    backgroundColor: theme.card,
                    borderColor: theme.border,
                },
            ]}
        >
            <Ionicons
                name={iconMap[type]}
                size={20}
                color={theme.primary}
                style={styles.icon}
            />

            <View style={styles.content}>
                <Text style={[styles.title, { color: theme.text }]}>
                    {title}
                </Text>

                <Text style={[styles.description, { color: theme.muted }]}>
                    {description}
                </Text>

                <Text style={[styles.date, { color: theme.muted }]}>
                    {new Date(date).toLocaleString()}
                </Text>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    row: {
        flexDirection: 'row',
        padding: 14,
        borderRadius: 8,
        borderWidth: 1,
    },
    icon: {
        marginRight: 12,
        marginTop: 2,
    },
    content: {
        flex: 1,
    },
    title: {
        fontSize: 15,
        fontWeight: '600',
        marginBottom: 4,
    },
    description: {
        fontSize: 14,
        marginBottom: 6,
    },
    date: {
        fontSize: 12,
        textAlign: 'right',
    },
});
