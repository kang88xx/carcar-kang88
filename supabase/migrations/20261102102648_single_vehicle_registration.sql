begin;
-- A plate identifies a vehicle; only owner-issued invitations authorize access.
-- No legacy records are merged or removed. Resolve conflicting legacy data first.
create function private.normalize_vehicle_plate(p_plate_number text) returns text
language sql immutable strict set search_path='' as $$
 select regexp_replace(upper(normalize(p_plate_number, NFKC)), '[[:space:]-]+', '', 'g');
$$;
revoke all on function private.normalize_vehicle_plate(text) from public, anon, authenticated;

-- Lock while checking and installing constraints so concurrent writes cannot slip in.
lock table public.vehicles, public.vehicle_members in share row exclusive mode;
do $$ begin
 if exists(select 1 from public.vehicles group by private.normalize_vehicle_plate(plate_number) having count(*)>1) then
  raise exception 'single_vehicle_migration_duplicate_plates';
 end if;
 if exists(select 1 from public.vehicle_members group by user_id having count(*)>1) then
  raise exception 'single_vehicle_migration_multiple_memberships';
 end if;
end $$;
create unique index vehicles_canonical_plate_key on public.vehicles(private.normalize_vehicle_plate(plate_number));
alter table public.vehicle_members add constraint vehicle_members_one_vehicle_per_user unique(user_id);
alter table public.apartments alter column allowed_floors set default array['F5','F4','F3','F2','F1','B1','B2','B3','B4','B5','B6'];

create function public.check_vehicle_plate(p_plate_number text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); plate text:=private.normalize_vehicle_plate(p_plate_number);
begin
 if not private.take_rate_limit(u,'plate_check',20) then return jsonb_build_object('ok',false,'error','rate_limited'); end if;
 -- Permit regional Korean and Latin formats, without pretending to verify ownership.
 if plate is null or char_length(plate) not between 2 and 20 or plate !~ '^[0-9A-Z가-힣]+$' then
  return jsonb_build_object('ok',false,'error','invalid_plate');
 end if;
 return jsonb_build_object('ok',true,'available',not exists(select 1 from public.vehicles where private.normalize_vehicle_plate(plate_number)=plate));
end $$;

create or replace function public.create_vehicle_with_membership(p_apartment_name text,p_plate_number text,p_nickname text,p_profile_nickname text default '나')
returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); a uuid; v uuid; plate text:=private.normalize_vehicle_plate(p_plate_number); failed_constraint text;
begin
 if plate is null or char_length(plate) not between 2 and 20 or plate !~ '^[0-9A-Z가-힣]+$' then
  raise exception 'invalid_plate' using errcode='22023';
 end if;
 if p_apartment_name is null or char_length(btrim(p_apartment_name)) not between 1 and 60
 or p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 40
 or p_profile_nickname is null or char_length(btrim(p_profile_nickname)) not between 1 and 40 then
  raise exception '아파트 이름, 차량 번호, 별칭을 확인해 주세요.' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if exists(select 1 from public.vehicle_members where user_id=u) then raise exception 'already_has_vehicle'; end if;
 insert into public.profiles(id,nickname) values(u,btrim(p_profile_nickname)) on conflict(id) do nothing;
 insert into public.apartments(owner_id,name) values(u,btrim(p_apartment_name)) returning id into a;
 insert into public.vehicles(apartment_id,owner_id,plate_number,nickname) values(a,u,plate,btrim(p_nickname)) returning id into v;
 insert into public.vehicle_members(vehicle_id,user_id,role) values(v,u,'owner');
 return v;
exception when unique_violation then
 get stacked diagnostics failed_constraint=CONSTRAINT_NAME;
 if failed_constraint='vehicles_canonical_plate_key' then raise exception 'plate_already_registered' using errcode='23505'; end if;
 if failed_constraint='vehicle_members_one_vehicle_per_user' then raise exception 'already_has_vehicle'; end if;
 raise;
end $$;

create or replace function public.redeem_invite_securely(p_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); inv public.vehicle_invites; v uuid;
begin
 -- Serialize all membership-creating operations for this account before vehicle locks.
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if not private.take_rate_limit(u,'invite_redeem',10) then return jsonb_build_object('ok',false,'error','rate_limited'); end if;
 if p_code is null or btrim(p_code) !~ '^[0-9a-f]{48}$' then return jsonb_build_object('ok',false,'error','invalid_invite'); end if;
 select vehicle_id into v from public.vehicle_invites where token_hash=encode(extensions.digest(btrim(p_code),'sha256'),'hex');
 if v is null then return jsonb_build_object('ok',false,'error','invalid_invite'); end if;
 perform 1 from public.vehicles where id=v for update;
 select * into inv from public.vehicle_invites where token_hash=encode(extensions.digest(btrim(p_code),'sha256'),'hex') for update;
 if inv.id is null or inv.expires_at<=clock_timestamp() or inv.remaining_uses<1 then return jsonb_build_object('ok',false,'error','invalid_invite'); end if;
 if exists(select 1 from public.vehicle_members where user_id=u and vehicle_id<>inv.vehicle_id) then
  return jsonb_build_object('ok',false,'error','already_has_vehicle');
 end if;
 if public.is_vehicle_member(inv.vehicle_id) then return jsonb_build_object('ok',true,'vehicle_id',inv.vehicle_id); end if;
 insert into public.profiles(id,nickname) values(u,'가족') on conflict(id) do nothing;
 insert into public.vehicle_members(vehicle_id,user_id,role) values(inv.vehicle_id,u,'member');
 update public.vehicle_invites set remaining_uses=remaining_uses-1 where id=inv.id;
 return jsonb_build_object('ok',true,'vehicle_id',inv.vehicle_id);
end $$;
-- Keep account deletion in the same user -> vehicle -> dependent-row lock order.
-- Otherwise deleting auth.users may wait for invite rate-limit rows while holding
-- the vehicle lock that a concurrent redemption is waiting to acquire.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user();
begin
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 perform 1 from public.vehicles where owner_id=u order by id for update;
 delete from public.vehicles where owner_id=u;
 delete from public.apartments where owner_id=u;
 delete from public.vehicle_invites where created_by=u;
 delete from auth.users where id=u;
end $$;

revoke all on function public.check_vehicle_plate(text) from public,anon;
grant execute on function public.check_vehicle_plate(text) to authenticated;
commit;
