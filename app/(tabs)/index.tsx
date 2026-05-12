import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  StatusBar,
} from 'react-native';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../../src/context/AuthContext';
import { RadarLoading } from '../../src/components/RadarLoading';
import { TacticalScreen } from '../../src/design/layout/TacticalScreen';
import { InstitutionalCard } from '../../src/design/components/InstitutionalCard';
import { InstitutionalButton } from '../../src/design/components/InstitutionalButton';
import { InstitutionalBadge } from '../../src/design/components/InstitutionalBadge';
import { InstitutionalSection } from '../../src/design/components/InstitutionalSection';
import { tatico } from '../../src/design/themes/tatico';
import { typographyPresets } from '../../src/design/tokens/typography';

export default function PainelScreen() {
  const router = useRouter();
  const { profile } = useAuth();
  const [loading, setLoading] = useState(true);

  // Mock Data — substituir pelos hooks RCC quando disponíveis
  const currentModule = 'Módulo 01';
  const currentLesson = 'Introdução à Hierarquia';
  const revisionsCount = 2;
  const progress = 42;

  const notices = [
    {
      id: 1,
      title: 'Atualização do Regulamento',
      body: 'O R-105 sofreu alterações...',
      date: '2026-01-20',
      unread: true,
    },
  ];

  useEffect(() => {
    const t = setTimeout(() => setLoading(false), 300);
    return () => clearTimeout(t);
  }, []);

  const hours = new Date().getHours();
  const period = hours < 12 ? 'Bom dia' : hours < 18 ? 'Boa tarde' : 'Boa noite';
  const displayName =
    profile?.nome_guerra ||
    (profile as any)?.nome?.split(' ')[0] ||
    'Recruta';

  if (loading) {
    return (
      <View style={[styles.loadingContainer, { backgroundColor: tatico.colors.background }]}>
        <RadarLoading color={tatico.colors.accent} />
      </View>
    );
  }

  return (
    <TacticalScreen scrollable contentStyle={styles.content}>
      <StatusBar barStyle="light-content" backgroundColor="transparent" translucent />

      {/* ── CABEÇALHO ── */}
      <View style={styles.header}>
        <View>
          <Text style={[typographyPresets.label, { color: tatico.colors.muted }]}>
            {period},
          </Text>
          <Text style={[typographyPresets.sectionTitle, { color: tatico.colors.text }]}>
            {displayName}
          </Text>
        </View>
        <InstitutionalBadge
          theme={tatico}
          label="Quartel Digital"
          variant="accent"
        />
      </View>

      {/* ── PLANO DE ESTUDOS ── */}
      <InstitutionalSection
        title="Plano de estudos"
        theme={tatico}
        titleRight={
          <InstitutionalBadge theme={tatico} label="Ativo" variant="success" />
        }
      >
        <TouchableOpacity
          activeOpacity={0.85}
          onPress={() => router.push('/(stack)/module/1')}
        >
          <InstitutionalCard theme={tatico} elevated accent>
            <View style={styles.studyRow}>
              <View
                style={[
                  styles.playIcon,
                  { backgroundColor: tatico.colors.accentSoft },
                ]}
              >
                <Ionicons name="play" size={22} color={tatico.colors.accent} />
              </View>
              <View style={styles.studyInfo}>
                <Text style={[typographyPresets.label, { color: tatico.colors.muted }]}>
                  Continuar estudando
                </Text>
                <Text
                  style={[typographyPresets.cardTitle, { color: tatico.colors.text, marginTop: 3 }]}
                >
                  {currentLesson}
                </Text>
                <Text
                  style={[
                    typographyPresets.bodySmall,
                    { color: tatico.colors.textSecondary, marginTop: 2 },
                  ]}
                >
                  {currentModule}
                </Text>
              </View>
              <Ionicons
                name="chevron-forward"
                size={18}
                color={tatico.colors.muted}
              />
            </View>

            {/* Barra de progresso */}
            <View
              style={[styles.progressTrack, { backgroundColor: tatico.colors.border }]}
            >
              <View
                style={[
                  styles.progressFill,
                  {
                    width: `${progress}%`,
                    backgroundColor: tatico.colors.accent,
                  },
                ]}
              />
            </View>
            <Text
              style={[
                typographyPresets.label,
                { color: tatico.colors.muted, marginTop: 6 },
              ]}
            >
              {progress}% concluído
            </Text>
          </InstitutionalCard>
        </TouchableOpacity>
      </InstitutionalSection>

      {/* ── COMUNICADOS ── */}
      <InstitutionalSection
        title="Comunicados"
        theme={tatico}
        titleRight={
          <TouchableOpacity onPress={() => router.push('/(tabs)/notices')}>
            <Text
              style={[typographyPresets.label, { color: tatico.colors.accent }]}
            >
              Ver todos
            </Text>
          </TouchableOpacity>
        }
      >
        {notices.map((notice) => (
          <TouchableOpacity
            key={notice.id}
            activeOpacity={0.85}
            onPress={() => router.push('/(tabs)/notices')}
          >
            <InstitutionalCard
              theme={tatico}
              style={styles.noticeCard}
              accent={notice.unread}
            >
              <View style={styles.noticeRow}>
                <View style={styles.noticeText}>
                  <Text
                    style={[
                      typographyPresets.cardTitle,
                      { color: tatico.colors.text },
                    ]}
                  >
                    {notice.title}
                  </Text>
                  <Text
                    style={[
                      typographyPresets.bodySmall,
                      { color: tatico.colors.textSecondary, marginTop: 4 },
                    ]}
                    numberOfLines={2}
                  >
                    {notice.body}
                  </Text>
                </View>
                {notice.unread && (
                  <InstitutionalBadge
                    theme={tatico}
                    label="Novo"
                    variant="accent"
                  />
                )}
              </View>
            </InstitutionalCard>
          </TouchableOpacity>
        ))}
      </InstitutionalSection>

      {/* ── ACESSO RÁPIDO ── */}
      <InstitutionalSection title="Acesso rápido" theme={tatico}>
        <View style={styles.quickRow}>
          <TouchableOpacity
            style={styles.quickItem}
            activeOpacity={0.85}
            onPress={() => router.push('/(tabs)/modules')}
          >
            <InstitutionalCard theme={tatico} style={styles.quickCard}>
              <Ionicons name="grid-outline" size={24} color={tatico.colors.accent} />
              <Text
                style={[
                  typographyPresets.label,
                  { color: tatico.colors.textSecondary, marginTop: 8 },
                ]}
              >
                Módulos
              </Text>
            </InstitutionalCard>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.quickItem}
            activeOpacity={0.85}
            onPress={() => router.push('/(tabs)/reviews')}
          >
            <InstitutionalCard theme={tatico} style={styles.quickCard}>
              <View style={styles.reviewIconWrapper}>
                <Ionicons name="book-outline" size={24} color={tatico.colors.accent} />
                {revisionsCount > 0 && (
                  <View
                    style={[
                      styles.reviewDot,
                      { backgroundColor: tatico.colors.accent },
                    ]}
                  />
                )}
              </View>
              <Text
                style={[
                  typographyPresets.label,
                  { color: tatico.colors.textSecondary, marginTop: 8 },
                ]}
              >
                Revisões
              </Text>
              {revisionsCount > 0 && (
                <Text
                  style={[
                    typographyPresets.bodySmall,
                    { color: tatico.colors.accent, marginTop: 2 },
                  ]}
                >
                  {revisionsCount} novas
                </Text>
              )}
            </InstitutionalCard>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.quickItem}
            activeOpacity={0.85}
            onPress={() => router.push('/(tabs)/ranking')}
          >
            <InstitutionalCard theme={tatico} style={styles.quickCard}>
              <Ionicons name="trophy-outline" size={24} color={tatico.colors.accent} />
              <Text
                style={[
                  typographyPresets.label,
                  { color: tatico.colors.textSecondary, marginTop: 8 },
                ]}
              >
                Ranking
              </Text>
            </InstitutionalCard>
          </TouchableOpacity>
        </View>
      </InstitutionalSection>

      {/* Padding para BottomBar */}
      <View style={{ height: 100 }} />
    </TacticalScreen>
  );
}

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    paddingTop: 56,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    marginBottom: 28,
  },
  studyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    marginBottom: 14,
  },
  playIcon: {
    width: 48,
    height: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
  studyInfo: {
    flex: 1,
  },
  progressTrack: {
    height: 4,
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 2,
  },
  noticeCard: {
    marginBottom: 8,
  },
  noticeRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
  },
  noticeText: {
    flex: 1,
  },
  quickRow: {
    flexDirection: 'row',
    gap: 10,
  },
  quickItem: {
    flex: 1,
  },
  quickCard: {
    alignItems: 'center',
    paddingVertical: 18,
  },
  reviewIconWrapper: {
    position: 'relative',
  },
  reviewDot: {
    position: 'absolute',
    top: -2,
    right: -4,
    width: 8,
    height: 8,
    borderRadius: 4,
  },
});
