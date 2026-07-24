-- Durable server-only state for audio upload reservations, object cleanup,
-- and post-commit metadata reconciliation. User/session IDs deliberately do
-- not have foreign keys so tombstones survive account/session deletion.
create table if not exists public.audio_storage_jobs (
  id bigserial primary key,
  -- Nullable only after terminal redaction; the privacy constraint below keeps
  -- account ownership mandatory while operational work is active.
  user_id bigint,
  session_id bigint,
  idempotency_key text not null unique,
  action text not null
    constraint audio_storage_jobs_action_check
    check (action in ('upload_reservation', 'delete_object', 'reconcile_metadata')),
  provider text not null
    constraint audio_storage_jobs_provider_check
    check (provider in ('local', 'supabase', 'unknown')),
  object_key text not null,
  size_bytes integer not null default 0
    constraint audio_storage_jobs_size_bytes_check
    check (size_bytes >= 0 and size_bytes <= 52428800),
  reason text not null,
  status text not null default 'pending'
    constraint audio_storage_jobs_status_check
    check (status in ('reserved', 'pending', 'in_progress', 'retryable_failure', 'completed', 'cancelled')),
  retry_count integer not null default 0
    constraint audio_storage_jobs_retry_count_check
    check (retry_count >= 0),
  next_retry_at timestamptz,
  safe_error_category text,
  details_json jsonb not null default '{}'::jsonb
    constraint audio_storage_jobs_details_object_check
    check (jsonb_typeof(details_json) = 'object'),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint audio_storage_jobs_terminal_privacy_check check (
    (
      status in ('completed', 'cancelled')
      and user_id is null
      and session_id is null
      and idempotency_key = 'terminal:' || id::text
      and object_key = '[redacted]'
      and size_bytes = 0
      and details_json = '{}'::jsonb
      and completed_at is not null
    )
    or
    (
      status not in ('completed', 'cancelled')
      and user_id is not null
      and object_key <> '[redacted]'
      and completed_at is null
    )
  )
);

-- If a prior local attempt created the table from an earlier draft, converge it
-- to the terminal-redaction contract before indexes/readiness checks run.
alter table public.audio_storage_jobs alter column user_id drop not null;

update public.audio_storage_jobs
set user_id = null,
    session_id = null,
    idempotency_key = 'terminal:' || id::text,
    object_key = '[redacted]',
    size_bytes = 0,
    details_json = '{}'::jsonb,
    completed_at = coalesce(completed_at, updated_at, created_at, now()),
    updated_at = now()
where status in ('completed', 'cancelled');

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.audio_storage_jobs'::regclass
      and conname = 'audio_storage_jobs_terminal_privacy_check'
  ) then
    alter table public.audio_storage_jobs
      add constraint audio_storage_jobs_terminal_privacy_check check (
        (
          status in ('completed', 'cancelled')
          and user_id is null
          and session_id is null
          and idempotency_key = 'terminal:' || id::text
          and object_key = '[redacted]'
          and size_bytes = 0
          and details_json = '{}'::jsonb
          and completed_at is not null
        )
        or
        (
          status not in ('completed', 'cancelled')
          and user_id is not null
          and object_key <> '[redacted]'
          and completed_at is null
        )
      );
  end if;
end
$$;

alter table public.audio_storage_jobs enable row level security;

-- The FastAPI backend owns this operational queue. Keep it inaccessible from
-- Supabase's browser-facing Data API even if exposure settings later drift.
do $$
declare
  app_role text;
begin
  for app_role in
    select rolname from pg_roles where rolname in ('anon', 'authenticated', 'service_role')
  loop
    execute format('revoke all privileges on table public.audio_storage_jobs from %I', app_role);
    execute format('revoke all privileges on sequence public.audio_storage_jobs_id_seq from %I', app_role);
  end loop;
end
$$;

revoke all privileges on table public.audio_storage_jobs from public;
revoke all privileges on sequence public.audio_storage_jobs_id_seq from public;

create index if not exists idx_audio_storage_jobs_account_state
  on public.audio_storage_jobs (user_id, action, status);

create index if not exists idx_audio_storage_jobs_retry_queue
  on public.audio_storage_jobs (status, next_retry_at, updated_at, id)
  where status in ('reserved', 'pending', 'in_progress', 'retryable_failure');

create index if not exists idx_audio_storage_jobs_session_id
  on public.audio_storage_jobs (session_id);

create index if not exists idx_audio_storage_jobs_terminal_purge
  on public.audio_storage_jobs (completed_at, id)
  where status in ('completed', 'cancelled');

comment on table public.audio_storage_jobs is
  'Backend-only operational queue. Terminal rows are immediately scrubbed of user/session/object/details and purged by FastAPI maintenance after a default 7-day TTL (bounded to 30 days).';

-- Rollback notes:
-- 1. Stop audio uploads and the maintenance executor.
-- 2. Confirm no rows remain in reserved/pending/in_progress/retryable_failure;
--    these rows may be the only durable reference to an object needing cleanup.
-- 3. Only then drop idx_audio_storage_jobs_* and public.audio_storage_jobs.
-- Re-granting anon/authenticated/service_role access is intentionally not part
-- of rollback: BrassTune routes application data through FastAPI, not Data API.
