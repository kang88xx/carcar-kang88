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

# Each competing transaction holds its acquired locks briefly until commit.
# Test-only wrappers expose stable RPC outcomes without swallowing unexpected errors.
"$psql_bin" -X -v ON_ERROR_STOP=1 -q <<'SQL'
insert into auth.users select ('60000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,8) i;
create function public.test_registration_attempt(action text,value text) returns jsonb language plpgsql as $$
begin
 if action='create' then return jsonb_build_object('ok',true,'vehicle_id',public.create_vehicle_with_membership('Race',value,'차'));
 else return public.redeem_invite_securely(value); end if;
exception when unique_violation or raise_exception then
 if sqlerrm not in ('plate_already_registered','already_has_vehicle') then raise; end if;
 return jsonb_build_object('ok',false,'error',sqlerrm);
end $$;
set role authenticated;
set request.jwt.claim.sub='60000000-0000-0000-0000-000000000001';
select public.create_vehicle_with_membership('Race','601가1111','차');
set request.jwt.claim.sub='60000000-0000-0000-0000-000000000002';
select public.create_vehicle_with_membership('Race','602가1111','차');
SQL
race_invite() {
 "$psql_bin" -X -At -q -v ON_ERROR_STOP=1 -v owner="$1" <<'SQL'
set role authenticated;
select set_config('request.jwt.claim.sub',:'owner',false) \gset
select public.create_invite_securely((select id from public.vehicles where owner_id=auth.uid()))->>'code';
SQL
}
race_attempt() {
 "$psql_bin" -X -At -q -v ON_ERROR_STOP=1 -v user_id="$1" -v action="$2" -v value="$3" <<'SQL'
set role authenticated;
select set_config('request.jwt.claim.sub',:'user_id',false) \gset
begin;
select public.test_registration_attempt(:'action',:'value');
select pg_sleep(0.3);
commit;
SQL
}
code_a="$(race_invite 60000000-0000-0000-0000-000000000001)"
code_b="$(race_invite 60000000-0000-0000-0000-000000000002)"
race_attempt 60000000-0000-0000-0000-000000000003 create ' ６０３가-１１１１ ' >"$PGHOST/plate-a.log" & pid_a=$!
race_attempt 60000000-0000-0000-0000-000000000004 create '603가1111' >"$PGHOST/plate-b.log" & pid_b=$!
wait "$pid_a"; wait "$pid_b"
race_attempt 60000000-0000-0000-0000-000000000005 create '605가1111' >"$PGHOST/create-join-a.log" & pid_a=$!
race_attempt 60000000-0000-0000-0000-000000000005 join "$code_a" >"$PGHOST/create-join-b.log" & pid_b=$!
wait "$pid_a"; wait "$pid_b"
# Fresh invite: the create/join outcome may or may not have consumed the previous one.
code_c="$(race_invite 60000000-0000-0000-0000-000000000001)"
race_attempt 60000000-0000-0000-0000-000000000006 join "$code_c" >"$PGHOST/join-join-a.log" & pid_a=$!
race_attempt 60000000-0000-0000-0000-000000000006 join "$code_b" >"$PGHOST/join-join-b.log" & pid_b=$!
wait "$pid_a"; wait "$pid_b"
python3 - "$PGHOST" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
for name,error in [('plate','plate_already_registered'),('create-join','already_has_vehicle'),('join-join','already_has_vehicle')]:
    results=[json.loads(next(line for line in (root/f'{name}-{suffix}.log').read_text().splitlines() if line.startswith('{'))) for suffix in ('a','b')]
    assert sum(r['ok'] is True for r in results)==1, results
    assert [r.get('error') for r in results if not r['ok']]==[error],results
    print(f'PASS: {name} race returns exactly one success and {error}')
PY
"$psql_bin" -X -v ON_ERROR_STOP=1 -q -v code_a="$code_a" -v code_b="$code_b" -v code_c="$code_c" <<'SQL'
do $$begin
 if (select count(*) from public.vehicles where private.normalize_vehicle_plate(plate_number)='603가1111')<>1 then raise exception 'FAIL: canonical plate race'; end if;
 if (select count(*) from public.vehicle_members where user_id='60000000-0000-0000-0000-000000000005')<>1 then raise exception 'FAIL: create/join membership race'; end if;
 if (select count(*) from public.vehicle_members where user_id='60000000-0000-0000-0000-000000000006')<>1 then raise exception 'FAIL: join/join membership race'; end if;
 if exists(select 1 from public.apartments a where owner_id::text like '60000000%' and not exists(select 1 from public.vehicles v where v.apartment_id=a.id)) then raise exception 'FAIL: racing create leaves orphan apartment'; end if;
 raise notice 'PASS: races preserve canonical uniqueness, one membership and atomic apartment creation';
end $$;
select set_config('test.race_tokens', :'code_b'||','||:'code_c',false);
do $$begin
 if (select sum(remaining_uses) from public.vehicle_invites where token_hash in(select encode(extensions.digest(x,'sha256'),'hex') from unnest(string_to_array(current_setting('test.race_tokens'),',')) x))<>1 then raise exception 'FAIL: losing join consumed invite'; end if;
 raise notice 'PASS: rejected concurrent join leaves its invite unconsumed';
end $$;
drop function public.test_registration_attempt(text,text);
SQL

# Deterministically overlap deletion with a redemption holding its rate-limit row.
# Before the common user lock, deletion held the vehicle while cascading into
# this row, and redemption then waited for that same vehicle: a deadlock cycle.
"$psql_bin" -X -v ON_ERROR_STOP=1 -q <<'SQL'
insert into auth.users values('80000000-0000-0000-0000-000000000001');
set role authenticated;
set request.jwt.claim.sub='80000000-0000-0000-0000-000000000001';
select public.create_vehicle_with_membership('Delete race','800가1111','차');
reset role;
create function private.test_pause_redemption() returns trigger language plpgsql as $$
begin
 if new.user_id='80000000-0000-0000-0000-000000000001' and new.action='invite_redeem' then perform pg_sleep(1); end if;
 return new;
end $$;
create trigger test_pause_redemption after insert or update on private.rpc_limits for each row execute function private.test_pause_redemption();
SQL
delete_race_code="$(race_invite 80000000-0000-0000-0000-000000000001)"
"$psql_bin" -X -At -q -v ON_ERROR_STOP=1 -v code="$delete_race_code" >"$PGHOST/delete-redeem.log" 2>&1 <<'SQL' &
set application_name='carcar-delete-redeem-test';
set role authenticated;
set request.jwt.claim.sub='80000000-0000-0000-0000-000000000001';
select public.redeem_invite_securely(:'code');
SQL
redeem_pid=$!
paused=false
for attempt in $(seq 1 100); do
 if [[ "$("$psql_bin" -X -At -q -v ON_ERROR_STOP=1 -c "select exists(select 1 from pg_stat_activity where application_name='carcar-delete-redeem-test' and wait_event='PgSleep')")" == t ]]; then paused=true; break; fi
 sleep 0.02
done
[[ "$paused" == true ]] || { printf 'FAIL: redemption did not reach lock barrier\n' >&2; exit 1; }
"$psql_bin" -X -q -v ON_ERROR_STOP=1 >"$PGHOST/concurrent-delete.log" 2>&1 <<'SQL' &
set role authenticated;
set request.jwt.claim.sub='80000000-0000-0000-0000-000000000001';
select public.delete_my_account();
SQL
delete_pid=$!
if ! wait "$redeem_pid"; then cat "$PGHOST/delete-redeem.log" >&2; exit 1; fi
if ! wait "$delete_pid"; then cat "$PGHOST/concurrent-delete.log" >&2; exit 1; fi
python3 - "$PGHOST/delete-redeem.log" <<'PY'
import json,pathlib,sys
result=json.loads(next(line for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if line.startswith('{')))
assert result['ok'] is True,result
print('PASS: overlapping redemption and account deletion finish without deadlock')
PY
"$psql_bin" -X -q -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if exists(select 1 from auth.users where id='80000000-0000-0000-0000-000000000001')
 or exists(select 1 from public.vehicles where owner_id='80000000-0000-0000-0000-000000000001')
 or exists(select 1 from public.vehicle_members where user_id='80000000-0000-0000-0000-000000000001')
 or exists(select 1 from public.apartments where owner_id='80000000-0000-0000-0000-000000000001')
 or exists(select 1 from private.rpc_limits where user_id='80000000-0000-0000-0000-000000000001') then raise exception 'FAIL: concurrent deletion left account or owned data'; end if;
 raise notice 'PASS: concurrent deletion removes account, vehicle, apartment, membership and rate-limit rows';
end $$;
drop trigger test_pause_redemption on private.rpc_limits;
drop function private.test_pause_redemption();
SQL
