# QD curriculum publication v1 — consumer conformance foundation

Server-side-only mirror of the canonical `quartel_curriculum_publication:v1` contract owned by RP OS.

This directory is intentionally under `supabase/functions/_shared/` so it is not bundled into the React Native learner client. Gate 5A provides only pure conformance helpers. It does **not** expose an HTTP receiver, transport, polling/sync, activation, learner-visible publication, or learner-state mutation.

The mirror preserves the producer contract invariants that matter before persistence: strict schema allowlists, supported artifact families, approved/published state, canonical JSON + SHA-256 verification, deterministic idempotency identity, source-version relation, quiz safety, explicit timezone timestamps, and deterministic release-manifest hashing.

The canonical producer implementation remains `gadelhajulio-crypto/recruta-padrao-os/packages/quartel-digital-publication-contract`. If the producer contract changes incompatibly, the QD consumer mirror must fail closed until a new contract schema version is implemented explicitly.
