alter table public.users
    add column if not exists avatar_object_key text,
    add column if not exists avatar_mime_type text,
    add column if not exists avatar_size_bytes integer,
    add column if not exists avatar_updated_at timestamptz,
    add column if not exists profile_setup_completed_at timestamptz;

-- Preserve established accounts that had already completed the prior setup
-- flow, without treating newly provider-seeded identity fields as completion.
update public.users
set profile_setup_completed_at = onboarding_completed_at
where profile_setup_completed_at is null
  and onboarding_completed_at is not null
  and nullif(btrim(username), '') is not null
  and nullif(btrim(display_name), '') is not null;

alter table public.users
    drop constraint if exists users_avatar_size_bytes_check,
    add constraint users_avatar_size_bytes_check
        check (avatar_size_bytes is null or (avatar_size_bytes > 0 and avatar_size_bytes <= 5242880));

-- The existing backend-only private-object queue was introduced for session
-- audio. Extend its constrained vocabulary for durable avatar reservations and
-- cleanup without weakening the terminal privacy shape.
alter table public.audio_storage_jobs
    drop constraint if exists audio_storage_jobs_action_check,
    add constraint audio_storage_jobs_action_check check (
        action in (
            'upload_reservation',
            'delete_object',
            'reconcile_metadata',
            'avatar_upload_reservation',
            'avatar_metadata_reconciliation'
        )
    ),
    drop constraint if exists audio_storage_jobs_provider_check,
    add constraint audio_storage_jobs_provider_check check (
        provider in ('local', 'supabase', 'unknown', 'supabase-avatar')
    );

-- The production Storage schema has these columns, while the deliberately
-- small PostgreSQL CI stub may not. Keep this migration repeatable in both.
do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'storage' and table_name = 'buckets'
      and column_name in ('public', 'file_size_limit', 'allowed_mime_types')
    group by table_schema, table_name
    having count(*) = 3
  ) then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('profile-avatars', 'profile-avatars', false, 5242880, array['image/jpeg', 'image/png']::text[])
    on conflict (id) do update
    set public = false,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;
  else
    insert into storage.buckets (id, name)
    values ('profile-avatars', 'profile-avatars')
    on conflict (id) do nothing;
  end if;
end
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on table public.users from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on table public.users from authenticated;
  end if;
end
$$;
