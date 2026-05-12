import { View, FlatList, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useInstructorMessages } from '../../src/hooks/useInstructorMessages';
import { InstructorMessageCard } from '../../src/components/cards/InstructorMessageCard';
import { InstitutionalLoading } from '../../src/components/InstitutionalLoading';
import { InstitutionalEmpty } from '../../src/components/InstitutionalEmpty';
import { TacticalScreen } from '../../src/design/layout/TacticalScreen';
import { InstitutionalHeader } from '../../src/design/components/InstitutionalHeader';
import { tatico } from '../../src/design/themes/tatico';
import { spacing } from '../../src/design/tokens/spacing';

export default function MensagensInstrutorScreen() {
  const router = useRouter();
  const { messages, loading, markAsRead } = useInstructorMessages();

  if (loading) {
    return <InstitutionalLoading />;
  }

  return (
    <TacticalScreen>
      <InstitutionalHeader title="Mensagens do instrutor" theme={tatico} />

      {!messages || messages.length === 0 ? (
        <View style={styles.empty}>
          <InstitutionalEmpty text="Nenhuma mensagem disponível no momento." />
        </View>
      ) : (
        <FlatList
          data={messages}
          keyExtractor={(item) => item.message_id}
          contentContainerStyle={styles.list}
          showsVerticalScrollIndicator={false}
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
      )}
    </TacticalScreen>
  );
}

const styles = StyleSheet.create({
  empty: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  list: {
    padding: spacing.m,
    paddingBottom: 120,
    gap: spacing.s,
  },
});
