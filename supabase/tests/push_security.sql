\set ON_ERROR_STOP on
create or replace function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin
 if v is distinct from true then raise exception 'FAIL: %',msg; end if; raise notice 'PASS: %',msg;
end $$;
insert into auth.users(id) values('90000000-0000-0000-0000-00000000000a'),('90000000-0000-0000-0000-00000000000b'),('90000000-0000-0000-0000-00000000000c');
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000a',false);
select public.create_vehicle_with_membership('알림 테스트','테스트차량','테스트') as vehicle \gset
select public.create_invite_securely(:'vehicle')->>'code' as invite \gset
select pg_temp.assert_true(public.get_my_device_settings('91000000-0000-0000-0000-00000000000a')->>'delivery_available'='false','Notification service defaults unavailable');
do $$begin
 begin perform public.save_device_settings(gen_random_uuid(),'ios',true,false,false,null,null,'Asia/Seoul',120,'apns',repeat('f',64)); raise exception 'FAIL: enabled unconfigured service'; exception when object_not_in_prerequisite_state then raise notice 'PASS: unconfigured delivery cannot be enabled'; end;
 begin perform public.set_push_delivery_available(true); raise exception 'FAIL: client toggles service'; exception when insufficient_privilege then raise notice 'PASS: client cannot enable delivery service'; end;
end $$;
reset role;
set role service_role;
select public.set_push_delivery_available(true);
reset role;
set role authenticated;
select public.save_device_settings('91000000-0000-0000-0000-00000000000a','ios',true,false,false,null,null,'Asia/Seoul',120,'apns',repeat('a',64));
select pg_temp.assert_true(public.get_my_device_settings('91000000-0000-0000-0000-00000000000a')->>'push_enabled'='true','Device explicit opt-in persists');
select pg_temp.assert_true(not(public.get_my_device_settings('91000000-0000-0000-0000-00000000000a')?'token'),'Settings response never includes provider token');
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000b',false);
select public.redeem_invite_securely(:'invite');
select public.save_device_settings('91000000-0000-0000-0000-00000000000b','android',true,false,false,null,null,'Asia/Seoul',120,'fcm',repeat('b',64));
select pg_temp.assert_true(public.get_my_device_settings('91000000-0000-0000-0000-00000000000a')->>'push_enabled'='false','Other user installation settings cannot be read');
-- A temporary server outage must not trap independent device preferences.
reset role;
select revision as previous_revision from private.push_devices where device_id=(select id from public.device_settings where user_id='90000000-0000-0000-0000-00000000000b') \gset
set role service_role;
select public.set_push_delivery_available(false);
reset role;
set role authenticated;
select public.save_device_settings('91000000-0000-0000-0000-00000000000b','android',true,true,false,'22:00','07:00','Asia/Seoul',240);
select pg_temp.assert_true(
 public.get_my_device_settings('91000000-0000-0000-0000-00000000000b') @> '{"push_enabled":true,"delivery_available":false,"live_enabled":true,"quiet_start":"22:00:00","quiet_end":"07:00:00","preferred_live_minutes":240}'::jsonb,
 'Existing enabled device can change live and quiet preferences while service unavailable');
select public.save_device_settings('91000000-0000-0000-0000-0000000000bb','android');
do $$begin
 begin perform public.save_device_settings('91000000-0000-0000-0000-00000000000b','android',true,false,false,null,null,'Asia/Seoul',120,'fcm',repeat('e',64)); raise exception 'FAIL: new token during outage'; exception when object_not_in_prerequisite_state then raise notice 'PASS: existing device cannot bind new token while unavailable'; end;
 begin perform public.save_device_settings('91000000-0000-0000-0000-00000000000b','android',true,false,false,null,null,'Asia/Seoul',120,'fcm'); raise exception 'FAIL: provider registration during outage'; exception when object_not_in_prerequisite_state then raise notice 'PASS: provider registration blocked while unavailable'; end;
 begin perform public.save_device_settings('91000000-0000-0000-0000-0000000000bb','android',true,false,false,null,null,'Asia/Seoul',120,'fcm',repeat('e',64)); raise exception 'FAIL: enable disabled device during outage'; exception when object_not_in_prerequisite_state then raise notice 'PASS: false-to-true activation blocked while unavailable'; end;
