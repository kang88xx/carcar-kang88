-- INITIAL DATA MODEL: review before running in production.
-- These SQL definitions cover the foundational schema and read/write RLS.
-- Security-sensitive operations (invite redeem/issue, parking insert+latest pointer,
-- device push tokens) must use separately reviewed transactional RPCs.

create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default '',
  created_at timestamptz not null default now()
);

create table public.apartments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id),
  name text not null,
  allowed_floors text[] not null default array['B1','B2','B3','B4'],
  allowed_zones text[] not null default array['A','B','C','D','E'],
  created_at timestamptz not null default now()
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  apartment_id uuid not null references public.apartments(id),
  owner_id uuid not null references auth.users(id),
  plate_number text not null,
  nickname text not null default '',
  icon_id text not null default 'car_blue',
  latest_parking_record_id uuid,
  created_at timestamptz not null default now(),
  constraint vehicle_icon_allowlist check (icon_id in
    ('car_blue','car_black','car_white','car_gold','car_mint','car_purple','car_red','car_gray'))
);

create table public.vehicle_members (
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  primary key(vehicle_id,user_id)
);

create table public.parking_records (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  floor text not null check (length(floor) between 1 and 20),
  zone text not null check (length(zone) between 1 and 20),
  spot text not null default '' check (length(spot) <= 20),
  note text not null default '' check (length(note) <= 500),
  image_path text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.vehicles add constraint fk_latest_parking
  foreign key (latest_parking_record_id) references public.parking_records(id) on delete set null;

create index parking_records_by_vehicle_time_idx on public.parking_records(vehicle_id, created_at desc);
create index vehicle_members_user_idx on public.vehicle_members(user_id);

create table public.vehicle_invites (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  remaining_uses integer not null default 1 check (remaining_uses >= 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.device_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  platform text not null check (platform in ('ios','android')),
  push_enabled boolean not null default false,
  live_enabled boolean not null default false,
  notify_own boolean not null default false,
  quiet_start time,
  quiet_end time,
  preferred_live_minutes integer not null default 120
    check (preferred_live_minutes in (60,120,240,480)),
  updated_at timestamptz not null default now(),
  unique(user_id, installation_id)
);

-- SECURITY: helper is safe for SELECT membership checks; avoid selecting
-- vehicle_members within its own RLS policy to prevent policy recursion.
create or replace function public.is_vehicle_member(p_vehicle_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.vehicle_members vm
    where vm.vehicle_id = p_vehicle_id and vm.user_id = (select auth.uid())
  );
$$;
revoke all on function public.is_vehicle_member(uuid) from public;
grant execute on function public.is_vehicle_member(uuid) to authenticated;

create or replace function public.is_vehicle_owner(p_vehicle_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.vehicles v
    where v.id = p_vehicle_id and v.owner_id = (select auth.uid())
  );
$$;
revoke all on function public.is_vehicle_owner(uuid) from public;
grant execute on function public.is_vehicle_owner(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.apartments enable row level security;
alter table public.vehicles enable row level security;
alter table public.vehicle_members enable row level security;
alter table public.parking_records enable row level security;
alter table public.vehicle_invites enable row level security;
alter table public.device_settings enable row level security;

create policy profiles_self_select on public.profiles for select to authenticated using (id=(select auth.uid()));
create policy profiles_self_insert on public.profiles for insert to authenticated with check (id=(select auth.uid()));
create policy profiles_self_update on public.profiles for update to authenticated using (id=(select auth.uid())) with check (id=(select auth.uid()));

create policy apartments_owner_read on public.apartments for select to authenticated
  using (owner_id=(select auth.uid()) or exists (
    select 1 from public.vehicles v where v.apartment_id=apartments.id and public.is_vehicle_member(v.id)
  ));
create policy apartments_owner_insert on public.apartments for insert to authenticated
  with check(owner_id=(select auth.uid()));
-- Apartment config mutations should be implemented via reviewed RPC only.

create policy vehicles_member_read on public.vehicles for select to authenticated
  using (public.is_vehicle_member(id) or owner_id=(select auth.uid()));
-- Vehicle creation and icon modifications via transactional RPC only.

create policy vehicle_members_member_read on public.vehicle_members for select to authenticated
  using (public.is_vehicle_member(vehicle_id));
-- Membership inserts/deletes via server-side validated RPC only.

create policy parking_members_read on public.parking_records for select to authenticated
  using (public.is_vehicle_member(vehicle_id));
-- Parking insert and latest pointer update via transactional RPC only.

-- Invite tokens are secret: no direct client read/write policies.

create policy settings_self_read on public.device_settings for select to authenticated
  using (user_id=(select auth.uid()));
create policy settings_self_insert on public.device_settings for insert to authenticated
  with check (user_id=(select auth.uid()));
create policy settings_self_update on public.device_settings for update to authenticated
  using (user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy settings_self_delete on public.device_settings for delete to authenticated
  using (user_id=(select auth.uid()));

-- RPC TODO (must implement before app CRUD):
-- create_vehicle_with_membership
-- create_invite_securely / redeem_invite_securely
-- create_parking_record_and_set_latest (idempotent)
-- set_vehicle_icon / remove_member / leave_vehicle
-- verify that parking_records.vehicle_id matches vehicles.latest_parking_record_id
-- add appropriate privileges, tests, rate limiting, storage policy and data retention.
