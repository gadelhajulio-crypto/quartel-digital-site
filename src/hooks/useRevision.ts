// Stub — feature de revisão de áudio não implementada.
// RevisaoAudioScreen usa este hook mas a tela não está roteada.

type Revision = { audioUrl: string };

export function useRevision() {
  return {
    loading: false as boolean,
    error: 'Funcionalidade não disponível.' as string | null,
    revision: null as Revision | null,
    canPlay: false as boolean,
  };
}