end $$;
reset role;
select pg_temp.assert_true((select revision=:'previous_revision'::uuid and token=repeat('b',64) from private.push_devices where device_id=(select id from public.device_settings where user_id='90000000-0000-0000-0000-00000000000b' and installation_id='91000000-0000-0000-0000-00000000000b')),'Independent preference save preserves original token binding');
set role authenticated;
select public.save_device_settings('91000000-0000-0000-0000-00000000000b','android',false,true,false,'22:00','07:00','Asia/Seoul',240);
select pg_temp.assert_true(public.get_my_device_settings('91000000-0000-0000-0000-00000000000b')->>'push_enabled'='false','Notification opt-out remains available during outage');
reset role;
-- Remove only the extra disabled fixture before single-device legacy scenarios.
delete from public.device_settings where user_id='90000000-0000-0000-0000-00000000000b' and installation_id='91000000-0000-0000-0000-0000000000bb';
set role service_role;
select public.set_push_delivery_available(true);
reset role;
set role authenticated;
select public.save_device_settings('91000000-0000-0000-0000-00000000000b','android',true,false,false,null,null,'Asia/Seoul',120,'fcm',repeat('b',64));

do $$begin
 begin perform 1 from private.push_devices; raise exception 'FAIL: token read'; exception when insufficient_privilege then raise notice 'PASS: authenticated cannot read push tokens'; end;
 begin perform public.claim_push_jobs(10); raise exception 'FAIL: public claim'; exception when insufficient_privilege then raise notice 'PASS: app cannot invoke worker claim'; end;
 begin insert into public.device_settings(user_id,installation_id,platform) values(auth.uid(),gen_random_uuid(),'ios'); raise exception 'FAIL: direct settings insert'; exception when insufficient_privilege then raise notice 'PASS: direct settings writes denied'; end;
 begin perform public.save_device_settings(gen_random_uuid(),'ios',true); raise exception 'FAIL: enabled without token'; exception when invalid_parameter_value then raise notice 'PASS: enabling without device token rejected'; end;
 begin perform public.save_device_settings(gen_random_uuid(),'ios',false,false,false,'22:00','22:00'); raise exception 'FAIL: equal quiet times'; exception when invalid_parameter_value then raise notice 'PASS: equal quiet times rejected'; end;
 begin perform public.save_device_settings(gen_random_uuid(),'ios',false,false,false,null,null,'Invalid/Zone'); raise exception 'FAIL: invalid timezone'; exception when invalid_parameter_value then raise notice 'PASS: invalid IANA timezone rejected'; end;
 begin perform public.save_device_settings(gen_random_uuid(),'ios',true,false,false,null,null,'Asia/Seoul',120,'apns','../../token'); raise exception 'FAIL: malformed token'; exception when invalid_parameter_value then raise notice 'PASS: malformed token rejected'; end;
 begin perform public.save_device_settings(gen_random_uuid(),'ios',true,false,false,null,null,'Asia/Seoul',120,'apns',repeat('a',64)); raise exception 'FAIL: steal token'; exception when unique_violation then raise notice 'PASS: another account cannot claim registered token'; end;
