\set ON_ERROR_STOP on
create function pg_temp.assert_true(value boolean,label text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-00000000000a'),
 ('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'),
 ('00000000-0000-0000-0000-00000000000d');
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
select public.create_vehicle_with_membership('우리 아파트','123가4567','우리 차','가족 A') as vehicle \gset
select set_config('test.vehicle',:'vehicle',false);
select pg_temp.assert_true((select count(*)=1 from public.vehicles),'Owner sees created vehicle');
select pg_temp.assert_true((select count(*)=1 from public.vehicle_members where role='owner'),'Owner membership created atomically');
select public.create_invite_securely(:'vehicle')->>'code' as code \gset
select pg_temp.assert_true(length(:'code')=48,'Invite has 192 random bits');
select public.create_parking_record_and_set_latest(:'vehicle','B2','C','24','기둥 옆','10000000-0000-0000-0000-000000000001')->>'id' as first_record \gset
select pg_temp.assert_true((select latest_parking_record_id=:'first_record' from public.vehicles where id=:'vehicle'),'Atomic latest record pointer');
select pg_temp.assert_true(public.create_parking_record_and_set_latest(:'vehicle','B2','C','24','기둥 옆','10000000-0000-0000-0000-000000000001')->>'id'=:'first_record','Duplicate save is idempotent');
select pg_temp.assert_true((select count(*)=1 from public.parking_records),'Duplicate creates no extra history');
do $$begin
 begin perform public.create_parking_record_and_set_latest(current_setting('test.vehicle')::uuid,'B1','A','','','10000000-0000-0000-0000-000000000001'); raise exception 'FAIL: conflicting retry accepted'; exception when invalid_parameter_value then raise notice 'PASS: conflicting idempotency payload rejected'; end;
 begin perform public.create_parking_record_and_set_latest(current_setting('test.vehicle')::uuid,'B99','A'); raise exception 'FAIL: invalid floor accepted'; exception when invalid_parameter_value then raise notice 'PASS: invalid floor rejected'; end;
 begin perform public.create_parking_record_and_set_latest(current_setting('test.vehicle')::uuid,'B1','Z'); raise exception 'FAIL: invalid zone accepted'; exception when invalid_parameter_value then raise notice 'PASS: invalid zone rejected'; end;
 begin perform public.create_parking_record_and_set_latest(current_setting('test.vehicle')::uuid,'B1','A',repeat('x',21)); raise exception 'FAIL: oversized spot accepted'; exception when invalid_parameter_value then raise notice 'PASS: oversized spot rejected'; end;
 begin perform public.create_parking_record_and_set_latest(current_setting('test.vehicle')::uuid,'B1','A','',repeat('x',501)); raise exception 'FAIL: oversized note accepted'; exception when invalid_parameter_value then raise notice 'PASS: oversized note rejected'; end;
 begin perform public.set_vehicle_icon(current_setting('test.vehicle')::uuid,'../../evil'); raise exception 'FAIL: invalid icon accepted'; exception when invalid_parameter_value then raise notice 'PASS: invalid icon rejected'; end;
 begin perform public.remove_member(current_setting('test.vehicle')::uuid,auth.uid()); raise exception 'FAIL: owner removed self'; exception when invalid_parameter_value then raise notice 'PASS: cannot remove owner'; end;
 begin insert into public.parking_records(vehicle_id,floor,zone,created_by) values(current_setting('test.vehicle')::uuid,'B1','A',auth.uid()); raise exception 'FAIL: direct parking write accepted'; exception when insufficient_privilege then raise notice 'PASS: direct parking write denied'; end;
 begin update public.vehicles set latest_parking_record_id=null; raise exception 'FAIL: direct pointer write accepted'; exception when insufficient_privilege then raise notice 'PASS: direct pointer write denied'; end;
 begin perform 1 from public.vehicle_invites; raise exception 'FAIL: invite hashes exposed'; exception when insufficient_privilege then raise notice 'PASS: invite hashes hidden'; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000c',false);
select pg_temp.assert_true((select count(*)=0 from public.vehicles where plate_number='123가4567'),'Plate number is not authorization');
select pg_temp.assert_true((select count(*)=0 from public.apartments),'Outsider cannot see apartment');
select pg_temp.assert_true((select count(*)=0 from public.parking_records),'Outsider cannot see parking history');
select pg_temp.assert_true((select count(*)=0 from public.vehicle_members),'Outsider cannot see family');
do $$begin
 begin perform public.create_parking_record_and_set_latest(current_setting('test.vehicle')::uuid,'B1','A'); raise exception 'FAIL: outsider saved parking'; exception when insufficient_privilege then raise notice 'PASS: outsider cannot save'; end;
 begin perform public.create_invite_securely(current_setting('test.vehicle')::uuid); raise exception 'FAIL: outsider issued invite'; exception when insufficient_privilege then raise notice 'PASS: outsider cannot invite'; end;
 begin perform public.list_vehicle_members(current_setting('test.vehicle')::uuid); raise exception 'FAIL: outsider listed members'; exception when insufficient_privilege then raise notice 'PASS: member-name RPC protects privacy'; end;
 begin perform public.remove_member(current_setting('test.vehicle')::uuid,'00000000-0000-0000-0000-00000000000a'); raise exception 'FAIL: outsider removed owner'; exception when insufficient_privilege then raise notice 'PASS: outsider cannot remove'; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000b',false);
select pg_temp.assert_true((public.redeem_invite_securely(:'code')->>'ok')::boolean,'Invited family member joins');
select pg_temp.assert_true((select count(*)=1 from public.vehicles),'Member can see vehicle');
select pg_temp.assert_true((select count(*)=1 from public.apartments),'Member can see apartment');
select pg_temp.assert_true((select count(*)=2 from public.list_vehicle_members(:'vehicle')),'Member can read family nicknames');
select pg_temp.assert_true((select count(*)=0 from public.profiles where id='00000000-0000-0000-0000-00000000000a'),'Direct profile reads restricted to self');
select public.create_parking_record_and_set_latest(:'vehicle','B3','D','7','가족 기록','10000000-0000-0000-0000-000000000002')->>'id' as second_record \gset
select pg_temp.assert_true((select latest_parking_record_id=:'second_record' from public.vehicles),'Member record becomes latest');
do $$begin
 begin perform public.set_vehicle_icon(current_setting('test.vehicle')::uuid,'car_red'); raise exception 'FAIL: member changed shared icon'; exception when insufficient_privilege then raise notice 'PASS: icon ownership enforced'; end;
 begin perform public.create_invite_securely(current_setting('test.vehicle')::uuid); raise exception 'FAIL: member created invite'; exception when insufficient_privilege then raise notice 'PASS: invite ownership enforced'; end;
end $$;
select public.save_device_settings('20000000-0000-0000-0000-000000000001','android');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
select pg_temp.assert_true((select count(*)=0 from public.device_settings),'Device settings independent across users');
select pg_temp.assert_true(public.create_parking_record_and_set_latest(:'vehicle','B2','C','24','기둥 옆','10000000-0000-0000-0000-000000000001')->>'id'=:'first_record','Old retry returns original record');
select pg_temp.assert_true((select latest_parking_record_id=:'second_record' from public.vehicles),'Old retry never overwrites newer parking');
select public.create_invite_securely(:'vehicle')->>'code' as expired_code \gset
reset role;
update public.vehicle_invites set expires_at=clock_timestamp()-interval '1 second' where token_hash=encode(extensions.digest(:'expired_code','sha256'),'hex');
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000c',false);
select pg_temp.assert_true(public.redeem_invite_securely(:'code')->>'error'='invalid_invite','Used invite cannot be redeemed again');
select pg_temp.assert_true(public.redeem_invite_securely(:'expired_code')->>'error'='invalid_invite','Expired invite rejected');
select pg_temp.assert_true(public.redeem_invite_securely('../wrong')->>'error'='invalid_invite','Malformed code rejected');
do $$begin for i in 1..7 loop perform public.redeem_invite_securely('invalid'); end loop; end $$;
select pg_temp.assert_true(public.redeem_invite_securely(repeat('a',48))->>'error'='rate_limited','Failed invite attempts persist and trigger rate limit');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
select public.update_apartment(:'vehicle','새 아파트',array['B1','B2','B3','B4','B5'],array['A','B','C','D','E']);
select public.create_parking_record_and_set_latest(:'vehicle','B5','A');
select pg_temp.assert_true((select name='새 아파트' from public.apartments),'Apartment configuration updated');
select public.set_vehicle_icon(:'vehicle','car_mint');
select pg_temp.assert_true((select icon_id='car_mint' from public.vehicles),'Shared icon updated');
select public.create_invite_securely(:'vehicle')->>'code' as revoked_code \gset
select public.remove_member(:'vehicle','00000000-0000-0000-0000-00000000000b');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000b',false);
select pg_temp.assert_true((select count(*)=0 from public.parking_records),'Removed member immediately loses read access');
select pg_temp.assert_true(public.redeem_invite_securely(:'revoked_code')->>'error'='invalid_invite','Outstanding invite revoked on member removal');
do $$begin
 begin perform public.create_parking_record_and_set_latest(current_setting('test.vehicle')::uuid,'B1','A'); raise exception 'FAIL: removed member saved'; exception when insufficient_privilege then raise notice 'PASS: removed member cannot save'; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
select public.create_invite_securely(:'vehicle')->>'code' as new_code \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000d',false);
select pg_temp.assert_true((public.redeem_invite_securely(:'new_code')->>'ok')::boolean,'Fresh owner invitation can grant membership');
select public.create_parking_record_and_set_latest(:'vehicle','B1','A','9','삭제 계정 기록');
select public.delete_my_account();
select pg_temp.assert_true((select count(*)=0 from public.vehicles),'Deleted account token cannot access vehicles');
do $$begin
 begin perform public.create_vehicle_with_membership('집','123가4567','차'); raise exception 'FAIL: deleted user token creates vehicle'; exception when insufficient_privilege then raise notice 'PASS: deleted account token rejected'; end;
end $$;
reset role;
select pg_temp.assert_true((select count(*)=1 from public.parking_records where created_by is null),'Deleted member records anonymized');
select pg_temp.assert_true(not exists(select 1 from auth.users where id='00000000-0000-0000-0000-00000000000d'),'Account removed');
select pg_temp.assert_true(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and has_function_privilege('anon',p.oid,'EXECUTE')),'No anonymous security-definer RPC access');
select pg_temp.assert_true(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity),'Every application table has RLS');
set role anon;
do $$begin
 begin perform public.create_vehicle_with_membership('집','123가4567','차'); raise exception 'FAIL: anon creates vehicle'; exception when insufficient_privilege then raise notice 'PASS: anonymous RPC denied'; end;
 begin perform 1 from public.vehicles; raise exception 'FAIL: anon table read'; exception when insufficient_privilege then raise notice 'PASS: anonymous table read denied'; end;
 begin perform public.is_vehicle_member(gen_random_uuid()); raise exception 'FAIL: anon membership helper'; exception when insufficient_privilege then raise notice 'PASS: anonymous membership helper denied despite hosted defaults'; end;
 begin perform public.is_vehicle_owner(gen_random_uuid()); raise exception 'FAIL: anon ownership helper'; exception when insufficient_privilege then raise notice 'PASS: anonymous ownership helper denied despite hosted defaults'; end;
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
select public.delete_my_account();
reset role;
select pg_temp.assert_true((select count(*)=0 from public.vehicles),'Owner account deletion removes owned vehicle');
select pg_temp.assert_true((select count(*)=0 from public.parking_records),'Owner account deletion removes vehicle history');
select pg_temp.assert_true((select count(*)=0 from public.apartments),'Owner account deletion removes owned apartment');
