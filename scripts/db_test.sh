#!/usr/bin/env bash
set -euo pipefail
# Requires PostgreSQL 16+ server/client binaries; never connects to a remote DB.
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
pg_bin="${PG_BIN:-/usr/lib/postgresql/16/bin}"
if [[ ! -x "$pg_bin/initdb" ]]; then
  printf 'Set PG_BIN to a PostgreSQL 16+ bin directory. No remote database was touched.\n' >&2
  exit 2
fi
run_dir="$(mktemp -d /tmp/carcar-db-test.XXXXXX)"
cleanup() {
  "$pg_bin/pg_ctl" -D "$run_dir/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$run_dir"
}
trap cleanup EXIT
"$pg_bin/initdb" -D "$run_dir/data" -A trust --no-locale -E UTF8 >"$run_dir/init.log"
"$pg_bin/pg_ctl" -D "$run_dir/data" -l "$run_dir/server.log" -o "-k $run_dir -p 55439 -c listen_addresses=''" -w start >/dev/null
export PG_BIN="$pg_bin"
export PGHOST="$run_dir" PGPORT=55439 PGDATABASE=postgres
export PGOPTIONS="-c statement_timeout=15000 -c lock_timeout=10000"
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -q -f "$repo_dir/supabase/tests/bootstrap.sql"
for migration in "$repo_dir"/supabase/migrations/*.sql; do
  "$pg_bin/psql" -X -v ON_ERROR_STOP=1 -q -f "$migration"
done
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -q -f "$repo_dir/supabase/tests/security.sql"
"$repo_dir/scripts/db_concurrency.sh"
printf '\nPASS: schema migrations and database security regression suite\n'
