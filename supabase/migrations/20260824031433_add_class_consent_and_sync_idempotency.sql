-- Durable, replay-safe native/web practice sync and explicit class aggregate
-- sharing consent. These application tables remain FastAPI-only: browser Data
-- API roles receive no grants or policies.

alter table if exists public.practice_sessions
  add column if not exists client_session_id text;

alter table if exists public.pitch_samples
  add column if not exists client_frame_index integer;

alter table if exists public.group_members
  add column if not exists aggregate_sharing_consented_at timestamptz,
  add column if not exists aggregate_sharing_scope_code text,
  add column if not exists roster_row_id text;

-- This identifier is operational metadata, not consent. Existing memberships
-- deliberately keep both aggregate-sharing fields NULL until the member opts in.
update public.group_members
set roster_row_id = gen_random_uuid()::text
where roster_row_id is null;

-- Keep the expand window compatible with the previous backend binary, which
-- does not yet send roster_row_id on INSERT.
alter table if exists public.group_members
  alter column roster_row_id set default gen_random_uuid()::text;

alter table if exists public.group_members
  alter column roster_row_id set not null;

-- Remove the pre-review draft constraint if a local database evaluated this
-- file before publication. Active legacy memberships are allowed to remain
-- unconsented; only a coherent explicit pair authorizes aggregate inclusion.
alter table if exists public.group_members
  drop constraint if exists group_members_active_aggregate_consent_check;

do $migration$
begin
  if to_regclass('public.practice_sessions') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.practice_sessions'::regclass
         and conname = 'uq_practice_sessions_user_client_session'
     ) then
    alter table public.practice_sessions
      add constraint uq_practice_sessions_user_client_session
      unique (user_id, client_session_id);
  end if;

  if to_regclass('public.pitch_samples') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.pitch_samples'::regclass
         and conname = 'uq_pitch_samples_session_client_frame'
     ) then
    alter table public.pitch_samples
      add constraint uq_pitch_samples_session_client_frame
      unique (session_id, client_frame_index);
  end if;

  if to_regclass('public.group_members') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.group_members'::regclass
         and conname = 'uq_group_members_roster_row_id'
     ) then
    alter table public.group_members
      add constraint uq_group_members_roster_row_id unique (roster_row_id);
  end if;

  if to_regclass('public.group_members') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.group_members'::regclass
         and conname = 'group_members_aggregate_sharing_scope_check'
     ) then
    alter table public.group_members
      add constraint group_members_aggregate_sharing_scope_check check (
        aggregate_sharing_scope_code is null
        or aggregate_sharing_scope_code = 'cloud_practice_sessions_since_membership_v1'
      ) not valid;
  end if;

  if to_regclass('public.group_members') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.group_members'::regclass
         and conname = 'group_members_aggregate_sharing_pair_check'
     ) then
    alter table public.group_members
      add constraint group_members_aggregate_sharing_pair_check check (
        (aggregate_sharing_consented_at is null)
        = (aggregate_sharing_scope_code is null)
      ) not valid;
  end if;
end
$migration$;

alter table if exists public.group_members
  validate constraint group_members_aggregate_sharing_scope_check;
alter table if exists public.group_members
  validate constraint group_members_aggregate_sharing_pair_check;

do $privacy$
declare
  app_role text;
  app_table text;
begin
  foreach app_table in array array['practice_sessions', 'pitch_samples', 'group_members']
  loop
    if to_regclass(format('public.%I', app_table)) is not null then
      execute format('alter table public.%I enable row level security', app_table);
      execute format('revoke all privileges on table public.%I from public', app_table);
    end if;
  end loop;

  for app_role in
    select rolname from pg_roles where rolname in ('anon', 'authenticated')
  loop
    foreach app_table in array array['practice_sessions', 'pitch_samples', 'group_members']
    loop
      if to_regclass(format('public.%I', app_table)) is not null then
        execute format(
          'revoke all privileges on table public.%I from %I',
          app_table,
          app_role
        );
      end if;
    end loop;
  end loop;
end
$privacy$;
