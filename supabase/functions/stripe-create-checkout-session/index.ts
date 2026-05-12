// stripe-create-checkout-session
// Cria uma Checkout Session da Stripe com metadata institucional.
// Requer JWT válido (verify_jwt = true no config.toml).

const STRIPE_API = 'https://api.stripe.com/v1';

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

async function stripePost(
  path: string,
  params: Record<string, string>,
  secretKey: string,
): Promise<Record<string, unknown>> {
  const res = await fetch(`${STRIPE_API}${path}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${secretKey}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(params).toString(),
  });

  const data = await res.json() as Record<string, unknown>;

  if (!res.ok) {
    const errMsg = (data.error as Record<string, string>)?.message ?? 'stripe_api_error';
    throw new Error(errMsg);
  }

  return data;
}

Deno.serve(async (req) => {
  const request_id = crypto.randomUUID();

  try {
    // ── Secrets ──────────────────────────────────────────────────────────────
    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const successUrl = Deno.env.get('STRIPE_SUCCESS_URL') ?? 'quarteldigital://checkout/success';
    const cancelUrl = Deno.env.get('STRIPE_CANCEL_URL') ?? 'quarteldigital://checkout/cancel';
    const priceIdMensal = Deno.env.get('STRIPE_PRICE_ID_MENSAL');
    const priceIdAnual = Deno.env.get('STRIPE_PRICE_ID_ANUAL');

    if (!stripeSecretKey || !supabaseUrl || !supabaseServiceKey) {
      console.error('[stripe-checkout] missing_env', { request_id });
      return json(500, { ok: false, reason: 'missing_env', request_id });
    }

    // ── Auth ──────────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return json(401, { ok: false, reason: 'missing_auth', request_id });
    }
    const userJwt = authHeader.slice(7);

    // ── Body ──────────────────────────────────────────────────────────────────
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json(400, { ok: false, reason: 'invalid_json', request_id });
    }

    const { recruta_id, plan_slug } = body as { recruta_id?: string; plan_slug?: string };

    if (!recruta_id || typeof recruta_id !== 'string') {
      return json(400, { ok: false, reason: 'missing_recruta_id', request_id });
    }
    if (!plan_slug || !['mensal', 'anual'].includes(plan_slug)) {
      return json(400, { ok: false, reason: 'invalid_plan_slug', request_id });
    }

    // ── Price ID ──────────────────────────────────────────────────────────────
    const price_id = plan_slug === 'mensal' ? priceIdMensal : priceIdAnual;
    if (!price_id) {
      console.error('[stripe-checkout] missing_price_id', { request_id, plan_slug });
      return json(500, { ok: false, reason: 'missing_price_id', request_id });
    }

    // ── Busca recruta no banco ────────────────────────────────────────────────
    // Usa o JWT do usuário para garantir que ele só acessa o próprio recruta_id
    const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2');

    const supabaseUser = createClient(supabaseUrl, supabaseServiceKey, {
      global: { headers: { Authorization: `Bearer ${userJwt}` } },
    });

    const { data: recruta, error: recrutaError } = await supabaseUser
      .from('v_identidade_recruta')
      .select('id, auth_id, nome, nome_guerra')
      .eq('id', recruta_id)
      .single();

    if (recrutaError || !recruta) {
      console.error('[stripe-checkout] recruta_not_found', {
        request_id,
        recruta_id,
        error: recrutaError?.message,
      });
      return json(404, { ok: false, reason: 'recruta_not_found', request_id });
    }

    // ── Busca email do usuário ────────────────────────────────────────────────
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
    const { data: userData, error: userError } = await supabaseAdmin.auth.admin.getUserById(
      recruta.auth_id,
    );

    if (userError || !userData?.user) {
      console.error('[stripe-checkout] user_not_found', {
        request_id,
        auth_id: recruta.auth_id,
        error: userError?.message,
      });
      return json(404, { ok: false, reason: 'user_not_found', request_id });
    }

    const correlation_id = crypto.randomUUID();
    const customerEmail = userData.user.email ?? '';

    console.log('[stripe-checkout] creating_session', {
      request_id,
      recruta_id,
      plan_slug,
      correlation_id,
    });

    // ── Cria Checkout Session na Stripe ───────────────────────────────────────
    const session = await stripePost(
      '/checkout/sessions',
      {
        'payment_method_types[]': 'card',
        'line_items[0][price]': price_id,
        'line_items[0][quantity]': '1',
        'mode': 'payment',
        'success_url': successUrl,
        'cancel_url': cancelUrl,
        'customer_email': customerEmail,
        // Metadata na session — disponível em checkout.session.completed
        'metadata[recruta_id]': recruta_id,
        'metadata[auth_id]': recruta.auth_id,
        'metadata[plan_slug]': plan_slug,
        'metadata[correlation_id]': correlation_id,
        
      },
      stripeSecretKey,
    );

    console.log('[stripe-checkout] session_created', {
      request_id,
      session_id: session.id,
      correlation_id,
    });

    return json(200, {
      ok: true,
      checkout_url: session.url,
      session_id: session.id,
      correlation_id,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[stripe-checkout] exception', { request_id, message });
    return json(500, { ok: false, reason: 'internal_error', request_id });
  }
});