end $$;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000c',false);
select public.save_device_settings('91000000-0000-0000-0000-00000000000c','android',true,false,false,null,null,'Asia/Seoul',120,'fcm',repeat('c',64));
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000a',false);
select public.create_parking_record_and_set_latest(:'vehicle','B1','A','','','93000000-0000-0000-0000-000000000001')->>'id' as record \gset
select public.create_parking_record_and_set_latest(:'vehicle','B1','A','','','93000000-0000-0000-0000-000000000001');
reset role;
select pg_temp.assert_true((select count(*)=1 from private.push_outbox where record_id=:'record'),'Only opted-in family member queued, own and outsider excluded');
select pg_temp.assert_true(private.push_is_quiet('22:00','07:00','Asia/Seoul','2026-11-02 14:00Z'),'Quiet interval crosses midnight');
select pg_temp.assert_true(private.push_is_quiet('22:00','07:00','Asia/Seoul','2026-11-01 22:00Z')=false,'Quiet end boundary is exclusive');
select pg_temp.assert_true(private.push_is_quiet('09:00','18:00','Asia/Seoul','2026-11-02 00:00Z'),'Daytime quiet start is inclusive');
set role service_role;
select * from public.claim_push_jobs(10) \gset
select pg_temp.assert_true((select count(*)=0 from public.claim_push_jobs(10)),'Leased job cannot be claimed twice');
select pg_temp.assert_true(public.prepare_push_delivery(:'job_id',gen_random_uuid()) is null,'Wrong worker lease cannot read token');
select pg_temp.assert_true(public.prepare_push_delivery(:'job_id',:'lease_token')->>'provider'='fcm','Worker rechecks and resolves eligible delivery');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000a',false);
select public.remove_member(:'vehicle','90000000-0000-0000-0000-00000000000b');
reset role;
set role service_role;
select pg_temp.assert_true(public.prepare_push_delivery(:'job_id',:'lease_token') is null,'Removal after claim prevents provider dispatch');
select pg_temp.assert_true(not public.finish_push_job(:'job_id',:'lease_token','sent'),'Skipped lease cannot later mark sent');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000a',false);
select public.create_invite_securely(:'vehicle')->>'code' as invite2 \gset
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000b',false);
select public.redeem_invite_securely(:'invite2');
select public.save_device_settings('91000000-0000-0000-0000-00000000000b','android',true,true,true,null,null,'Asia/Seoul',240);
select public.create_parking_record_and_set_latest(:'vehicle','B2','B')->>'id' as own_record \gset
reset role;
select pg_temp.assert_true((select count(*)=2 from private.push_outbox where record_id=:'own_record'),'Own-record opt-in independently adds own device');
-- Isolate member job to exercise retries, token rotation and logout boundaries.
update private.push_outbox set state='skipped' where device_id=(select id from public.device_settings where user_id='90000000-0000-0000-0000-00000000000a');
set role service_role;
select * from public.claim_push_jobs(1) \gset
select pg_temp.assert_true(public.finish_push_job(:'job_id',:'lease_token','retry',1),'Provider retry returns leased job to queue');
select pg_temp.assert_true((select count(*)=0 from public.claim_push_jobs(1)),'Retry delay is bounded below, no immediate loop');
reset role;
update private.push_outbox set available_at=clock_timestamp()-interval '1 second' where id=:'job_id';
set role service_role;
select * from public.claim_push_jobs(1) \gset
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000b',false);
select public.save_device_settings('91000000-0000-0000-0000-00000000000b','android',true,true,true,null,null,'Asia/Seoul',240,'fcm',repeat('d',64));
reset role;
set role service_role;
select pg_temp.assert_true(public.finish_push_job(:'job_id',:'lease_token','invalid_token'),'Old delivery rejection is recorded');
reset role;
select pg_temp.assert_true((select token=repeat('d',64) from private.push_devices where device_id=(select id from public.device_settings where user_id='90000000-0000-0000-0000-00000000000b')),'Stale rejection cannot delete rotated token');
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000b',false);
select public.create_parking_record_and_set_latest(:'vehicle','B3','C')->>'id' as lease_record \gset
reset role;
update private.push_outbox set state='skipped' where device_id=(select id from public.device_settings where user_id='90000000-0000-0000-0000-00000000000a');
set role service_role;
select * from public.claim_push_jobs(1) \gset
select :'lease_token' as previous_lease \gset
reset role;
update private.push_outbox set lease_until=clock_timestamp()-interval '1 second' where id=:'job_id';
set role service_role;
select * from public.claim_push_jobs(1) \gset
select pg_temp.assert_true(:'lease_token'<>:'previous_lease','Abandoned worker lease is replaced');
select pg_temp.assert_true(not public.finish_push_job(:'job_id',:'previous_lease','sent'),'Previous worker cannot acknowledge replacement lease');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000b',false);
select public.save_device_settings('91000000-0000-0000-0000-00000000000b','android',true,true,true,
 ((clock_timestamp() at time zone 'Asia/Seoul')-interval '1 minute')::time,
 ((clock_timestamp() at time zone 'Asia/Seoul')+interval '1 hour')::time,'Asia/Seoul',240);
