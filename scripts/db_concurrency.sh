#!/usr/bin/env bash
set -euo pipefail
# Invoked only by db_test.sh against its temporary Unix-domain socket.
: "${PGHOST:?Temporary database socket required}"
: "${PG_BIN:?Postgres binary path required}"
case "$PGHOST" in /tmp/carcar-db-test.*) ;; *) printf 'Refusing non-test database\n' >&2; exit 2;; esac
psql_bin="$PG_BIN/psql"
"$psql_bin" -X -v ON_ERROR_STOP=1 -q <<'SQL'
insert into auth.users values('30000000-0000-0000-0000-000000000001'),('30000000-0000-0000-0000-000000000002'),('30000000-0000-0000-0000-000000000003'),('30000000-0000-0000-0000-000000000004');
set role authenticated;
set request.jwt.claim.sub='30000000-0000-0000-0000-000000000001';
select public.create_vehicle_with_membership('Concurrency','111가1111','Race test') as v \gset
select public.create_invite_securely(:'v')->>'code' as code \gset
set request.jwt.claim.sub='30000000-0000-0000-0000-000000000002';
select public.redeem_invite_securely(:'code');
SQL
vehicle="$($psql_bin -X -At -v ON_ERROR_STOP=1 -c "select id from public.vehicles where owner_id='30000000-0000-0000-0000-000000000001'")"
pids=()
for i in $(seq 1 10); do
  user_suffix=$((i % 2 + 1))
  "$psql_bin" -X -v ON_ERROR_STOP=1 -q -v vehicle="$vehicle" -v user_id="30000000-0000-0000-0000-00000000000$user_suffix" -v spot="$i" >"$PGHOST/concurrent-$i.log" 2>&1 <<'SQL' &
set role authenticated;
select set_config('request.jwt.claim.sub',:'user_id',false);
select public.create_parking_record_and_set_latest(:'vehicle','B2','C',:'spot');
SQL
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
"$psql_bin" -X -v ON_ERROR_STOP=1 -q <<'SQL'
do $$begin
 if (select count(*) from public.parking_records where vehicle_id=(select id from public.vehicles where owner_id='30000000-0000-0000-0000-000000000001'))<>10 then raise exception 'FAIL: concurrent records lost'; end if;
 if not exists(select 1 from public.vehicles v where v.owner_id='30000000-0000-0000-0000-000000000001' and v.latest_parking_record_id=(select id from public.parking_records r where r.vehicle_id=v.id order by created_at desc limit 1)) then raise exception 'FAIL: pointer is not last committed serialized write'; end if;
 raise notice 'PASS: 10 parallel A/B writes preserve history and latest pointer';
end $$;
SQL
pids=()
for i in 1 2; do
 "$psql_bin" -X -v ON_ERROR_STOP=1 -q -v vehicle="$vehicle" >"$PGHOST/idempotent-$i.log" 2>&1 <<'SQL' &
set role authenticated;
set request.jwt.claim.sub='30000000-0000-0000-0000-000000000001';
select public.create_parking_record_and_set_latest(:'vehicle','B3','D','8','','40000000-0000-0000-0000-000000000001');
SQL
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
"$psql_bin" -X -v ON_ERROR_STOP=1 -q <<'SQL'
do $$begin
 if (select count(*) from public.parking_records where idempotency_key='40000000-0000-0000-0000-000000000001')<>1 then raise exception 'FAIL: concurrent retry duplicated'; end if;
 raise notice 'PASS: parallel identical retries create exactly one record';
end $$;
SQL
code="$($psql_bin -X -At -v ON_ERROR_STOP=1 -q -v vehicle="$vehicle" <<'SQL'
set role authenticated;
set request.jwt.claim.sub='30000000-0000-0000-0000-000000000001';
select public.create_invite_securely(:'vehicle')->>'code';
SQL
)"
pids=()
for i in 3 4; do
 "$psql_bin" -X -v ON_ERROR_STOP=1 -q -v code="$code" -v user_id="30000000-0000-0000-0000-00000000000$i" >"$PGHOST/invite-race-$i.log" 2>&1 <<'SQL' &
set role authenticated;
select set_config('request.jwt.claim.sub',:'user_id',false);
select public.redeem_invite_securely(:'code');
SQL
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
"$psql_bin" -X -v ON_ERROR_STOP=1 -q <<'SQL'
do $$begin
 if (select count(*) from public.vehicle_members where user_id in ('30000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000004'))<>1 then raise exception 'FAIL: single-use invite granted multiple memberships'; end if;
 if exists(select 1 from public.vehicle_invites where remaining_uses<0) then raise exception 'FAIL: invite underflow'; end if;
 raise notice 'PASS: parallel redemption consumes single-use invite exactly once';
end $$;
SQL
