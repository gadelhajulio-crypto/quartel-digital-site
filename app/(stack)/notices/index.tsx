import { View, Text, FlatList, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { useInstitutionalNotices } from '../../../src/hooks/useInstitutionalNotices';
import { NoticeCard } from '../../../src/components/cards/NoticeCard';
import { InstitutionalLoading } from '../../../src/components/InstitutionalLoading';
import { InstitutionalEmpty } from '../../../src/components/InstitutionalEmpty';

export default function AvisosScreen() {
    const { theme } = useForceTheme();
    const router = useRouter();
    const { notices, loading, markAsRead } = useInstitutionalNotices();

    if (loading) {
        return <InstitutionalLoading />;
    }

    if (!notices || notices.length === 0) {
        return (
            <View style={[styles.container, { backgroundColor: theme.background }]}>
                <Text style={[styles.header, { color: theme.textPrimary }]}>
                    Avisos Institucionais
                </Text>
                <InstitutionalEmpty text="Nenhum aviso institucional no momento." />
            </View>
        );
    }

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Header institucional */}
            <Text style={[styles.header, { color: theme.textPrimary }]}>
                Avisos Institucionais
            </Text>

            <FlatList
                data={notices}
                keyExtractor={(item) => item.notice_id}
                contentContainerStyle={styles.list}
                renderItem={({ item }) => (
                    <NoticeCard
                        title={item.title}
                        body={item.body}
                        date={item.created_at}
                        unread={!item.is_read}
                        onOpen={async () => {
                            if (!item.is_read) {
                                await markAsRead(item.notice_id);
                            }

                            if (item.deep_link) {
                                router.push(item.deep_link);
                            }
                        }}
                    />
                )}
            />
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        padding: 16,
    },
    header: {
        fontSize: 20,
        fontWeight: '600',
        marginBottom: 16,
    },
    list: {
        gap: 12,
    },
});
