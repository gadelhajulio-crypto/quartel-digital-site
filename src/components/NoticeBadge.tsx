import { TouchableOpacity, View, Text, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useForceTheme } from '../context/ForceThemeContext';

interface NoticeBadgeProps {
    unreadCount: number;
}

export function NoticeBadge({ unreadCount }: NoticeBadgeProps) {
    const { theme } = useForceTheme();
    const router = useRouter();

    if (!unreadCount || unreadCount <= 0) {
        return null;
    }

    return (
        <TouchableOpacity
            onPress={() => router.push('/avisos')}
            style={styles.wrapper}
            accessibilityLabel="Avisos institucionais não lidos"
        >
            <View
                style={[
                    styles.badge,
                    {
                        backgroundColor: theme.primary,
                    },
                ]}
            >
                {unreadCount > 9 ? (
                    <Text style={styles.text}>9+</Text>
                ) : (
                    <Text style={styles.text}>{unreadCount}</Text>
                )}
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
