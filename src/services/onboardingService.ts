import { supabase } from '../lib/supabase';

type Forca = 'marinha' | 'exercito' | 'aeronautica';

export type OnboardingStatus = {
  recruta_id: string;
  onboarding_concluido: boolean;
  forca_definida: boolean;
  nome_guerra_definido: boolean;
};

/**
 * Consulta v_onboarding_status via RCC.
 * Retorna null se o recruta ainda não tem row em `recrutas` (pré-onboarding).
 * Usa maybeSingle() para evitar PGRST116 quando não há row.
 */
export async function getOnboardingStatus(): Promise<OnboardingStatus | null> {
  const { data, error } = await supabase
    .from('v_onboarding_status')
    .select('recruta_id, onboarding_concluido, forca_definida, nome_guerra_definido')
    .maybeSingle();

  if (error) {
    console.error('[ONBOARDING] Error fetching v_onboarding_status:', error);
    throw error;
  }

  return data as OnboardingStatus | null;
}

export async function saveOnboardingData(
  _recrutaId: string,
  forca: Forca,
  nomeGuerra: string
): Promise<void> {
  // rpc_complete_onboarding: SECURITY DEFINER usa auth.uid() internamente
  const { error } = await supabase.rpc('rpc_complete_onboarding', {
    p_forca: forca,
    p_nome_guerra: nomeGuerra,
  });

  if (error) {
    console.warn('[ONBOARDING] Falha institucional ao registrar vínculo.');
    throw error;
  }
}
