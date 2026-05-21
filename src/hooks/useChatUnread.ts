// RCC Wave 2b — useChatUnread
// Fonte única de unread_count para o avatar do instrutor.
// Lê v_chat_conversas_recruta via loadConversas() — banco é a verdade.
// Frontend NÃO calcula nem armazena unread localmente de forma autoritativa.

import { useCallback, useEffect, useState } from 'react';
import { loadConversas } from '../services/chatService';

export function useChatUnread(instructorSlug: string | null) {
  const [unreadCount, setUnreadCount] = useState<number>(0);

  const refresh = useCallback(async () => {
    if (!instructorSlug) {
      setUnreadCount(0);
      return;
    }
    try {
      const conversas = await loadConversas();
      const conversa = conversas.find((c) => c.instrutor_slug === instructorSlug);
      const count = conversa?.unread_count ?? 0;
      console.log('[CHAT_UNREAD_W2] unread_loaded', {
        instrutor_slug: instructorSlug,
        unread_count:   count,
      });
      setUnreadCount(count);
    } catch {
      // Falha silenciosa — badge e informativo, nao bloqueia UX
    }
  }, [instructorSlug]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { unreadCount, refresh };
}
