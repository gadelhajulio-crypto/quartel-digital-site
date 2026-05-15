// RCC-0.5 / Wave 2 — Seletor 3D de Instrutor (Deck Empilhado)
// Layout: 1 card central flutuante na frente + 2 cards idle atrás/embaixo.
// Gesto: swipe horizontal → card de trás sobe para frente, central desce.
// Sem ScrollView. Sem duplicação de array. Apenas 3 cards reais.
// Persistência: rpc_update_instructor_profile(p_instructor_profile_id=slug).

import React, { useEffect, useRef, useState } from 'react';
import {
  Animated,
  ActivityIndicator,
  Dimensions,
  Image,
  PanResponder,
  Platform,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useRouter } from 'expo-router';
import { supabase } from '../../../src/lib/supabase';
import { useAuth } from '../../../src/context/AuthContext';
import { useInstructors, reloadInstructors } from '../../../src/hooks/useInstructors';
import { InstitutionalHeader } from '../../../src/design/components/InstitutionalHeader';
import { InstitutionalButton } from '../../../src/design/components/InstitutionalButton';
import { InstitutionalBadge } from '../../../src/design/components/InstitutionalBadge';
import { tatico } from '../../../src/design/themes/tatico';
import { typographyPresets } from '../../../src/design/tokens/typography';
import { spacing } from '../../../src/design/tokens/spacing';
import { radius } from '../../../src/design/tokens/radius';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

// ── Geometria do pôster ──────────────────────────────────────────────────────
// POSTER_RATIO medido dos assets reais (1122×1402 px, todos os 6 cards iguais).
// Com ratio exato + resizeMode='stretch', a moldura abraça o pôster sem gap.
const POSTER_RATIO  = 1122 / 1402; // 0.8003
const POSTER_WIDTH  = Math.round(SCREEN_WIDTH * 0.78);
const POSTER_HEIGHT = Math.round(POSTER_WIDTH / POSTER_RATIO);
const POSTER_LEFT   = Math.round((SCREEN_WIDTH - POSTER_WIDTH) / 2);

// ── Parâmetros do deck 3D ────────────────────────────────────────────────────
// B_X/B_Y: deslocamento dos cards de trás em relação ao centro
// B_SCALE: escala dos cards de trás
// B_OPACITY: opacidade dos cards de trás
const B_X = 72;
const B_Y = 78;
const B_SCALE = 0.82;
const B_OPACITY = 0.55;

// ── Parâmetros de gesto ───────────────────────────────────────────────────────
// TRANSITION_PX: distância que swipeX percorre para completar a transição
// SWIPE_THRESHOLD: distância mínima para confirmar swipe
const TRANSITION_PX = SCREEN_WIDTH * 0.46;
const SWIPE_THRESHOLD = SCREEN_WIDTH * 0.18;
const VELOCITY_THRESHOLD = 0.4;

// ── Assets locais (bundled) ───────────────────────────────────────────────────
// require() = imediato, sem rede, sem skeleton infinito.
// Mapeado por slug canônico (ramos/rocha/sara) × variante (selected/idle).
const CARD_ASSETS = {
  ramos: {
    selected: require('../../../assets/instructors/cards/ramos-card-selected.png'),
    idle:     require('../../../assets/instructors/cards/ramos-card-idle.png'),
  },
  rocha: {
    selected: require('../../../assets/instructors/cards/rocha-card-selected.png'),
    idle:     require('../../../assets/instructors/cards/rocha-card-idle.png'),
  },
  sara: {
    selected: require('../../../assets/instructors/cards/sara-card-selected.png'),
    idle:     require('../../../assets/instructors/cards/sara-card-idle.png'),
  },
} as const;

// ── InstructorCardImage ──────────────────────────────────────────────────────
// source={require(...)} — asset local, zero latência de rede.
// Skeleton apenas se slug desconhecido (fallback seguro).
type CardImageProps = {
  slug: string;
  variant: 'idle' | 'selected';
  slot: 'center' | 'left' | 'right';
};

