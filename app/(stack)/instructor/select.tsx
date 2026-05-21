// RCC-0.5 / Wave 2 — Seletor 3D de Instrutor (Deck Empilhado)
// Layout: 1 card central flutuante na frente + 2 cards atrás/embaixo.
// Gesto: swipe horizontal → card de trás sobe para frente, central desce.
// Sem ScrollView. Sem duplicação de array. Apenas 3 cards reais.
// Persistência: rpc_update_instructor_profile(p_instructor_profile_id=slug).

import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Animated,
  ActivityIndicator,
  Dimensions,
  GestureResponderHandlers,
  Image,
  InteractionManager,
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
// Mapeado por slug canônico (ramos/rocha/sara). Um único asset por instrutor.
// Fonte canônica para o deck — qualquer outro require de card deve referenciar
// este mapa, não duplicar o path.
//
// NOTE:
// ramos-card-selected.png possui margem interna no próprio canvas.
// Qualquer gap visual deve ser corrigido no asset export,
// não no layout do carousel.
const CARD_ASSETS = {
  ramos: require('../../../assets/instructors/cards/ramos-card-selected.png'),
  rocha: require('../../../assets/instructors/cards/rocha-card-selected.png'),
  sara:  require('../../../assets/instructors/cards/sara-card-selected.png'),
} as const;

// ── Tipos compartilhados ─────────────────────────────────────────────────────
type UxState  = 'idle' | 'saving' | 'error';
type DragDir  = 'left' | 'right' | null;
type CardRole = 'left' | 'center' | 'right';

// ── InstructorInfoPanel ───────────────────────────────────────────────────────
// React.memo: re-renderiza SOMENTE quando displayedInstructor muda (após InteractionManager).
// Completamente isolado do deck — atualização de texto não dispara repaint nos cards.
type InfoPanelProps = {
  instructor: { titulo?: string | null; nome?: string | null; descricao?: string | null } | null;
};
const InstructorInfoPanel = React.memo(function InstructorInfoPanel({ instructor }: InfoPanelProps) {
  return (
    <View style={styles.labelArea}>
      <Text style={[typographyPresets.label, { color: tatico.colors.accent }]} numberOfLines={1}>
        {instructor?.titulo ?? ''}
      </Text>
      <Text
        style={[typographyPresets.sectionTitle, { color: tatico.colors.text, marginTop: 2 }]}
        numberOfLines={1}
      >
        {instructor?.nome ?? ''}
      </Text>
      {instructor?.descricao ? (
        <Text
          style={[typographyPresets.bodySmall, { color: tatico.colors.textSecondary, marginTop: 4 }]}
          numberOfLines={2}
          ellipsizeMode="tail"
        >
          {instructor.descricao}
        </Text>
      ) : null}
    </View>
  );
});

