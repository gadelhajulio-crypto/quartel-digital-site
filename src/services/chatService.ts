// RCC Wave 1 — Chat Service
// Contratos de leitura: views RCC.
// Contratos de escrita: RPCs + Edge Function instrutor-send.
// Nunca escreve tabelas diretamente. Nunca calcula unread.

import { supabase } from '../lib/supabase';

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

// ── Views RCC (leitura) ────────────────────────────────────────────────────────

export async function loadConversas(): Promise<ChatConversa[]> {
  const { data, error } = await supabase
    .from('v_chat_conversas_recruta')
    .select('*')
    .order('last_message_at', { ascending: false, nullsFirst: false });

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
  console.log('[CHAT_W1] load_conversation_start', { instrutor_slug });

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

  console.log('[CHAT_W1] load_messages_start', {
    hasClientMessageId: !!payload.client_message_id,
    hasSessionId: !!payload.session_id,
    instrutor_slug: payload.instrutor_slug,
    source: payload.source,
  });

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

    console.warn('[CHAT_W1] edge_function_error', {
      status:             (error as any)?.context?.status ?? (error as any)?.status ?? null,
      reason:             _bodyJson?.reason              ?? null,
      detail:             _bodyJson?.detail              ?? null,
      central_request_id: _bodyJson?.central_request_id ?? null,
      ef_request_id:      _bodyJson?.request_id         ?? null,
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
      console.warn('[CHAT_W1] persist_failed_partial_response');
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
