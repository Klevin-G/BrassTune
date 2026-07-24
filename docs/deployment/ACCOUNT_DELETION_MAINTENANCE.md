# Account-deletion retry maintenance (Supabase only)

The retry executor is scheduled inside Supabase with `pg_cron` and calls Render
asynchronously with `pg_net`. It replaces the retired GitHub Actions workflow,
uses zero GitHub Actions minutes, and keeps its credentials in Vault.

## Production verification

Verified on 2026-07-24 against merged revision
`974271f963628fa6fb07374ce8ec04825230a577`:

- Supabase migration `20260724053727` is recorded, and the named job is active
  with schedule `*/15 * * * *`.
- Render deploy `dep-d9hg17epbkes73a0d7cg` is live at the same revision; public
  readiness reports every check healthy.
- A manually generated valid signed request returned `204`; replaying the same
  nonce and using the retired static-secret header each returned `403`.
- A manual call through the private SQL signer produced pg_net request `1745`
  with `204` and no error.
- The first scheduled cron run, run `1748` at 06:15 UTC, succeeded; its pg_net
  request `1747` returned `204` with no error.
- The obsolete maintenance-only GitHub runner registration, container, volume,
  and image tags were removed after the scheduled success. General Linux/macOS
  runners were not changed, and every remaining workflow stays manually disabled.

## One-time preflight

Before applying migration
`20260724053727_schedule_account_deletion_maintenance_via_supabase_cron.sql`,
use the Supabase Dashboard Vault UI to create exactly one secret with each of
these stable names:

- `brasstune_account_deletion_retry_url` — the approved Render production origin.
- `brasstune_maintenance_hmac_key_id` — the current non-secret key identifier.
- `brasstune_maintenance_hmac_key` — the current base64-encoded HMAC key, with at
  least 32 decoded bytes.

The key ID/key must match the private Render configuration variables
`BRASSTUNE_MAINTENANCE_HMAC_KEY_ID` and `BRASSTUNE_MAINTENANCE_HMAC_KEY` for the
new HMAC-authenticated maintenance contract. Do not put the values in migrations,
GitHub secrets, shell history, logs, screenshots, or this repository.

Run this no-secret inventory query in Supabase SQL Editor. It returns names and
counts only, never decrypted values:

```sql
select name, count(*) as count
from vault.secrets
where name in (
  'brasstune_account_deletion_retry_url',
  'brasstune_maintenance_hmac_key_id',
  'brasstune_maintenance_hmac_key'
)
group by name
order by name;
```

The migration fails closed unless all `pg_cron`, `pg_net`, `pgcrypto`, and
Vault prerequisites are present; each stable Vault name appears exactly once;
the URL matches the approved Render origin; and the decoded HMAC key is at
least 32 bytes. It creates a private `SECURITY INVOKER` function with an empty
search path and no arguments, then schedules the stable job name
`brasstune-account-deletion-retry` every 15 minutes with `cron.schedule`.
It never edits `cron.job` directly.

## Request contract

The scheduled function always sends `POST {}` to
`/api/maintenance/account-deletions/retry` with `Content-Type: application/json`
and these authenticated headers:

- `X-BrassTune-Maintenance-Version: v1`
- `X-BrassTune-Maintenance-Key-Id`
- `X-BrassTune-Maintenance-Timestamp`
- `X-BrassTune-Maintenance-Nonce`
- `X-BrassTune-Maintenance-Purpose: account-deletions-retry-v1`
- `X-BrassTune-Maintenance-Signature`

The signature is unpadded base64url HMAC-SHA256 over the LF-joined canonical
fields: `v1`, `POST`, path, empty sorted query, lowercase SHA-256 hex of `{}`,
epoch timestamp, nonce, and purpose. The exact request URL, body, and headers
are constructed inside the zero-argument function; callers cannot supply
alternatives.

## Observability and incident controls

These queries expose schedule and response metadata only. Do not select Vault's
decrypted view or `net` request payload/header columns while troubleshooting.

```sql
select jobid, jobname, schedule, active
from cron.job
where jobname = 'brasstune-account-deletion-retry';

select id, status_code, error_msg, created
from net._http_response
order by id desc
limit 20;
```

`pg_net` keeps response history for a limited period, so copy the safe status,
timestamp, and error category into the incident record before it expires.

Fail closed during an incident or maintenance window:

```sql
select cron.unschedule('brasstune-account-deletion-retry');
```

To restore it after the cause is resolved, reapply the reviewed migration through
a new explicit reviewed migration, or run the same safe scheduling function directly:

```sql
select cron.schedule(
  'brasstune-account-deletion-retry',
  '*/15 * * * *',
  $cron$select brasstune_private.enqueue_account_deletion_retry();$cron$
);
```

`cron.schedule` owns the same-name schedule update. Do not insert, update, or
delete rows in `cron.job` directly.

## Rotation

Rotate the key ID and key together in this order:

1. Deploy Render with the new current pair in
   `BRASSTUNE_MAINTENANCE_HMAC_KEY_ID`/`BRASSTUNE_MAINTENANCE_HMAC_KEY` and the
   old pair retained in its private previous-key configuration.
2. Use the Vault Dashboard edit/update flow to update the same stable Vault names
   to the new pair, preserving exactly one row for each name.
3. Verify the inventory counts and observe at least one successful scheduled
   request after the five-minute replay window has elapsed.
4. Only then remove the old private previous-key pair from Render and redeploy.

Never switch Vault before Render accepts the new key, create a second "current"
secret row, or paste a key into SQL, GitHub, logs, or support tickets.