reset role;
set role service_role;
select pg_temp.assert_true(public.prepare_push_delivery(:'job_id',:'lease_token') is null,'Quiet policy changed after claim is rechecked before send');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000a',false);
select public.create_parking_record_and_set_latest(:'vehicle','B4','D')->>'id' as quiet_record \gset
reset role;
select pg_temp.assert_true(not exists(select 1 from private.push_outbox where record_id=:'quiet_record'),'No jobs are queued during recipient quiet hours');
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000b',false);
select public.save_device_settings('91000000-0000-0000-0000-00000000000b','android',true,true,true,null,null,'Asia/Seoul',240);
select public.create_parking_record_and_set_latest(:'vehicle','B3','C')->>'id' as retry_record \gset
reset role;
update private.push_outbox set state='skipped' where device_id=(select id from public.device_settings where user_id='90000000-0000-0000-0000-00000000000a');
set role service_role;
select * from public.claim_push_jobs(1) \gset
reset role;
update private.push_outbox set attempts=6,lease_until=clock_timestamp()-interval '1 second' where id=:'job_id';
set role service_role;
select pg_temp.assert_true((select count(*)=0 from public.claim_push_jobs(1)),'Crashed final attempt cannot retry indefinitely');
reset role;
select pg_temp.assert_true((select state='dead' from private.push_outbox where id=:'job_id'),'Exhausted lease becomes terminal');
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000b',false);
select public.create_parking_record_and_set_latest(:'vehicle','B4','D')->>'id' as logout_record \gset
select public.unregister_push_device('91000000-0000-0000-0000-00000000000b');
reset role;
select pg_temp.assert_true(not exists(select 1 from private.push_devices where device_id=(select id from public.device_settings where user_id='90000000-0000-0000-0000-00000000000b')),'Logout removes device token');
select pg_temp.assert_true(not exists(select 1 from private.push_outbox j join public.device_settings d on d.id=j.device_id where d.user_id='90000000-0000-0000-0000-00000000000b' and j.state in ('pending','processing')),'Logout cancels queued and leased deliveries');
select pg_temp.assert_true((select live_enabled and preferred_live_minutes=240 from public.device_settings where user_id='90000000-0000-0000-0000-00000000000b'),'Unregister preserves independent finding-display preference');
-- Every active job is expired without sending after the one-hour retention window.
update private.push_outbox set created_at=clock_timestamp()-interval '2 hours' where state in ('pending','processing');
set role service_role;
select pg_temp.assert_true((select count(*)=0 from public.claim_push_jobs(20)),'Expired notification is never claimed');
reset role;
set role anon;
do $$begin
 begin perform public.get_my_device_settings(gen_random_uuid()); raise exception 'FAIL: anonymous settings'; exception when insufficient_privilege then raise notice 'PASS: anonymous settings denied'; end;
 begin perform public.prepare_push_delivery(gen_random_uuid(),gen_random_uuid()); raise exception 'FAIL: anonymous worker'; exception when insufficient_privilege then raise notice 'PASS: anonymous worker denied'; end;
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000b',false);
select public.delete_my_account();
reset role;
select pg_temp.assert_true(not exists(select 1 from public.device_settings where user_id='90000000-0000-0000-0000-00000000000b'),'Account deletion cascades device settings and token');
set role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-00000000000a',false);
select public.delete_my_account();
reset role;
select pg_temp.assert_true((select count(*)=0 from private.push_outbox),'Vehicle deletion removes notification jobs');
delete from auth.users where id='90000000-0000-0000-0000-00000000000c';