// ── InstructorDeckMemo ────────────────────────────────────────────────────────
// React.memo: re-renderiza SOMENTE quando visualCenterIndex ou dragDir muda.
// NÃO recebe titulo, nome, descricao — zero acoplamento com dados textuais.
// Interpolações criadas internamente via useMemo (swipeX é ref estável → executam uma vez).
// Cada card instructor tem key={slug} fixo → nunca remontado, source nunca muda.
type DeckInstructor = { slug: string };
type DeckMemoProps = {
  instructors: DeckInstructor[];
  N: number;
  visualCenterIndex: number;
  swipeX: Animated.Value;
  dragDir: DragDir;
  panHandlers: GestureResponderHandlers;
};
const InstructorDeckMemo = React.memo(function InstructorDeck({
  instructors,
  N,
  visualCenterIndex,
  swipeX,
  dragDir,
  panHandlers,
}: DeckMemoProps) {
  // Interpolações: criadas uma única vez (swipeX nunca muda de referência).
  const centerTransX = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [-B_X, 0, B_X],        extrapolate: 'clamp' }), [swipeX]);
  const centerTransY = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [B_Y, 0, B_Y],          extrapolate: 'clamp' }), [swipeX]);
  const centerScale  = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [B_SCALE, 1.0, B_SCALE], extrapolate: 'clamp' }), [swipeX]);
  const centerOpacity= useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [B_OPACITY, 1.0, B_OPACITY], extrapolate: 'clamp' }), [swipeX]);
  const centerRotate = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: ['-4deg', '0deg', '4deg'], extrapolate: 'clamp' }), [swipeX]);

  const rightTransX  = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [0, B_X, B_X],           extrapolate: 'clamp' }), [swipeX]);
  const rightTransY  = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [0, B_Y, B_Y],           extrapolate: 'clamp' }), [swipeX]);
  const rightScale   = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [1.0, B_SCALE, B_SCALE],  extrapolate: 'clamp' }), [swipeX]);
  const rightOpacity = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [1.0, B_OPACITY, B_OPACITY], extrapolate: 'clamp' }), [swipeX]);
  const rightRotate  = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: ['0deg', '4deg', '4deg'], extrapolate: 'clamp' }), [swipeX]);

  const leftTransX   = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [-B_X, -B_X, 0],         extrapolate: 'clamp' }), [swipeX]);
  const leftTransY   = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [B_Y, B_Y, 0],           extrapolate: 'clamp' }), [swipeX]);
  const leftScale    = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [B_SCALE, B_SCALE, 1.0],  extrapolate: 'clamp' }), [swipeX]);
  const leftOpacity  = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: [B_OPACITY, B_OPACITY, 1.0], extrapolate: 'clamp' }), [swipeX]);
  const leftRotate   = useMemo(() => swipeX.interpolate({ inputRange: [-TRANSITION_PX, 0, TRANSITION_PX], outputRange: ['-4deg', '-4deg', '0deg'], extrapolate: 'clamp' }), [swipeX]);

  function slotZIndex(role: CardRole): number {
    if (dragDir === 'left')  return role === 'right'  ? 30 : role === 'center' ? 20 : 10;
    if (dragDir === 'right') return role === 'left'   ? 30 : role === 'center' ? 20 : 10;
    return role === 'center' ? 30 : 10;
  }

  return (
    <View style={styles.deckArea} {...panHandlers}>
      {instructors.map((instructor, i) => {
        const asset = CARD_ASSETS[instructor.slug as keyof typeof CARD_ASSETS];
        if (!asset) return null;

        const role: CardRole =
          i === visualCenterIndex
            ? 'center'
            : i === (visualCenterIndex - 1 + N) % N
            ? 'left'
            : 'right';

        const transX = role === 'center' ? centerTransX : role === 'left' ? leftTransX  : rightTransX;
        const transY = role === 'center' ? centerTransY : role === 'left' ? leftTransY  : rightTransY;
        const sc     = role === 'center' ? centerScale  : role === 'left' ? leftScale   : rightScale;
        const op     = role === 'center' ? centerOpacity: role === 'left' ? leftOpacity : rightOpacity;
        const rot    = role === 'center' ? centerRotate : role === 'left' ? leftRotate  : rightRotate;

        return (
          <Animated.View
            key={instructor.slug}
            style={[
              styles.card,
              {
                zIndex: slotZIndex(role),
                transform: [
                  { translateX: transX },
                  { translateY: transY },
                  { scale: sc },
                  { rotate: rot },
                ],
                opacity: op,
              },
            ]}
          >
            <Image
              source={asset}
              style={{ width: POSTER_WIDTH, height: POSTER_HEIGHT }}
              resizeMode="contain"
              fadeDuration={0}
            />
          </Animated.View>
        );
      })}
    </View>
  );
});

// ── Screen ───────────────────────────────────────────────────────────────────

