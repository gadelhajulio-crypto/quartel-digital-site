// RCC Wave 1 — Chat Institucional
// Frontend renderiza. Edge Function orquestra. RPCs governam. Banco é verdade.

import React, { useState, useRef, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  ActivityIndicator,
  Animated,
} from 'react-native';
import * as Crypto from 'expo-crypto';
import { useRouter } from 'expo-router';
import { useAuth } from '../context/AuthContext';
import { useNetworkGuard } from '../hooks/useNetworkGuard';
import {
  sendMessageW1,
  openConversationRpc,
  loadMensagens,
  markReadRpc,
  loadUnreadStatus,
  ChatError,
  type ChatMensagem,
  type ChatPayloadW1,
} from '../services/chatService';
import { FORCE_GLOW, DEFAULT_GLOW } from '../constants/instructors';
import { useInstructors } from '../hooks/useInstructors';
import { InstitutionalHeader } from '../design/components/InstitutionalHeader';
import { InstitutionalInput } from '../design/components/InstitutionalInput';
import { InstitutionalBadge } from '../design/components/InstitutionalBadge';
import { tatico } from '../design/themes/tatico';
import { obsidiana } from '../design/themes/obsidiana';
import { typographyPresets } from '../design/tokens/typography';
import { spacing } from '../design/tokens/spacing';
import { radius } from '../design/tokens/radius';

const BOTTOMBAR_HEIGHT = Platform.OS === 'ios' ? 75 : 66;

// ── Mensagem local (apenas visual — nunca persistida como 'sending') ───────────

type LocalMessage = {
  localId: string;
  text: string;
  client_message_id: string;
  status: 'sending' | 'failed';
  timestamp: Date;
};

// ── Componentes de mensagem ───────────────────────────────────────────────────

function SystemMessage({ text }: { text: string }) {
  return (
    <View style={msgStyles.systemRow}>
      <View style={[msgStyles.systemLine, { backgroundColor: tatico.colors.border }]} />
      <Text style={[typographyPresets.label, msgStyles.systemText]}>{text}</Text>
      <View style={[msgStyles.systemLine, { backgroundColor: tatico.colors.border }]} />
    </View>
  );
}

function RecrutaMessage({
  text,
  timestamp,
  status,
}: {
  text: string;
  timestamp: string | Date;
  status?: 'sending' | 'sent' | 'read' | 'failed';
}) {
  const d = typeof timestamp === 'string' ? new Date(timestamp) : timestamp;
  const timeStr = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

  return (
    <View style={msgStyles.recrutaRow}>
      <View
        style={[
          msgStyles.recrutaBubble,
          {
            backgroundColor: tatico.colors.accentSoft,
            borderColor: tatico.colors.accent,
          },
        ]}
      >
        <Text style={[typographyPresets.body, { color: tatico.colors.text }]}>{text}</Text>
        <Text style={[typographyPresets.label, msgStyles.timestamp]}>
          {timeStr}
          {status === 'sending' && '  ···'}
          {status === 'failed' && '  !'}
        </Text>
      </View>
    </View>
  );
}

function InstrutorMessage({
  text,
  timestamp,
  instructorName,
  glowColor,
  status,
  onRetry,
}: {
  text: string;
  timestamp: string | Date;
  instructorName: string;
  glowColor: string;
  status?: string;
  onRetry?: () => void;
}) {
  const d = typeof timestamp === 'string' ? new Date(timestamp) : timestamp;
  const timeStr = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

  return (
    <View style={msgStyles.instrutorRow}>
      <View
        style={[
          msgStyles.instrutorBubble,
          {
            backgroundColor: tatico.colors.card,
            borderColor: tatico.colors.border,
            borderLeftColor: glowColor,
          },
        ]}
      >
        <Text style={[typographyPresets.label, { color: glowColor, marginBottom: 4 }]}>
          {instructorName}
        </Text>
        <Text style={[typographyPresets.body, { color: tatico.colors.text }]}>{text}</Text>
        <View style={msgStyles.instrutorFooter}>
          <Text style={[typographyPresets.label, { color: tatico.colors.muted }]}>{timeStr}</Text>
          {status === 'failed' && onRetry && (
            <TouchableOpacity onPress={onRetry} style={msgStyles.retryBtn}>
              <Text style={[typographyPresets.label, { color: tatico.colors.accent }]}>
                Tentar novamente
              </Text>
            </TouchableOpacity>
          )}
        </View>
      </View>
    </View>
  );
}

