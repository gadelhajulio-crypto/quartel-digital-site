import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useForceTheme } from '../../context/ForceThemeContext';

interface InstructorMessageCardProps {
    title: string;
    body: string;
    date: string;
    unread: boolean;
    onOpen: () => void;
}

export function InstructorMessageCard({
    title,
    body,
    date,
    unread,
    onOpen,
}: InstructorMessageCardProps) {
    const { theme } = useForceTheme();

    return (
        <TouchableOpacity
            onPress={onOpen}
            style={[
                styles.card,
                {
                    backgroundColor: theme.card,
                    borderColor: unread ? theme.primary : theme.border,
                },
            ]}
        >
            <Text style={[styles.title, { color: theme.text }]}>
                {title}
            </Text>

            <Text style={[styles.body, { color: theme.muted }]}>
                {body}
            </Text>

            <Text style={[styles.date, { color: theme.muted }]}>
                {new Date(date).toLocaleDateString()}
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
        marginBottom: 6,
    },
    body: {
        fontSize: 14,
        marginBottom: 10,
    },
    date: {
        fontSize: 12,
        textAlign: 'right',
    },
});
