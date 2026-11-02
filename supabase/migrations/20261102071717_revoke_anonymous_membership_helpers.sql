-- Hosted Supabase may grant anon EXECUTE directly through default privileges.
-- REVOKE FROM PUBLIC alone does not remove that direct grant. Preserve the
-- authenticated helper access required by existing vehicle-membership RLS.
revoke all on function public.is_vehicle_member(uuid),public.is_vehicle_owner(uuid) from public,anon;
grant execute on function public.is_vehicle_member(uuid),public.is_vehicle_owner(uuid) to authenticated;
