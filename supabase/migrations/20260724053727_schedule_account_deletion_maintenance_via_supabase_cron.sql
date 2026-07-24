-- Move the account-deletion retry trigger out of GitHub Actions.  The cron
-- worker reads the three secrets from Vault only at execution time; this file
-- deliberately contains names and validation rules, never credential values.
--
-- The job command invokes a zero-argument, SECURITY INVOKER function.  It has
-- no caller-supplied URL, headers, or body and therefore cannot be repurposed
-- as an arbitrary outbound request primitive.

-- Backend-only replay cache for signed maintenance requests. Only the SHA-256
-- digest of each nonce is retained; raw nonces, signatures, bodies, and user
-- identifiers are never stored here.
create table if not exists public.maintenance_request_nonces (
  id bigserial primary key,
  nonce_digest text not null unique
    constraint maintenance_request_nonces_digest_check
    check (nonce_digest ~ '^[0-9a-f]{64}$'),
  key_id text not null
    constraint maintenance_request_nonces_key_id_check
    check (key_id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'),
  purpose text not null
    constraint maintenance_request_nonces_purpose_check
    check (purpose in ('account-deletions-retry-v1', 'audio-storage-retry-v1')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

alter table public.maintenance_request_nonces enable row level security;

do $privacy$
declare
  app_role text;
begin
  for app_role in
    select rolname from pg_roles where rolname in ('anon', 'authenticated', 'service_role')
  loop
    execute format(
      'revoke all privileges on table public.maintenance_request_nonces from %I',
      app_role
    );
    execute format(
      'revoke all privileges on sequence public.maintenance_request_nonces_id_seq from %I',
      app_role
    );
  end loop;
end;
$privacy$;

revoke all privileges on table public.maintenance_request_nonces from public;
revoke all privileges on sequence public.maintenance_request_nonces_id_seq from public;

create index if not exists idx_maintenance_request_nonces_expires_at
  on public.maintenance_request_nonces (expires_at);

comment on table public.maintenance_request_nonces is
  'Backend-only short-lived replay cache for signed maintenance requests. Stores nonce digests and coarse executor metadata only.';

do $bootstrap$
declare
  required_extension text;
  secret_name text;
  secret_count integer;
  url_value text;
  key_id_value text;
  key_base64_value text;
  key_value bytea;
begin
  foreach required_extension in array array['pg_cron', 'pg_net', 'pgcrypto', 'supabase_vault']
  loop
    if not exists (
      select 1 from pg_extension where extname = required_extension
    ) then
      raise exception 'Account-deletion scheduler requires extension %', required_extension;
    end if;
  end loop;

  if to_regclass('vault.decrypted_secrets') is null then
    raise exception 'Account-deletion scheduler requires vault.decrypted_secrets';
  end if;

  if to_regprocedure('cron.schedule(text,text,text)') is null
    or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null
    or to_regprocedure('extensions.hmac(bytea,bytea,text)') is null
    or to_regprocedure('extensions.digest(bytea,text)') is null
    or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception 'Account-deletion scheduler requires pg_cron, pg_net, and pgcrypto functions in their approved schemas';
  end if;

  foreach secret_name in array array[
    'brasstune_account_deletion_retry_url',
    'brasstune_maintenance_hmac_key_id',
    'brasstune_maintenance_hmac_key'
  ]
  loop
    select count(*)
      into secret_count
      from vault.decrypted_secrets
     where name = secret_name;
    if secret_count <> 1 then
      raise exception 'Account-deletion scheduler requires exactly one Vault secret named %, found %', secret_name, secret_count;
    end if;
  end loop;

  select decrypted_secret
    into strict url_value
    from vault.decrypted_secrets
   where name = 'brasstune_account_deletion_retry_url';
  if url_value <> 'https://brasstune-u8qj.onrender.com' then
    raise exception 'Account-deletion scheduler URL Vault secret must equal the approved Render production origin';
  end if;

  select decrypted_secret
    into strict key_id_value
    from vault.decrypted_secrets
   where name = 'brasstune_maintenance_hmac_key_id';
  if key_id_value is null
    or key_id_value !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' then
    raise exception 'Account-deletion scheduler maintenance key id is invalid';
  end if;

  select decrypted_secret
    into strict key_base64_value
    from vault.decrypted_secrets
   where name = 'brasstune_maintenance_hmac_key';
  if key_base64_value is null
    or key_base64_value !~ '^[A-Za-z0-9+/]+={0,2}$'
    or length(key_base64_value) % 4 <> 0 then
    raise exception 'Account-deletion scheduler maintenance HMAC key must be padded base64';
  end if;
  key_value := pg_catalog.decode(key_base64_value, 'base64');
  if octet_length(key_value) < 32 then
    raise exception 'Account-deletion scheduler maintenance HMAC key is too short';
  end if;
end;
$bootstrap$;

create schema if not exists brasstune_private;

revoke all privileges on schema brasstune_private from public;
revoke all privileges on schema brasstune_private from anon;
revoke all privileges on schema brasstune_private from authenticated;
revoke all privileges on schema brasstune_private from service_role;

create or replace function brasstune_private.enqueue_account_deletion_retry()
returns bigint
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_url text;
  v_key_id text;
  v_key_base64 text;
  v_key bytea;
  v_timestamp text;
  v_nonce text;
  v_body text := '{}';
  v_body_sha256 text;
  v_canonical text;
  v_signature text;
  v_headers jsonb;
  v_secret_count integer;
begin
  select count(*)
    into v_secret_count
    from vault.decrypted_secrets
   where name = 'brasstune_account_deletion_retry_url';
  if v_secret_count <> 1 then
    raise exception 'Account-deletion scheduler requires exactly one current retry URL Vault secret';
  end if;
  select decrypted_secret into strict v_url
    from vault.decrypted_secrets
   where name = 'brasstune_account_deletion_retry_url';
  if v_url <> 'https://brasstune-u8qj.onrender.com' then
    raise exception 'Account-deletion scheduler retry URL does not match approved production origin';
  end if;

  select count(*)
    into v_secret_count
    from vault.decrypted_secrets
   where name = 'brasstune_maintenance_hmac_key_id';
  if v_secret_count <> 1 then
    raise exception 'Account-deletion scheduler requires exactly one current maintenance key id';
  end if;
  select decrypted_secret into strict v_key_id
    from vault.decrypted_secrets
   where name = 'brasstune_maintenance_hmac_key_id';
  if v_key_id is null or v_key_id !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' then
    raise exception 'Account-deletion scheduler maintenance key id is invalid';
  end if;

  select count(*)
    into v_secret_count
    from vault.decrypted_secrets
   where name = 'brasstune_maintenance_hmac_key';
  if v_secret_count <> 1 then
    raise exception 'Account-deletion scheduler requires exactly one current maintenance HMAC key';
  end if;
  select decrypted_secret into strict v_key_base64
    from vault.decrypted_secrets
   where name = 'brasstune_maintenance_hmac_key';
  if v_key_base64 is null
    or v_key_base64 !~ '^[A-Za-z0-9+/]+={0,2}$'
    or length(v_key_base64) % 4 <> 0 then
    raise exception 'Account-deletion scheduler maintenance HMAC key must be padded base64';
  end if;
  v_key := pg_catalog.decode(v_key_base64, 'base64');
  if octet_length(v_key) < 32 then
    raise exception 'Account-deletion scheduler maintenance HMAC key is too short';
  end if;

  v_timestamp := floor(extract(epoch from clock_timestamp()))::bigint::text;
  v_nonce := pg_catalog.encode(extensions.gen_random_bytes(24), 'hex');
  v_body_sha256 := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(v_body, 'UTF8'), 'sha256'),
    'hex'
  );
  v_canonical := concat_ws(
    E'\n',
    'v1',
    'POST',
    '/api/maintenance/account-deletions/retry',
    '',
    v_body_sha256,
    v_timestamp,
    v_nonce,
    'account-deletions-retry-v1'
  );
  v_signature := rtrim(
    translate(
      pg_catalog.encode(
        extensions.hmac(pg_catalog.convert_to(v_canonical, 'UTF8'), v_key, 'sha256'),
        'base64'
      ),
      '+/', '-_'
    ),
    '='
  );
  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'X-BrassTune-Maintenance-Version', 'v1',
    'X-BrassTune-Maintenance-Key-Id', v_key_id,
    'X-BrassTune-Maintenance-Timestamp', v_timestamp,
    'X-BrassTune-Maintenance-Nonce', v_nonce,
    'X-BrassTune-Maintenance-Purpose', 'account-deletions-retry-v1',
    'X-BrassTune-Maintenance-Signature', v_signature
  );

  return net.http_post(
    url := v_url || '/api/maintenance/account-deletions/retry',
    body := v_body::jsonb,
    params := '{}'::jsonb,
    headers := v_headers,
    timeout_milliseconds := 55000
  );
end;
$function$;

revoke all privileges on function brasstune_private.enqueue_account_deletion_retry() from public;
revoke all privileges on function brasstune_private.enqueue_account_deletion_retry() from anon;
revoke all privileges on function brasstune_private.enqueue_account_deletion_retry() from authenticated;
revoke all privileges on function brasstune_private.enqueue_account_deletion_retry() from service_role;

-- cron.schedule updates the same named job on supported Supabase pg_cron;
-- never edit cron.job directly.
select cron.schedule(
  'brasstune-account-deletion-retry',
  '*/15 * * * *',
  $cron$select brasstune_private.enqueue_account_deletion_retry();$cron$
);
