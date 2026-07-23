-- Privacy-preserving account-deletion state. Raw local/provider identifiers are
-- needed only while cleanup can still be retried. Completed rows are converted
-- by the backend into a minimal keyed HMAC tombstone plus a scrubbed, short-lived
-- operational row.
alter table public.account_deletion_jobs alter column user_id drop not null;

create table if not exists public.deleted_identity_tombstones (
  id bigserial primary key,
  subject_digest text not null unique
    constraint deleted_identity_tombstones_digest_check
    check (subject_digest ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.deleted_identity_tombstone_config (
  id smallint primary key
    constraint deleted_identity_tombstone_config_singleton_check check (id = 1),
  key_verifier text not null
    constraint deleted_identity_tombstone_config_verifier_check
    check (key_verifier ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

alter table public.deleted_identity_tombstones enable row level security;
alter table public.deleted_identity_tombstone_config enable row level security;

do $$
declare
  app_role text;
begin
  for app_role in
    select rolname from pg_roles where rolname in ('anon', 'authenticated', 'service_role')
  loop
    execute format('revoke all privileges on table public.account_deletion_jobs from %I', app_role);
    execute format('revoke all privileges on sequence public.account_deletion_jobs_id_seq from %I', app_role);
    execute format('revoke all privileges on table public.deleted_identity_tombstones from %I', app_role);
    execute format('revoke all privileges on sequence public.deleted_identity_tombstones_id_seq from %I', app_role);
    execute format('revoke all privileges on table public.deleted_identity_tombstone_config from %I', app_role);
  end loop;
end
$$;

revoke all privileges on table public.account_deletion_jobs from public;
revoke all privileges on sequence public.account_deletion_jobs_id_seq from public;
revoke all privileges on table public.deleted_identity_tombstones from public;
revoke all privileges on sequence public.deleted_identity_tombstones_id_seq from public;
revoke all privileges on table public.deleted_identity_tombstone_config from public;

create index if not exists idx_account_deletion_jobs_retry_queue
  on public.account_deletion_jobs (status, next_retry_at, updated_at, id)
  where status in ('pending', 'in_progress', 'retryable_failure');

create index if not exists idx_account_deletion_jobs_terminal_purge
  on public.account_deletion_jobs (completed_at, id)
  where status = 'completed';

-- NOT VALID deliberately preserves forward compatibility with completed rows
-- written before keyed tombstones existed. The Render pre-readiness scrubber
-- backfills their HMACs, removes raw identifiers/counts, then validates this
-- constraint. New or updated rows are enforced immediately by PostgreSQL.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.account_deletion_jobs'::regclass
      and conname = 'account_deletion_jobs_terminal_privacy_check'
  ) then
    alter table public.account_deletion_jobs
      add constraint account_deletion_jobs_terminal_privacy_check check (
        (
          status = 'completed'
          and user_id is null
          and supabase_user_id is null
          and idempotency_key = 'terminal:' || id::text
          and counts_json = '{}'::jsonb
          and completed_at is not null
        )
        or
        (
          status <> 'completed'
          and user_id is not null
          and idempotency_key <> 'terminal:' || id::text
          and completed_at is null
        )
      ) not valid;
  end if;
end
$$;

comment on table public.deleted_identity_tombstones is
  'Backend-only permanent deletion deny list containing keyed HMAC-SHA256 Supabase subject digests; never raw identity values.';

comment on table public.deleted_identity_tombstone_config is
  'Backend-only singleton HMAC key verifier. Detects accidental deletion-tombstone key loss or rotation without storing the key.';

comment on table public.account_deletion_jobs is
  'Backend-only operational deletion queue. Completed rows are immediately scrubbed and purged after a default 7-day TTL bounded to 30 days.';

-- Rollback is intentionally staged: stop account-deletion workers; confirm no
-- legacy completed rows still need tombstone backfill; remove the privacy check
-- and indexes; and only then drop deleted_identity_tombstones. Dropping the
-- tombstones re-enables recreation of deleted Supabase subjects and therefore
-- requires an explicit product/security decision.
