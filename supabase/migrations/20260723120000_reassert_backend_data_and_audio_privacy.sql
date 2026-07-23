-- Reassert the FastAPI-only data path after all currently known application
-- tables exist. This migration is separately sequenced and idempotent so a
-- partial earlier rollout converges without rewriting migration history.
do $$
declare
  app_role text;
  app_table text;
  app_tables constant text[] := array[
    'users',
    'instrument_profiles',
    'practice_sessions',
    'pitch_samples',
    'note_events',
    'groups',
    'group_members',
    'invitations',
    'recommendations',
    'account_deletion_jobs',
    'usage_events',
    'audio_storage_jobs'
  ];
begin
  foreach app_table in array app_tables
  loop
    if to_regclass(format('public.%I', app_table)) is not null then
      execute format(
        'alter table public.%I enable row level security',
        app_table
      );
      execute format(
        'revoke all privileges on table public.%I from public',
        app_table
      );
    end if;
  end loop;

  revoke all privileges on all sequences in schema public from public;
  alter default privileges in schema public
    revoke all privileges on tables from public;
  alter default privileges in schema public
    revoke all privileges on sequences from public;

  for app_role in
    select rolname
    from pg_roles
    where rolname in ('anon', 'authenticated')
  loop
    foreach app_table in array app_tables
    loop
      if to_regclass(format('public.%I', app_table)) is not null then
        execute format(
          'revoke all privileges on table public.%I from %I',
          app_table,
          app_role
        );
      end if;
    end loop;

    execute format(
      'revoke all privileges on all sequences in schema public from %I',
      app_role
    );
    execute format(
      'alter default privileges in schema public revoke all privileges on tables from %I',
      app_role
    );
    execute format(
      'alter default privileges in schema public revoke all privileges on sequences from %I',
      app_role
    );
    execute format(
      'alter default privileges in schema public revoke execute on functions from %I',
      app_role
    );
  end loop;
end
$$;

alter default privileges in schema public
  revoke execute on functions from public;

-- audio_storage_jobs is backend operational state and is intentionally also
-- unavailable to service_role through the Data API.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role')
     and to_regclass('public.audio_storage_jobs') is not null then
    revoke all privileges on table public.audio_storage_jobs from service_role;
    revoke all privileges on sequence public.audio_storage_jobs_id_seq from service_role;
  end if;
end
$$;

-- Reassert the static session-audio bucket controls without assuming the
-- lightweight PostgreSQL CI storage stub exposes every managed Supabase column.
do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'storage'
      and table_name = 'buckets'
      and column_name = 'public'
  ) then
    update storage.buckets
    set public = false
    where id = 'session-audio';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'storage'
      and table_name = 'buckets'
      and column_name = 'file_size_limit'
  ) then
    update storage.buckets
    set file_size_limit = 52428800
    where id = 'session-audio';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'storage'
      and table_name = 'buckets'
      and column_name = 'allowed_mime_types'
  ) then
    update storage.buckets
    set allowed_mime_types = array[
      'audio/webm',
      'audio/mp4',
      'audio/mpeg',
      'audio/wav',
      'audio/ogg'
    ]::text[]
    where id = 'session-audio';
  end if;
end
$$;

-- Storage policies are provider-managed objects. The application readiness
-- gate verifies that browser-facing policies cannot reach session-audio; this
-- migration deliberately does not drop unknown policies for unrelated buckets.
