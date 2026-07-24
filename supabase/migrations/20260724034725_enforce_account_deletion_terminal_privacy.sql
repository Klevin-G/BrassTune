-- Contract phase for account-deletion privacy. This migration is intentionally
-- data-preserving: the deployed privacy-aware backend must initialize the
-- singleton config and scrub every completed job during the expand phase.
--
-- Supabase applies each migration batch and its history record transactionally,
-- so every prerequisite, lock, constraint change, and phase update below is one
-- atomic unit. This is deliberately a one-shot migration: replay after success
-- fails closed because the config is no longer in expand and the named
-- constraint already exists. Do not make replay silently idempotent.

-- Prevent a completion write from racing between the prerequisite scan and the
-- installation of the constraint. The lock is held until the transaction ends.
lock table public.account_deletion_jobs in share row exclusive mode;
lock table public.deleted_identity_tombstone_config in share row exclusive mode;

do $contract$
declare
  config_rows bigint;
  current_phase text;
  current_key_verifier text;
begin
  select count(*)
  into config_rows
  from public.deleted_identity_tombstone_config;

  if config_rows <> 1 then
    raise exception
      'account deletion privacy contract requires exactly one config row total with id=1, found %',
      config_rows;
  end if;

  select enforcement_phase, key_verifier
  into current_phase, current_key_verifier
  from public.deleted_identity_tombstone_config
  where id = 1
  for update;

  if not found then
    raise exception
      'account deletion privacy contract requires exactly one config row total and it must have id=1';
  end if;

  if current_phase <> 'expand' then
    raise exception
      'account deletion privacy contract requires config id=1 in expand, found %',
      current_phase;
  end if;

  if current_key_verifier is null
    or current_key_verifier !~ '^[0-9a-f]{64}$'
  then
    raise exception
      'account deletion privacy contract requires config id=1 key_verifier to be lowercase 64-hex';
  end if;

  if exists (
    select 1
    from public.account_deletion_jobs
    where status = 'completed'
      and not (
        stage = 'completed'
        and user_id is null
        and supabase_user_id is null
        and idempotency_key = 'terminal:' || id::text
        and safe_error_category is null
        and counts_json = '{}'::jsonb
        and next_retry_at is null
        and completed_at is not null
      )
  ) then
    raise exception
      'account deletion privacy contract requires all completed jobs to be fully scrubbed';
  end if;
end
$contract$;

alter table public.account_deletion_jobs
  add constraint account_deletion_jobs_terminal_privacy_check
  check (
    status <> 'completed'
    or (
      stage = 'completed'
      and user_id is null
      and supabase_user_id is null
      and idempotency_key = 'terminal:' || id::text
      and safe_error_category is null
      and counts_json = '{}'::jsonb
      and next_retry_at is null
      and completed_at is not null
    )
  ) not valid;

alter table public.account_deletion_jobs
  validate constraint account_deletion_jobs_terminal_privacy_check;

do $phase$
declare
  updated_rows integer;
begin
  update public.deleted_identity_tombstone_config
  set enforcement_phase = 'contract'
  where id = 1
    and enforcement_phase = 'expand';

  get diagnostics updated_rows = row_count;
  if updated_rows <> 1 then
    raise exception
      'account deletion privacy contract phase update affected % rows instead of exactly one',
      updated_rows;
  end if;
end
$phase$;
