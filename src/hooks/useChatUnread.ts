// RCC Wave 2b — useChatUnread
// Fonte única de unread_count para o avatar do instrutor.
// Lê v_chat_conversas_recruta via loadConversas() — banco é a verdade.
// Frontend NÃO calcula nem armazena unread localmente de forma autoritativa.
//
// Wave 5a-1: inscrito no chatUnreadBus — atualiza ao retorno ao foreground.

import { useCallback, useEffect, useRef, useState } from 'react';
import { loadConversas } from '../services/chatService';
import { logChatEvent } from '../utils/chatTelemetry';
import { subscribeChatUnreadRefresh } from '../events/chatUnreadBus';

export function useChatUnread(instructorSlug: string | null) {
  const [unreadCount, setUnreadCount] = useState<number>(0);
  // Versão monotônica: cada refresh recebe um ticket; apenas o último vence.
  // Evita que refresh anterior (com count antigo) sobrescreva um mais recente.
  // Não bloqueia chamadas paralelas — ao contrário do isRefreshingRef anterior,
  // que causava race com o foreground event ao tocar uma push notification.
  const refreshTicketRef = useRef(0);

  const refresh = useCallback(async () => {
    const ticket = ++refreshTicketRef.current;

    if (!instructorSlug) {
      setUnreadCount(0);
      return;
    }
    try {
      const conversas = await loadConversas();
      if (ticket !== refreshTicketRef.current) return; // resultado stale — ignorar
      const conversa = conversas.find((c) => c.instrutor_slug === instructorSlug);
      const count = conversa?.unread_count ?? 0;
      logChatEvent('unread_loaded', { instrutor_codigo: instructorSlug, count });
      setUnreadCount(count);
    } catch {
      // Falha silenciosa — badge é informativo, nao bloqueia UX
    }
  }, [instructorSlug]);

  // Refresh inicial no mount / troca de instrutor
  useEffect(() => {
    refresh();
  }, [refresh]);

  // Refresh ao retorno ao foreground (Wave 5a-1)
  useEffect(() => {
    return subscribeChatUnreadRefresh(refresh);
  }, [refresh]);

  return { unreadCount, refresh };
}
