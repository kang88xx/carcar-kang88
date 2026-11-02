-- Transactional application API. No external services or paid infrastructure.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create schema if not exists extensions;
alter extension pgcrypto set schema extensions;

alter table public.parking_records add column idempotency_key uuid;
create unique index parking_idempotency on public.parking_records(vehicle_id, created_by, idempotency_key);
alter table public.parking_records alter column created_by drop not null;
alter table public.parking_records drop constraint parking_records_created_by_fkey;
alter table public.parking_records add constraint parking_records_created_by_fkey foreign key(created_by) references auth.users(id) on delete set null;
alter table public.profiles add constraint profile_nickname_length check (char_length(nickname) <= 40);
alter table public.device_settings add constraint quiet_hours_pair check ((quiet_start is null) = (quiet_end is null));
create index vehicles_apartment_idx on public.vehicles(apartment_id);
create index vehicles_owner_idx on public.vehicles(owner_id);
create index apartments_owner_idx on public.apartments(owner_id);
create index invites_vehicle_idx on public.vehicle_invites(vehicle_id);

create table private.rpc_limits (
 user_id uuid not null references auth.users(id) on delete cascade,
 action text not null,
 window_started timestamptz not null,
 attempts integer not null,
 primary key(user_id,action)
);
alter table private.rpc_limits enable row level security;

create function private.require_user() returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid := auth.uid();
begin
 if u is null or not exists(select 1 from auth.users where id=u) then
  raise exception '로그인이 필요합니다.' using errcode='42501';
 end if;
 return u;
end $$;

create function private.take_rate_limit(p_user uuid,p_action text,p_max integer) returns boolean
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 insert into private.rpc_limits values(p_user,p_action,clock_timestamp(),1)
 on conflict(user_id,action) do update set
 attempts=case when private.rpc_limits.window_started < clock_timestamp()-interval '10 minutes' then 1 else private.rpc_limits.attempts+1 end,
 window_started=case when private.rpc_limits.window_started < clock_timestamp()-interval '10 minutes' then clock_timestamp() else private.rpc_limits.window_started end
 returning attempts into n;
 return n <= p_max;
end $$;

create function public.create_vehicle_with_membership(p_apartment_name text,p_plate_number text,p_nickname text,p_profile_nickname text default '나')
returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); a uuid; v uuid;
begin
 if p_apartment_name is null or char_length(btrim(p_apartment_name)) not between 1 and 60
 or p_plate_number is null or char_length(btrim(p_plate_number)) not between 2 and 20
 or p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 40
 or p_profile_nickname is null or char_length(btrim(p_profile_nickname)) not between 1 and 40 then
  raise exception '아파트 이름, 차량 번호, 별칭을 확인해 주세요.' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text, 0));
 if (select count(*) from public.vehicles where owner_id=u)>=10 then raise exception '차량은 최대 10대까지 등록할 수 있습니다.'; end if;
 insert into public.profiles(id,nickname) values(u,btrim(p_profile_nickname)) on conflict(id) do nothing;
 insert into public.apartments(owner_id,name) values(u,btrim(p_apartment_name)) returning id into a;
 insert into public.vehicles(apartment_id,owner_id,plate_number,nickname) values(a,u,btrim(p_plate_number),btrim(p_nickname)) returning id into v;
 insert into public.vehicle_members(vehicle_id,user_id,role) values(v,u,'owner');
 return v;
end $$;

create function public.create_invite_securely(p_vehicle_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); code text; expires timestamptz:=clock_timestamp()+interval '24 hours';
begin
 perform 1 from public.vehicles where id=p_vehicle_id for update;
 if not public.is_vehicle_owner(p_vehicle_id) then raise exception '차량 소유자만 초대할 수 있습니다.' using errcode='42501'; end if;
 if not private.take_rate_limit(u,'invite_issue',10) then return jsonb_build_object('ok',false,'error','rate_limited'); end if;
 code:=encode(extensions.gen_random_bytes(24),'hex');
 insert into public.vehicle_invites(vehicle_id,token_hash,expires_at,created_by)
 values(p_vehicle_id,encode(extensions.digest(code,'sha256'),'hex'),expires,u);
 return jsonb_build_object('ok',true,'code',code,'expires_at',expires);
end $$;

