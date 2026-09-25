# Billing RPC Audit — Commerce Conformance Hardening v1

Date: 2026-09-25
Status: **versioned source sufficient for design; migration not yet applied**

## Sources audited

- `supabase/remote/supabase_remote_schema.sql`
- `supabase/baseline/00000000000000_remote_baseline.sql`
- `supabase/baseline/modules/06_billing.sql`
- current Stripe Edge Function and n8n workflow on `mobile/main`

## Confirmed current model

`billing_assinaturas` is one row per recruit and carries current access/billing projection.

`billing_pagamentos` is append-oriented per provider event and has a unique provider-event idempotency model.

`rpc_billing_processar_evento_pagamento`:
- validates recruit and event id;
- deduplicates by gateway + event id;
- derives subscription/access status from payment status;
- upserts the current `billing_assinaturas` row;
- inserts a payment/event record;
- reconciles the recruit access projection;
- preserves a reconciliation log.

`rpc_billing_reconciliar_pagamentos` derives product access from `billing_assinaturas` and existing validity/trial fields.

## Critical gap: event idempotency is not payment-object monotonicity

The current idempotency protects only replay of the **same provider event id**.

A later refund/dispute has a different Stripe event id. A stale success event with another legitimate event id can therefore overwrite the single `billing_assinaturas` projection back to active unless transition precedence is introduced.

RP Commerce requires both:
- provider-event idempotency; and
- monotonic/current-state transition protection for the provider payment object.

## Safe migration strategy

Do not replace the existing RPC signature in place.

Add an additive v2 processing RPC dedicated to the one-time 365-day offer. It should:
1. accept normalized provider event kind and provider payment object id;
2. store every event append-only;
3. lock the recruit's current billing row during transition;
4. apply explicit transition precedence;
5. grant 365 days only on a verified succeeded transition;
6. revoke on refund/dispute without deleting history;
7. ignore expiration as an access mutation;
8. preserve service-role-only write authority;
9. emit reconciliation evidence.

The existing RPC remains available until sandbox conformance passes and cutover is explicitly approved.

## Proposed precedence

For a single provider payment object:

```text
pending < succeeded < refunded/disputed
failed is terminal for that attempt unless a later verified success belongs to the same reconciled payment semantics
expired checkout does not mutate a succeeded/refunded/disputed payment
```

Refund/dispute outrank success for access eligibility. An older/lower-precedence event cannot reactivate access.

## 365-day grant policy

For first successful purchase:
`vigente_inicio = processing time`
`vigente_fim = vigente_inicio + interval '365 days'`

A repeat purchase/renewal policy is deliberately not invented here. Whether a second valid purchase extends from `max(now(), vigente_fim)` or is disallowed requires an explicit commercial decision.

## Stop gate discovered

Before implementing the v2 grant logic, the **repeat-purchase/renewal rule must be frozen** because it changes entitlement arithmetic and customer outcome.

Everything else is sufficiently evidenced to continue with non-granting schema/contract preparation.
