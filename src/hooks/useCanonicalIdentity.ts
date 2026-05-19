import { useEffect } from 'react';
import { useAuth } from '../context/AuthContext';

/**
 * Identidade canônica institucional.
 *
 * REGRA FUNDAMENTAL (Sprint 3):
 *   - auth_user_id  → auth.uid()    — usar APENAS para auth puro (sign-in/out, RCC session)
 *   - recruta_id    → recrutas.id   — usar para TODAS as queries de domínio
 *
 * Para usuários legados (ex: GADELHA), auth_user_id ≠ recruta_id.
 * Filtros de domínio que usam auth_user_id retornam 0 rows silenciosamente.
 *
 * profile.id é populado de v_identidade_recruta WHERE auth_id = auth.uid()
 * e já retorna recrutas.id — zero roundtrip adicional necessário.
 */
export interface CanonicalIdentity {
  /** auth.uid() — usar apenas para auth puro (sign-in/out, RCC session management) */
  auth_user_id: string | null;
  /** recrutas.id — usar para todas as queries de domínio (progresso, ranking, medalhas) */
  recruta_id: string | null;
  forca: string | null;
  nome_guerra: string | null;
  /** true quando profile foi carregado do banco (profileLoading = false e profile != null) */
  isResolved: boolean;
}

export function useCanonicalIdentity(): CanonicalIdentity {
  const { session, profile, profileLoading } = useAuth();

  const auth_user_id = session?.user?.id ?? null;
  const recruta_id = profile?.id ?? null;
  const forca = profile?.forca ?? null;
  const nome_guerra = profile?.nome_guerra ?? null;
  const isResolved = !profileLoading && profile !== null;

  useEffect(() => {
    if (!__DEV__ || !isResolved || !auth_user_id || !recruta_id) return;
    if (auth_user_id !== recruta_id) {
      console.info(
        '[CanonicalIdentity] LEGADO — auth_user_id ≠ recruta_id (Fix-03 ativo)',
        { auth_user_id, recruta_id }
      );
    } else {
      console.info('[CanonicalIdentity] resolvido — ids coincidem', { recruta_id });
    }
  }, [isResolved, auth_user_id, recruta_id]);

  return { auth_user_id, recruta_id, forca, nome_guerra, isResolved };
}
