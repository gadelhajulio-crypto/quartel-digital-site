import { supabase } from '../lib/supabase';

export type PlanSlug = 'mensal' | 'anual';

export interface CheckoutSessionResult {
  checkout_url: string;
  session_id: string;
  correlation_id: string;
}

export async function createCheckoutSession(
  recruta_id: string,
  plan_slug: PlanSlug,
): Promise<CheckoutSessionResult> {
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) throw new Error('UNAUTHENTICATED');

  const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
  if (!supabaseUrl) throw new Error('MISSING_SUPABASE_URL');

  const res = await fetch(
    `${supabaseUrl}/functions/v1/stripe-create-checkout-session`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ recruta_id, plan_slug }),
    },
  );

  const data = await res.json();

  if (!res.ok || !data.ok) {
    console.error('[STRIPE_SERVICE] checkout_error', { reason: data.reason, status: res.status });
    throw new Error(data.reason ?? 'CHECKOUT_ERROR');
  }

  return {
    checkout_url: data.checkout_url,
    session_id: data.session_id,
    correlation_id: data.correlation_id,
  };
}
