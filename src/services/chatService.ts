// RCC Wave 1 — Chat Service
// Contratos de leitura: views RCC.
// Contratos de escrita: RPCs + Edge Function instrutor-send.
// Nunca escreve tabelas diretamente. Nunca calcula unread.

import { supabase, supabaseUrl, supabaseAnonKey } from '../lib/supabase';
import { logChatEvent } from '../utils/chatTelemetry';

// ── Tipos RCC Wave 1 ───────────────────────────────────────────────────────────

export type ChatPayloadW1 = {
  instrutor_slug: string;
  client_message_id: string;
  idempotency_key: string; // formato: chat:<recruta_id>:<client_message_id>
  text: string;
  session_id: string;
  source: 'app';
};

export type PersistedMessage = {
  mensagem_id?: string;
  conversa_id?: string;
  assistant_text: string;
  correlation_id: string;
};

export type ChatConversa = {
  conversa_id: string;
  recruta_id: string;
  instrutor_slug: string;
  instrutor_nome: string;
  instrutor_titulo: string;
  avatar_asset_tipo: string | null;
  chat_icon_asset_tipo: string | null;
  status: string;
  unread_count: number;
  has_unread: boolean;
  opened_at: string | null;
  last_message_at: string | null;
  updated_at: string;
  // Wave 3a: preview da última mensagem — vem truncado do banco (LEFT 120)
  last_message_preview: string | null;
  last_message_role: 'user' | 'assistant' | null;
};

export type ChatMensagem = {
  mensagem_id: string;
  conversa_id: string;
  recruta_id: string;
  instrutor_slug: string;
  role: 'user' | 'assistant';
  conteudo: string;
  status: string;
  client_message_id: string | null;
  correlation_id: string | null;
  origem: string | null;
  created_at: string;
};

export type ChatUnreadStatus = {
  conversa_id: string;
  recruta_id: string;
  instrutor_slug: string;
  unread_count: number;
  has_unread: boolean;
  last_read_at: string | null;
  updated_at: string;
};

export type InstructorApp = {
  instrutor_id: string;
  slug: string;
  codigo: string;
  nome: string;
  titulo: string;
  descricao: string | null;
  ordem_exibicao: number;
  ativo: boolean;
  // URLs resolvidas via v_instrutores_app (institutional_assets join)
  avatar_url: string | null;
  chat_icon_url: string | null;
  whatsapp_avatar_url: string | null;
  card_selected_url: string | null;
  card_idle_url: string | null;
};

// ── Erros tipados ──────────────────────────────────────────────────────────────

export type ChatErrorCode =
  | 'timeout'
  | 'offline'
  | 'auth'
  | 'server'
  | 'validation'
  | 'onboarding_incomplete'
  | 'instructor_missing'
  | 'persist_failed';

export class ChatError extends Error {
  constructor(
    public readonly code: ChatErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'ChatError';
  }
}

export const CHAT_TIMEOUT_MS = 35_000;
export const STREAM_TIMEOUT_MS = 40_000;

// ── Streaming (Wave 5f) ────────────────────────────────────────────────────────

export type StreamEvent =
  | { type: 'delta'; delta: string }
  | { type: 'done'; conversa_id?: string; ok: boolean; correlation_id?: string; assistant_text?: string; from_cache?: boolean }
  | { type: 'error'; reason: string };

// ── SSE streaming (Wave 5f) ────────────────────────────────────────────────────
//
// streamMessageW1: tenta SSE streaming via Accept: text/event-stream.
// Se ReadableStream não disponível (Hermes sem polyfill) ou streaming falhar,
// yield { type: 'error', reason: 'stream_unavailable' } imediatamente —
// permitindo que o caller faça fallback para sendMessageW1.
//
// Uso no ChatScreen:
//   const gen = streamMessageW1(payload);
//   for await (const ev of gen) {
//     if (ev.type === 'delta')        // appenda ao texto parcial
//     else if (ev.type === 'done')    // stream completo, recarregar DB
//     else if (ev.type === 'error')   // fallback ou mostrar erro
//   }

