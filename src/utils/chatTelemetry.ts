// Wave 3d — Telemetria Institucional C5
// Padrão [CHAT_C5] para eventos operacionais do canal institucional.
//
// INVARIANTES:
//   - nunca capturar conteúdo de mensagens
//   - nunca capturar tokens, chaves ou PII
//   - conversa_id exposto apenas como prefixo de 8 chars
//   - campos permitidos são enumerados explicitamente
//   - sem vendor analytics — apenas console local auditável

export type ChatC5Event =
  | 'chat_opened'
  | 'messages_loaded'
  | 'messages_load_failed'
  | 'message_send_started'
  | 'message_send_succeeded'
  | 'message_send_failed'
  | 'message_retry_started'
  | 'message_retry_succeeded'
  | 'message_retry_failed'
  | 'message_retry_discarded'
  | 'unread_loaded'
  | 'unread_cleared'
  | 'draft_restored'
  | 'draft_saved'
  | 'draft_cleared'
  | 'conversations_loaded'
  | 'conversations_load_failed'
  | 'pagination_loaded'
  | 'pagination_end'
  | 'pagination_failed';

// Campos permitidos — TypeScript impede campos proibidos em tempo de compilação
export type ChatC5Meta = {
  instrutor_codigo?: string;         // ex: 'objetivo', 'estrategico', 'didatico'
  conversa_id_prefix?: string;       // apenas primeiros 8 chars do UUID
  correlation_id?: string | null;
  count?: number;
  ms?: number;
  status?: string;
  error_code?: string;
  is_refresh?: boolean;
  with_preview?: number;
  has_more?: boolean;
};

/**
 * Registra evento C5 no canal de chat.
 * Campos proibidos: texto de mensagem, tokens, chaves, PII, body_raw, UUIDs completos.
 */
export function logChatEvent(event: ChatC5Event, meta?: ChatC5Meta): void {
  console.log(`[CHAT_C5] ${event}`, meta ?? {});
}

/**
 * Extrai prefixo seguro de conversa_id (8 chars).
 * Nunca logar o UUID completo.
 */
export function conversaPrefix(conversa_id: string | null | undefined): string | undefined {
  if (!conversa_id) return undefined;
  return conversa_id.slice(0, 8);
}
