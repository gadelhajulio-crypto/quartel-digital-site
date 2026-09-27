// Commerce Conformance Hardening v1 — Stripe Checkout
// Server-authoritative offer mapping. Client never supplies a Stripe Price ID.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@14.21.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", { apiVersion: "2024-04-10" });
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const OFFERS = {
  quartel_365d: {
    priceId: Deno.env.get("STRIPE_PRICE_QUARTEL_365D") ?? "",
  },
} as const;

serve(async (req) => {
  try {
    const auth = req.headers.get("Authorization");
    if (!auth) return new Response("Unauthorized", { status: 401 });

    const client = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: auth } } });
    const { data: { user }, error: userError } = await client.auth.getUser();
    if (userError || !user) return new Response("Unauthorized", { status: 401 });

    const body = await req.json().catch(() => ({}));
    const offerId = body?.offer_id === "quartel_365d" ? "quartel_365d" : null;
    if (!offerId) return Response.json({ error: "OFFER_NAO_SUPORTADA" }, { status: 400 });

    const { data: recruit, error: recruitError } = await client
      .from("recrutas")
      .select("id")
      .eq("auth_id", user.id)
      .single();
    if (recruitError || !recruit) return Response.json({ error: "RECRUTA_NAO_ENCONTRADO" }, { status: 403 });

    // Never trust a client-provided recruta_id or price id.
    if (body?.recruta_id && body.recruta_id !== recruit.id) {
      return Response.json({ error: "RECRUTA_NAO_AUTORIZADO" }, { status: 403 });
    }

    const priceId = OFFERS[offerId].priceId;
    if (!priceId) return Response.json({ error: "OFFER_PRICE_NAO_CONFIGURADO" }, { status: 503 });

    const correlationId = crypto.randomUUID();
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [{ price: priceId, quantity: 1 }],
      client_reference_id: recruit.id,
      metadata: {
        source_system: "quartel-digital",
        offer_id: offerId,
        beneficiary_ref: recruit.id,
        correlation_id: correlationId,
      },
      success_url: `${Deno.env.get("APP_SUCCESS_URL") ?? "quarteldigital://billing/success"}?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: Deno.env.get("APP_CANCEL_URL") ?? "quarteldigital://billing/cancel",
    });

    return Response.json({ checkout_url: session.url, session_id: session.id, correlation_id: correlationId });
  } catch (error) {
    console.error("stripe-create-checkout-session failed", error instanceof Error ? error.message : "unknown");
    return Response.json({ error: "CHECKOUT_CREATE_FAILED" }, { status: 500 });
  }
});
