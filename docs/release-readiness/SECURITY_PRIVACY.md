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
- Production local-auth defaults are disabled unless explicitly allowed.
- Backend server-side checks enforce session, audio, analytics, recommendation, export, and ensemble scoping.
- WebSocket `stop_session` now requires session ownership/admin.
- Audio upload and PCM payload sizes are capped.
- Supabase storage delete/read helpers avoid exposing upstream error bodies.
- Account deletion requires confirmation and removes sessions, audio, memberships, invitations, recommendations, teacher-owned groups, user row, and Supabase identity/session when configured.
- Frontend account deletion requires export action visibility and exact confirmation text.

## Known Risks

- WebSocket auth currently uses a query-string token. Prefer a short-lived WebSocket ticket or first-message auth before production scale.
- Supabase revocation/deletion occurs after local DB commit; failures return error but local data may already be deleted. Add outbox/retry for stronger operational guarantees.
- Hosted Render WebSocket route currently fails with `404`; production tuner WebSocket cannot be called verified until deployment/routing is fixed.
- Live Supabase deletion/export was not tested because disposable live credentials were not provided.
