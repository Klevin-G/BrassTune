# Render operations (Supabase pg_cron)

The Render free web service (`https://brasstune-u8qj.onrender.com`) spins down after
~15 minutes of inactivity, adding a ~40s cold start to the next request. It is kept
warm by a Postgres `pg_cron` job in Supabase — **not** GitHub Actions — so it consumes
zero CI minutes. Account-deletion retry maintenance uses the same database-native
approach; see [ACCOUNT_DELETION_MAINTENANCE.md](ACCOUNT_DELETION_MAINTENANCE.md).

## How it works

A scheduled job in the Supabase database pings `/api/live` every 14 minutes via
`pg_net`. The timeout is 55s so a cold service is woken (not just timed out):

```sql
-- extensions (one-time)
create extension if not exists pg_net;
create extension if not exists pg_cron;

-- schedule (every 14 min, 55s timeout to survive a cold start)
select cron.schedule(
  'render-keepalive',
  '*/14 * * * *',
  $$select net.http_get(url := 'https://brasstune-u8qj.onrender.com/api/live', timeout_milliseconds := 55000)$$
);
```

Inspect / manage:

```sql
select jobid, schedule, active, command from cron.job where jobname = 'render-keepalive';
select status_code, error_msg from net._http_response order by id desc limit 5;  -- recent pings
select cron.unschedule('render-keepalive');                                       -- to disable
```

## Notes

- The previous `.github/workflows/render-keepalive.yml` and account-deletion retry
  workflow were removed — neither task consumes GitHub Actions minutes.
- Keeping the service warm 24/7 uses ~720 of Render free tier's 750 instance-hours/month.
  If that margin matters, narrow the cron to active hours (e.g. `*/14 6-23 * * *`).
