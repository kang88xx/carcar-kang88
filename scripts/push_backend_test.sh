#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
pg_bin="${PG_BIN:-/usr/lib/postgresql/16/bin}"
[[ -x "$pg_bin/initdb" ]] || { echo 'Set PG_BIN to PostgreSQL 16+; no remote DB is touched.' >&2; exit 2; }
run_dir="$(mktemp -d /tmp/carcar-push-test.XXXXXX)"
cleanup() { "$pg_bin/pg_ctl" -D "$run_dir/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$run_dir"; }
trap cleanup EXIT
"$pg_bin/initdb" -D "$run_dir/data" -A trust --no-locale -E UTF8 > "$run_dir/init.log"
"$pg_bin/pg_ctl" -D "$run_dir/data" -l "$run_dir/server.log" -o "-k $run_dir -p 55440 -c listen_addresses=''" -w start >/dev/null
export PGHOST="$run_dir" PGPORT=55440 PGDATABASE=postgres
export PGOPTIONS='-c statement_timeout=15000 -c lock_timeout=10000'
"$pg_bin/psql" -X -q -v ON_ERROR_STOP=1 -f "$repo_dir/supabase/tests/bootstrap.sql"
for migration in "$repo_dir"/supabase/migrations/*.sql; do "$pg_bin/psql" -X -q -v ON_ERROR_STOP=1 -f "$migration"; done
"$pg_bin/psql" -X -q -v ON_ERROR_STOP=1 -f "$repo_dir/supabase/tests/push_security.sql"
# Two independent worker connections must never claim the same job.
"$pg_bin/psql" -X -q -v ON_ERROR_STOP=1 <<'SQL' > "$run_dir/fixture.txt"
insert into auth.users values('92000000-0000-0000-0000-00000000000a');
set role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-0000-0000-00000000000a',false);
select public.create_vehicle_with_membership('동시성','동시성차량','테스트') as vehicle \gset
select public.save_device_settings(gen_random_uuid(),'android',true,false,true,null,null,'UTC',120,'fcm',repeat('x',40)||n) from generate_series(1,20) n;
select public.create_parking_record_and_set_latest(:'vehicle','B1','A');
SQL
claim="set role service_role; select job_id from public.claim_push_jobs(10);"
"$pg_bin/psql" -X -qAt -v ON_ERROR_STOP=1 -c "$claim" > "$run_dir/claim-a" &
first=$!
"$pg_bin/psql" -X -qAt -v ON_ERROR_STOP=1 -c "$claim" > "$run_dir/claim-b" &
second=$!
wait "$first"
wait "$second"
python3 - "$run_dir/claim-a" "$run_dir/claim-b" <<'PY'
import pathlib,sys
rows=[line for path in sys.argv[1:] for line in pathlib.Path(path).read_text().splitlines() if line]
assert len(rows)==20 and len(set(rows))==20, 'Concurrent worker leases overlap or lost jobs'
print('PASS: simultaneous workers claim 20 distinct jobs without overlap')
PY
node --test "$repo_dir/supabase/tests/push_worker.test.mjs"
