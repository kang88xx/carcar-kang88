-- Device opt-in and a private, bounded notification outbox. Network calls never
-- run in the parking transaction. Deploy the separate worker before scheduling.
alter table public.device_settings add column timezone text not null default 'Asia/Seoul';
alter table public.device_settings add constraint quiet_hours_distinct check (quiet_start is null or quiet_start <> quiet_end);
revoke insert,update,delete on public.device_settings from authenticated;

create table private.push_configuration (
 singleton boolean primary key default true check (singleton),
 delivery_available boolean not null default false,
 updated_at timestamptz not null default now()
);
insert into private.push_configuration(singleton) values(true);
alter table private.push_configuration enable row level security;
revoke all on private.push_configuration from public,anon,authenticated;

create function public.set_push_delivery_available(p_available boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if p_available is null then raise exception 'Readiness flag is required' using errcode='22023'; end if;
 insert into private.push_configuration(singleton,delivery_available) values(true,p_available)
 on conflict(singleton) do update set delivery_available=excluded.delivery_available,updated_at=clock_timestamp();
end $$;
revoke all on function public.set_push_delivery_available(boolean) from public,anon,authenticated;
grant execute on function public.set_push_delivery_available(boolean) to service_role;

create table private.push_devices (
 device_id uuid primary key references public.device_settings(id) on delete cascade,
 provider text not null check (provider in ('apns','fcm')),
 environment text not null check (environment in ('production','sandbox')),
 token text not null check (char_length(token) between 32 and 4096),
 revision uuid not null default gen_random_uuid(),
 updated_at timestamptz not null default now()
);
create unique index push_token_unique on private.push_devices(provider,environment,(extensions.digest(token,'sha256')));
alter table private.push_devices enable row level security;
revoke all on private.push_devices from public,anon,authenticated;

create table private.push_outbox (
 id uuid primary key default gen_random_uuid(),
 record_id uuid not null references public.parking_records(id) on delete cascade,
 device_id uuid not null references public.device_settings(id) on delete cascade,
 token_revision uuid not null,
 state text not null default 'pending' check (state in ('pending','processing','sent','skipped','dead')),
 attempts integer not null default 0 check (attempts between 0 and 6),
 available_at timestamptz not null default now(),
 lease_token uuid,
 lease_until timestamptz,
 created_at timestamptz not null default now(),
 finished_at timestamptz,
 result_code text,
 unique(record_id,device_id)
);
create index push_outbox_due on private.push_outbox(available_at,created_at) where state in ('pending','processing');
alter table private.push_outbox enable row level security;
revoke all on private.push_outbox from public,anon,authenticated;

create function private.push_is_quiet(p_start time,p_end time,p_timezone text,p_at timestamptz)
returns boolean language sql stable set search_path='' as $$
 select case when p_start is null then false
 when p_start<p_end then (p_at at time zone p_timezone)::time >= p_start and (p_at at time zone p_timezone)::time < p_end
 else (p_at at time zone p_timezone)::time >= p_start or (p_at at time zone p_timezone)::time < p_end end
$$;
revoke all on function private.push_is_quiet(time,time,text,timestamptz) from public,anon,authenticated;

create function public.get_my_device_settings(p_installation_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); result jsonb;
begin
 select to_jsonb(d) into result from public.device_settings d where d.user_id=u and d.installation_id=p_installation_id;
 return coalesce(result,jsonb_build_object('installation_id',p_installation_id,'push_enabled',false,'live_enabled',false,'notify_own',false,'quiet_start',null,'quiet_end',null,'timezone','Asia/Seoul','preferred_live_minutes',120)) || jsonb_build_object('delivery_available',coalesce((select delivery_available from private.push_configuration where singleton),false));
end $$;

create function public.save_device_settings(
 p_installation_id uuid,p_platform text,p_push_enabled boolean default false,
 p_live_enabled boolean default false,p_notify_own boolean default false,
 p_quiet_start time default null,p_quiet_end time default null,p_timezone text default 'Asia/Seoul',
 p_preferred_live_minutes integer default 120,p_push_provider text default null,
 p_push_token text default null,p_push_environment text default 'production') returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); d public.device_settings;