function InstructorCardImage({ slug, variant, slot }: CardImageProps) {
  const assets = CARD_ASSETS[slug as keyof typeof CARD_ASSETS];
  const source = assets ? (variant === 'selected' ? assets.selected : assets.idle) : null;

  // Log apenas quando source mudar (diagnóstico de flash)
  console.log('[INSTRUCTOR_CARD_SOURCE]', { slot, slug, variant, hasSource: !!source });

  if (!source) {
    // Slug desconhecido: loga mas não mostra skeleton durante animação.
    // Nunca deve acontecer em produção (slugs vêm de CARD_ASSETS).
    console.warn('[INSTRUCTOR_CARD_SOURCE] missing asset for slug:', slug);
    return <View style={cardImageStyles.skeleton} />;
  }

  return (
    <Image
      source={source}
      style={cardImageStyles.fill}
      resizeMode="stretch"
      fadeDuration={0}
    />
  );
}

const cardImageStyles = StyleSheet.create({
  fill: { width: '100%', height: '100%' },
  skeleton: { width: '100%', height: '100%', backgroundColor: '#0d1520' },
});

// ── Screen ───────────────────────────────────────────────────────────────────
type UxState = 'idle' | 'saving' | 'error';
type DragDir = 'left' | 'right' | null;

export default function SelectInstructorScreen() {
  const router = useRouter();
  const { profile, refetchProfile } = useAuth();
  const { instructors, loading: loadingInstructors, error: loadError } = useInstructors();

  // ── Log de versão — confirma qual arquivo está renderizando ──────────────
  useEffect(() => {
    console.log('[INSTRUCTOR_SELECT_RENDERED]', {
      route: 'app/(stack)/instructor/select.tsx',
      version: 'final-ratio-fix-v1',
      POSTER_RATIO: (1122 / 1402).toFixed(4),
    });
  }, []);

  const N = instructors.length;

  const [centerIndex, setCenterIndex] = useState(0);
  const [uxState, setUxState] = useState<UxState>('idle');
  const [errorMsg, setErrorMsg] = useState('');
  // dragDir controla zIndex durante gesto: qual card está subindo
  const [dragDir, setDragDir] = useState<DragDir>(null);

  // selectedSlug sempre derivado do centerIndex — sem estado separado
  const selectedSlug = instructors[centerIndex]?.slug ?? null;

  const NRef = useRef(N);
  useEffect(() => { NRef.current = N; }, [N]);

  // swipeX: deslocamento bruto do gesto em pixels, clamped a [-TP, TP]
  // Negativo = swipe para esquerda (próximo), Positivo = swipe para direita (anterior)
  const swipeX = useRef(new Animated.Value(0)).current;
  const isAnimating = useRef(false);
  const initialized = useRef(false);
  const dragDirRef = useRef<DragDir>(null);

  // ── Inicialização: índice do instrutor atual + prefetch ───────────────────
  useEffect(() => {
    if (N === 0 || initialized.current) return;
    initialized.current = true;

    const profileCodigo = profile?.instructor_profile_id ?? '';
    const currentIdx = Math.max(
      0,
      instructors.findIndex((i) => i.codigo === profileCodigo),
    );
    setCenterIndex(currentIdx);

    console.log('[INSTRUCTOR_DECK_INIT]', {
      profileCodigo,
      initialCenterIndex: currentIdx,
      instructorsCount: N,
      slugs: instructors.map((i) => i.slug),
    });

    // Assets de card são locais (require) — sem prefetch necessário.
    // Avatar ainda pode ser remoto; prefetch fire-and-forget para InstructorButton.
    instructors.forEach((inst) => {
      if (inst.avatar_url) Image.prefetch(inst.avatar_url).catch(() => {});
    });
  }, [N]);

  // ── Interpolações 3D ──────────────────────────────────────────────────────
  //
  // swipeX=0          → deck idle (center na frente, back-left/right atrás)
  // swipeX=-TP        → transição completa para esquerda: right sobe ao centro
  // swipeX=+TP        → transição completa para direita: left sobe ao centro
  //
  // CARD CENTRAL: sai para left-back em swipeX=-TP, para right-back em +TP
  const centerTransX = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [-B_X, 0, B_X],
    extrapolate: 'clamp',
  });
  const centerTransY = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [B_Y, 0, B_Y],
    extrapolate: 'clamp',
  });
  const centerScale = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [B_SCALE, 1.0, B_SCALE],
    extrapolate: 'clamp',
  });
  const centerOpacity = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [B_OPACITY, 1.0, B_OPACITY],
    extrapolate: 'clamp',
  });
  const centerRotate = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: ['-4deg', '0deg', '4deg'],
    extrapolate: 'clamp',
  });

  // CARD DIREITO (back-right): sobe ao centro em swipeX=-TP, fica parado em +TP
  const rightTransX = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [0, B_X, B_X],
    extrapolate: 'clamp',
  });
  const rightTransY = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [0, B_Y, B_Y],
    extrapolate: 'clamp',
  });
  const rightScale = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [1.0, B_SCALE, B_SCALE],
    extrapolate: 'clamp',
  });
  const rightOpacity = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [1.0, B_OPACITY, B_OPACITY],
    extrapolate: 'clamp',
  });
  const rightRotate = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: ['0deg', '4deg', '4deg'],
    extrapolate: 'clamp',
  });

  // CARD ESQUERDO (back-left): sobe ao centro em swipeX=+TP, fica parado em -TP
  const leftTransX = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [-B_X, -B_X, 0],
    extrapolate: 'clamp',
  });
  const leftTransY = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [B_Y, B_Y, 0],
    extrapolate: 'clamp',
  });
  const leftScale = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [B_SCALE, B_SCALE, 1.0],
    extrapolate: 'clamp',
  });
  const leftOpacity = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: [B_OPACITY, B_OPACITY, 1.0],
    extrapolate: 'clamp',
  });
  const leftRotate = swipeX.interpolate({
    inputRange: [-TRANSITION_PX, 0, TRANSITION_PX],
    outputRange: ['-4deg', '-4deg', '0deg'],
    extrapolate: 'clamp',
  });

  // ── ZIndex por slot ───────────────────────────────────────────────────────
  // dragDir determina qual card está subindo e precisa ficar acima dos outros.
  // zIndex não é animável — controlado por estado React.
  function slotZIndex(slot: 'center' | 'left' | 'right'): number {
    if (dragDir === 'left') {
      // Swipe esquerda: right sobe
      if (slot === 'right') return 30;
      if (slot === 'center') return 20;
      return 10;
    }
    if (dragDir === 'right') {
      // Swipe direita: left sobe
      if (slot === 'left') return 30;
      if (slot === 'center') return 20;
      return 10;
    }
    // Idle: center no topo
    return slot === 'center' ? 30 : 10;
  }

  // ── PanResponder ──────────────────────────────────────────────────────────
  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => false,
      onMoveShouldSetPanResponder: (_, { dx, dy }) =>
        !isAnimating.current &&
        NRef.current > 1 &&
        Math.abs(dx) > Math.abs(dy) * 1.5 &&
        Math.abs(dx) > 8,

      onPanResponderMove: (_, { dx }) => {
        // Atualiza dragDir apenas quando direção muda (evita re-renders excessivos)
        const dir: DragDir = dx < 0 ? 'left' : 'right';
        if (dragDirRef.current !== dir) {
          dragDirRef.current = dir;
          setDragDir(dir);
        }
        swipeX.setValue(Math.max(-TRANSITION_PX, Math.min(TRANSITION_PX, dx)));
      },

      onPanResponderRelease: (_, { dx, vx }) => {
        const goNext = dx < -SWIPE_THRESHOLD || vx < -VELOCITY_THRESHOLD;
        const goPrev = dx > SWIPE_THRESHOLD || vx > VELOCITY_THRESHOLD;

        function springTo(target: number, onDone?: () => void) {
          isAnimating.current = true;
          Animated.spring(swipeX, {
            toValue: target,
            useNativeDriver: false,
            friction: 6,
            tension: 140,
          }).start(({ finished }) => {
            isAnimating.current = false;
            if (finished) onDone?.();
          });
        }

        if (goNext && NRef.current > 1) {
          springTo(-TRANSITION_PX, () => {
            // setCenterIndex primeiro, depois reset no próximo frame via rAF:
            // permite que React comite o novo índice antes de resetar swipeX,
            // reduzindo o flash do instrutor anterior na posição central.
            setCenterIndex((prev) => (prev + 1) % NRef.current);
            requestAnimationFrame(() => {
              swipeX.setValue(0);
              dragDirRef.current = null;
              setDragDir(null);
            });
          });
        } else if (goPrev && NRef.current > 1) {
          springTo(TRANSITION_PX, () => {
            setCenterIndex((prev) => (prev - 1 + NRef.current) % NRef.current);
            requestAnimationFrame(() => {
              swipeX.setValue(0);
              dragDirRef.current = null;
              setDragDir(null);
            });
          });
        } else {
          springTo(0, () => {
            dragDirRef.current = null;
            setDragDir(null);
          });
        }
      },

      onPanResponderTerminate: () => {
        isAnimating.current = false;
        dragDirRef.current = null;
        setDragDir(null);
        Animated.spring(swipeX, {
          toValue: 0,
          useNativeDriver: false,
          friction: 6,
          tension: 140,
        }).start();
      },
    }),
  ).current;

  // ── Handlers ─────────────────────────────────────────────────────────────
  function handleBack() {
    if (router.canGoBack()) router.back();
    else router.replace('/(tabs)/chat');
  }

  async function handleConfirm() {
    if (!selectedSlug || uxState === 'saving') return;
    setErrorMsg('');
    setUxState('saving');

    const rpcPayload = { p_instructor_profile_id: selectedSlug };
    const selectedInstructor = instructors.find((i) => i.slug === selectedSlug) ?? null;

    // ── [INSTRUCTOR_DEBUG] selected_before_save ───────────────────────────
    console.log('[INSTRUCTOR_DEBUG] selected_before_save', {
      selectedSlug,
      selectedCodigo: selectedInstructor?.codigo ?? null,
      profile_instructor_profile_id: profile?.instructor_profile_id ?? null,
      instructors_slugs: instructors.map((i) => i.slug),
      instructors_codigos: instructors.map((i) => i.codigo),
    });

    // ── [INSTRUCTOR_DEBUG] rpc_payload ────────────────────────────────────
    console.log('[INSTRUCTOR_DEBUG] rpc_payload', rpcPayload);

    try {
      const { data: rpcData, error: rpcError } = await supabase.rpc(
        'rpc_update_instructor_profile',
        rpcPayload,
      );

      // ── [INSTRUCTOR_DEBUG] rpc_response ───────────────────────────────
      console.log('[INSTRUCTOR_DEBUG] rpc_response', {
        data: rpcData,
        error: rpcError
          ? { message: rpcError.message, code: rpcError.code, hint: rpcError.hint }
          : null,
      });

      if (rpcError) {
        setErrorMsg(rpcError.message || 'Erro ao salvar instrutor.');
        setUxState('error');
        return;
      }

      // ── Auditoria: valor real em profiles (antes do refetch) ──────────
      const { data: dbRow, error: dbErr } = await supabase
        .from('profiles')
        .select('instructor_profile_id')
        .maybeSingle();

      const resolvedFromDb = instructors.find(
        (i) =>
          i.codigo === dbRow?.instructor_profile_id ||
          i.slug === dbRow?.instructor_profile_id,
      ) ?? null;

      // ── [INSTRUCTOR_DEBUG] resolved_slug ──────────────────────────────
      console.log('[INSTRUCTOR_DEBUG] resolved_slug', {
        db_raw: dbRow?.instructor_profile_id ?? null,
        db_error: dbErr?.message ?? null,
        resolved_slug: resolvedFromDb?.slug ?? null,
        resolved_codigo: resolvedFromDb?.codigo ?? null,
      });

      // ── Atualiza estado global ────────────────────────────────────────
      await reloadInstructors();
      await refetchProfile();

      // ── Lê v_identidade_recruta pós-refetch (fonte canônica do AuthContext) ─
      const { data: vidRow, error: vidErr } = await supabase
        .from('v_identidade_recruta')
        .select('instructor_profile_id')
        .maybeSingle();

      const resolvedAfterRefetch = instructors.find(
        (i) =>
          i.codigo === vidRow?.instructor_profile_id ||
          i.slug === vidRow?.instructor_profile_id,
      ) ?? null;

      // ── [INSTRUCTOR_DEBUG] profile_after_refetch ─────────────────────
      console.log('[INSTRUCTOR_DEBUG] profile_after_refetch', {
        instructor_profile_id: vidRow?.instructor_profile_id ?? null,
        vid_error: vidErr?.message ?? null,
      });

      // ── [INSTRUCTOR_DEBUG] hydration_source ──────────────────────────
      console.log('[INSTRUCTOR_DEBUG] hydration_source', {
        view: 'v_identidade_recruta',
        join: 'LEFT JOIN profiles ON profiles.id = recrutas.id',
        field: 'profiles.instructor_profile_id',
        note: 'Se LEFT JOIN retornar null, instructor_profile_id será null',
      });

      // ── [INSTRUCTOR_DEBUG] dashboard_instructor ───────────────────────
      // InstructorButton: instructors.find(i => i.codigo === profile.instructor_profile_id)
      console.log('[INSTRUCTOR_DEBUG] dashboard_instructor', {
        lookup_key: vidRow?.instructor_profile_id ?? null,
        resolved_slug: resolvedAfterRefetch?.slug ?? null,
        resolved_nome: resolvedAfterRefetch?.nome ?? null,
        will_show_avatar: resolvedAfterRefetch !== null,
      });

      // ── [INSTRUCTOR_DEBUG] chat_instructor ────────────────────────────
      // ChatScreen: const instructorSlug = profile?.instructor_profile_id ?? 'objetivo'
      // (usa o codigo, não o slug — fallback 'objetivo' = Ramos)
      console.log('[INSTRUCTOR_DEBUG] chat_instructor', {
        instructorSlug_value: vidRow?.instructor_profile_id ?? 'objetivo',
        note: 'ChatScreen usa instructor_profile_id como codigo (não slug)',
      });

      router.replace('/(tabs)/chat');
    } catch (err: any) {
      const msg = err?.message ?? String(err);
      console.warn('[INSTRUCTOR_DEBUG] exception', { message: msg });
      setErrorMsg(msg || 'Erro inesperado.');
      setUxState('error');
    }
  }

  // ── Derivações de render ──────────────────────────────────────────────────
  const isSaving = uxState === 'saving';
  const centerInstructor = instructors[centerIndex] ?? null;
  const leftInstructor = N > 0 ? instructors[(centerIndex - 1 + N) % N] : null;
  const rightInstructor = N > 0 ? instructors[(centerIndex + 1) % N] : null;

  return (
    <View style={[styles.root, { backgroundColor: tatico.colors.background }]}>
      <InstitutionalHeader
        theme={tatico as any}
        title="Selecionar instrutor"
        onBack={handleBack}
        style={styles.header}
      />

      {/* Loading de rede */}
      {loadingInstructors && (
        <View style={styles.centered}>
          <ActivityIndicator color={tatico.colors.accent} size="large" />
        </View>
      )}

      {/* Erro de rede */}
      {loadError && !loadingInstructors && N === 0 && (
        <View style={styles.centered}>
          <InstitutionalBadge
            theme={tatico as any}
            label="Não foi possível carregar os instrutores. Verifique sua conexão."
            variant="error"
          />
        </View>
      )}

      {/* ── Deck 3D ── renderiza imediatamente; skeleton cobre imagens pendentes */}
      {!loadingInstructors && N > 0 && (
        <>
          {/* Identidade do instrutor central */}
          <View style={styles.labelArea}>
            <Text
              style={[typographyPresets.label, { color: tatico.colors.accent }]}
              numberOfLines={1}
            >
              {centerInstructor?.titulo ?? ''}
            </Text>
            <Text
              style={[typographyPresets.sectionTitle, { color: tatico.colors.text, marginTop: 2 }]}
              numberOfLines={1}
            >
              {centerInstructor?.nome ?? ''}
            </Text>
            {centerInstructor?.descricao ? (
              <Text
                style={[
                  typographyPresets.bodySmall,
                  { color: tatico.colors.textSecondary, marginTop: 4 },
                ]}
                numberOfLines={2}
                ellipsizeMode="tail"
              >
                {centerInstructor.descricao}
              </Text>
            ) : null}
          </View>

          {/* Área do deck — captura gestos */}
          <View style={styles.deckArea} {...panResponder.panHandlers}>

            {/* Card esquerdo (back-left, idle) */}
            {leftInstructor && (
              <Animated.View
                style={[
                  styles.card,
                  {
                    borderColor: tatico.colors.border,
                    zIndex: slotZIndex('left'),
                    transform: [
                      { translateX: leftTransX },
                      { translateY: leftTransY },
                      { scale: leftScale },
                      { rotate: leftRotate },
                    ],
                    opacity: leftOpacity,
                  },
                ]}
              >
                <InstructorCardImage
                  key="slot-left"
                  slug={leftInstructor.slug}
                  variant="idle"
                  slot="left"
                />
              </Animated.View>
            )}

            {/* Card direito (back-right, idle) */}
            {rightInstructor && (
              <Animated.View
                style={[
                  styles.card,
                  {
                    borderColor: tatico.colors.border,
                    zIndex: slotZIndex('right'),
                    transform: [
                      { translateX: rightTransX },
                      { translateY: rightTransY },
                      { scale: rightScale },
                      { rotate: rightRotate },
                    ],
                    opacity: rightOpacity,
                  },
                ]}
              >
                <InstructorCardImage
                  key="slot-right"
                  slug={rightInstructor.slug}
                  variant="idle"
                  slot="right"
                />
              </Animated.View>
            )}

            {/* Card central (frente, selected) */}
            {centerInstructor && (
              <Animated.View
                style={[
                  styles.card,
                  {
                    borderColor: tatico.colors.accent,
                    borderWidth: 2,
                    zIndex: slotZIndex('center'),
                    transform: [
                      { translateX: centerTransX },
                      { translateY: centerTransY },
                      { scale: centerScale },
                      { rotate: centerRotate },
                    ],
                    opacity: centerOpacity,
                  },
                ]}
              >
                <InstructorCardImage
                  key="slot-center"
                  slug={centerInstructor.slug}
                  variant="selected"
                  slot="center"
                />
              </Animated.View>
            )}
          </View>

          {/* Dots — exatamente N pontos, refletem o card central */}
          <View style={styles.dots}>
            {instructors.map((_, idx) => (
              <View
                key={idx}
                style={[
                  styles.dot,
                  {
                    backgroundColor:
                      idx === centerIndex ? tatico.colors.accent : tatico.colors.border,
                    width: idx === centerIndex ? 18 : 6,
                  },
                ]}
              />
            ))}
          </View>
        </>
      )}

      {/* Rodapé fixo */}
      <View
        style={[
          styles.footer,
          {
            backgroundColor: tatico.colors.background,
            borderTopColor: tatico.colors.border,
          },
        ]}
      >
        {uxState === 'error' && errorMsg !== '' && (
          <InstitutionalBadge
            theme={tatico as any}
            label={errorMsg}
            variant="error"
            style={styles.errorBadge}
          />
        )}
        <InstitutionalButton
          theme={tatico as any}
          label={isSaving ? 'Salvando...' : 'CONFIRMAR INSTRUTOR'}
          onPress={handleConfirm}
          disabled={!selectedSlug || isSaving || loadingInstructors}
          loading={isSaving}
          size="l"
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  header: {
    paddingTop: Platform.OS === 'ios' ? 52 : 16,
  },
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.m,
  },
  labelArea: {
    alignItems: 'center',
    paddingHorizontal: spacing.l,
    paddingTop: spacing.m,
    paddingBottom: spacing.s,
    height: 108,        // fixo: label + nome + 2 linhas descrição — deck não sobe/desce
    justifyContent: 'center',
    overflow: 'hidden', // garante que texto longo não empurra o deck
  },
  deckArea: {
    // Altura = exatamente o card. Cards de trás transbordam para baixo (overflow visible).
    height: POSTER_HEIGHT,
    alignSelf: 'stretch',
    overflow: 'visible',
  },
  card: {
    position: 'absolute',
    left: POSTER_LEFT,
    top: 0,
    width: POSTER_WIDTH,
    height: POSTER_HEIGHT,
    padding: 0,
    margin: 0,
    borderRadius: radius.l,
    borderWidth: 1,
    overflow: 'hidden',
    // transparent: sem cor sólida visível entre moldura e imagem caso
    // o asset não tenha exatamente POSTER_RATIO (evita "gap colorido").
    backgroundColor: 'transparent',
  },
  dots: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 6,
    paddingVertical: spacing.s,
  },
  dot: {
    height: 6,
    borderRadius: 3,
  },
  footer: {
    paddingHorizontal: spacing.m,
    paddingTop: spacing.m,
    paddingBottom: Platform.OS === 'ios' ? 32 : spacing.m,
    borderTopWidth: 1,
  },
  errorBadge: {
    marginBottom: spacing.s,
  },
});
