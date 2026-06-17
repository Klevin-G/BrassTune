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
- `.env.example` contains placeholders only.

## Tests Added

- Production 401 without token.
- 403 for another user’s session.
- Audio upload/playback.
- Bad upload MIME rejection.
- ZIP export contents.
- Director add-by-username success.
- Student add-by-username denial.

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
(cd backend && pip-audit -r requirements.txt \
  --ignore-vuln PYSEC-2026-161 \
  --ignore-vuln GHSA-wqp7-x3pw-xc5r \
  --ignore-vuln GHSA-x746-7m8f-x49c \
  --ignore-vuln GHSA-82w8-qh3p-5jfq \
  --ignore-vuln GHSA-jp82-jpqv-5vv3)
(cd backend && bandit -r app -x app/tests)
gitleaks detect --source .
```

The Starlette ignores are exact and temporary. The current published FastAPI package still requires `starlette<1.0.0`, while these advisories list fixed Starlette versions outside that supported range. New dependency advisories still fail CI.

## Supabase Notes

- Do not use user-editable metadata for authorization.
- Keep service/secret keys server-only.
- Keep `session-audio` private.
- Verify Data API table exposure settings on new Supabase projects.
- Keep RLS enabled for public tables.

## Remaining Risks

- Rate limiting is documented but not fully implemented.
- Supabase RLS policies are intentionally conservative scaffolding until direct table access is designed.
- Real-device microphone validation is still manual.
- Supabase Storage delete is deferred to lifecycle/admin policy; local delete is implemented.
