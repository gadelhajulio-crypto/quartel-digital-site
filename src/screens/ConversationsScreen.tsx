// RCC Wave 2d — Lista Institucional de Conversas
// Fonte única: v_chat_conversas_recruta via loadConversas().
// Frontend renderiza. Banco é verdade.
// Sem realtime, sem subscriptions, sem polling automático.

import React, { useState, useCallback, useEffect, memo } from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  RefreshControl,
  Image,
  Platform,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '../context/AuthContext';
import { loadConversas, type ChatConversa } from '../services/chatService';
import { useInstructors } from '../hooks/useInstructors';
import { InstitutionalHeader } from '../design/components/InstitutionalHeader';
import { tatico } from '../design/themes/tatico';
import { typographyPresets } from '../design/tokens/typography';
import { spacing } from '../design/tokens/spacing';
import { radius } from '../design/tokens/radius';

// Avatares locais: fallback garantido para todos os instrutores canônicos
const LOCAL_AVATARS: Record<string, any> = {
  ramos: require('../../assets/instructors/avatars/ramos-avatar-circle.png'),
  rocha: require('../../assets/instructors/avatars/rocha-avatar-circle.png'),
  sara:  require('../../assets/instructors/avatars/sara-avatar-circle.png'),
};

// ── Tempo relativo ────────────────────────────────────────────────────────────

function relativeTime(isoString: string | null): string {
  if (!isoString) return '—';
  const diff = Date.now() - new Date(isoString).getTime();
  const minutes = Math.floor(diff / 60_000);
  if (minutes < 1)  return 'agora';
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24)   return `${hours}h`;
  const days = Math.floor(hours / 24);
  if (days < 30)    return `${days}d`;
  return new Date(isoString).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' });
}

// ── Preview institucional ─────────────────────────────────────────────────────

function formatPreview(role: 'user' | 'assistant' | null, preview: string | null): string {
  if (!preview) return 'Nenhum registro textual disponível.';
  const text = preview.trim();
  if (!text) return 'Nenhum registro textual disponível.';
  if (role === 'user')      return `Você: ${text}`;
  if (role === 'assistant') return `Instrutor: ${text}`;
  return text;
}

// ── Card de conversa ──────────────────────────────────────────────────────────

type CardProps = {
  conversa: ChatConversa;
  avatarSource: any;
  glowColor: string;
  onPress: () => void;
};

const ConversationCard = memo(function ConversationCard({
  conversa,
  avatarSource,
  glowColor,
  onPress,
}: CardProps) {
  const hasUnread = conversa.has_unread;

  return (
    <TouchableOpacity
      style={[
        cardStyles.root,
        {
          backgroundColor: tatico.colors.card,
          borderColor: hasUnread ? glowColor : tatico.colors.border,
          borderLeftColor: glowColor,
        },
      ]}
      onPress={onPress}
      activeOpacity={0.75}
    >
      {/* Avatar */}
      <View
        style={[
          cardStyles.avatarWrapper,
          {
            borderColor: hasUnread ? glowColor : tatico.colors.border,
          },
        ]}
      >
        {avatarSource && (
          <Image source={avatarSource} style={cardStyles.avatar} resizeMode="cover" />
        )}
        {hasUnread && (
          <View
            style={[
              cardStyles.unreadDot,
              { backgroundColor: glowColor, borderColor: tatico.colors.card },
            ]}
          />
        )}
      </View>

      {/* Conteúdo */}
      <View style={cardStyles.content}>
        <View style={cardStyles.topRow}>
          <Text
            style={[
              typographyPresets.label,
              cardStyles.instructorName,
              { color: hasUnread ? tatico.colors.text : tatico.colors.muted },
            ]}
            numberOfLines={1}
          >
            {conversa.instrutor_nome}
          </Text>
          <Text style={[typographyPresets.label, { color: tatico.colors.muted }]}>
            {relativeTime(conversa.last_message_at)}
          </Text>
        </View>

        <View style={cardStyles.bottomRow}>
          <Text
            style={[
              typographyPresets.label,
              cardStyles.preview,
              { color: hasUnread ? tatico.colors.text : tatico.colors.muted },
            ]}
            numberOfLines={1}
            ellipsizeMode="tail"
          >
            {formatPreview(conversa.last_message_role, conversa.last_message_preview)}
          </Text>

          {conversa.unread_count > 0 && (
            <View
              style={[
                cardStyles.badge,
                { backgroundColor: tatico.colors.accent, borderColor: tatico.colors.card },
              ]}
            >
              <Text style={cardStyles.badgeText}>
                {conversa.unread_count > 9 ? '9+' : String(conversa.unread_count)}
              </Text>
            </View>
          )}
        </View>
      </View>
    </TouchableOpacity>
  );
});

// ── Tela principal ────────────────────────────────────────────────────────────

