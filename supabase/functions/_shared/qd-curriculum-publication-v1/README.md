# QD curriculum publication v1 — consumer foundation

Server-side-only consumer foundation for the canonical `quartel_curriculum_publication:v1` contract owned by RP OS.

This directory is intentionally under `supabase/functions/_shared/` so it is not bundled into the React Native learner client.

## Gate 5A

Gate 5A established:
- a fail-closed consumer conformance mirror;
- explicit `stable_source_id -> local_uuid` mapping schema;
- append-only artifact/release staging schema;
- deny-by-default learner/client access to staging.

The canonical producer implementation remains `gadelhajulio-crypto/recruta-padrao-os/packages/quartel-digital-publication-contract`.

## Gate 5B shadow-ingestion core

Gate 5B adds only a server-side shadow-ingestion core and staging adapter:
- envelopes are fully validated before any staging write;
- same source/version + same hash is `REPLAY`;
- same source/version + different hash is `CONFLICT`;
- lower source versions are `STALE`;
- higher source versions append as `NEWER`;
- release + release-membership persistence is one atomic database operation;
- persistence targets only `qd_curriculum_*` staging tables.

Gate 5B still does **not** provide:
- an HTTP/network receiver;
- a transport choice;
- producer authentication/authorization;
- polling or automatic synchronization;
- source mapping population;
- activation or rollback;
- learner-visible publication;
- mutation of modules, lessons, quizzes, progress, attempts, responses, XP, ranking, entitlement, identity, messaging, or other learner state.

The transport/auth boundary remains intentionally unresolved. No endpoint may be exposed until that security/architecture decision is made explicitly.

If the producer contract changes incompatibly, the consumer must fail closed until a new contract schema version is implemented explicitly.


## Gate 5C shadow receiver transport

Gate 5C adds a repository-only HTTP receiver implementation that remains disabled by default.

Security boundary:
- proposed transport: HTTPS POST;
- proposed producer authentication: integration-scoped HMAC-SHA256;
- signed inputs bind timestamp, nonce and SHA-256 of the exact raw request body;
- HMAC is verified before any nonce reservation or staging write;
- authenticated nonces are reserved atomically in a transport-only append-only ledger;
- a 300-second clock-skew window and 1 MiB request-size ceiling are enforced;
- key ids support bounded secret rotation;
- secrets remain runtime-only and are never stored in Git or this documentation.

Activation state:
- `supabase/config.toml` has `enabled = false` for `qd-curriculum-shadow-receiver`;
- runtime additionally requires `QD_CURRICULUM_RECEIVER_ENABLED=true`;
- no HMAC secret is provisioned;
- no producer signer is implemented or activated;
- Gate 5A/5B/5C migrations remain unapplied;
- no automatic synchronization or learner-visible activation exists.

Runtime configuration names, if a later approved gate activates shadow traffic:
- `QD_CURRICULUM_RECEIVER_ENABLED`;
- `QD_CURRICULUM_HMAC_KEYS_JSON`;
- standard server-side `SUPABASE_URL`;
- standard server-side `SUPABASE_SERVICE_ROLE_KEY`.

The HMAC keyring must contain only integration-specific secrets. Provider keys, learner JWTs, Supabase anon keys and Supabase service-role keys must never be reused as transport credentials.
