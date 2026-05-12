// RCC-0.5 — Timeline Institucional de Histórico
// Linha temporal vertical com agrupamento por dia.

import React from 'react';
import { View, Text, StyleSheet, SectionList } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { dossie } from '../../design/themes/dossie';
import { typographyPresets } from '../../design/tokens/typography';
import { spacing } from '../../design/tokens/spacing';
import { radius } from '../../design/tokens/radius';
import type { StudentHistoryItem } from '../../hooks/useStudentHistory';
import {
  mapEventType,
  sanitizeTitle,
  sanitizeDescription,
} from '../../utils/institutionalEventMapper';

// ── Configuração visual por tipo de evento ─────────────────────────────────────

type EventConfig = { icon: keyof typeof Ionicons.glyphMap; color: string };

const EVENT_CONFIG: Record<string, EventConfig> = {
  lesson:  { icon: 'book-outline',               color: '#1a6498' },
  review:  { icon: 'refresh-circle-outline',     color: '#5570a8' },
  xp:      { icon: 'trending-up-outline',        color: dossie.colors.success },
  medal:   { icon: 'ribbon-outline',             color: '#8a5c00' },
  system:  { icon: 'information-circle-outline', color: dossie.colors.muted },
  module:  { icon: 'layers-outline',             color: dossie.colors.accent },
};

const DEFAULT_CONFIG: EventConfig = { icon: 'ellipse-outline', color: dossie.colors.muted };

function getConfig(eventType: string): EventConfig {
  return EVENT_CONFIG[eventType] ?? DEFAULT_CONFIG;
}

// ── Agrupamento por dia ────────────────────────────────────────────────────────

type DaySection = { title: string; data: StudentHistoryItem[] };

const MONTHS_PT = ['JAN','FEV','MAR','ABR','MAI','JUN','JUL','AGO','SET','OUT','NOV','DEZ'];

function formatDayHeader(isoDate: string): string {
  const today = new Date();
  const todayIso = today.toISOString().slice(0, 10);
  const yesterdayIso = new Date(today.getTime() - 86_400_000).toISOString().slice(0, 10);

  const d = new Date(isoDate + 'T12:00:00');
  const dd = String(d.getDate()).padStart(2, '0');
  const mon = MONTHS_PT[d.getMonth()];
  const yr = d.getFullYear();

  if (isoDate === todayIso)      return `HOJE  ·  ${dd} ${mon}`;
  if (isoDate === yesterdayIso)  return `ONTEM  ·  ${dd} ${mon}`;
  return `${dd} ${mon} ${yr}`;
}

function groupByDay(items: StudentHistoryItem[]): DaySection[] {
  const map = new Map<string, StudentHistoryItem[]>();
  for (const item of items) {
    const key = item.created_at.slice(0, 10);
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(item);
  }
  return Array.from(map.entries())
    .sort(([a], [b]) => b.localeCompare(a))
    .map(([isoDate, data]) => ({ title: formatDayHeader(isoDate), data }));
}

// ── Item de timeline ───────────────────────────────────────────────────────────

function TimelineItem({
  item,
  isLast,
}: {
  item: StudentHistoryItem;
  isLast: boolean;
}) {
  const cfg = getConfig(item.event_type);
  const time = new Date(item.created_at).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  });
  const title = sanitizeTitle(item.title);
  const description = sanitizeDescription(item.description);

  return (
    <View style={itemStyles.row}>
      {/* Spine: ponto de evento + linha de conexão */}
      <View style={itemStyles.spine}>
        <View
          style={[
            itemStyles.dot,
            { borderColor: cfg.color, backgroundColor: dossie.colors.background },
          ]}
        >
          <Ionicons name={cfg.icon} size={11} color={cfg.color} />
        </View>
        {!isLast && (
          <View style={[itemStyles.line, { backgroundColor: dossie.colors.border }]} />
        )}
      </View>

      {/* Conteúdo do evento */}
      <View
        style={[
          itemStyles.card,
          {
            backgroundColor: dossie.colors.card,
            borderColor: dossie.colors.border,
          },
        ]}
      >
        <View style={itemStyles.cardTop}>
          <Text
            style={[
              typographyPresets.label,
              { color: cfg.color, letterSpacing: 1 },
            ]}
          >
            {mapEventType(item.event_type)}
          </Text>
          <Text style={[typographyPresets.label, { color: dossie.colors.muted }]}>
            {time}
          </Text>
        </View>
        <Text
          style={[typographyPresets.body, { color: dossie.colors.text, fontWeight: '600' }]}
          numberOfLines={2}
        >
          {title}
        </Text>
        {!!description && (
          <Text
            style={[
              typographyPresets.bodySmall,
              { color: dossie.colors.textSecondary, marginTop: 2 },
            ]}
            numberOfLines={3}
          >
            {description}
          </Text>
        )}
      </View>
    </View>
  );
}

// ── Cabeçalho de dia ───────────────────────────────────────────────────────────

function DayHeader({ title }: { title: string }) {
  return (
    <View style={dayStyles.row}>
      <View style={[dayStyles.line, { backgroundColor: dossie.colors.border }]} />
      <Text
        style={[
          typographyPresets.label,
          { color: dossie.colors.muted, letterSpacing: 1.5 },
        ]}
      >
        {title}
      </Text>
      <View style={[dayStyles.line, { backgroundColor: dossie.colors.border }]} />
    </View>
  );
}

// ── Componente principal ───────────────────────────────────────────────────────

export function HistoryTimeline({ items }: { items: StudentHistoryItem[] }) {
  const sections = groupByDay(items);

  return (
    <SectionList
      sections={sections}
      keyExtractor={(item) => item.history_id}
      showsVerticalScrollIndicator={false}
      stickySectionHeadersEnabled={false}
      contentContainerStyle={listStyles.content}
      renderSectionHeader={({ section }) => <DayHeader title={section.title} />}
      renderItem={({ item, index, section }) => (
        <TimelineItem item={item} isLast={index === section.data.length - 1} />
      )}
    />
  );
}

// ── Estilos ────────────────────────────────────────────────────────────────────

const SPINE_WIDTH = 32;
const DOT_SIZE = 24;

const itemStyles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    minHeight: 48,
  },
  spine: {
    width: SPINE_WIDTH,
    alignItems: 'center',
  },
  dot: {
    width: DOT_SIZE,
    height: DOT_SIZE,
    borderRadius: DOT_SIZE / 2,
    borderWidth: 1.5,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 1,
  },
  line: {
    flex: 1,
    width: 1.5,
    marginVertical: 2,
  },
  card: {
    flex: 1,
    marginLeft: spacing.s,
    marginBottom: spacing.s,
    padding: spacing.m,
    borderRadius: radius.m,
    borderWidth: 1,
  },
  cardTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 4,
  },
});

const dayStyles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.m,
    gap: spacing.s,
  },
  line: {
    flex: 1,
    height: 1,
  },
});

const listStyles = StyleSheet.create({
  content: {
    paddingTop: spacing.s,
    paddingHorizontal: spacing.m,
    paddingBottom: 120,
  },
});
