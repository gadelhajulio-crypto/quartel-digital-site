import { View, FlatList, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useInstitutionalNotices } from '../../src/hooks/useInstitutionalNotices';
import { NoticeCard } from '../../src/components/cards/NoticeCard';
import { InstitutionalLoading } from '../../src/components/InstitutionalLoading';
import { InstitutionalEmpty } from '../../src/components/InstitutionalEmpty';
import { TacticalScreen } from '../../src/design/layout/TacticalScreen';
import { InstitutionalHeader } from '../../src/design/components/InstitutionalHeader';
import { tatico } from '../../src/design/themes/tatico';
import { spacing } from '../../src/design/tokens/spacing';

export default function AvisosScreen() {
  const router = useRouter();
  const { notices, loading, markAsRead } = useInstitutionalNotices();

  if (loading) {
    return <InstitutionalLoading />;
  }

  return (
    <TacticalScreen>
      <InstitutionalHeader title="Comunicados" theme={tatico} />

      {!notices || notices.length === 0 ? (
        <View style={styles.empty}>
          <InstitutionalEmpty text="Nenhum comunicado institucional no momento." />
        </View>
      ) : (
        <FlatList
          data={notices}
          keyExtractor={(item) => item.notice_id}
          contentContainerStyle={styles.list}
          showsVerticalScrollIndicator={false}
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
