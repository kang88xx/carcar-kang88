-- Ephemeral PostgreSQL ONLY. Supabase provides these roles and auth objects.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
-- Mirror hosted direct function grants, not only PostgreSQL PUBLIC defaults.
alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant usage on schema auth,public to authenticated,anon;
grant execute on function auth.uid() to authenticated,anon;
-- Hosted Supabase installs pgcrypto in extensions; test that upgrade path too.
create schema extensions;
create extension pgcrypto with schema extensions;
