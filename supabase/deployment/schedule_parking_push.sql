-- Apply only after deploying parking-push and configuring its server secrets.
-- Vault entries must already exist: carcar_project_url and carcar_push_worker_secret.
-- Their values are never migration literals or SELECT output. This script does
-- not create a project, enable billing, or send a device notification itself.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

do $$ begin
 if not exists(select 1 from vault.decrypted_secrets where name='carcar_project_url' and decrypted_secret ~ '^https://[a-z0-9]+\.supabase\.co$')
 or not exists(select 1 from vault.decrypted_secrets where name='carcar_push_worker_secret' and length(decrypted_secret)>=32) then
  raise exception 'Configure the parking worker URL and strong secret in Vault first';
 end if;
end $$;

create or replace function private.dispatch_due_parking_push() returns void
language plpgsql security definer set search_path='' as $$
declare target text; secret text;
begin
 if not coalesce((select delivery_available from private.push_configuration where singleton),false) then return; end if;
 if not pg_try_advisory_xact_lock(754210036) then return; end if;
 if not exists(select 1 from private.push_outbox where state in ('pending','processing')
 and available_at<=clock_timestamp() and (lease_until is null or lease_until<=clock_timestamp())) then return; end if;
 select decrypted_secret into target from vault.decrypted_secrets where name='carcar_project_url';
 select decrypted_secret into secret from vault.decrypted_secrets where name='carcar_push_worker_secret';
 if target !~ '^https://[a-z0-9]+\.supabase\.co$' or target is null or length(secret)<32 or secret is null then return; end if;
 perform net.http_post(url:=target||'/functions/v1/parking-push',
 headers:=jsonb_build_object('Content-Type','application/json','x-carcar-worker-secret',secret),
 body:='{}'::jsonb,timeout_milliseconds:=120000);
end $$;
revoke all on function private.dispatch_due_parking_push() from public,anon,authenticated,service_role;
-- Re-running updates this named job, not other application schedules.
select cron.schedule('carcar-parking-push','* * * * *','select private.dispatch_due_parking_push();');
