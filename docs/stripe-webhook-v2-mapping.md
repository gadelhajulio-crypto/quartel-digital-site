# Stripe webhook -> Billing RPC v2 mapping

This is the normative mapping for the n8n/Stripe adapter. Production workflow activation is outside this PR.

| Stripe event | Preconditions/reconciliation | RPC event kind | Access mutation |
|---|---|---|---|
| checkout.session.completed | retrieve/reconcile Session; payment_status=paid; stable PaymentIntent id present | payment.succeeded | yes |
| checkout.session.completed | not paid | payment.pending | no grant |
| checkout.session.async_payment_succeeded | reconcile paid; stable PaymentIntent id | payment.succeeded | yes |
| checkout.session.async_payment_failed | stable payment object id | payment.failed | no grant |
| checkout.session.expired | no successful payment reconciled | checkout.expired | none |
| charge.refunded | resolve PaymentIntent/payment object id | payment.refunded | revoke |
| charge.dispute.created | resolve PaymentIntent/payment object id | payment.disputed | revoke |

## Required adapter order

1. Verify Stripe signature against raw request body.
2. Deduplicate provider event id.
3. Retrieve/reconcile the relevant Stripe object when payment truth is ambiguous.
4. Validate `metadata.source_system=quartel-digital` and `offer_id=quartel_365d`.
5. Resolve beneficiary/product-local recruit reference from trusted checkout metadata/client reference.
6. Pass stable provider payment object id separately from Stripe event id.
7. Call `rpc_billing_processar_evento_pagamento_v2` with service role.
8. Treat an RPC response with `transition_applied=false` as processed-but-superseded, not as an error.
9. Never send recovery communication in the webhook workflow.

## Amount

Amount is taken from the reconciled Stripe object in integer minor units. Never accept amount from client metadata.

## Important

A Checkout Session id is not interchangeable with a PaymentIntent id. The provider-payment monotonic state must key the stable payment object used across success/refund/dispute correlation.
