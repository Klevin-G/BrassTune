# Security Review

## Changes Added

- Backend auth context validates Supabase Bearer tokens when configured.
- Production mode rejects private requests without authentication.
- Local mode still supports seeded guest/demo access.
- Session reads/writes, exports, audio, and analytics scope to the current user unless admin.
- WebSocket persistence checks session ownership.
- Audio upload validates MIME type and size.
- Audio storage keys are generated server-side.
- Local audio paths reject traversal.
- Local video/audio import decodes in the browser and never uploads the source media file.
- Export endpoints are protected and support authenticated blob downloads in the frontend.
- Ensemble mutations require director/admin ownership.
- CORS origins are env-configured for production.
- HTTP abuse controls combine a per-client global budget, canonical route-family
  budget, and stricter class-join/expensive-operation budgets. Numeric and UUID
  path rotation cannot create a fresh route budget.
- Render disables Uvicorn proxy-header rewriting; the application consumes the
  raw forwarding chain and validates Render's documented first client-IP entry.
  A malformed first entry fails back to the socket peer without scanning later
  attacker-controlled values.
- WebSocket connections are capped per network and account; audio frames have
  frame/PCM budgets, pitch computation has a process-wide concurrency cap, and
  pending session IDs are bounded per connection.
- `.env.example` contains placeholders only.

## Tests Added

- Production 401 without token.
- 403 for another user’s session.
- Audio upload/playback.
- Bad upload MIME rejection.
- ZIP export contents.
- Director add-by-username success.
- Student add-by-username denial.
- HTTP route-rotation, bucket-cardinality, proxy-hop, and expensive-operation limits.
- WebSocket connection release, account/network caps, burst closure, compute,
  and pending-session bounds.

Abuse-limit defaults can be tuned with `BRASSTUNE_GLOBAL_RATE_LIMIT_PER_MINUTE`,
`BRASSTUNE_RATE_LIMIT_PER_MINUTE`, `BRASSTUNE_CLASS_JOIN_RATE_LIMIT_PER_MINUTE`,
`BRASSTUNE_EXPENSIVE_MUTATION_RATE_LIMIT_PER_MINUTE`,
`BRASSTUNE_WS_MAX_CONNECTIONS_PER_IP`,
`BRASSTUNE_WS_MAX_CONNECTIONS_PER_ACCOUNT`,
`BRASSTUNE_WS_MAX_AUDIO_FRAMES_PER_SECOND`,
`BRASSTUNE_WS_MAX_PCM_SAMPLES_PER_SECOND`, and
`BRASSTUNE_WS_MAX_CONCURRENT_PITCH_COMPUTATIONS`.

Persistent account quotas default to:

- `BRASSTUNE_MAX_OWNED_CLASSES_PER_USER=10`
- `BRASSTUNE_MAX_ACTIVE_CLASS_MEMBERSHIPS_PER_USER=20`
- `BRASSTUNE_MAX_PENDING_CLASS_INVITATIONS_PER_USER=20`
- `BRASSTUNE_MAX_SESSIONS_PER_USER=5000`
- `BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER=524288000` (500 MiB)

Class quotas require values from `1` through `10000`; `0`, negative, or invalid
values fall back to the safe defaults above. Session and audio quotas accept `0`
only as a deliberate unlimited local/test setting. Negative or invalid session,
audio, HTTP, and WebSocket safety limits fall back to their safe defaults.
Export limits are mandatory: zero, negative, or invalid values fall back to
their safe defaults instead of disabling response-size protections.

## Tooling

GitHub Actions security workflow runs:

- `npm audit --omit=dev`
- `pip-audit`
- `bandit`
- `gitleaks`

Local checks should be run before release:

```bash
(cd frontend && npm audit --omit=dev)
(cd backend && python -m pip install pip-audit bandit)
(cd backend && pip-audit -r requirements.txt -r requirements-dev.txt)
(cd backend && bandit -r app -x app/tests)
gitleaks detect --source .
```

Do not add vulnerability ignores merely to make the audit green. The checked-in
security floor currently resolves to patched FastAPI/Starlette versions; new
dependency advisories must fail CI until they are remediated or explicitly reviewed.

## Supabase Notes

- Do not use user-editable metadata for authorization.
- Keep service/secret keys server-only.
- Keep `session-audio` private.
- Verify Data API table exposure settings on new Supabase projects.
- Keep RLS enabled for public tables.

## Remaining Risks

- Abuse counters are process-local. A multi-process or horizontally scaled
  deployment needs a shared limiter store to enforce one global budget.
- Confirm the live Supabase dashboard uses only exact production redirects or
  owner-suffix-restricted preview callbacks; repository config cannot prove
  provider drift is absent.
- Supabase RLS policies are intentionally conservative scaffolding until direct table access is designed.
- Real-device microphone validation is still manual.
- Supabase Storage object deletion is implemented for session deletion, practice-data clearing, account deletion, and retry recovery. The remaining risk is live disposable-account/storage verification, including provider failures and cleanup retries.