begin
 if p_installation_id is null or p_platform is null or p_platform not in ('ios','android')
 or p_push_enabled is null or p_live_enabled is null or p_notify_own is null
 or p_preferred_live_minutes is null or p_preferred_live_minutes not in (60,120,240,480)
 or (p_quiet_start is null)<>(p_quiet_end is null) or p_quiet_start=p_quiet_end
 or p_timezone is null or not exists(select 1 from pg_catalog.pg_timezone_names where name=p_timezone)
 then raise exception '기기 알림 설정을 확인해 주세요.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,2));
 select * into d from public.device_settings where user_id=u and installation_id=p_installation_id for update;
 -- During an outage, existing opt-in can be retained while independent display
 -- and quiet preferences change. New activation or token binding still fails.
 if p_push_enabled and not coalesce((select delivery_available from private.push_configuration where singleton),false)
 and (d.id is null or not d.push_enabled or p_push_token is not null or p_push_provider is not null) then
  raise exception '가족 알림 서비스를 준비하고 있어요. 잠시 후 다시 시도해 주세요.' using errcode='55000'; end if;
 if d.id is null
 and (select count(*) from public.device_settings where user_id=u)>=20 then
  raise exception '등록 가능한 기기 수를 초과했어요.' using errcode='22023'; end if;
 insert into public.device_settings(user_id,installation_id,platform,push_enabled,live_enabled,notify_own,quiet_start,quiet_end,timezone,preferred_live_minutes)
 values(u,p_installation_id,p_platform,p_push_enabled,p_live_enabled,p_notify_own,p_quiet_start,p_quiet_end,p_timezone,p_preferred_live_minutes)
 on conflict(user_id,installation_id) do update set platform=excluded.platform,push_enabled=excluded.push_enabled,
 live_enabled=excluded.live_enabled,notify_own=excluded.notify_own,quiet_start=excluded.quiet_start,quiet_end=excluded.quiet_end,
 timezone=excluded.timezone,preferred_live_minutes=excluded.preferred_live_minutes,updated_at=clock_timestamp()
 returning * into d;
 if p_push_enabled then
  if p_push_token is not null then
   if p_push_provider is null or p_push_environment is null
   or p_push_environment not in ('production','sandbox')
   or (p_platform='ios' and (p_push_provider<>'apns' or p_push_token !~ '^[0-9a-fA-F]{64,200}$'))
   or (p_platform='android' and (p_push_provider<>'fcm' or p_push_environment<>'production' or (char_length(p_push_token) not between 32 and 4096 or p_push_token !~ '^[A-Za-z0-9:_-]+$')))
   then raise exception '알림 기기 등록 정보를 확인해 주세요.' using errcode='22023'; end if;
   insert into private.push_devices(device_id,provider,environment,token)
   values(d.id,p_push_provider,p_push_environment,case when p_push_provider='apns' then lower(p_push_token) else p_push_token end)
   on conflict(device_id) do update set provider=excluded.provider,environment=excluded.environment,token=excluded.token,
    revision=case when (private.push_devices.provider,private.push_devices.environment,private.push_devices.token) is distinct from (excluded.provider,excluded.environment,excluded.token) then gen_random_uuid() else private.push_devices.revision end,
    updated_at=clock_timestamp();
  end if;
  if not exists(select 1 from private.push_devices x where x.device_id=d.id and x.provider=case when p_platform='ios' then 'apns' else 'fcm' end) then
   raise exception '먼저 이 기기의 알림을 허용해 주세요.' using errcode='22023'; end if;
 else
  delete from private.push_devices where device_id=d.id;
  update private.push_outbox set state='skipped',finished_at=clock_timestamp(),result_code='disabled',lease_token=null,lease_until=null where device_id=d.id and state in ('pending','processing');
 end if;
 return to_jsonb(d) || jsonb_build_object('delivery_available',coalesce((select delivery_available from private.push_configuration where singleton),false));
end $$;

