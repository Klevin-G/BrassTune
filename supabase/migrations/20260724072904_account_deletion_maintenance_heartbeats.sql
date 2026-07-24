-- Durable, backend-owned success proof for asynchronous maintenance triggers.
-- pg_cron only proves that pg_net accepted an outbound request; this row is
-- advanced by FastAPI after authenticated account-deletion maintenance finishes.
create table if not exists public.maintenance_heartbeats (
  purpose text primary key
    constraint maintenance_heartbeats_purpose_check
    check (purpose = 'account-deletions-retry-v1'),
  last_succeeded_at timestamptz not null
);

alter table public.maintenance_heartbeats enable row level security;

do $privacy$
declare
  app_role text;
begin
  for app_role in
    select rolname from pg_roles where rolname in ('anon', 'authenticated', 'service_role')
  loop
    execute format(
      'revoke all privileges on table public.maintenance_heartbeats from %I',
      app_role
    );
  end loop;
end;
$privacy$;

revoke all privileges on table public.maintenance_heartbeats from public;

comment on table public.maintenance_heartbeats is
  'Backend-only last-success timestamps for authenticated maintenance endpoints; contains no request, credential, user, or object identifiers.';
