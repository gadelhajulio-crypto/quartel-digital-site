// Wave 5a-1 — Bus leve de refresh de unread institucional.
//
// Desacopla o authForegroundCoordinator do hook useChatUnread.
// O coordinator emite; os hooks inscritos reagem de forma independente.
//
// INVARIANTES:
//   - sem estado de dados (apenas listeners)
//   - sem dependências externas
//   - retorno de subscribe é a função de cleanup (padrão pub/sub)
//   - emit é fire-and-forget síncrono: cada listener é responsável pelo próprio guard

type Listener = () => void;

const _listeners = new Set<Listener>();

/**
 * Inscreve um listener para eventos de refresh de unread.
 * Retorna função de cleanup — chamar no unmount do hook.
 */
export function subscribeChatUnreadRefresh(listener: Listener): () => void {
  _listeners.add(listener);
  return () => { _listeners.delete(listener); };
}

/**
 * Emite evento de refresh para todos os hooks inscritos.
 * Chamado pelo authForegroundCoordinator na transição para AppState.active.
 */
export function emitChatUnreadRefresh(): void {
  _listeners.forEach((l) => l());
}