create function public.redeem_invite_securely(p_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); inv public.vehicle_invites; v uuid;
begin
 -- Return errors, never raise after charging: failed attempts must commit.
 if not private.take_rate_limit(u,'invite_redeem',10) then return jsonb_build_object('ok',false,'error','rate_limited'); end if;
 if p_code is null or btrim(p_code) !~ '^[0-9a-f]{48}$' then return jsonb_build_object('ok',false,'error','invalid_invite'); end if;
 select vehicle_id into v from public.vehicle_invites where token_hash=encode(extensions.digest(btrim(p_code),'sha256'),'hex');
 if v is null then return jsonb_build_object('ok',false,'error','invalid_invite'); end if;
 -- Same lock order as membership removal and parking writes.
 perform 1 from public.vehicles where id=v for update;
 select * into inv from public.vehicle_invites where token_hash=encode(extensions.digest(btrim(p_code),'sha256'),'hex') for update;
 if inv.id is null or inv.expires_at <= clock_timestamp() or inv.remaining_uses < 1 then return jsonb_build_object('ok',false,'error','invalid_invite'); end if;
 if public.is_vehicle_member(inv.vehicle_id) then return jsonb_build_object('ok',true,'vehicle_id',inv.vehicle_id); end if;
 insert into public.profiles(id,nickname) values(u,'가족') on conflict(id) do nothing;
 insert into public.vehicle_members(vehicle_id,user_id,role) values(inv.vehicle_id,u,'member');
 update public.vehicle_invites set remaining_uses=remaining_uses-1 where id=inv.id;
 return jsonb_build_object('ok',true,'vehicle_id',inv.vehicle_id);
end $$;

create function public.create_parking_record_and_set_latest(p_vehicle_id uuid,p_floor text,p_zone text,p_spot text default '',p_note text default '',p_idempotency_key uuid default gen_random_uuid())
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); a public.apartments; v public.vehicles; r public.parking_records;
begin
 select * into v from public.vehicles where id=p_vehicle_id for update;
 if not public.is_vehicle_member(p_vehicle_id) then raise exception '차량 구성원만 기록할 수 있습니다.' using errcode='42501'; end if;
 select * into a from public.apartments where id=v.apartment_id;
 if p_idempotency_key is null or p_floor is null or not(p_floor=any(a.allowed_floors))
 or p_zone is null or not(p_zone=any(a.allowed_zones)) or p_spot is null or char_length(p_spot)>20
 or p_note is null or char_length(p_note)>500 then raise exception '주차 위치 입력값을 확인해 주세요.' using errcode='22023'; end if;
 select * into r from public.parking_records where vehicle_id=p_vehicle_id and created_by=u and idempotency_key=p_idempotency_key;
 if r.id is not null then
  if (r.floor,r.zone,r.spot,r.note) is distinct from (p_floor,p_zone,btrim(p_spot),btrim(p_note)) then raise exception '같은 저장 요청의 내용이 변경되었습니다.' using errcode='22023'; end if;
  return to_jsonb(r);
 end if;
 insert into public.parking_records(vehicle_id,floor,zone,spot,note,created_by,created_at,idempotency_key)
 values(p_vehicle_id,p_floor,p_zone,btrim(p_spot),btrim(p_note),u,clock_timestamp(),p_idempotency_key) returning * into r;
 update public.vehicles set latest_parking_record_id=r.id where id=p_vehicle_id;
 return to_jsonb(r);
end $$;

create function private.check_latest_vehicle() returns trigger language plpgsql set search_path='' as $$
begin
 if new.latest_parking_record_id is not null and not exists(select 1 from public.parking_records where id=new.latest_parking_record_id and vehicle_id=new.id) then raise exception 'Latest parking record must belong to the vehicle.'; end if;
 return new;
end $$;
create trigger validate_latest_vehicle before insert or update of latest_parking_record_id on public.vehicles for each row execute function private.check_latest_vehicle();

