import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useForceTheme } from '../../context/ForceThemeContext';

interface NoticeCardProps {
    title: string;
    body: string;
    date: string;
    unread: boolean;
    onOpen: () => void;
}

export function NoticeCard({
    title,
    body,
    date,
    unread,
    onOpen,
    variant = 'default'
}: NoticeCardProps & { variant?: 'default' | 'dashboard' }) {
    const { theme } = useForceTheme();

    const isDashboard = variant === 'dashboard';
    const bgColor = isDashboard ? theme.dashboard.card : theme.card;
    const textColor = isDashboard ? theme.dashboard.textPrimary : theme.textPrimary;
    const mutedColor = isDashboard ? theme.dashboard.textSecondary : theme.textMuted;
    const borderColor = isDashboard ? theme.dashboard.border : (unread ? theme.primary : theme.border);
    const shadowStyle = isDashboard ? {
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.05,
        shadowRadius: 4,
        elevation: 2,
        borderWidth: 0,
    } : { borderWidth: 1 };

    return (
        <TouchableOpacity
            onPress={onOpen}
            style={[
                styles.card,
                {
                    backgroundColor: bgColor,
                    borderColor: borderColor,
                },
                shadowStyle
            ]}
        >
            <View style={styles.header}>
                <Text style={[styles.title, { color: textColor, flex: 1 }]}>
                    {title}
                </Text>
                {unread && !isDashboard && (
                    <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: theme.primary }} />
                )}
            </View>

            <Text style={[styles.body, { color: mutedColor }]}>
                {body}
            </Text>

            <Text style={[styles.date, { color: mutedColor }]}>
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
    header: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        marginBottom: 6,
    },
    title: {
        fontSize: 16,
        fontWeight: '600',
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
