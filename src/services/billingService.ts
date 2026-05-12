import { supabase } from '../lib/supabase';

export interface BillingStatus {
  acesso_liberado: boolean;
  plano_atual: string | null;
  status_assinatura: string | null;
  validade: string | null;
  trial_restante: number | null;
}

export async function getBillingStatus(): Promise<BillingStatus> {
  const { data, error } = await supabase
    .from('v_billing_status_recruta_v2')
    .select('acesso_liberado, plano_atual, status_assinatura, validade, trial_restante')
    .single();

  if (error) {
    console.error('[BILLING] Error fetching billing status:', error);
    throw error;
  }

  if (!data) {
    throw new Error('BILLING_EMPTY_RESPONSE');
  }

  return data as BillingStatus;
}
