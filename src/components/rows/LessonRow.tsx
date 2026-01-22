import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useForceTheme } from '../../context/ForceThemeContext';

export type LessonStatus = 'blocked' | 'available' | 'completed';

interface LessonRowProps {
    order: number;
    title: string;
    status: LessonStatus;
    onPress: () => void;
}

export function LessonRow({
    order,
    title,
    status,
    onPress,
}: LessonRowProps) {
    const { theme } = useForceTheme();

    const isBlocked = status === 'blocked';

    const iconName =
        status === 'completed'
            ? 'checkmark-circle'
            : status === 'available'
                ? 'play-circle'
                : 'lock-closed';

    const iconColor =
        status === 'completed'
            ? theme.success
            : status === 'available'
                ? theme.primary
                : theme.muted;

    return (
        <TouchableOpacity
            onPress={onPress}
            disabled={isBlocked}
            style={[
                styles.row,
                {
                    backgroundColor: theme.card,
                    borderColor: theme.border,
                    opacity: isBlocked ? 0.6 : 1,
                },
            ]}
        >
            <Text style={[styles.order, { color: theme.muted }]}>
                {order}.
            </Text>

            <View style={styles.content}>
                <Text style={[styles.title, { color: theme.text }]}>
                    {title}
                </Text>
            </View>

            <Ionicons name={iconName} size={22} color={iconColor} />
        </TouchableOpacity>
    );
}

const styles = StyleSheet.create({
    row: {
        flexDirection: 'row',
        alignItems: 'center',
        padding: 12,
        borderRadius: 6,
        borderWidth: 1,
    },
    order: {
        width: 28,
        fontSize: 14,
        textAlign: 'right',
        marginRight: 8,
    },
    content: {
        flex: 1,
    },
    title: {
        fontSize: 15,
    },
});