// EmptyConversationState removido — substituído por mensagem inicial do instrutor

function ProcessingIndicator({ glowColor }: { glowColor: string }) {
  const dotOpacity = useRef(new Animated.Value(0.3)).current;

  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(dotOpacity, { toValue: 1, duration: 600, useNativeDriver: true }),
        Animated.timing(dotOpacity, { toValue: 0.3, duration: 600, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [dotOpacity]);

  return (
    <View style={processingStyles.row}>
      <View style={[processingStyles.bar, { backgroundColor: glowColor }]} />
      <Animated.Text
        style={[
          typographyPresets.label,
          processingStyles.text,
          { color: tatico.colors.muted, opacity: dotOpacity },
        ]}
      >
        Processando resposta ···
      </Animated.Text>
    </View>
  );
}

function ChatErrorBanner({ message, onDismiss }: { message: string; onDismiss: () => void }) {
  return (
    <TouchableOpacity
      style={[
        errorBannerStyles.root,
        {
          backgroundColor: obsidiana.colors.error + '22',
          borderBottomColor: obsidiana.colors.error,
        },
      ]}
      onPress={onDismiss}
      activeOpacity={0.8}
    >
      <Text style={[typographyPresets.label, { color: obsidiana.colors.error }]}>{message}</Text>
      <Text style={[typographyPresets.label, { color: obsidiana.colors.error, opacity: 0.7 }]}>
        ✕
      </Text>
    </TouchableOpacity>
  );
}

// ── Gate: perfil incompleto ────────────────────────────────────────────────────

function ChatGateIncompleteProfile({
  reason,
  onAction,
  onBack,
}: {
  reason: 'onboarding' | 'instructor';
  onAction: () => void;
  onBack: () => void;
}) {
  const isOnboarding = reason === 'onboarding';
  return (
    <View style={[gateStyles.root, { backgroundColor: tatico.colors.background }]}>
      <InstitutionalHeader
        theme={tatico}
        title="Canal do Instrutor"
        onBack={onBack}
        style={{ paddingTop: Platform.OS === 'ios' ? 52 : 16 }}
      />
      <View style={gateStyles.body}>
        <View
          style={[
            gateStyles.card,
            { backgroundColor: tatico.colors.card, borderColor: tatico.colors.border },
          ]}
        >
          <Text
            style={[
              typographyPresets.label,
              { color: tatico.colors.muted, letterSpacing: 1.5, marginBottom: 12 },
            ]}
          >
            {isOnboarding ? 'CADASTRO INCOMPLETO' : 'INSTRUTOR NÃO SELECIONADO'}
          </Text>
          <Text
            style={[typographyPresets.body, { color: tatico.colors.text, marginBottom: 8 }]}
          >
            {isOnboarding
              ? 'Para acessar o canal do instrutor, conclua o cadastro institucional.'
              : 'Selecione seu instrutor institucional para ativar o canal de comunicação.'}
          </Text>
          <TouchableOpacity
            style={[gateStyles.btn, { backgroundColor: tatico.colors.accent }]}
            onPress={onAction}
            activeOpacity={0.8}
          >
            <Text
              style={[
                typographyPresets.label,
                { color: tatico.colors.background, letterSpacing: 1 },
              ]}
            >
              {isOnboarding ? 'CONCLUIR CADASTRO' : 'SELECIONAR INSTRUTOR'}
            </Text>
          </TouchableOpacity>
        </View>
      </View>
    </View>
  );
}

// ── Tela principal ────────────────────────────────────────────────────────────

export default function ChatScreen() {
  const router = useRouter();
  const { profile } = useAuth();
  const online = useNetworkGuard();

  const onboardingOk = !!(profile?.forca && profile?.onboarding_concluido);
  const instructorOk = !!profile?.instructor_profile_id;

  // instructorSlug = codigo do perfil (objetivo/estrategico/didatico), usado nas RPCs de chat
  const instructorSlug = profile?.instructor_profile_id ?? 'objetivo';
  const forca = profile?.forca ?? 'marinha';
  const glowColor = FORCE_GLOW[forca] ?? DEFAULT_GLOW;

  // Dados do instrutor vindos da view (backend-driven)
  const { instructors } = useInstructors();
  const instructorData = instructors.find((i) => i.codigo === instructorSlug) ?? null;
  const instructorName = instructorData?.nome ?? '—';
  const instructorTitle = instructorData?.titulo ?? '—';

  const FORCA_LABEL: Record<string, string> = {
    marinha: 'MB',
    exercito: 'EB',
    aeronautica: 'FAB',
  };
  const forcaLabel = FORCA_LABEL[forca] ?? forca.toUpperCase();

  // Sessão local — identificador único por mount
  const sessionId = useRef(Crypto.randomUUID()).current;
  const recrutaId = profile?.id ?? '';

  // Estado da conversa (DB)
  const [conversaId, setConversaId] = useState<string | null>(null);
  const [mensagens, setMensagens] = useState<ChatMensagem[]>([]);
  const [conversaLoading, setConversaLoading] = useState(false);
  const [messagesLoading, setMessagesLoading] = useState(false);

  // Estado de envio
  const [localMessages, setLocalMessages] = useState<LocalMessage[]>([]);
  const [isSending, setIsSending] = useState(false);
  const [inputText, setInputText] = useState('');
  const [sendError, setSendError] = useState<string | null>(null);

  // Retry: mantém o client_message_id da última tentativa falha
  const pendingRetry = useRef<{ text: string; client_message_id: string } | null>(null);

  const flatListRef = useRef<FlatList>(null);

  // ── Inicialização: abrir conversa existente ──────────────────────────────────

  useEffect(() => {
    if (!onboardingOk || !instructorOk) return;

    async function initConversation() {
      setConversaLoading(true);
      try {
        const result = await openConversationRpc(instructorSlug);
        if (result?.conversa_id) {
          setConversaId(result.conversa_id);
          await fetchMensagens(result.conversa_id);
          await tryMarkRead(result.conversa_id);
        }
      } catch (err) {
        // Sem conversa ainda — estado vazio é válido
        console.log('[CHAT_W1] no_existing_conversation', {
          instrutor_slug: instructorSlug,
          err: err instanceof ChatError ? err.code : String(err),
        });
      } finally {
        setConversaLoading(false);
      }
    }

    initConversation();
  }, [onboardingOk, instructorOk, instructorSlug]);

  async function fetchMensagens(cid: string) {
    setMessagesLoading(true);
    try {
      const msgs = await loadMensagens(cid);
      setMensagens(msgs);
      // Remover mensagens locais cujos client_message_id já estão no DB
      const dbIds = new Set(msgs.map((m) => m.client_message_id).filter(Boolean));
      setLocalMessages((prev) =>
        prev.filter((lm) => !dbIds.has(lm.client_message_id) || lm.status === 'failed'),
      );
      setTimeout(() => flatListRef.current?.scrollToEnd({ animated: false }), 80);
    } catch (err) {
      console.warn('[CHAT_W1] fetch_messages_error', err);
    } finally {
      setMessagesLoading(false);
    }
  }

  async function tryMarkRead(cid: string) {
    try {
      const statuses = await loadUnreadStatus();
      const unread = statuses.find((s) => s.conversa_id === cid && s.has_unread);
      if (unread) {
        await markReadRpc(cid);
      }
    } catch {
      // Falha silenciosa — unread é informativo
    }
  }

  // ── Envio ────────────────────────────────────────────────────────────────────

  const handleSend = useCallback(
    async (text: string, existingClientMessageId?: string) => {
      const trimmed = text.trim();
      if (!trimmed || isSending) return;

      if (!online) {
        setSendError('Sem conexão com a rede. Verifique e tente novamente.');
        return;
      }

      setSendError(null);

      const clientMsgId = existingClientMessageId ?? Crypto.randomUUID();
      const localId = existingClientMessageId ? `retry-${clientMsgId}` : clientMsgId;

      // Remover mensagem anterior com mesmo client_message_id (retry)
      if (existingClientMessageId) {
        setLocalMessages((prev) =>
          prev.filter((lm) => lm.client_message_id !== existingClientMessageId),
        );
      }

      // Adicionar mensagem visual "sending"
      const localMsg: LocalMessage = {
        localId,
        text: trimmed,
        client_message_id: clientMsgId,
        status: 'sending',
        timestamp: new Date(),
      };
      setLocalMessages((prev) => [...prev, localMsg]);
      setInputText('');
      setIsSending(true);
      pendingRetry.current = null;

      setTimeout(() => flatListRef.current?.scrollToEnd({ animated: true }), 80);

      const idempotency_key = `chat:${recrutaId}:${clientMsgId}`;

      const payload: ChatPayloadW1 = {
        instrutor_slug: instructorSlug,
        client_message_id: clientMsgId,
        idempotency_key,
        text: trimmed,
        session_id: sessionId,
        source: 'app',
      };

      try {
        const result = await sendMessageW1(payload);

        // Se a conversa foi criada neste envio, guardar o conversa_id
        const cid = result.conversa_id ?? conversaId;
        if (result.conversa_id && !conversaId) {
          setConversaId(result.conversa_id);
        }

        // Recarregar mensagens do DB (inclui o par user+assistant persistido)
        if (cid) {
          await fetchMensagens(cid);
        } else {
          // Persistência parcial: mostrar resposta mas marcar como não persistida
          setLocalMessages((prev) =>
            prev.map((lm) =>
              lm.client_message_id === clientMsgId
                ? { ...lm, status: 'failed' }
                : lm,
            ),
          );
          const assistantLocal: LocalMessage = {
            localId: `assistant-${clientMsgId}`,
            text: result.assistant_text,
            client_message_id: `assistant-${clientMsgId}`,
            status: 'failed',
            timestamp: new Date(),
          };
          setLocalMessages((prev) => [...prev, assistantLocal]);
        }

        pendingRetry.current = null;
      } catch (err) {
        const errorMsg =
          err instanceof ChatError
            ? err.message
            : 'Falha na comunicação com o QG. Tente novamente.';

        // Marcar mensagem local como "failed"
        setLocalMessages((prev) =>
          prev.map((lm) =>
            lm.client_message_id === clientMsgId ? { ...lm, status: 'failed' } : lm,
          ),
        );

        setSendError(errorMsg);
        pendingRetry.current = { text: trimmed, client_message_id: clientMsgId };
      } finally {
        setIsSending(false);
      }
    },
    [isSending, online, instructorSlug, sessionId, recrutaId, conversaId],
  );

  function handleRetry() {
    if (pendingRetry.current) {
      const { text, client_message_id } = pendingRetry.current;
      handleSend(text, client_message_id);
    }
  }

  function handleBack() {
    if (router.canGoBack()) {
      router.back();
    } else {
      router.replace('/');
    }
  }

  // ── Gates ────────────────────────────────────────────────────────────────────

  if (!onboardingOk) {
    return (
      <ChatGateIncompleteProfile
        reason="onboarding"
        onAction={() => router.replace('/(onboarding)/welcome' as any)}
        onBack={handleBack}
      />
    );
  }

  if (!instructorOk) {
    return (
      <ChatGateIncompleteProfile
        reason="instructor"
        onAction={() => router.push('/(stack)/instructor/select' as any)}
        onBack={handleBack}
      />
    );
  }

  // ── Render de itens ───────────────────────────────────────────────────────────

  type ListItem =
    | { kind: 'db'; msg: ChatMensagem }
    | { kind: 'local'; lm: LocalMessage };

  const dbItems: ListItem[] = mensagens.map((m) => ({ kind: 'db', msg: m }));
  const localIds = new Set(mensagens.map((m) => m.client_message_id).filter(Boolean));
  const pendingItems: ListItem[] = localMessages
    .filter((lm) => !localIds.has(lm.client_message_id) || lm.status === 'failed')
    .map((lm) => ({ kind: 'local', lm }));
  const allItems: ListItem[] = [...dbItems, ...pendingItems];

  function renderItem({ item }: { item: ListItem }) {
    if (item.kind === 'db') {
      const m = item.msg;
      if (m.role === 'user') {
        return (
          <RecrutaMessage
            text={m.conteudo}
            timestamp={m.created_at}
            status={m.status as any}
          />
        );
      }
      return (
        <InstrutorMessage
          text={m.conteudo}
          timestamp={m.created_at}
          instructorName={instructorName}
          glowColor={glowColor}
          status={m.status}
        />
      );
    }

    const lm = item.lm;
    // Mensagens locais do recruta
    if (!lm.localId.startsWith('assistant-')) {
      return (
        <RecrutaMessage
          text={lm.text}
          timestamp={lm.timestamp}
          status={lm.status}
        />
      );
    }
    // Resposta local parcial (persist_failed)
    return (
      <InstrutorMessage
        text={lm.text}
        timestamp={lm.timestamp}
        instructorName={instructorName}
        glowColor={glowColor}
        status="failed"
        onRetry={handleRetry}
      />
    );
  }

  const isLoading = conversaLoading || messagesLoading;
  const isEmpty = !isLoading && mensagens.length === 0 && localMessages.length === 0;

  // ── Render ────────────────────────────────────────────────────────────────────

  return (
    <View style={[styles.root, { backgroundColor: tatico.colors.background }]}>
      <InstitutionalHeader
        theme={tatico}
        title={instructorName}
        subtitle={instructorTitle}
        onBack={handleBack}
        rightSlot={
          <InstitutionalBadge theme={tatico} label={forcaLabel} variant="accent" />
        }
        style={styles.header}
      />

      {/* Banner offline */}
      {!online && (
        <View
          style={[
            styles.offlineBanner,
            {
              backgroundColor: obsidiana.colors.error + '22',
              borderBottomColor: obsidiana.colors.error,
            },
          ]}
        >
          <InstitutionalBadge
            theme={tatico}
            label="Sem conexão — canal de comunicação indisponível"
            variant="error"
          />
        </View>
      )}

      {/* Banner de erro de envio */}
      {sendError && (
        <ChatErrorBanner message={sendError} onDismiss={() => setSendError(null)} />
      )}

      <KeyboardAvoidingView
        style={styles.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        keyboardVerticalOffset={Platform.OS === 'ios' ? BOTTOMBAR_HEIGHT : 0}
      >
        {isLoading ? (
          <View style={styles.loadingCenter}>
            <ActivityIndicator color={glowColor} />
          </View>
        ) : isEmpty ? (
          <View style={welcomeStyles.root}>
            <SystemMessage text="Início do canal" />
            <InstrutorMessage
              text="Canal de comunicação institucional ativo. Estou disponível para orientar sua formação e esclarecer suas dúvidas. Como posso auxiliá-lo?"
              timestamp={new Date()}
              instructorName={instructorName}
              glowColor={glowColor}
            />
          </View>
        ) : (
          <FlatList
            ref={flatListRef}
            data={allItems}
            keyExtractor={(item) =>
              item.kind === 'db' ? item.msg.mensagem_id : item.lm.localId
            }
            renderItem={renderItem}
            contentContainerStyle={styles.listContent}
            showsVerticalScrollIndicator={false}
            onContentSizeChange={() =>
              flatListRef.current?.scrollToEnd({ animated: false })
            }
            keyboardShouldPersistTaps="handled"
          />
        )}

        {isSending && (
          <View style={styles.processingWrapper}>
            <ProcessingIndicator glowColor={glowColor} />
          </View>
        )}

        {/* Compositor */}
        <View
          style={[
            styles.composer,
            {
              backgroundColor: tatico.colors.card,
              borderTopColor: tatico.colors.border,
            },
          ]}
        >
          <InstitutionalInput
            theme={tatico}
            placeholder="Digite sua mensagem institucional..."
            value={inputText}
            onChangeText={setInputText}
            multiline
            containerStyle={styles.inputContainer}
            style={styles.inputField}
            onSubmitEditing={() => handleSend(inputText)}
            blurOnSubmit={false}
            editable={!isSending}
          />

          <TouchableOpacity
            style={[
              styles.sendBtn,
              {
                backgroundColor:
                  inputText.trim() && !isSending
                    ? glowColor
                    : tatico.colors.border,
              },
            ]}
            onPress={() => handleSend(inputText)}
            disabled={!inputText.trim() || isSending}
            activeOpacity={0.8}
          >
            {isSending ? (
              <ActivityIndicator color={tatico.colors.text} size="small" />
            ) : (
              <Text style={styles.sendArrow}>↑</Text>
            )}
          </TouchableOpacity>
        </View>

        <View style={styles.bottomBarSpacer} />
      </KeyboardAvoidingView>
    </View>
  );
}

// ── Estilos ───────────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  root: { flex: 1 },
  flex: { flex: 1 },
  header: { paddingTop: Platform.OS === 'ios' ? 52 : 16 },
  offlineBanner: {
    padding: spacing.s,
    borderBottomWidth: 1,
    alignItems: 'center',
  },
  loadingCenter: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  listContent: {
    padding: spacing.m,
    paddingBottom: spacing.l,
    gap: spacing.s,
  },
  processingWrapper: {
    paddingHorizontal: spacing.m,
    paddingBottom: spacing.xs,
  },
  composer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    padding: spacing.m,
    borderTopWidth: 1,
    gap: spacing.s,
    paddingBottom: Platform.OS === 'ios' ? 28 : spacing.m,
  },
  bottomBarSpacer: { height: BOTTOMBAR_HEIGHT },
  inputContainer: { flex: 1, marginBottom: 0 },
  inputField: { maxHeight: 100, paddingTop: 10 },
  sendBtn: {
    width: 44,
    height: 44,
    borderRadius: radius.s,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 2,
  },
  sendArrow: { color: tatico.colors.text, fontSize: 18, fontWeight: '700' },
});

