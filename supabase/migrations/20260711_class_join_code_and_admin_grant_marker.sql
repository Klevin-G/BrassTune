-- Class join codes: a short shareable code students type to self-join a class.
alter table if exists public.groups
  add column if not exists join_code varchar;

create unique index if not exists groups_join_code_key
  on public.groups (join_code)
  where join_code is not null;

-- Backfill a join code for any existing class that lacks one.
update public.groups
set join_code = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6))
where join_code is null;

-- Marker so admin granted by BRASSTUNE_ADMIN_EMAILS can be safely revoked when
-- the email is removed, without touching admins granted another way.
alter table if exists public.users
  add column if not exists admin_granted_by_env boolean not null default false;

-- Existing admins predate the marker; assume they were env-granted so the list
-- stays the source of truth (they are re-granted on next sign-in if still listed).
update public.users
set admin_granted_by_env = true
where role = 'admin' and admin_granted_by_env = false;
