-- BrassTune routes application data through FastAPI. Deny direct Data API
-- privileges for browser roles even if project exposure settings drift later.
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
    'usage_events'
  ];
begin
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

-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default. Remove that
-- default so future functions must receive deliberate, named grants.
alter default privileges in schema public
  revoke execute on functions from public;

-- Keep the private session-audio bucket bounded to the formats the backend
-- validates. The lightweight PostgreSQL CI storage stub has only id/name/public,
-- so optional production Storage columns are guarded individually.
do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'storage'
      and table_name = 'buckets'
      and column_name = 'public'
  ) then
    update storage.buckets
    set public = false
    where id = 'session-audio';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'storage'
      and table_name = 'buckets'
      and column_name = 'file_size_limit'
  ) then
    update storage.buckets
    set file_size_limit = 52428800
    where id = 'session-audio';
  end if;

  if exists (
    select 1
    from information_schema.columns
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
