#!/bin/sh
set -eu

runner_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
run_id="${$}"
image="admin-contracts-pg17-pgtap-test:${run_id}"
container="admin-contracts-pg17-pgtap-test-${run_id}"

cleanup() {
  docker rm --force "$container" >/dev/null 2>&1 || true
  docker image rm --force "$image" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

docker build --pull --tag "$image" --file "$runner_dir/Dockerfile" "$runner_dir"
docker run --detach --rm \
  --name "$container" \
  --network none \
  --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=256m \
  --env POSTGRES_USER=runner_test \
  --env POSTGRES_PASSWORD=pg17_test_only_password \
  --env POSTGRES_DB=runner_test \
  "$image" >/dev/null

ready=0
attempt=0
while [ "$attempt" -lt 30 ]; do
  if docker exec "$container" pg_isready --username=runner_test --dbname=postgres >/dev/null 2>&1; then
    ready=1
    break
  fi
  attempt=$((attempt + 1))
  sleep 1
done

if [ "$ready" -ne 1 ]; then
  docker logs "$container"
  echo "PostgreSQL test container did not become ready." >&2
  exit 1
fi

if [ "$(docker exec "$container" psql \
  --username=runner_test \
  --dbname=postgres \
  --tuples-only \
  --no-align \
  --set=ON_ERROR_STOP=1 \
  --command="SELECT 1 FROM pg_database WHERE datname = 'runner_test'")" != "1" ]; then
  docker exec "$container" psql \
    --username=runner_test \
    --dbname=postgres \
    --set=ON_ERROR_STOP=1 \
    --command='CREATE DATABASE runner_test'
fi

docker exec --interactive "$container" psql \
  --username=runner_test \
  --dbname=runner_test \
  --set=ON_ERROR_STOP=1 <<'SQL'
SELECT version();
CREATE EXTENSION pgtap;
SELECT extversion FROM pg_extension WHERE extname = 'pgtap';
DO $$
BEGIN
  IF current_setting('server_version_num')::integer / 10000 <> 17 THEN
    RAISE EXCEPTION 'Expected PostgreSQL major version 17';
  END IF;
  IF (SELECT extversion FROM pg_extension WHERE extname = 'pgtap') <> '1.3.4' THEN
    RAISE EXCEPTION 'Expected pgTAP version 1.3.4';
  END IF;
END
$$;
SQL

docker exec --interactive "$container" psql \
  --username=runner_test \
  --dbname=runner_test \
  --set=ON_ERROR_STOP=1 < "$runner_dir/../admin_contracts_v2_fixture.sql"

docker exec --interactive "$container" psql \
  --username=runner_test \
  --dbname=runner_test \
  --set=ON_ERROR_STOP=1 < "$runner_dir/../../migrations/20260917001000_admin_contracts_v2.sql"

if ! test_output=$(docker exec --interactive "$container" psql \
  --username=runner_test \
  --dbname=runner_test \
  --set=ON_ERROR_STOP=1 < "$runner_dir/../admin_contracts_v2.test.sql" 2>&1); then
  printf '%s\n' "$test_output"
  exit 1
fi
printf '%s\n' "$test_output"
case "$test_output" in
  *"not ok"*|*"Looks like you planned"*)
    echo "pgTAP administrative contract tests failed." >&2
    exit 1
    ;;
esac

docker exec --interactive "$container" psql \
  --username=runner_test \
  --dbname=runner_test \
  --set=ON_ERROR_STOP=1 <<'SQL'
BEGIN;
DELETE FROM public.billing_pagamentos;
DELETE FROM public.billing_reconciliation_issues;
DELETE FROM public.billing_reconciliacao;
DELETE FROM public.billing_notificacoes_log;
DELETE FROM public.eventos_institucionais;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.v_admin_pagamentos_confirmados) <> 0 THEN
    RAISE EXCEPTION 'empty payments fixture is not empty';
  END IF;
  IF (SELECT count(*) FROM public.v_admin_alertas) <> 0 THEN
    RAISE EXCEPTION 'empty alerts fixture is not empty';
  END IF;
  IF (SELECT count(*) FROM public.v_admin_atividade_recente) <> 0 THEN
    RAISE EXCEPTION 'empty activity fixture is not empty';
  END IF;
END
$$;
ROLLBACK;
SQL

docker exec --interactive "$container" psql \
  --username=runner_test \
  --dbname=runner_test \
  --set=ON_ERROR_STOP=1 <<'SQL'
SET ROLE service_role;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.v_admin_pagamentos_confirmados) <> 3 THEN
    RAISE EXCEPTION 'service_role cannot read the payments view contract';
  END IF;
  IF (SELECT count(*) FROM public.v_admin_alertas) <> 5 THEN
    RAISE EXCEPTION 'service_role cannot read the alerts view contract';
  END IF;
  IF (SELECT count(*) FROM public.v_admin_atividade_recente) <> 2 THEN
    RAISE EXCEPTION 'service_role cannot read the activity view contract';
  END IF;
END
$$;
SQL

echo "PostgreSQL 17 and pgTAP 1.3.4 runner probe passed."
