import React from 'react';
import { View, Text, ActivityIndicator, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { useMonthlyChampion } from '../../src/hooks/useMonthlyChampion';
import { useAuth } from '../../src/context/AuthContext';
import { TacticalScreen } from '../../src/design/layout/TacticalScreen';
import { InstitutionalCard } from '../../src/design/components/InstitutionalCard';
import { InstitutionalBadge } from '../../src/design/components/InstitutionalBadge';
import { tatico } from '../../src/design/themes/tatico';
import { typographyPresets } from '../../src/design/tokens/typography';
import { spacing } from '../../src/design/tokens/spacing';

export default function ChampionScreen() {
  const { profile } = useAuth();
  const userForce = profile?.forca || 'marinha';
  const { champion, loading } = useMonthlyChampion(userForce);

  const currentMonthName = format(new Date(), 'MMMM', { locale: ptBR }).toUpperCase();
  const name =
    champion?.profiles?.war_name ||
    champion?.profiles?.full_name ||
    champion?.profiles?.name ||
    'Recruta';

  if (loading) {
    return (
      <TacticalScreen>
        <View style={styles.center}>
          <ActivityIndicator size="large" color={tatico.colors.accent} />
        </View>
      </TacticalScreen>
    );
  }

  return (
    <TacticalScreen scrollable contentStyle={styles.content}>
      {/* Troféu */}
      <View style={styles.trophyRow}>
        <Ionicons name="trophy" size={64} color={tatico.colors.accent} />
      </View>

      {/* Mês */}
      <Text style={[typographyPresets.label, styles.month]}>
        {currentMonthName}
      </Text>

      {champion ? (
        <InstitutionalCard theme={tatico} elevated accent style={styles.card}>
          {/* Posição */}
          <Text style={[styles.rankNum, { color: tatico.colors.accent }]}>
            #1
          </Text>

          {/* Nome */}
          <Text style={[typographyPresets.sectionTitle, styles.name, { color: tatico.colors.text }]}>
            {name}
          </Text>

          <View style={[styles.divider, { backgroundColor: tatico.colors.border }]} />

          {/* Força */}
          <InstitutionalBadge
            theme={tatico}
            label={userForce.toUpperCase()}
            variant="muted"
          />
        </InstitutionalCard>
      ) : (
        <Text style={[typographyPresets.body, { color: tatico.colors.muted, textAlign: 'center' }]}>
          Ranking mensal em implantação.
        </Text>
      )}

      <View style={{ height: 120 }} />
    </TacticalScreen>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingTop: spacing.xxl,
    alignItems: 'center',
  },
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  trophyRow: {
    marginBottom: spacing.m,
  },
  month: {
    color: tatico.colors.muted,
    marginBottom: spacing.xl,
    letterSpacing: 3,
  },
  card: {
    width: '100%',
    alignItems: 'center',
    paddingVertical: spacing.xl,
  },
  rankNum: {
    fontSize: 52,
    fontWeight: '700',
    marginBottom: spacing.s,
  },
  name: {
    textAlign: 'center',
    marginBottom: spacing.m,
    textTransform: 'uppercase',
  },
  divider: {
    width: 40,
    height: 1.5,
    marginBottom: spacing.m,
  },
});