const msgStyles = StyleSheet.create({
  systemRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.s,
    marginVertical: spacing.xs,
  },
  systemLine: { flex: 1, height: 1 },
  systemText: { color: tatico.colors.muted, letterSpacing: 1.5 },
  recrutaRow: { alignItems: 'flex-end' },
  recrutaBubble: {
    maxWidth: '78%',
    padding: spacing.m,
    borderRadius: radius.m,
    borderWidth: 1,
    borderBottomRightRadius: radius.xs,
    gap: spacing.xs,
  },
  timestamp: { color: tatico.colors.muted, alignSelf: 'flex-end', marginTop: 2 },
  instrutorRow: { alignItems: 'flex-start' },
  instrutorBubble: {
    maxWidth: '92%',
    padding: spacing.m,
    borderRadius: radius.m,
    borderWidth: 1,
    borderLeftWidth: 3,
    borderBottomLeftRadius: radius.xs,
    gap: spacing.xs,
  },
  instrutorFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: spacing.xs,
  },
  retryBtn: { paddingVertical: 2, paddingHorizontal: spacing.s },
});

const processingStyles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.s,
    paddingVertical: spacing.xs,
  },
  bar: { width: 3, height: 14, borderRadius: 2, opacity: 0.7 },
  text: { letterSpacing: 1.5 },
});

const welcomeStyles = StyleSheet.create({
  // Mensagem inicial posicionada na base — como uma mensagem recém-chegada
  root: {
    flex: 1,
    justifyContent: 'flex-end',
    padding: spacing.m,
    paddingBottom: spacing.l,
    gap: spacing.s,
  },
});

const errorBannerStyles = StyleSheet.create({
  root: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: spacing.s,
    paddingHorizontal: spacing.m,
    borderBottomWidth: 1,
  },
});

const gateStyles = StyleSheet.create({
  root: { flex: 1 },
  body: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.l,
  },
  card: {
    width: '100%',
    maxWidth: 360,
    padding: spacing.l,
    borderRadius: radius.m,
    borderWidth: 1,
    gap: spacing.s,
  },
  btn: {
    marginTop: spacing.m,
    paddingVertical: 14,
    borderRadius: radius.s,
    alignItems: 'center',
  },
});
