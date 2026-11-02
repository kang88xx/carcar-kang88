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
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -q -f "$repo_dir/supabase/tests/single_vehicle.sql"
"$repo_dir/scripts/db_concurrency.sh"
# Prove the new migration refuses legacy conflicts atomically, without deleting data.
for conflict in duplicate_plates multiple_memberships; do
  "$pg_bin/createdb" single_vehicle_preflight
  sed '/^create role /d' "$repo_dir/supabase/tests/bootstrap.sql" | "$pg_bin/psql" -X -d single_vehicle_preflight -v ON_ERROR_STOP=1 -q
  for migration in "$repo_dir"/supabase/migrations/*.sql; do
    [[ "$migration" == *single_vehicle_registration.sql ]] && break
    "$pg_bin/psql" -X -d single_vehicle_preflight -v ON_ERROR_STOP=1 -q -f "$migration"
  done
  "$pg_bin/psql" -X -d single_vehicle_preflight -v ON_ERROR_STOP=1 -q -v conflict="$conflict" <<'SQL'
insert into auth.users values('70000000-0000-0000-0000-000000000001'),('70000000-0000-0000-0000-000000000002');
set role authenticated;
set request.jwt.claim.sub='70000000-0000-0000-0000-000000000001';
select public.create_vehicle_with_membership('Legacy','700가1111','차');
select case when :'conflict'='duplicate_plates' then '70000000-0000-0000-0000-000000000002' else '70000000-0000-0000-0000-000000000001' end as second_user \gset
select set_config('request.jwt.claim.sub',:'second_user',false);
select public.create_vehicle_with_membership('Legacy',case when :'conflict'='duplicate_plates' then '７００가-１１１１' else '700가2222' end,'차');
SQL
  if "$pg_bin/psql" -X -d single_vehicle_preflight -v ON_ERROR_STOP=1 -q -f "$repo_dir/supabase/migrations/20261102102648_single_vehicle_registration.sql" >"$run_dir/preflight.log" 2>&1; then
    printf 'FAIL: conflicting legacy migration accepted\n' >&2; exit 1
  fi
  preflight_log="$(cat "$run_dir/preflight.log")"
  [[ "$preflight_log" == *"single_vehicle_migration_$conflict"* ]] || { cat "$run_dir/preflight.log" >&2; exit 1; }
  "$pg_bin/psql" -X -d single_vehicle_preflight -v ON_ERROR_STOP=1 -q <<'SQL'
do $$begin
 if (select count(*) from public.vehicles)<>2 or (select count(*) from public.vehicle_members)<>2 then raise exception 'FAIL: preflight deleted legacy data'; end if;
 if to_regprocedure('private.normalize_vehicle_plate(text)') is not null then raise exception 'FAIL: failed migration was partially applied'; end if;
end $$;
SQL
  "$pg_bin/dropdb" single_vehicle_preflight
  printf 'PASS: legacy %s migration fails closed and rolls back atomically\n' "$conflict"
done
printf '\nPASS: schema migrations and database security regression suite\n'