export async function* streamMessageW1(
  payload: ChatPayloadW1,
): AsyncGenerator<StreamEvent> {
  if (!payload.text.trim()) {
    yield { type: 'error', reason: 'empty_message' };
    return;
  }

  // Verificar suporte a ReadableStream antes de tentar (evita erro em Hermes antigo)
  if (
    typeof ReadableStream === 'undefined' ||
    typeof AbortController === 'undefined'
  ) {
    yield { type: 'error', reason: 'stream_unavailable' };
    return;
  }

  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) {
    yield { type: 'error', reason: 'session_expired' };
    return;
  }

  const controller = new AbortController();
  const timeoutId  = setTimeout(() => controller.abort(), STREAM_TIMEOUT_MS);

  try {
    let response: Response;
    try {
      response = await fetch(
        `${supabaseUrl}/functions/v1/instrutor-send`,
        {
          method:  'POST',
          headers: {
            Authorization:  `Bearer ${session.access_token}`,
            'Content-Type': 'application/json',
            Accept:         'text/event-stream',
            apikey:         supabaseAnonKey,
          },
          body: JSON.stringify({
            text:              payload.text,
            client_message_id: payload.client_message_id,
            session_id:        payload.session_id,
            source:            payload.source,
            instrutor_slug:    payload.instrutor_slug,
          }),
          signal: controller.signal,
        },
      );
    } catch {
      yield { type: 'error', reason: 'stream_unavailable' };
      return;
    }

    if (!response.ok) {
      yield { type: 'error', reason: 'stream_unavailable' };
      return;
    }

    // response.body pode ser null em Hermes sem suporte a streaming
    if (!response.body || typeof (response.body as any).getReader !== 'function') {
      yield { type: 'error', reason: 'stream_unavailable' };
      return;
    }

    const reader  = (response.body as ReadableStream<Uint8Array>).getReader();
    const decoder = new TextDecoder();
    let   buffer  = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const parts = buffer.split('\n\n');
      buffer = parts.pop() ?? '';

      for (const part of parts) {
        if (!part.startsWith('data: ')) continue;
        try {
          const event = JSON.parse(part.slice(6)) as StreamEvent;
          yield event;
          if (event.type === 'done' || event.type === 'error') return;
        } catch {
          // malformed SSE event — skip
        }
      }
    }
  } catch (err) {
    if ((err as any)?.name === 'AbortError') {
      yield { type: 'error', reason: 'timeout' };
    } else {
      yield { type: 'error', reason: 'network_error' };
    }
  } finally {
    clearTimeout(timeoutId);
  }
}

// ── Views RCC (leitura) ────────────────────────────────────────────────────────

export async function loadConversas(
  options?: { before?: string; limit?: number },
): Promise<ChatConversa[]> {
  const limit = options?.limit ?? 20;

  let query = supabase
    .from('v_chat_conversas_recruta')
    .select('*')
    .order('updated_at', { ascending: false, nullsFirst: false })
    .limit(limit);

  if (options?.before) {
    query = query.lt('updated_at', options.before);
  }

  const { data, error } = await query;
  if (error) throw new ChatError('server', error.message);
  return (data ?? []) as ChatConversa[];
}

export async function loadMensagens(
  conversa_id: string,
  options?: { before?: string; limit?: number },
): Promise<ChatMensagem[]> {
  const limit = options?.limit ?? 30;

  let query = supabase
    .from('v_chat_mensagens_recruta')
    .select('*')
    .eq('conversa_id', conversa_id)
    .order('created_at', { ascending: false })
    .limit(limit);

  if (options?.before) {
    query = query.lt('created_at', options.before);
  }

  const { data, error } = await query;
  if (error) throw new ChatError('server', error.message);
  // Banco retorna DESC (página mais recente). Inverter para ASC no frontend.
  return ((data ?? []) as ChatMensagem[]).reverse();
}

