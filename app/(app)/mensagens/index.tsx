import { View, Text, FlatList, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { useInstructorMessages } from '../../../src/hooks/useInstructorMessages';
import { InstructorMessageCard } from '../../../src/components/cards/InstructorMessageCard';
import { InstitutionalLoading } from '../../../src/components/InstitutionalLoading';
import { InstitutionalEmpty } from '../../../src/components/InstitutionalEmpty';

export default function MensagensInstrutorScreen() {
    const { theme } = useForceTheme();
    const router = useRouter();
    const { messages, loading, markAsRead } = useInstructorMessages();

    if (loading) {
        return <InstitutionalLoading />;
    }

    if (!messages || messages.length === 0) {
        return (
            <View style={[styles.container, { backgroundColor: theme.background }]}>
                <Text style={[styles.header, { color: theme.primary }]}>
                    Mensagens do Instrutor
                </Text>
                <InstitutionalEmpty text="Nenhum registro disponível no momento." />
            </View>
        );
    }

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            <Text style={[styles.header, { color: theme.primary }]}>
                Mensagens do Instrutor
            </Text>

            <FlatList
                data={messages}
                keyExtractor={(item) => item.message_id}
                contentContainerStyle={styles.list}
                renderItem={({ item }) => (
                    <InstructorMessageCard
                        title={item.title}
                        body={item.body}
                        date={item.created_at}
                        unread={!item.is_read}
                        onOpen={async () => {
                            if (!item.is_read) {
                                await markAsRead(item.message_id);
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
