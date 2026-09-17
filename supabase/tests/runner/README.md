# Disposable PostgreSQL 17 + pgTAP runner

From the repository root, run:

```sh
sh supabase/tests/runner/run.sh
```

The runner builds a temporary image from `postgres:17-alpine`, installs the
pinned pgTAP 1.3.4 release, and verifies PostgreSQL 17 plus the installed
extension. It starts a container on Docker's isolated `none` network, publishes
no host port, mounts no volume, and uses a test-only password. The exit trap
removes the temporary container and image on success, failure, or interruption.

This probe validates the disposable database and pgTAP installation. It does not
connect to Supabase, apply migrations, or touch any production database.
