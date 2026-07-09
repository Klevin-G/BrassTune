# Threat Model

Date: 2026-06-18

## Assets

- Supabase identities, sessions, and OAuth provider configuration.
- Backend user rows, roles, practice sessions, pitch samples, note events, recommendations, ensembles, memberships, invitations, exports, and audio objects.
- Web/native auth tokens and account deletion/export flows.
- Teacher aggregate reports and student roster membership state.

## Primary Risks And Mitigations

| Risk | Impact | Mitigation In Repo | Remaining Work |
|---|---|---|---|
| Token leakage through WebSocket URLs | Access tokens can appear in logs, screenshots, proxies, or diagnostics | Frontend now opens `/ws/pitch` without query token and sends a first auth frame; Audio Lab no longer receives tokenized URLs | Consider short-lived WS tickets after live auth is available |
| Email-only Supabase linking inherits privileged local role | Self-provisioned account could claim director/admin role | Email fallback without app metadata now demotes privileged local rows to `student`; regression test added | Define owner-approved teacher provisioning/invitation process |
| Cross-group report exposure | Students/non-owners can read aggregate ensemble metrics | Aggregate summary/report now require group manager; group roster remains visible to active members | Add full invitation/membership effective-date model |
| Account deletion split-brain | Local data and Supabase Auth can diverge on partial failure | Local app data/audio cleanup runs first; external Supabase identity/storage cleanup failure records a durable retry/tombstone and blocks account re-creation | Run live Supabase deletion/retry acceptance with disposable users and document old-token behavior |
| Storage orphaning | Audio objects remain after bulk row deletion | Demo/admin clear paths call audio delete before deleting session rows | Add periodic storage reconciliation for Supabase buckets |
| Overbroad CORS preview regex | Unowned Vercel origins can make credentialed requests if they obtain a token | Render config no longer sets broad `https://.*\\.vercel\\.app` by default | Owner must set exact production/preview origins |
| Oversized media/audio payloads | Browser/backend memory and storage pressure | PCM schema cap, upload limit, local media preflight, batch cap, audit tests | Add ASGI raw JSON request-size middleware and quotas |
| Live Supabase project drift | Public `SECURITY DEFINER` function may be callable by `anon`/`authenticated` | Applied `20260618_lock_down_rls_auto_enable`; verified `anon_execute=false` and `authenticated_execute=false` | Periodically rerun Supabase advisors and migration-drift checks |

## Trust Boundaries

- Browser and native clients are untrusted; backend authorization must enforce all session, audio, export, and ensemble access.
- Supabase service role keys must stay server-only.
- Vercel/Render/Supabase settings are deployment state and must be verified separately from local tests.
- Simulator audio tests do not prove physical microphone quality.
