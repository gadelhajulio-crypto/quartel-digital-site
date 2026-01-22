import { TouchableOpacity, View, Text, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useForceTheme } from '../context/ForceThemeContext';

interface InstructorMessageBadgeProps {
    unreadCount: number;
}

export function InstructorMessageBadge({ unreadCount }: InstructorMessageBadgeProps) {
    const { theme } = useForceTheme();
    const router = useRouter();

    if (!unreadCount || unreadCount <= 0) {
        return null;
    }

    return (
        <TouchableOpacity
            onPress={() => router.push('/mensagens')}
            style={styles.wrapper}
            accessibilityLabel="Mensagens do instrutor não lidas"
        >
            <View
                style={[
                    styles.badge,
                    { backgroundColor: theme.primary },
                ]}
            >
                <Text style={styles.text}>
                    {unreadCount > 9 ? '9+' : unreadCount}
                </Text>
            </View>
        </TouchableOpacity>
    );
}

const styles = StyleSheet.create({
    wrapper: {
        alignSelf: 'flex-end',
    },
    badge: {
        minWidth: 18,
        height: 18,
        borderRadius: 9,
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: 4,
    },
    text: {
        color: '#FFF',
        fontSize: 11,
        fontWeight: '600',
    },
});