create function public.list_vehicle_members(p_vehicle_id uuid)
returns table(user_id uuid,nickname text,role text,joined_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
 perform private.require_user();
 if not public.is_vehicle_member(p_vehicle_id) then raise exception '차량 구성원만 조회할 수 있습니다.' using errcode='42501'; end if;
 return query select m.user_id,coalesce(nullif(p.nickname,''),'가족'),m.role,m.joined_at from public.vehicle_members m left join public.profiles p on p.id=m.user_id where m.vehicle_id=p_vehicle_id order by m.joined_at,m.user_id;
end $$;

create function public.set_vehicle_icon(p_vehicle_id uuid,p_icon_id text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.require_user();
 perform 1 from public.vehicles where id=p_vehicle_id for update;
 if not public.is_vehicle_owner(p_vehicle_id) then raise exception '차량 소유자만 변경할 수 있습니다.' using errcode='42501'; end if;
 if p_icon_id is null or p_icon_id not in ('car_blue','car_black','car_white','car_gold','car_mint','car_purple','car_red','car_gray') then raise exception '지원하지 않는 차량 아이콘입니다.' using errcode='22023'; end if;
 update public.vehicles set icon_id=p_icon_id where id=p_vehicle_id;
end $$;

create function public.remove_member(p_vehicle_id uuid,p_user_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.require_user();
 perform 1 from public.vehicles where id=p_vehicle_id for update;
 if not public.is_vehicle_owner(p_vehicle_id) then raise exception '차량 소유자만 구성원을 관리할 수 있습니다.' using errcode='42501'; end if;
 if p_user_id=auth.uid() then raise exception '소유자는 내보낼 수 없습니다.' using errcode='22023'; end if;
 delete from public.vehicle_members where vehicle_id=p_vehicle_id and user_id=p_user_id and role='member';
 -- Revoke every outstanding invite so a removed member cannot reuse a known code.
 update public.vehicle_invites set remaining_uses=0 where vehicle_id=p_vehicle_id;
end $$;

create function public.leave_vehicle(p_vehicle_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user();
begin
 perform 1 from public.vehicles where id=p_vehicle_id for update;
 if public.is_vehicle_owner(p_vehicle_id) then raise exception '소유자는 차량을 탈퇴할 수 없습니다.' using errcode='22023'; end if;
 delete from public.vehicle_members where vehicle_id=p_vehicle_id and user_id=u;
end $$;

create function public.update_apartment(p_vehicle_id uuid,p_name text,p_allowed_floors text[],p_allowed_zones text[]) returns void
language plpgsql security definer set search_path='' as $$
declare a uuid;
begin
 perform private.require_user();
 select apartment_id into a from public.vehicles where id=p_vehicle_id for update;
 if not public.is_vehicle_owner(p_vehicle_id) then raise exception '차량 소유자만 변경할 수 있습니다.' using errcode='42501'; end if;
 if p_name is null or char_length(btrim(p_name)) not between 1 and 60
 or coalesce(cardinality(p_allowed_floors),0) not between 1 and 20 or coalesce(cardinality(p_allowed_zones),0) not between 1 and 30
 or exists(select 1 from unnest(p_allowed_floors || p_allowed_zones) x where x is null or x<>btrim(x) or char_length(x) not between 1 and 20)
 or cardinality(p_allowed_floors)<>(select count(distinct x) from unnest(p_allowed_floors) x)
 or cardinality(p_allowed_zones)<>(select count(distinct x) from unnest(p_allowed_zones) x)
 then raise exception '층수와 구역을 확인해 주세요.' using errcode='22023'; end if;
 update public.apartments set name=btrim(p_name),allowed_floors=p_allowed_floors,allowed_zones=p_allowed_zones where id=a and owner_id=auth.uid();
end $$;

create function public.delete_my_account() returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user();
begin
 -- Ownership and deletion policy: owned vehicles + history are removed; records
 -- on other families' vehicles remain with an anonymous author.
 perform 1 from public.vehicles where owner_id=u order by id for update;
 delete from public.vehicles where owner_id=u;
 delete from public.apartments where owner_id=u;
 delete from public.vehicle_invites where created_by=u;
 delete from auth.users where id=u;
end $$;

-- Tight table privileges supplement RLS; no direct writes to authoritative records.
revoke all on public.profiles,public.apartments,public.vehicles,public.vehicle_members,public.parking_records,public.vehicle_invites,public.device_settings from anon,authenticated;
grant select on public.profiles,public.apartments,public.vehicles,public.vehicle_members,public.parking_records,public.device_settings to authenticated;
grant insert(id,nickname),update(nickname) on public.profiles to authenticated;
grant insert,update,delete on public.device_settings to authenticated;
revoke all on function private.require_user(),private.take_rate_limit(uuid,text,integer),private.check_latest_vehicle() from public,anon,authenticated;
-- Explicitly list this application's functions; never alter unrelated public RPCs.
revoke all on function public.create_vehicle_with_membership(text,text,text,text),public.create_invite_securely(uuid),public.redeem_invite_securely(text),public.create_parking_record_and_set_latest(uuid,text,text,text,text,uuid),public.list_vehicle_members(uuid),public.set_vehicle_icon(uuid,text),public.remove_member(uuid,uuid),public.leave_vehicle(uuid),public.update_apartment(uuid,text,text[],text[]),public.delete_my_account() from public,anon;
grant execute on function public.create_vehicle_with_membership(text,text,text,text),public.create_invite_securely(uuid),public.redeem_invite_securely(text),public.create_parking_record_and_set_latest(uuid,text,text,text,text,uuid),public.list_vehicle_members(uuid),public.set_vehicle_icon(uuid,text),public.remove_member(uuid,uuid),public.leave_vehicle(uuid),public.update_apartment(uuid,text,text[],text[]),public.delete_my_account() to authenticated;

-- Realtime is optional on local PostgreSQL; Supabase creates this publication.
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  alter publication supabase_realtime add table public.vehicles,public.parking_records,public.vehicle_members;
 end if;
end $$;