export async function loadUnreadStatus(): Promise<ChatUnreadStatus[]> {
  const { data, error } = await supabase
    .from('v_chat_unread_status')
    .select('*');

  if (error) throw new ChatError('server', error.message);
  return (data ?? []) as ChatUnreadStatus[];
}

export async function loadInstructors(): Promise<InstructorApp[]> {
  const { data, error } = await supabase
    .from('v_instrutores_app')
    .select('*')
    .eq('ativo', true)
    .order('ordem_exibicao', { ascending: true });

  if (error) throw new ChatError('server', error.message);
  return (data ?? []) as InstructorApp[];
}

// ── RPCs (escrita via contratos) ───────────────────────────────────────────────

export async function openConversationRpc(
  instrutor_slug: string,
): Promise<{ conversa_id: string; status: string } | null> {
  const { data, error } = await supabase.rpc('rpc_chat_open_conversation', {
    p_instrutor_slug: instrutor_slug,
  });

  if (error) throw new ChatError('server', error.message);
  return (data as { conversa_id: string; status: string } | null) ?? null;
}

export async function markReadRpc(conversa_id: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_chat_mark_read', {
    p_conversa_id: conversa_id,
  });

  if (error) throw new ChatError('server', error.message);
}

// ── Edge Function instrutor-send ───────────────────────────────────────────────

export async function sendMessageW1(payload: ChatPayloadW1): Promise<PersistedMessage> {
  if (!payload.text.trim()) {
    throw new ChatError('validation', 'Mensagem vazia.');
  }

  const invocation = supabase.functions.invoke('instrutor-send', {
    body: {
      text: payload.text,
      client_message_id: payload.client_message_id,
      session_id: payload.session_id,
      source: payload.source,
      instrutor_slug: payload.instrutor_slug,
    },
  });

  const timeout = new Promise<never>((_, reject) =>
    setTimeout(
      () =>
        reject(
          new ChatError(
            'timeout',
            'O QG não respondeu a tempo. Tente novamente.',
          ),
        ),
      CHAT_TIMEOUT_MS,
    ),
  );

  const { data, error } = await Promise.race([invocation, timeout]);

  if (error) {
    // Extrair campos estruturados do body retornado pela Edge Function
    let _bodyJson: Record<string, unknown> | null = null;
    try {
      const _ctx = (error as any)?.context;
      if (_ctx && typeof _ctx.text === 'function') {
        try { _bodyJson = JSON.parse(await _ctx.text()); } catch {}
      }
    } catch {}

    logChatEvent('message_send_failed', {
      error_code: String(_bodyJson?.reason ?? (error as any)?.context?.status ?? 'ef_error'),
      status:     String((error as any)?.context?.status ?? ''),
      correlation_id: (_bodyJson?.central_request_id as string) ?? null,
    });
    throw new ChatError('server', 'Falha na comunicação com o QG. Tente novamente.');
  }

  const reason = data?.reason;

  if (reason === 'onboarding_incomplete') {
    throw new ChatError(
      'onboarding_incomplete',
      'Cadastro institucional incompleto. Conclua o onboarding para acessar o instrutor.',
    );
  }
  if (reason === 'instructor_missing') {
    throw new ChatError(
      'instructor_missing',
      'Instrutor não identificado. Selecione seu instrutor para continuar.',
    );
  }

  if (!data?.ok) {
    if (reason === 'persist_failed' && data?.assistant_text) {
      // Resposta gerada mas não persistida — retornar para o usuário ver
      logChatEvent('message_send_failed', { error_code: 'persist_failed' });
      return {
        assistant_text: data.assistant_text as string,
        correlation_id: data.correlation_id as string ?? '',
      };
    }
    throw new ChatError('server', 'Falha no processamento institucional. Tente novamente.');
  }

  return {
    mensagem_id: (data as any).mensagem_id as string | undefined,
    conversa_id: (data as any).conversa_id as string | undefined,
    assistant_text: ((data as any).assistant_text as string) ?? '',
    correlation_id: (data.correlation_id as string) ?? '',
  };
}
