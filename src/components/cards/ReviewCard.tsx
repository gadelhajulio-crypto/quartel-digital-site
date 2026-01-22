import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useForceTheme } from '../../context/ForceThemeContext';

type ReviewType = 'audio' | 'video';
type ReviewStatus = 'available' | 'blocked';

interface ReviewCardProps {
    lessonTitle: string;
    type: ReviewType;
    status: ReviewStatus;
    onPress: () => void;
}

export function ReviewCard({
    lessonTitle,
    type,
    status,
    onPress,
}: ReviewCardProps) {
    const { theme } = useForceTheme();

    const isBlocked = status === 'blocked';

    const iconName =
        type === 'audio' ? 'headset' : 'videocam';

    const statusColor =
        status === 'available' ? theme.primary : theme.muted;

    return (
        <TouchableOpacity
            onPress={onPress}
            disabled={isBlocked}
            style={[
                styles.card,
                {
                    backgroundColor: theme.card,
                    borderColor: theme.border,
                    opacity: isBlocked ? 0.6 : 1,
                },
            ]}
        >
            <Ionicons
                name={iconName}
                size={22}
                color={statusColor}
                style={styles.icon}
            />

            <View style={styles.content}>
                <Text style={[styles.lesson, { color: theme.text }]}>
                    {lessonTitle}
                </Text>

                <Text style={[styles.meta, { color: theme.muted }]}>
                    Revisão em {type === 'audio' ? 'Áudio' : 'Vídeo'}
                </Text>
            </View>

            <Ionicons
                name={isBlocked ? 'lock-closed' : 'play-circle'}
                size={22}
                color={statusColor}
            />
        </TouchableOpacity>
    );
}

const styles = StyleSheet.create({
    card: {
        flexDirection: 'row',
        alignItems: 'center',
        padding: 14,
        borderRadius: 8,
        borderWidth: 1,
    },
    icon: {
        marginRight: 12,
    },
    content: {
        flex: 1,
    },
    lesson: {
        fontSize: 15,
        fontWeight: '500',
    },
    meta: {
        fontSize: 13,
        marginTop: 2,
    },
});
