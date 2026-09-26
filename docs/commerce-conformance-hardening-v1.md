# Commerce Conformance Hardening v1

Date: 2026-09-25
Status: **implementation mission — pre-production**
Base: `mobile/main`

## Objective

Bring Quartel Digital's existing Stripe/billing runtime into conformance with RP Commerce v1 while preserving its bank-first access architecture.

This mission must not deploy production, rotate secrets, activate the n8n workflow, or mutate production data.

## Current evidence

The current runtime already has:
- authenticated checkout creation;
- Stripe Checkout;
- webhook signature verification in n8n;
- provider event idempotency in DB/RPC design;
- service-role billing writes;
- read-only access projection to the app;
- reconciliation structures.

## Mandatory corrections

### 1. Freeze the current commercial offer

The approved offer is a **one-time purchase granting 365 days of Quartel Digital access**.

Historical monthly/annual recurring-subscription semantics must not silently drive new code.

Use an offer identifier such as `quartel_365d` rather than treating `anual` as a recurring subscription. Price remains environment/provider configuration; do not hard-code R$297 or R$397 into authoritative server logic.

### 2. Checkout semantics

Stripe Checkout remains `mode=payment` for the one-time 365-day offer.

The server must derive the provider Price ID from the approved server-side offer mapping. Client input selects only an allowed offer identifier.

Persist/emit enough source data to correlate:
- source checkout attempt;
- Stripe Checkout Session;
- recruta/product-local beneficiary reference;
- correlation id;
- immutable offer snapshot/version where the DB model supports it.

### 3. Do not equate completed with paid

`checkout.session.completed` must not automatically map to `paid`.

For synchronous card checkout, require Stripe session/payment status evidence equivalent to `payment_status=paid` before success.

Support asynchronous success/failure events if asynchronous methods are enabled later.

### 4. Add terminal adverse events

Handle and idempotently persist:
- refund;
- dispute;
- checkout expiration.

Refund/dispute must revoke or make access ineligible through the authoritative DB policy without deleting payment history.

A stale/replayed older success event must never resurrect access after refund/dispute.

### 5. Entitlement

A successful one-time purchase grants **365 days** of access from the authoritative grant instant according to DB policy.

Payment fact and entitlement/access fact remain distinct.

Do not let redirect/deep-link grant access. Existing gate revalidation remains.

### 6. Abandonment

`checkout.session.expired` records an expired checkout fact.

Do not send WhatsApp/e-mail from this workflow.

An abandonment/recovery candidate is a separate downstream decision and must be invalidated if payment later succeeds.

### 7. Communication

`billing_notificacoes_log` may record operational notification attempts, but it is not consent authority.

No new commercial recovery message may be sent by this mission.

## Required tests

- paid checkout grants one 365-day entitlement/access period;
- completed but unpaid checkout does not grant access;
- duplicate provider event is idempotent;
- expired checkout does not grant/revoke paid access;
- paid -> refund revokes access while preserving history;
- paid -> dispute revokes access while preserving history;
- paid -> refund/dispute -> stale paid replay does not resurrect access;
- client cannot choose arbitrary Price ID;
- client/deep-link cannot grant access;
- unauthorized recruta_id cannot create checkout;
- normalized amount remains integer minor units;
- no PII/raw Stripe payload enters RP Commerce projection.

## Deliverables

1. versioned DB migration(s), additive/reversible where practical;
2. checkout Edge Function hardening;
3. webhook normalization hardening;
4. DB/RPC transition hardening;
5. tests/fixtures for the above invariants;
6. updated Stripe integration documentation reflecting one-time 365-day access;
7. no deployment.

## Stop conditions

Stop and report instead of guessing if:
- current RPC definitions needed for safe mutation are not versioned/available;
- production schema differs materially from the audited baseline;
- a change would require destructive migration;
- refund/dispute semantics cannot be made monotonic with current schema;
- current Stripe provider configuration must be inspected using secrets/dashboard access.
