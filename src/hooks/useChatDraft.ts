// Wave 3c — useChatDraft
// Preservação local não-autoritativa de rascunho por instrutor.
//
// INVARIANTES:
//   - draft NÃO é persistência institucional
//   - draft NÃO substitui mensagens reais
//   - banco-first preservado: draft nunca vai para RPCs ou views
//   - chave isolada por instrutor: chat_draft:<instructorSlug>
//   - falhas de SecureStore são silenciosas (draft é conveniência, não crítico)

import { useState, useEffect, useCallback, useRef } from 'react';
import * as SecureStore from 'expo-secure-store';

const DRAFT_KEY_PREFIX = 'chat_draft:';
const DEBOUNCE_MS = 400;

export function useChatDraft(instructorSlug: string | null) {
  // draft: texto inicial carregado do storage (apenas para restauração no mount)
  const [draft, setDraft] = useState<string>('');
  // restored: true quando um draft não-vazio foi carregado do storage
  const [restored, setRestored] = useState(false);

  const debounceTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastSaved = useRef<string>('');

  // Carrega draft ao montar / quando instrutor muda
  useEffect(() => {
    setDraft('');
    setRestored(false);
    lastSaved.current = '';

    if (!instructorSlug) return;

    SecureStore.getItemAsync(`${DRAFT_KEY_PREFIX}${instructorSlug}`)
      .then((value) => {
        if (value && value.trim()) {
          setDraft(value);
          setRestored(true);
          console.log('[CHAT_DRAFT_W3] draft_restored', { instrutor_slug: instructorSlug });
        }
      })
      .catch(() => {
        // Falha silenciosa — draft é conveniência UX, não bloqueia nada
      });
  }, [instructorSlug]);

  // Salva rascunho com debounce — evita write por keypress
  const saveDraft = useCallback(
    (text: string) => {
      if (!instructorSlug) return;
      if (debounceTimer.current) clearTimeout(debounceTimer.current);

      debounceTimer.current = setTimeout(async () => {
        if (text === lastSaved.current) return; // write idêntico → ignorar
        lastSaved.current = text;

        try {
          if (text.trim()) {
            await SecureStore.setItemAsync(`${DRAFT_KEY_PREFIX}${instructorSlug}`, text);
            console.log('[CHAT_DRAFT_W3] draft_saved', { instrutor_slug: instructorSlug });
          } else {
            await SecureStore.deleteItemAsync(`${DRAFT_KEY_PREFIX}${instructorSlug}`);
            console.log('[CHAT_DRAFT_W3] draft_cleared', { instrutor_slug: instructorSlug });
          }
        } catch {
          // Falha silenciosa
        }
      }, DEBOUNCE_MS);
    },
    [instructorSlug],
  );

  // Limpa draft imediatamente (após envio bem-sucedido ou troca de instrutor)
  const clearDraft = useCallback(async () => {
    if (debounceTimer.current) clearTimeout(debounceTimer.current);
    lastSaved.current = '';
    setDraft('');
    setRestored(false);

    if (!instructorSlug) return;
    try {
      await SecureStore.deleteItemAsync(`${DRAFT_KEY_PREFIX}${instructorSlug}`);
      console.log('[CHAT_DRAFT_W3] draft_cleared', { instrutor_slug: instructorSlug });
    } catch {
      // Falha silenciosa
    }
  }, [instructorSlug]);

  // Cleanup do debounce ao desmontar
  useEffect(() => {
    return () => {
      if (debounceTimer.current) clearTimeout(debounceTimer.current);
    };
  }, []);

  return { draft, restored, saveDraft, clearDraft };
}
