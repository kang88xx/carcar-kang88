\set ON_ERROR_STOP on
begin;
create or replace function pg_temp.assert_true(value boolean,label text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users values ('60000000-0000-0000-0000-000000000001');
set role authenticated;
set request.jwt.claim.sub='60000000-0000-0000-0000-000000000001';
select public.create_vehicle_with_membership('옵션 검사','600가1234','차') as vehicle \gset
select set_config('test.options_vehicle', :'vehicle', true);
select pg_temp.assert_true((select allowed_zones=array['A','B','C','D','E','F','가','나','다','라','마','바'] from public.apartments),'New apartment zone defaults');
reset role;
update public.apartments set allowed_floors=array['F5','F4','F3','F2','F1','B1','B2','B3','B4','B5','B6'], allowed_zones=array['A','B','C','D','E'] where owner_id='60000000-0000-0000-0000-000000000001';
insert into public.apartments(owner_id,name,allowed_floors,allowed_zones) values
 ('60000000-0000-0000-0000-000000000001','initial',array['B1','B2','B3','B4'],array['Z']),
 ('60000000-0000-0000-0000-000000000001','custom',array['B6','F9'],array['가','Z']);
set role authenticated;
select public.create_parking_record_and_set_latest(:'vehicle','B6','E','','기존 가족 메모')->>'id' as old_record \gset
reset role;
\ir ../migrations/20261106034310_parking_option_defaults.sql
select pg_temp.assert_true((select allowed_floors=array['F1','F2','F3','F4','F5','B1','B2','B3','B4','B5'] and allowed_zones=array['A','B','C','D','E','F','가','나','다','라','마','바'] from public.apartments where name='옵션 검사'),'Known legacy defaults upgrade');
select pg_temp.assert_true((select allowed_floors=array['F1','F2','F3','F4','F5','B1','B2','B3','B4','B5'] and allowed_zones=array['Z'] from public.apartments where name='initial'),'Initial floors upgrade independently of custom zones');
select pg_temp.assert_true((select allowed_floors=array['B6','F9'] and allowed_zones=array['가','Z'] from public.apartments where name='custom'),'Custom settings survive');
select pg_temp.assert_true((select floor='B6' and note='기존 가족 메모' from public.parking_records where id=:'old_record'),'Old floor and memo survive');
select pg_temp.assert_true((select latest_parking_record_id=:'old_record' from public.vehicles where id=:'vehicle'),'Latest pointer survives');
select pg_temp.assert_true((select count(*)=1 from public.vehicle_members where vehicle_id=:'vehicle'),'Membership survives');
set role authenticated;
select pg_temp.assert_true(public.create_parking_record_and_set_latest(:'vehicle','F5','F')->>'zone'='F','F zone saves');
select pg_temp.assert_true(public.create_parking_record_and_set_latest(:'vehicle','B5','가')->>'zone'='가','가 zone saves');
select pg_temp.assert_true(public.create_parking_record_and_set_latest(:'vehicle','F1','바')->>'zone'='바','바 zone saves');
do $$begin
 begin perform public.create_parking_record_and_set_latest(current_setting('test.options_vehicle')::uuid,'B6','A'); raise exception 'FAIL: B6 accepted'; exception when invalid_parameter_value then raise notice 'PASS: B6 rejected for new records'; end;
end $$;
reset role;
rollback;
