-- Durable server-only state for audio upload reservations, object cleanup,
-- and post-commit metadata reconciliation. User/session IDs deliberately do
-- not have foreign keys so tombstones survive account/session deletion.
create table if not exists public.audio_storage_jobs (
  id bigserial primary key,
  user_id bigint not null,
  session_id bigint,
  idempotency_key text not null unique,
  action text not null check (action in ('upload_reservation', 'delete_object', 'reconcile_metadata')),
  provider text not null,
  object_key text not null,
  size_bytes integer not null default 0 check (size_bytes >= 0),
  reason text not null,
  status text not null default 'pending'
    check (status in ('reserved', 'pending', 'in_progress', 'retryable_failure', 'completed', 'cancelled')),
  retry_count integer not null default 0 check (retry_count >= 0),
  next_retry_at timestamptz,
  safe_error_category text,
  details_json jsonb not null default '{}'::jsonb,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.audio_storage_jobs enable row level security;

-- The FastAPI backend owns this operational queue. Keep it inaccessible from
-- Supabase's browser-facing Data API even if exposure settings later drift.
do $$
declare
  app_role text;
begin
  for app_role in
    select rolname from pg_roles where rolname in ('anon', 'authenticated')
  loop
    execute format('revoke all privileges on table public.audio_storage_jobs from %I', app_role);
    execute format('revoke all privileges on sequence public.audio_storage_jobs_id_seq from %I', app_role);
  end loop;
end
$$;

create index if not exists idx_audio_storage_jobs_account_state
  on public.audio_storage_jobs (user_id, action, status);

create index if not exists idx_audio_storage_jobs_retry_queue
  on public.audio_storage_jobs (status, next_retry_at, updated_at)
  where status in ('reserved', 'pending', 'in_progress', 'retryable_failure');

create index if not exists idx_audio_storage_jobs_session_id
  on public.audio_storage_jobs (session_id);
