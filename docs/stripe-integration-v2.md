# Quartel Digital — Stripe Integration v2 (target)

Status: pre-production contract.

## Commercial model

Quartel Digital uses a one-time Stripe Checkout purchase for offer `quartel_365d`.

A successful verified purchase grants 365 days. If a recruit buys again while access is still active, the new 365-day period starts at the existing `vigente_fim`; if expired, it starts at processing time.

There is no automatic renewal in this model.

## Authority chain

```text
App -> authenticated Edge Function -> Stripe Checkout
Stripe -> verified webhook -> normalized event -> service-role RPC v2
RPC v2 -> payment history + provider-payment current state + access projection
App -> read-only billing status -> gate
```

Redirect/deep link never grants access.

## Required Stripe mapping

- completed + reconciled `payment_status=paid` -> `payment.succeeded`
- async payment succeeded -> `payment.succeeded`
- async payment failed -> `payment.failed`
- session expired -> `checkout.expired`
- charge refunded -> `payment.refunded`
- dispute created -> `payment.disputed`

The webhook adapter must supply the stable provider payment object id separately from the provider event id.

## Monotonicity

Event-id idempotency prevents duplicate event processing. `billing_provider_payment_state` additionally prevents a lower-precedence later/replayed event from resurrecting access after refund/dispute.

## Recovery

Checkout expiration is recorded only. This integration sends no abandonment/recovery message. Such action belongs downstream to governed Growth + communication authorization.