create function public.unregister_push_device(p_installation_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_user(); d uuid;
begin
 select id into d from public.device_settings where user_id=u and installation_id=p_installation_id for update;
 delete from private.push_devices where device_id=d;
 update public.device_settings set push_enabled=false,updated_at=clock_timestamp() where id=d;
 update private.push_outbox set state='skipped',finished_at=clock_timestamp(),result_code='unregistered',lease_token=null,lease_until=null where device_id=d and state in ('pending','processing');
end $$;

create function private.enqueue_parking_push() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if not coalesce((select delivery_available from private.push_configuration where singleton),false) then return new; end if;
 insert into private.push_outbox(record_id,device_id,token_revision)
 select new.id,d.id,t.revision from public.vehicle_members m
 join public.device_settings d on d.user_id=m.user_id and d.push_enabled
 join private.push_devices t on t.device_id=d.id
 where m.vehicle_id=new.vehicle_id and (d.notify_own or m.user_id is distinct from new.created_by)
 and not private.push_is_quiet(d.quiet_start,d.quiet_end,d.timezone,clock_timestamp())
 on conflict(record_id,device_id) do nothing;
 return new;
end $$;
revoke all on function private.enqueue_parking_push() from public,anon,authenticated;
create trigger enqueue_parking_notification after insert on public.parking_records for each row execute function private.enqueue_parking_push();

-- Service-only RPCs are exposed solely for the trusted Edge worker. They return
-- no customer data other than the minimum opaque provider token and vehicle ID.
create function public.claim_push_jobs(p_limit integer default 10)
returns table(job_id uuid,lease_token uuid) language plpgsql security definer set search_path='' as $$
begin
 if not coalesce((select delivery_available from private.push_configuration where singleton),false) then return; end if;
 delete from private.push_outbox where created_at<clock_timestamp()-interval '7 days';
 update private.push_outbox set state='dead',finished_at=clock_timestamp(),result_code='expired',lease_token=null,lease_until=null
 where state in ('pending','processing') and (created_at<clock_timestamp()-interval '1 hour' or (attempts>=6 and (lease_until is null or lease_until<=clock_timestamp())));
 return query with next_jobs as (
 select j.id from private.push_outbox j where j.state in ('pending','processing') and j.attempts<6
 and j.available_at<=clock_timestamp() and (j.lease_until is null or j.lease_until<=clock_timestamp())
 order by j.created_at for update skip locked limit greatest(1,least(coalesce(p_limit,10),20))
 ) update private.push_outbox j set state='processing',attempts=j.attempts+1,lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes'
 from next_jobs n where j.id=n.id returning j.id,j.lease_token;
end $$;

create function public.prepare_push_delivery(p_job_id uuid,p_lease_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare j private.push_outbox; d public.device_settings; t private.push_devices; r public.parking_records;
begin
 select * into j from private.push_outbox where id=p_job_id and state='processing' and lease_token=p_lease_token and lease_until>clock_timestamp() for update;
 if j.id is null then return null; end if;
 if not coalesce((select delivery_available from private.push_configuration where singleton),false) then return null; end if;
 select * into d from public.device_settings where id=j.device_id;
 select * into t from private.push_devices where device_id=j.device_id;
 select * into r from public.parking_records where id=j.record_id;
 if d.id is null or t.device_id is null or r.id is null or not d.push_enabled or t.revision<>j.token_revision
 or j.created_at<clock_timestamp()-interval '1 hour'
 or not exists(select 1 from auth.users where id=d.user_id)
 or not exists(select 1 from public.vehicle_members where vehicle_id=r.vehicle_id and user_id=d.user_id)
 or not exists(select 1 from public.vehicles where id=r.vehicle_id and latest_parking_record_id=r.id)
 or (not d.notify_own and d.user_id=r.created_by)
 or private.push_is_quiet(d.quiet_start,d.quiet_end,d.timezone,clock_timestamp()) then
  update private.push_outbox set state='skipped',finished_at=clock_timestamp(),result_code='ineligible',lease_token=null,lease_until=null where id=j.id;
  return null;
 end if;
 return jsonb_build_object('job_id',j.id,'provider',t.provider,'environment',t.environment,'token',t.token,'vehicle_id',r.vehicle_id,'expires_at',extract(epoch from j.created_at+interval '1 hour')::bigint);
end $$;

create function public.finish_push_job(p_job_id uuid,p_lease_token uuid,p_result text,p_retry_seconds integer default 60) returns boolean
language plpgsql security definer set search_path='' as $$
declare j private.push_outbox; device uuid;
begin
 if p_result is null or p_result not in ('sent','invalid_token','retry','rejected','configuration_error') then raise exception 'Invalid push result' using errcode='22023'; end if;
 -- Same device-before-job lock order as settings changes and logout.
 select device_id into device from private.push_outbox where id=p_job_id;
 perform 1 from public.device_settings where id=device for update;
 if not found then return false; end if;
 select * into j from private.push_outbox where id=p_job_id and state='processing' and lease_token=p_lease_token and lease_until>clock_timestamp() for update;
 if j.id is null then return false; end if;
 if p_result='invalid_token' then
  delete from private.push_devices where device_id=j.device_id and revision=j.token_revision;
  if found then update public.device_settings set push_enabled=false,updated_at=clock_timestamp() where id=j.device_id; end if;
 end if;
 update private.push_outbox set state=case when p_result='sent' then 'sent' when p_result in ('retry','configuration_error') and attempts<6 then 'pending' else 'dead' end,
 available_at=clock_timestamp()+make_interval(secs=>greatest(30,least(coalesce(p_retry_seconds,60),3600),least(30*power(2,attempts-1)::integer,1800))),
 finished_at=case when p_result in ('retry','configuration_error') and attempts<6 then null else clock_timestamp() end,
 result_code=p_result,lease_token=null,lease_until=null where id=j.id;
 return true;
end $$;

revoke all on function public.get_my_device_settings(uuid),public.save_device_settings(uuid,text,boolean,boolean,boolean,time,time,text,integer,text,text,text),public.unregister_push_device(uuid) from public,anon;
grant execute on function public.get_my_device_settings(uuid),public.save_device_settings(uuid,text,boolean,boolean,boolean,time,time,text,integer,text,text,text),public.unregister_push_device(uuid) to authenticated;
revoke all on function public.claim_push_jobs(integer),public.prepare_push_delivery(uuid,uuid),public.finish_push_job(uuid,uuid,text,integer) from public,anon,authenticated;
grant execute on function public.claim_push_jobs(integer),public.prepare_push_delivery(uuid,uuid),public.finish_push_job(uuid,uuid,text,integer) to service_role;
