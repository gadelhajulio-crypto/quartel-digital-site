# Ecosystem Handoff — RP Commerce Foundation v1

Date: 2026-09-25
Audience: RP OS, Growth Intelligence, E Agora, Quartel Digital, Biblioteca Estratégica, Além da Farda, architecture/control-plane agents.

## What changed

A new ecosystem boundary, **RP Commerce**, is being introduced as a provider-neutral contract. Stripe is the first provider, but Stripe identifiers and schemas are not ecosystem identity.

This is a contract/governance layer first. It is **not yet a new central production service**.

## Canonical distinctions all agents must preserve

```text
Offer != Checkout Attempt != Order != Payment != Subscription != Entitlement
Purchaser != Beneficiary
Payment provider identity != RP person identity
Commercial eligibility != communication authorization
```

Do not create shortcuts that collapse these concepts.

## Ownership

- Origin commerce runtime owns its authoritative checkout/order/payment processing.
- Payment provider supplies provider facts; verified adapters accept/reconcile them.
- Product/access domain remains authority for entitlement/access.
- RP OS may consume approved projections; it does not gain universal commerce write authority from this work.
- Growth owns commercial interpretation, recovery eligibility, next-best-action and experiments; it does not own payment truth or entitlement truth.
- Communication execution must independently enforce consent/purpose/channel/suppression.
- Architecture Registry owns the cross-system contract and ownership record.

## Current product state

### E Agora
Existing proven one-time Stripe reference. Preserve its product-specific activation/founder semantics locally. Conform reusable events to RP Commerce v1.

### Quartel Digital
Hardening underway. Target commercial model is one-time `quartel_365d`: successful purchase grants 365 days. Valid repurchase extends from `max(now, current expiry)`. Refund/dispute must not allow stale success to resurrect access.

### Biblioteca Estratégica
Studio/editorial runtime must not become subscriber/payment authority. A subscriber-facing runtime or explicitly approved commerce runtime is required before Stripe Billing integration.

### Além da Farda
Detailed financial-planning data stays product-local. Define entitlement boundary before adding recurring billing. Commerce/Growth must receive only minimized references/facts.

## Events agents may consume

RP Commerce v1 normalizes:
- checkout started/expired/abandoned_candidate;
- order created;
- payment pending/succeeded/failed/refunded/disputed;
- subscription started/active/past_due/recovered/canceled/ended;
- invoice paid/payment_failed;
- entitlement granted/revoked/expired.

Consumers must dedupe normalized events and tolerate ordering/reconciliation corrections.

## Prohibitions until a later ADR

Do not:
- create a canonical `rp_subject_id` from Stripe customer/email/phone/CPF;
- move all entitlement writes into RP OS;
- build Customer 360 person joins from provider ids;
- send WhatsApp/e-mail merely because checkout expired or invoice failed;
- store raw Stripe payload/card data in ecosystem events;
- make Biblioteca Studio own subscriptions;
- export Além da Farda's detailed financial data into commerce;
- create a shared production `rp-commerce-runtime` solely to reduce code duplication.

## Integration rule for agents

When a task touches checkout, payment, refund, dispute, subscription, billing, entitlement, abandonment, dunning or financial communication, first check the RP Commerce contract/ADR and state explicitly:
1. authoritative source;
2. normalized event emitted/consumed;
3. entitlement effect, if any;
4. identity/reference semantics;
5. communication authorization boundary.

If any of these are unclear, stop before creating a new cross-system ownership assumption.

## Current implementation posture

No production cutover is implied by the Registry work or Quartel hardening branch. Existing product runtimes remain operational truth until their own tested migration/cutover is approved.
