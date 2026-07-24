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
  enforcement_phase text not null default 'expand'
    constraint deleted_identity_tombstone_config_enforcement_phase_check
    check (enforcement_phase in ('expand', 'contract')),
  created_at timestamptz not null default now()
);

-- Keep the expand migration idempotent for disposable/local databases that may
-- already have the pre-phase version of the config table.
alter table public.deleted_identity_tombstone_config
  add column if not exists enforcement_phase text not null default 'expand';

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

-- Expand phase only: do not add the terminal privacy CHECK here. PostgreSQL
-- enforces CHECK constraints added NOT VALID for every subsequent insert and
-- update, so adding it before the privacy-aware backend is live would break the
-- known-good b84dacc writer and make that rollback unsafe. The backend startup
-- scrubber initializes the keyed tombstone state and converts legacy terminal
-- rows. 20260724034725_enforce_account_deletion_terminal_privacy.sql is the
-- separately applied contract phase and adds/validates the strict CHECK only
-- after that scrub succeeds.

comment on table public.deleted_identity_tombstones is
  'Backend-only permanent deletion deny list containing keyed HMAC-SHA256 Supabase subject digests; never raw identity values.';

comment on table public.deleted_identity_tombstone_config is
  'Backend-only singleton HMAC key verifier and explicit expand/contract rollout state. Detects accidental deletion-tombstone key loss or rotation without storing the key.';

comment on table public.account_deletion_jobs is
  'Backend-only operational deletion queue. Completed rows are immediately scrubbed and purged after a default 7-day TTL bounded to 30 days.';

-- Expand-phase rollback remains compatible with b84dacc because this migration
-- adds no terminal-row CHECK. After the separate contract migration is applied,
-- b84dacc is no longer a compatible rollback: retain and use the exact deployed
-- privacy-aware backend artifact. Dropping tombstones re-enables recreation of
-- deleted Supabase subjects and requires an explicit product/security decision.
