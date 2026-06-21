alter table if exists public.group_members
  add column if not exists active_since timestamptz,
  add column if not exists removed_at timestamptz;

update public.group_members
set active_since = created_at
where active_since is null;

create table if not exists public.account_deletion_jobs (
  id bigserial primary key,
  user_id bigint not null,
  supabase_user_id text,
  idempotency_key text not null unique,
  stage text not null default 'requested',
  status text not null default 'pending',
  retry_count integer not null default 0,
  next_retry_at timestamptz,
  safe_error_category text,
  counts_json jsonb not null default '{}'::jsonb,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.account_deletion_jobs enable row level security;

create index if not exists idx_account_deletion_jobs_user_id
  on public.account_deletion_jobs(user_id);

create index if not exists idx_account_deletion_jobs_supabase_user_id
  on public.account_deletion_jobs(supabase_user_id);

create index if not exists idx_group_members_active_window
  on public.group_members(group_id, user_id, status, active_since);