export default function ConversationsScreen() {
  const router = useRouter();
  const { profile } = useAuth();
  const { instructors } = useInstructors();

  const forca = profile?.forca ?? 'marinha';
  const FORCE_GLOW: Record<string, string> = {
    marinha:     '#4FC3F7',
    exercito:    '#81C784',
    aeronautica: '#FFD54F',
  };
  const glowColor = FORCE_GLOW[forca] ?? '#4FC3F7';

  const [conversas, setConversas] = useState<ChatConversa[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Mapa codigo → instrutor (para resolver avatar via slug visual)
  const instructorByCode = React.useMemo(() => {
    const map: Record<string, typeof instructors[0]> = {};
    instructors.forEach((i) => { map[i.codigo] = i; });
    return map;
  }, [instructors]);

  const fetchConversas = useCallback(async (isRefresh = false) => {
    if (isRefresh) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }
    setError(null);
    try {
      const data = await loadConversas();
      setConversas(data);
      console.log('[CHAT_LIST_W2]', isRefresh ? 'conversations_refresh' : 'conversations_loaded', {
        count: data.length,
      });
      console.log('[CHAT_LIST_W3] preview_loaded', {
        with_preview: data.filter((c) => !!c.last_message_preview).length,
      });
    } catch {
      setError('Falha ao carregar registros institucionais.');
      console.warn('[CHAT_LIST_W2] conversations_error');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    fetchConversas(false);
  }, [fetchConversas]);

  function handleBack() {
    if (router.canGoBack()) {
      router.back();
    } else {
      router.replace('/');
    }
  }

  function openChat() {
    router.push('/(tabs)/chat' as any);
  }

  function resolveAvatar(instrutor_slug: string) {
    const instructor = instructorByCode[instrutor_slug];
    const localKey = instructor?.slug ?? null;
    if (localKey && LOCAL_AVATARS[localKey]) return LOCAL_AVATARS[localKey];
    if (instructor?.avatar_url) return { uri: instructor.avatar_url };
    return null;
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <View style={[styles.root, { backgroundColor: tatico.colors.background }]}>
      <InstitutionalHeader
        theme={tatico}
        title="Conversas"
        subtitle="Canal institucional"
        onBack={handleBack}
        style={styles.header}
      />

      {loading ? (
        <View style={styles.center}>
          <ActivityIndicator color={glowColor} />
          <Text style={[typographyPresets.label, styles.stateText, { color: tatico.colors.muted }]}>
            Sincronizando conversas institucionais…
          </Text>
        </View>
      ) : error ? (
        <View style={styles.center}>
          <Text style={[typographyPresets.label, styles.stateText, { color: tatico.colors.muted }]}>
            {error}
          </Text>
          <TouchableOpacity
            style={[styles.ctaBtn, { backgroundColor: tatico.colors.accent }]}
            onPress={() => fetchConversas(false)}
            activeOpacity={0.8}
          >
            <Text style={[typographyPresets.label, styles.ctaBtnText]}>
              TENTAR NOVAMENTE
            </Text>
          </TouchableOpacity>
        </View>
      ) : conversas.length === 0 ? (
        <View style={styles.center}>
          <Text style={[typographyPresets.label, styles.stateText, { color: tatico.colors.muted }]}>
            Nenhuma conversa operacional encontrada.
          </Text>
          <TouchableOpacity
            style={[styles.ctaBtn, { backgroundColor: tatico.colors.accent }]}
            onPress={openChat}
            activeOpacity={0.8}
          >
            <Text style={[typographyPresets.label, styles.ctaBtnText]}>
              INICIAR CANAL
            </Text>
          </TouchableOpacity>
        </View>
      ) : (
        <FlatList
          data={conversas}
          keyExtractor={(item) => item.conversa_id}
          renderItem={({ item }) => (
            <ConversationCard
              conversa={item}
              avatarSource={resolveAvatar(item.instrutor_slug)}
              glowColor={glowColor}
              onPress={openChat}
            />
          )}
          contentContainerStyle={styles.listContent}
          showsVerticalScrollIndicator={false}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={() => fetchConversas(true)}
              tintColor={glowColor}
              colors={[glowColor]}
            />
          }
          ItemSeparatorComponent={() => <View style={styles.separator} />}
        />
      )}
    </View>
  );
}

// ── Estilos ───────────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  root: { flex: 1 },
  header: { paddingTop: Platform.OS === 'ios' ? 52 : 16 },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.l,
    gap: spacing.m,
  },
  stateText: {
    letterSpacing: 1,
    textAlign: 'center',
  },
  ctaBtn: {
    marginTop: spacing.s,
    paddingVertical: 12,
    paddingHorizontal: spacing.l,
    borderRadius: radius.s,
    alignItems: 'center',
  },
  ctaBtnText: {
    color: tatico.colors.background,
    letterSpacing: 1,
  },
  listContent: {
    padding: spacing.m,
    paddingBottom: spacing.xl ?? 40,
  },
  separator: {
    height: spacing.s,
  },
});

const cardStyles = StyleSheet.create({
  root: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: spacing.m,
    borderRadius: radius.m,
    borderWidth: 1,
    borderLeftWidth: 3,
    gap: spacing.m,
  },
  avatarWrapper: {
    width: 52,
    height: 52,
    borderRadius: 26,
    borderWidth: 1.5,
    overflow: 'visible',
  },
  avatar: {
    width: 52,
    height: 52,
    borderRadius: 26,
  },
  unreadDot: {
    position: 'absolute',
    bottom: 1,
    right: 1,
    width: 10,
    height: 10,
    borderRadius: 5,
    borderWidth: 1.5,
  },
  content: {
    flex: 1,
    gap: spacing.xs,
  },
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  instructorName: {
    flex: 1,
    letterSpacing: 1,
    marginRight: spacing.s,
  },
  bottomRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  preview: {
    flex: 1,
    letterSpacing: 0.3,
    marginRight: spacing.s,
  },
  badge: {
    minWidth: 18,
    height: 18,
    borderRadius: 9,
    borderWidth: 1.5,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  badgeText: {
    color: '#FFFFFF',
    fontSize: 9,
    fontWeight: '700',
    lineHeight: 12,
  },
});
