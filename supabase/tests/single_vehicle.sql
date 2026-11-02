\set ON_ERROR_STOP on
create function pg_temp.assert_true(value boolean,label text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users values('50000000-0000-0000-0000-000000000001'),('50000000-0000-0000-0000-000000000002'),('50000000-0000-0000-0000-000000000003');
select pg_temp.assert_true(private.normalize_vehicle_plate(E' １２３가-４５６７\t')='123가4567','NFKC whitespace and hyphen canonicalization');
select pg_temp.assert_true(private.normalize_vehicle_plate(' ab-123 ')='AB123','Latin case canonicalization');
set role anon;
do $$begin
 begin perform public.check_vehicle_plate('123가4567'); raise exception 'FAIL: anonymous availability'; exception when insufficient_privilege then raise notice 'PASS: anonymous availability denied'; end;
end $$;
set role authenticated;
set request.jwt.claim.sub='50000000-0000-0000-0000-000000000001';
select pg_temp.assert_true(public.check_vehicle_plate('１２３가-４５６７')='{"ok":true,"available":true}'::jsonb,'Available response contains only boolean');
select public.create_vehicle_with_membership('가족','１２３가-４５６７','차') as first_vehicle \gset
select set_config('test.first_vehicle',:'first_vehicle',false);
select pg_temp.assert_true((select plate_number='123가4567' from public.vehicles),'Stored plate is canonical');
select pg_temp.assert_true((select allowed_floors=array['F5','F4','F3','F2','F1','B1','B2','B3','B4','B5','B6'] from public.apartments),'New apartment floor defaults');
select public.create_invite_securely(:'first_vehicle')->>'code' as first_code \gset
select set_config('test.first_code',:'first_code',false);
select pg_temp.assert_true((public.redeem_invite_securely(:'first_code')->>'ok')::boolean,'Same vehicle valid invite no-op');
do $$begin
 begin perform public.create_vehicle_with_membership('가족','999가9999','차'); raise exception 'FAIL: second vehicle'; exception when raise_exception then if sqlerrm<>'already_has_vehicle' then raise; end if; raise notice 'PASS: second vehicle rejected'; end;
end $$;
set request.jwt.claim.sub='50000000-0000-0000-0000-000000000002';
select pg_temp.assert_true(public.check_vehicle_plate('123 가-4567')='{"ok":true,"available":false}'::jsonb,'Occupied response exposes no owner or vehicle ID');
select pg_temp.assert_true((select count(*)=0 from public.vehicles),'Availability does not grant vehicle read');
do $$begin
 begin perform public.create_vehicle_with_membership('가족','123 가4567','차'); raise exception 'FAIL: duplicate plate'; exception when unique_violation then if sqlerrm<>'plate_already_registered' then raise; end if; raise notice 'PASS: duplicate canonical plate rejected'; end;
 begin perform public.create_vehicle_with_membership('가족','🚘','차'); raise exception 'FAIL: invalid plate'; exception when invalid_parameter_value then if sqlerrm<>'invalid_plate' then raise; end if; raise notice 'PASS: invalid plate rejected on create'; end;
end $$;
select public.create_vehicle_with_membership('가족','서울12나3456','차') as second_vehicle \gset
select pg_temp.assert_true(public.redeem_invite_securely(:'first_code')='{"ok":false,"error":"already_has_vehicle"}'::jsonb,'Other vehicle invite rejected');
reset role;
select pg_temp.assert_true((select remaining_uses=1 from public.vehicle_invites where token_hash=encode(extensions.digest(:'first_code','sha256'),'hex')),'Rejected and same-car joins do not consume invite');
select pg_temp.assert_true((select count(*)=2 from public.apartments where owner_id::text like '50000000%'),'Failed create leaves no orphan apartment');
set role authenticated;
set request.jwt.claim.sub='50000000-0000-0000-0000-000000000003';
select pg_temp.assert_true(public.check_vehicle_plate(null)->>'error'='invalid_plate','Null plate rejected');
select pg_temp.assert_true(public.check_vehicle_plate(' - ')->>'error'='invalid_plate','Empty canonical plate rejected');
select pg_temp.assert_true(public.check_vehicle_plate(repeat('1',21))->>'error'='invalid_plate','Overlong canonical plate rejected');
select pg_temp.assert_true(public.check_vehicle_plate('12/345')->>'error'='invalid_plate','Unexpected punctuation rejected');
select public.check_vehicle_plate('999가9999') from generate_series(1,16);
select pg_temp.assert_true(public.check_vehicle_plate('999가9999')->>'error'='rate_limited','Availability rate limit includes invalid attempts');
select pg_temp.assert_true((public.redeem_invite_securely(:'first_code')->>'ok')::boolean,'Rejected invite remains redeemable by eligible account');
select pg_temp.assert_true(public.redeem_invite_securely(:'first_code')->>'error'='invalid_invite','Used invite remains invalid for same member');
reset role;
