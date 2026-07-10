-- Keep Supabase storage lean: raw per-frame pitch_samples power the fine
-- session-review timeline but dwarf everything else. Note events + session
-- aggregates (small) are kept forever, so analytics/rosters/reports are
-- unaffected. Prune raw frames older than 90 days, and usage events older
-- than 365 days, weekly via pg_cron (already enabled for the keep-alive job).

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Re-schedule idempotently.
    perform cron.unschedule(jobid) from cron.job where jobname = 'brasstune-prune-pitch-samples';
    perform cron.schedule(
      'brasstune-prune-pitch-samples',
      '17 4 * * 0',
      $job$delete from public.pitch_samples where created_at < now() - interval '90 days'$job$
    );

    perform cron.unschedule(jobid) from cron.job where jobname = 'brasstune-prune-usage-events';
    perform cron.schedule(
      'brasstune-prune-usage-events',
      '27 4 * * 0',
      $job$delete from public.usage_events where created_at < now() - interval '365 days'$job$
    );
  end if;
end $$;
