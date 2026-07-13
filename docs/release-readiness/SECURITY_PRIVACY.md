# Security And Privacy Data Map

## Data Categories

| Data | Purpose | Storage | Third Parties | Retention | Export | Deletion | Required |
|---|---|---|---|---|---|---|---|
| Account profile | Auth, display, role, instrument | Backend DB, Supabase Auth | Supabase | Account lifetime | `/api/users/me/export.zip` | `DELETE /api/users/me` plus Supabase admin delete when configured | Required for accounts |
| Email | Sign-in/reset/contact identity | Supabase Auth, backend user row | Supabase | Account lifetime | Account export | Account deletion | Required for email accounts |
| Auth tokens | Session authentication | Supabase client/session storage; native Keychain session storage | Supabase | Session lifetime | Not exported | Sign-out/global revoke path | Required for auth |
| Practice sessions | User progress and review | Backend DB | Render/Supabase DB hosting depending deployment | Until user deletes/export policy | Session/all ZIP | Account deletion or session deletion | Required for analytics |
| Pitch samples | Tuning analysis | Backend DB | Backend hosting | Until session/account deletion | CSV/JSON/ZIP | Session/account deletion | Required for analytics |
| Note events | Segmented note metrics | Backend DB | Backend hosting | Until session/account deletion | CSV/JSON/ZIP | Session/account deletion | Required for analytics |
| Recommendations | Practice guidance | Backend DB | Backend hosting | Until regenerated/deleted | Account export | Account deletion | Optional output |
| Audio recordings | Relisten/playback | Local storage or Supabase Storage | Supabase Storage when configured | Until session/account deletion | ZIP/audio endpoint | Session/account deletion deletes object | Optional; consent required |
| Ensemble groups | Teacher/student workflows | Backend DB | Backend hosting | Until director deletion/archive policy | Report/export | Teacher-owned groups deleted on teacher account deletion | Optional |
| Group memberships | Roster/access control | Backend DB | Backend hosting | Until removed/group deleted | Group/report export | Account deletion or group deletion | Optional |
| Invitations | Join/provisioning | Backend DB | Backend hosting | Until accepted/expired/deleted | Admin/report export | Account/group deletion | Optional |
| Logs | Operations/debugging | Host logs | Vercel/Render/Supabase | Provider retention | Not user-exported | Provider retention process | Operational |

## Implemented Controls

- JWT/Supabase auth context maps users through `supabase_user_id` or local dev tokens.
- Production local-auth defaults are disabled, and production startup now requires Supabase configuration. `BRASSTUNE_ALLOW_LOCAL_AUTH` is rejected in production.
- Backend server-side checks enforce session, audio, analytics, recommendation, export, and ensemble scoping.
- WebSocket URLs no longer carry bearer tokens; signed-in clients send an initial auth message, `stop_session` requires session ownership/admin, query-token auth is rejected, and production WebSocket origins must be explicitly allowed.
- Audio upload, raw WebSocket message, pitch-frame, and PCM payload sizes are capped.
- Global JSON request bodies are rejected before parsing when they exceed `BRASSTUNE_MAX_JSON_BODY_BYTES`. HTTP throttling now layers a per-client global budget, canonical route-family budget, and stricter class-join/expensive-operation budgets so rotating resource IDs cannot bypass limits or exhaust the route-bucket table.
- Render disables Uvicorn's automatic proxy-header rewriting. Following Render's April 2026 guidance and first-entry contract, the application validates the first `X-Forwarded-For` value for HTTP and WebSocket limits. A missing, oversized, scoped, or malformed first value falls back to the socket peer without scanning later attacker-controlled entries.
- WebSocket abuse controls cap connections per network/account, audio frames and PCM samples per second, concurrent pitch computations, and pending session IDs per connection.
- Account quotas bound owned classes, active memberships, pending invitations,
  cloud sessions, and stored recording bytes. Recording replacement subtracts the
  current session's prior size before evaluating the per-user audio quota.
- Score-practice source PDFs/images stay local by default; raw SVG is rejected instead of rendered.
- Guest export uses local guest data instead of cloud export endpoints.
- Supabase storage delete/read helpers avoid exposing upstream error bodies.
- Account export includes account profile, sessions, memberships, owned groups, invitations, recommendations, and session files for the authenticated user.
- Account deletion requires confirmation, records staged cleanup state, removes sessions, audio, memberships, invitations, recommendations, teacher-owned groups, and the user row, and blocks Supabase re-creation while external identity cleanup is queued.
- Frontend account deletion requires export action visibility and exact confirmation text.
- Aggregate ensemble summary/report endpoints require group manager access; active student members can view their group but not aggregate reports.

## Known Risks

- Account deletion now blocks re-login/re-creation while external cleanup is queued. The scheduled retry workflow exists, but production durability still requires `BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET` in Render and the GitHub production environment plus live disposable-account verification.
- WebSocket origin checks mirror the exact HTTP CORS policy. Production regex use remains disabled unless `BRASSTUNE_ALLOW_CORS_REGEX=1`; exact owner-controlled origins are preferred.
- Score image/PDF validation includes magic-byte/active-content checks and decoded-pixel caps, but still needs EXIF orientation/private metadata handling and stronger visual quality checks.
- Metronome click bleed, long-run drift, and physical-device audio behavior are not verified.
- Live observation on 2026-07-12: hosted Render `/api/version` reported `36a225ce0de638771c02bd7d5d7cebb25e6d2871`. The local committed baseline for this work was `a2be09eeb9f4cfa4b74e36eef8b07862dd45b091`; the current multi-class/play-along/security candidate is still uncommitted and is not deployed. Local or simulator results must not be attributed to the live Render SHA.
- Live Supabase deletion/export was not tested because disposable live credentials were not provided. The schema migrations needed for account deletion durability were applied to project `yznziwewxrlwnwiynlvl` on 2026-07-04, but Render deployment and disposable account/storage/delete journeys remain unverified.
- Supabase live-project drift was remediated for `public.rls_auto_enable()` by revoking execute from `public`, `anon`, and `authenticated`; verification showed `anon_execute=false` and `authenticated_execute=false`.
- A clean Supabase baseline plus the account-deletion/membership-window, invitation-index, usage, pruning, and 2026-07-11 class-code migrations are recorded on the linked project. The three 2026-07-12 membership uniqueness, join-code rotation, and Data API/storage-lockdown migrations remain local candidate work until they pass exact-SHA PostgreSQL CI and are deliberately applied. FastAPI remains the only application data path.
- Hosted smoke and account-deletion retry automation now validate approved BrassTune Vercel/Render hostnames before attaching Vercel bypass or maintenance secret headers.
- Native app production flows remain fixture-backed in several areas despite passing simulator builds/tests.
- Dependency audit evidence must stay tied to the exact environment and pushed SHA. The resolved local Python 3.12 environment reported no known vulnerabilities with `pip-audit --local`; the direct requirements-file resolver remained blocked by a temporary `ensurepip` SIGABRT. Treat the Security workflow on the exact pushed SHA as the remote merge gate.
