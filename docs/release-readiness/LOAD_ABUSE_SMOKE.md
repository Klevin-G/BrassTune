# Load And Abuse Smoke

Status: conservative smoke guidance for closed beta. This is not a benchmark, penetration test, or capacity guarantee.

## Scope

Run only against owner-approved production or staging URLs. Keep volume low enough to avoid disrupting testers, exhausting provider quotas, or creating synthetic user data that looks real.

## Preflight

- Confirm owner approval for target URL and time window.
- Confirm `APP_ENV=production` and production CORS origins are configured.
- Confirm Render, Vercel, Supabase, and GitHub Actions dashboards are accessible to the owner.
- Confirm no real student roster, private recording, or personal account is used.

## Smoke Checks

1. Hosted baseline:
   ```bash
   BRASSTUNE_WEB_BASE_URL=https://brasstune.vercel.app \
   BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
   BRASSTUNE_WS_BASE_URL=wss://brasstune-u8qj.onrender.com \
   npm run smoke:hosted
   ```
2. Health burst, low volume:
   ```bash
   for i in $(seq 1 10); do
     curl -fsS --max-time 30 https://brasstune-u8qj.onrender.com/api/health >/dev/null &
   done
   wait
   ```
3. CORS rejection: send an `OPTIONS` request from an unapproved origin and confirm it is not granted.
4. Auth enforcement: call one private endpoint without a bearer token in production and confirm it rejects access.
5. Audio abuse: with a disposable account only, confirm bad MIME and oversized upload tests reject cleanly.
6. WebSocket abuse: open a guest WebSocket and confirm unauthenticated frames receive an app-level auth-required response rather than saving data.

## Pass Criteria

- Health recovers within the expected cold-start window.
- CORS allows only approved origins.
- Private endpoints reject missing/invalid auth.
- Bad payloads return controlled 4xx/413 responses.
- No secrets, stack traces, raw provider errors, or cross-user data appear in responses.

## Risks And Limits

- Render free services can spin down and have monthly usage limits; keepalive reduces cold starts but does not guarantee uptime.
- Supabase Auth has provider-side rate limits; do not loop sign-up/reset tests.
- These checks do not replace a load test, WebSocket soak, security test, or physical-device beta.
