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

Never expose `SUPABASE_SECRET_KEY` in Vercel or the browser bundle.

## Auth Flow

The React app uses `@supabase/supabase-js` with the publishable key. The backend validates Bearer tokens through Supabase `/auth/v1/user`, then syncs a local `User` row keyed by `supabase_user_id`.

Local mode permits no-token guest/demo requests. Production mode requires a token for private session, export, audio, and ensemble endpoints.

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

Migrations:

```text
supabase/migrations/20260616_brasstune_baseline.sql
supabase/migrations/20260617_brasstune_production_readiness.sql
supabase/migrations/20260618_lock_down_rls_auto_enable.sql
```

`20260616_brasstune_baseline.sql` is the clean-database schema baseline. `20260617_brasstune_production_readiness.sql` remains additive for existing deployments, and `20260618_lock_down_rls_auto_enable.sql` revokes public execution from the drifted helper RPC reported by Supabase advisors.

Supabase changed Data API exposure behavior in 2026, so after applying migrations verify exposed schema grants deliberately. Keep RLS enabled on public tables and do not add broad browser grants until direct browser-to-table access is designed.

## Security Notes

- Do not use user-editable metadata for authorization.
- Store roles in backend-controlled local rows or Supabase app metadata.
- Keep the `session-audio` bucket private.
- Use signed URLs for playback.
- Restrict CORS with `CORS_ALLOWED_ORIGINS` in production.
