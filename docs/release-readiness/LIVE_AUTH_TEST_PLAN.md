# Live Auth Test Plan

Status: blocked until the owner provides disposable Supabase/Apple test configuration. Do not use personal credentials or real student data.

## Preconditions

- Vercel production env vars are set: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_API_BASE_URL`, `VITE_WS_BASE_URL`.
- Render production env vars are set: Supabase URL, publishable key, secret key, JWKS URL, database URL, and `APP_ENV=production`.
- Supabase Site URL is `https://brass-tune.vercel.app`.
- Supabase redirect allowlist includes `/auth/callback` and `/auth/reset-password` for production and approved previews only.
- Email/password auth policy, confirmation requirement, and SMTP sender are owner-approved.
- Apple provider is configured only with owner-approved Apple Developer values.

## Test Accounts

Use disposable accounts:

- new email/password user
- existing confirmed email/password user
- teacher/director persona
- student persona
- Apple OAuth test identity if Apple provider setup is approved

Do not record passwords, reset links, tokens, service keys, Apple private keys, or full email addresses in docs.

## Required Cases

| Case | Expected Result | Evidence |
|---|---|---|
| Sign up with valid email/password | Confirmation or signed-in state follows configured policy | Redacted screenshot/log note |
| Duplicate sign-up | Friendly error or safe no-op | Redacted screenshot/log note |
| Weak password | Rejected with understandable message | Redacted screenshot/log note |
| Sign in/out | Session appears and clears across reload | Redacted screenshot/log note |
| Password reset | Email arrives, callback works, new password signs in | Redacted email header/timestamp only |
| Apple cancel/error | User returns to `/auth/callback` with readable failure state | Redacted screenshot/log note |
| Apple success | Session is created and profile/onboarding can complete | Redacted screenshot/log note |
| Token refresh/reload | Authenticated API calls continue after reload | Redacted network status only |
| Authenticated session save | Practice session is scoped to that user | Session id only |
| Export | Export contains only the signed-in user's data | File manifest only |
| Account deletion | App data, storage object, local session, and Supabase identity cleanup complete | Redacted provider/admin evidence |

## Stop Conditions

Stop testing and file a `P0`/`P1` issue if auth loops, account deletion is partial, another user's data is visible, Supabase service keys appear in the browser, or reset/Apple links redirect to an unapproved host.

## Result Log

Record each run with date, environment, commit/deployment, tester persona, pass/fail, evidence location, and follow-up issue link. Unknown provider state should remain marked unknown.
