# Supabase Integration

BrassTune supports local SQLite demo mode by default and Supabase-backed production mode when environment variables are configured.

## Environment Variables

Frontend:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_API_BASE_URL`
- `VITE_WS_BASE_URL`

Backend:
- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `SUPABASE_PUBLISHABLE_KEY`
- `DATABASE_URL` or `BRASSTUNE_DATABASE_URL`
- `SESSION_AUDIO_STORAGE_BACKEND=supabase`
- `SUPABASE_STORAGE_BUCKET=session-audio`
- `CORS_ALLOWED_ORIGINS`
- `APP_ENV=production`
- `BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET`

Never expose `SUPABASE_SECRET_KEY` in Vercel or the browser bundle.

## Auth Flow

The React app uses `@supabase/supabase-js` with the publishable key. The backend validates Bearer tokens through Supabase `/auth/v1/user`, then syncs a local `User` row keyed by `supabase_user_id`.

Local mode permits no-token guest/demo requests. Production mode requires a token for private session, export, audio, and ensemble endpoints.

## Hosted Auth Setup

Configure Supabase before inviting auth testers:

1. Set Site URL to `https://brass-tune.vercel.app`.
2. Add redirect allowlist entries for:
   - `https://brass-tune.vercel.app/auth/callback`
   - `https://brass-tune.vercel.app/auth/reset-password`
   - approved Vercel preview URL patterns used for owner-controlled testing
   - approved Vercel preview reset-password URL patterns used for owner-controlled testing
   - local development callback and reset-password URLs only for dev environments
3. Enable email/password auth and decide whether email confirmation is required.
4. Configure custom SMTP before relying on password-reset delivery at beta scale.
5. Configure Apple provider only after Apple Developer Services ID/native capability values are final.
6. Keep production auth rate limits and bot-abuse settings reviewed before external testers are invited.

Use exact production redirect URLs where possible. Wildcard preview redirects are acceptable only for owner-controlled previews and should be reviewed before public release.

## Live Auth Test Gates

Do not mark live auth complete until disposable live accounts verify:

- email sign-up, confirmation, duplicate account, weak password, sign-in, sign-out, and token refresh
- password reset email delivery and callback recovery
- Apple OAuth start, cancel/error, successful callback, and account profile completion
- authenticated session save/export/delete
- account deletion cleanup for app data, Supabase identity, storage objects, and session state
- account deletion retry executor completion for retryable Supabase identity cleanup jobs

Record results in `docs/release-readiness/LIVE_AUTH_TEST_PLAN.md`. Do not use real user data or paste tokens, reset links, service keys, or Apple private keys into docs.

## Storage

Production audio storage uses a private Supabase Storage bucket:

```text
session-audio
```

Object key pattern:

```text
{user_id}/{session_id}/recording.webm
```

Playback URLs are generated server-side. The frontend never receives the service key.

Uploaded source videos are different: BrassTune does not store them in Supabase. Local media import decodes the selected file in the browser, saves only derived pitch frames, and leaves the original video/audio on the user’s device.

## Database

Local development uses SQLite. Production can use Supabase Postgres via `DATABASE_URL` or `BRASSTUNE_DATABASE_URL`.

Production deployments fail closed when `APP_ENV` is deployed and no PostgreSQL URL is configured. Local SQLite is only for local/test/dev.

Migrations:

```text
supabase/migrations/20260616_brasstune_baseline.sql
supabase/migrations/20260617_brasstune_production_readiness.sql
supabase/migrations/20260618_lock_down_rls_auto_enable.sql
supabase/migrations/20260620_account_deletion_and_membership_windows.sql
supabase/migrations/20260625_invitation_fk_indexes.sql
```

`20260616_brasstune_baseline.sql` is the clean-database schema baseline. `20260617_brasstune_production_readiness.sql` remains additive for existing deployments, `20260618_lock_down_rls_auto_enable.sql` revokes public execution from the drifted helper RPC reported by Supabase advisors, `20260620_account_deletion_and_membership_windows.sql` adds account deletion and membership-window schema, and `20260625_invitation_fk_indexes.sql` adds the missing invitation foreign-key indexes reported by Supabase advisors.

As of the 2026-07-04 provider gate, the connected project `yznziwewxrlwnwiynlvl` records all five migrations. The June 20 and June 25 migrations were applied through Supabase migration history as `20260704022241` and `20260704022304` after a zero-row production safety snapshot.

Post-apply verification showed:

- `public.account_deletion_jobs` exists and has RLS enabled.
- `account_deletion_jobs.counts_json` is `jsonb not null default '{}'::jsonb`.
- `public.group_members.active_since` and `public.group_members.removed_at` exist.
- `idx_group_members_active_window`, `idx_invitations_invited_user_id`, and `idx_invitations_invited_by_user_id` exist.
- Row counts stayed at zero for `auth.users`, app tables, `account_deletion_jobs`, and `storage.objects`.
- `session-audio` remains private with the expected audio MIME allowlist.
- Supabase security advisors still report RLS-enabled/no-policy informational notices because FastAPI mediates app access and no direct browser table policies are intentionally present.
- Supabase performance advisors no longer report the invitation foreign-key index gaps; remaining unused-index notices are expected on an empty project.

Supabase changed Data API exposure behavior in 2026, so after applying migrations verify exposed schema grants deliberately. Keep RLS enabled on public tables and do not add broad browser grants until direct browser-to-table access is designed.

## Security Notes

- Do not use user-editable metadata for authorization.
- Store roles in backend-controlled local rows or explicit backend admin tooling. User/app metadata from Supabase Auth must not grant privileged local roles.
- Keep the `session-audio` bucket private.
- Use signed URLs for playback.
- Restrict CORS with `CORS_ALLOWED_ORIGINS` in production.
- Keep service-role or secret keys only in Render/Supabase/GitHub secret stores; never expose them through `VITE_*` frontend variables.