export default function SelectInstructorScreen() {
  const router = useRouter();
  const { profile, refetchProfile } = useAuth();
  const { instructors, loading: loadingInstructors, error: loadError } = useInstructors();

  // ── Log de versão — confirma qual arquivo está renderizando ──────────────
  useEffect(() => {
    console.log('[INSTRUCTOR_SELECT_RENDERED]', {
      route: 'app/(stack)/instructor/select.tsx',
      version: 'no-idle-v1',
      POSTER_RATIO: (1122 / 1402).toFixed(4),
    });
  }, []);

  const N = instructors.length;

  const [centerIndex, setCenterIndex] = useState(0);
  const [uxState, setUxState] = useState<UxState>('idle');
  const [errorMsg, setErrorMsg] = useState('');
  // dragDir controla zIndex durante gesto: qual card está subindo
  const [dragDir, setDragDir] = useState<DragDir>(null);
  // displayedInstructor: fonte exclusiva de título/nome/descrição.
  // Atualizado com InteractionManager.runAfterInteractions após a animação —
  // garante que o re-render de texto não coincide com nenhum frame do deck.
  const [displayedInstructor, setDisplayedInstructor] = useState<InfoPanelProps['instructor']>(null);

  // selectedSlug sempre derivado do centerIndex — sem estado separado
  const selectedSlug = instructors[centerIndex]?.slug ?? null;

  const NRef = useRef(N);
  useEffect(() => { NRef.current = N; }, [N]);

  // Refs para leitura síncrona dentro dos callbacks do PanResponder
  // (evita closures stale sem criar novos PanResponders a cada render).
  const centerIndexRef = useRef(centerIndex);
  useEffect(() => { centerIndexRef.current = centerIndex; }, [centerIndex]);
  const instructorsRef = useRef(instructors);
  useEffect(() => { instructorsRef.current = instructors; }, [instructors]);

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
    setDisplayedInstructor(instructors[currentIdx] ?? null);

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
            const newIdx = (centerIndexRef.current + 1) % NRef.current;
            // 1. Atualiza deck imediatamente (geometry only — InstructorDeckMemo re-renderiza).
            setCenterIndex(newIdx);
            dragDirRef.current = null;
            setDragDir(null);
            swipeX.setValue(0);
            // 2. Atualiza texto depois que todas as interações/animações terminaram.
            //    InstructorInfoPanel re-renderiza em isolamento — o deck já está quieto.
            InteractionManager.runAfterInteractions(() => {
              setDisplayedInstructor(instructorsRef.current[newIdx] ?? null);
            });
          });
        } else if (goPrev && NRef.current > 1) {
          springTo(TRANSITION_PX, () => {
            const newIdx = (centerIndexRef.current - 1 + NRef.current) % NRef.current;
            setCenterIndex(newIdx);
            dragDirRef.current = null;
            setDragDir(null);
            swipeX.setValue(0);
            InteractionManager.runAfterInteractions(() => {
              setDisplayedInstructor(instructorsRef.current[newIdx] ?? null);
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

    try {
      const { data: rpcData, error: rpcError } = await supabase.rpc(
        'rpc_update_instructor_profile',
        rpcPayload,
      );

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

      router.replace('/(tabs)/chat');
    } catch (err: any) {
      const msg = err?.message ?? String(err);
      setErrorMsg(msg || 'Erro inesperado.');
      setUxState('error');
    }
  }

  // ── Derivações de render ──────────────────────────────────────────────────
  const isSaving = uxState === 'saving';

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

      {/* ── Deck 3D ── */}
      {!loadingInstructors && N > 0 && (
        <>
          {/* Painel de texto — isolado do deck via React.memo + InteractionManager */}
          <InstructorInfoPanel instructor={displayedInstructor} />

          {/* Deck de cards físicos — isolado do texto via React.memo */}
          <InstructorDeckMemo
            instructors={instructors}
            N={N}
            visualCenterIndex={centerIndex}
            swipeX={swipeX}
            dragDir={dragDir}
            panHandlers={panResponder.panHandlers}
          />

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
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: radius.l,
    borderWidth: 1,
    // Cor única em todos os slots — sem troca de borda durante swipe (elimina flash)
    borderColor: 'transparent',
    overflow: 'hidden',
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
