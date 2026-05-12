import React from 'react';
import { View, Text, FlatList, ActivityIndicator, StyleSheet } from 'react-native';
import { useRankingList, RankingItem } from '../../src/hooks/useRankingList';
import { useAuth } from '../../src/context/AuthContext';
import { TacticalScreen } from '../../src/design/layout/TacticalScreen';
import { InstitutionalHeader } from '../../src/design/components/InstitutionalHeader';
import { InstitutionalCard } from '../../src/design/components/InstitutionalCard';
import { InstitutionalBadge } from '../../src/design/components/InstitutionalBadge';
import { InstitutionalEmpty } from '../../src/components/InstitutionalEmpty';
import { tatico } from '../../src/design/themes/tatico';
import { typographyPresets } from '../../src/design/tokens/typography';
import { spacing } from '../../src/design/tokens/spacing';

export default function RankingScreen() {
  const { session, profile } = useAuth();
  const userId = session?.user?.id;
  const userForce = profile?.forca || 'marinha';
  const { rankingList, loading } = useRankingList(userForce);

  if (loading) {
    return (
      <TacticalScreen>
        <View style={styles.center}>
          <ActivityIndicator size="large" color={tatico.colors.accent} />
        </View>
      </TacticalScreen>
    );
  }

  const renderItem = ({ item, index }: { item: RankingItem; index: number }) => {
    const isCurrentUser = item.user_id === userId;
    const name = item.war_name || item.full_name || 'Recruta';
    const isTop3 = index < 3;

    return (
      <InstitutionalCard
        theme={tatico}
        accent={isCurrentUser}
        style={[styles.item, { marginBottom: spacing.s }]}
      >
        <View style={styles.itemRow}>
          <View style={styles.rankCol}>
            <Text
              style={[
                typographyPresets.cardTitle,
                {
                  color: isTop3 ? tatico.colors.accent : tatico.colors.muted,
                  minWidth: 32,
                  textAlign: 'center',
                },
              ]}
            >
              {index + 1}º
            </Text>
          </View>

          <View style={styles.nameCol}>
            <Text
              style={[
                typographyPresets.cardTitle,
                { color: tatico.colors.text },
              ]}
              numberOfLines={1}
            >
              {name}
            </Text>
            {isCurrentUser && (
              <InstitutionalBadge
                theme={tatico}
                label="Você"
                variant="accent"
                style={{ marginTop: 3 }}
              />
            )}
          </View>

          <Text
            style={[
              typographyPresets.cardTitle,
              { color: isCurrentUser ? tatico.colors.accent : tatico.colors.textSecondary },
            ]}
          >
            {item.xp_mensal} XP
          </Text>
        </View>
      </InstitutionalCard>
    );
  };

  return (
    <TacticalScreen>
      <InstitutionalHeader title="Ranking mensal" theme={tatico} />

      <FlatList
        data={rankingList}
        renderItem={renderItem}
        keyExtractor={(item) => item.user_id}
        contentContainerStyle={styles.list}
        showsVerticalScrollIndicator={false}
        ListEmptyComponent={
          <InstitutionalEmpty text="O ranking completo estará disponível em breve." />
        }
        ListFooterComponent={
          <Text style={[typographyPresets.label, styles.footer]}>
            Atualizado automaticamente · Top 50 da Força
          </Text>
        }
      />
    </TacticalScreen>
  );
}

const styles = StyleSheet.create({
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  list: {
    padding: spacing.m,
    paddingBottom: 120,
  },
  item: {
    paddingVertical: spacing.s,
  },
  itemRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.m,
  },
  rankCol: {
    width: 36,
    alignItems: 'center',
  },
  nameCol: {
    flex: 1,
  },
  footer: {
    color: tatico.colors.muted,
    textAlign: 'center',
    marginTop: spacing.m,
    marginBottom: spacing.l,
  },
});
