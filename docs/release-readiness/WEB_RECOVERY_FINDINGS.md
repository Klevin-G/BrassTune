# Web Recovery Findings Ledger

Date: 2026-06-25, continued 2026-06-28 and 2026-07-04
Branch: `arya-s/web-production-recovery-20260625`
Baseline SHA: `1c998d5480f52b5fcf0e2c143f5078893caead66`
Scope: Web, backend, Supabase, Vercel, Render, GitHub automation, and release evidence.

Swift/native parity work is split out of PR #7. The native continuation lives in PR #8 (`arya/native-swift-parity-surfaces-20260628`) so the web production recovery gate and native readiness gate remain separate.

## Findings

| ID | Severity | Service | Evidence | Root cause | Fix in this branch | Verification status | Final status |
|---|---|---|---|---|---|---|---|
| WR-001 | P0 | Render/backend auth | `render.yaml` set `BRASSTUNE_AUTH_MODE=disabled`; protected bearer requests returned account-unavailable behavior. | Production accepted a guest-first beta config. | `render.yaml` now sets `BRASSTUNE_AUTH_MODE=supabase`; deployed environments reject disabled auth at startup. | Backend tests added for fail-closed startup. Live Render env not mutated. | Blocked on deployment/env apply. |
| WR-002 | P0 | Backend database | `backend/requirements.txt` had SQLAlchemy but no PostgreSQL driver; database code silently defaulted to SQLite. | Production DB path was optional and local fallback was allowed in deployed envs. | Added `psycopg[binary]`; deployed envs require a PostgreSQL URL; local SQLite remains dev/test only; SQLAlchemy floor is 2.x. | Backend config tests added. Live Render DB URL not inspected. | Blocked on Render env verification. |
| WR-003 | P0 | Supabase schema | Live Supabase migrations lacked `20260620_account_deletion_and_membership_windows`; required columns/table absent. | Repo schema and live schema drifted. | Added `/api/ready` schema checks and Render `preDeployCommand`; added `20260625_invitation_fk_indexes.sql`. | On 2026-07-04, Supabase project `uvbcvqupelcrncyhqsrq` recorded `20260704022241` / `20260620_account_deletion_and_membership_windows` and `20260704022304` / `20260625_invitation_fk_indexes`; row counts remained zero. | Fixed in Supabase; pending Render deploy verification. |
| WR-004 | P1 | Health/release gate | `/api/health` returned constant success and hosted smoke treated it as sufficient. | Liveness and readiness were conflated. | Added `/api/live`, `/api/ready`, `/api/version`; Render health uses `/api/live`; smoke checks readiness/version. | Backend endpoint tests and smoke script changes added. Live production still lacks these until deploy. | Pending deploy. |
| WR-005 | P1 | Frontend auth | `AuthContext` used `Boolean(session)` and swallowed profile failures. | Supabase browser session could be mistaken for backend-ready account state. | `isSignedIn` now requires session plus backend profile; sign-in/sign-up profile loading verifies the current backend profile; profile failures are visible. | Frontend unit tests and build passed. Live auth still needs disposable account verification. | Needs live browser auth journey. |
| WR-006 | P1 | Account deletion UI | Frontend did not distinguish queued external cleanup from finished deletion. | Deletion response status was not surfaced accurately. | Client type includes deletion status; queued external cleanup signs the browser out and tells the user cleanup is queued. A scheduled retry endpoint/workflow was added. | Backend retry tests, frontend unit tests, and build passed. | Needs live deletion journey and provider secret. |
| WR-007 | P1 | Vercel runtime | Team alias was not recognized; unknown Vercel hosts could fall back to same-origin API/WS. | Hosted-origin matching was too narrow. | Runtime config recognizes team alias and all Vercel hosts use Render fallback unless explicitly configured. | Frontend URL tests, build, and local E2E passed. | Pending hosted redeploy verification. |
| WR-008 | P1 | Vercel preview gate | Hosted Playwright skipped protected previews and optional API/WS checks. | Release tests treated preview protection as a skip. | Protected preview now fails without bypass/share; API/WS vars are required for hosted smoke. | Hosted strict Playwright reached the live backend gate and failed only because production Render is stale. | Pending CI/live bypass and redeploy. |
| WR-009 | P1 | Vercel Swift-only builds | Vercel had no ignored-build step. | Static web project rebuilt for native-only changes. | Added `frontend/scripts/vercel-ignore-build.mjs` and wired both Vercel configs. | Local unit/build/E2E passed; Vercel production settings not mutated. | Pending Vercel verification. |
| WR-010 | P1 | GitHub release flow | Production smoke was manual only and Vercel CLI floated latest. | Deployment workflow lacked automatic post-deploy smoke, browser smoke, and runner-variable fallback routing. | Production smoke triggers after successful Deploy workflow; Node aligned to 24; Vercel CLI pinned; account deletion retry workflow added; BrassTune workflows now accept JSON `runs-on` repository variables with hosted defaults; production smoke includes protocol and browser-hosted jobs. | Touched workflow YAML parsed locally; Actions inventory completed with `gh`; PR checks reran on `f97a3054dfa266b5a2771f87c6bf923b10bf828c` and failed before runner start with a billing/spending-limit annotation. | Code/config fixed locally; CI blocked on owner billing/spending action. |
| WR-011 | P2 | Supabase performance | Advisors reported missing invitation FK indexes. | Migration set was incomplete for FK lookup performance. | Added additive index migration `20260625_invitation_fk_indexes.sql`. | Applied on 2026-07-04; post-apply advisors no longer report the invitation FK index gaps. | Fixed in Supabase; remaining unused-index notices are expected on empty tables. |
| WR-012 | P2 | Render keepalive docs | Keepalive used `/api/health` as if it were dependency health. | Liveness/readiness terminology drift. | Keepalive now uses `/api/live`; docs updated. | Workflow not run. | Pending deploy. |

## Production Blockers

- Render management connector, CLI, or `RENDER_API_KEY` is not available in this environment, so live Render env values, deployment IDs, logs, and rollback targets cannot be verified here.
- The Supabase project is currently `ACTIVE_HEALTHY`, not the stale `INACTIVE` observation, but the live migration history still lacks `20260620_account_deletion_and_membership_windows` and `20260625_invitation_fk_indexes`.
- GitHub CLI is installed and authenticated as `aryasalem09` with `repo` and `workflow` scopes. Billing usage diagnostics require an additional `user` scope; organization-level runner/policy APIs for `slhstsa` require `admin:org`. Fresh PR checks now expose the precise root cause through check annotations: recent account payments have failed or the Actions spending limit needs to be increased.
- Live authenticated browser journeys require disposable credentials and provider/Supabase settings that were not available without printing or creating secrets.
- Current production hosted smoke still fails because `https://brasstune.onrender.com/api/ready` and `/api/version` return 404 from the stale backend.

## 2026-06-27 GitHub Actions Continuation

- PR #7 was inspected at head SHA `4d258ce0a480c27b0c48b9a0321ccf7325c39487`; Backend, Frontend, and Security failed with zero-step jobs, no runner name, `ubuntu-latest` labels, and unavailable job logs/artifacts.
- BrassTune Actions is enabled; allowed actions are not blocked; default workflow token permission is read; no BrassTune self-hosted repository runners or runner variables are configured.
- Accessible `aryasalem09/*` and `slhstsa/*` repositories were inventoried for active queued/in-progress/waiting/requested/pending Actions runs. No safe active cross-repository runs were present to cancel.
- The noncritical scheduled `Render Keepalive` workflow (`render-keepalive.yml`, workflow ID `299560762`) was temporarily disabled because it was repeatedly producing zero-step scheduled failures on `main`. It was re-enabled after the billing/spending-limit root cause was proven, because leaving it disabled no longer recovered capacity.
- Repository secret names required by the recovery workflows were checked by name only; values were not printed.
- PR #7 checks were rerun on `f97a3054dfa266b5a2771f87c6bf923b10bf828c`; Backend, Frontend, Security, and Swift still failed with zero steps, and their check-run annotations state: "The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings."

## 2026-06-27 Local Web Validation

- Backend: `cd backend && .venv/bin/python -m pytest` -> 90 passed.
- Frontend unit: `cd frontend && npm test` -> 41 passed.
- Frontend build: `cd frontend && npm run build` -> passed.
- Frontend local E2E: `cd frontend && CI=true npm run e2e:local` -> 80 passed.
- Frontend audit: `cd frontend && npm audit --omit=dev` -> 0 vulnerabilities.
- Backend security: `cd backend && .venv/bin/python -m bandit -r app -x app/tests` -> no issues identified.
- Backend dependency audit: `cd backend && .venv/bin/python -m pip_audit --local` -> no known vulnerabilities. Requirement-file audit still hits the local ensurepip crash.

## 2026-06-28 Native Split Record

- Swift/native files were removed from PR #7 and moved to draft PR #8, `Native Swift parity surfaces`.
- PR #8 owns native SwiftUI design parity, `BRASSTUNE_SWIFT_RUNNER`, native build/test evidence, and the native readiness doc.
- PR #7 must not use PR #8 native validation as web production evidence.

## Next Required Live Gates

1. Set Render production env values by secret name only: `APP_ENV`, `BRASSTUNE_AUTH_MODE`, `BRASSTUNE_DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SECRET_KEY`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_STORAGE_BUCKET`, `BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET`, and CORS origins.
2. Deploy the exact reviewed commit to Render and Vercel.
3. Verify `https://brasstune.onrender.com/api/version` reports the expected SHA and `https://brasstune.onrender.com/api/ready` passes.
4. Run strict hosted Playwright with Vercel automation bypass and disposable live auth users.
5. Keep PR #7 Backend, Frontend, Security, PostgreSQL integration, and Vercel preview checks green on the final head.

## 2026-07-04 Provider Gate Continuation

- PR #7 head `cf59508f314c631217e2bcc6ff4f7d6f0cf9f2b1` was rechecked before provider work. Backend, PostgreSQL integration, Frontend, Security, and Vercel preview checks were green and recorded steps. PR #7 still contains no `swift/**` files.
- Supabase project `uvbcvqupelcrncyhqsrq` was `ACTIVE_HEALTHY` on Postgres 17.6.1 before mutation.
- Pre-migration row counts were zero for `auth.users`, `public.users`, `public.practice_sessions`, `public.pitch_samples`, `public.note_events`, `public.groups`, `public.group_members`, `public.invitations`, `public.recommendations`, and `storage.objects`.
- Backup/rollback evidence available in this environment was schema, RLS, grants, index, advisor, storage bucket, and row-count capture through the Supabase MCP. A full provider backup/download was not available without a direct database connection string or dashboard backup access.
- Applied Supabase migrations in order through the authorized migration mechanism:
  - `20260704022241` / `20260620_account_deletion_and_membership_windows`
  - `20260704022304` / `20260625_invitation_fk_indexes`
- Post-migration row counts remained zero, `session-audio` remained private, RLS remained enabled, and no direct table policies were added.
- Verified `account_deletion_jobs.counts_json` is `jsonb`, `group_members.active_since` and `group_members.removed_at` exist, and the account-deletion, membership-window, and invitation FK indexes exist.
- Supabase security advisors still report RLS-enabled/no-policy informational notices for app tables. This matches the current FastAPI-mediated access model and does not broaden browser table access.
- Supabase performance advisors no longer report the pre-existing invitation FK index warnings. Remaining unused-index notices are expected because the production project currently has no app rows.
- Render public backend remains stale after the database migration: `/api/health` returns 200, but `/api/live`, `/api/ready`, and `/api/version` return 404 until the PR #7 backend is deployed.
- Repository secret names exist for `RENDER_API_KEY`, `RENDER_SERVICE_ID`, and `RENDER_DEPLOY_HOOK_URL`, but no Render MCP tool, local Render CLI, or readable local `RENDER_API_KEY` is available in this session. The existing `.github/workflows/deploy.yml` deploy jobs are guarded to `refs/heads/main`, so triggering them before merge would not deploy the PR #7 SHA.
- Vercel preview deployment `dpl_7qwD1oeGNrjhPPatT1FnGcNLhGg2` is Ready at exact SHA `cf59508f314c631217e2bcc6ff4f7d6f0cf9f2b1`. A Vercel MCP share URL was generated, but MCP fetch still redirected to Vercel SSO, so browser-hosted preview smoke remains blocked without the real automation bypass secret.
- Secret-bearing smoke and retry paths now fail closed on exact BrassTune-owned hostnames before sending Vercel bypass or maintenance secret headers. `scripts/hosted-smoke.mjs` and `frontend/scripts/run-hosted-smoke.mjs` allow only BrassTune Vercel hosts plus `brasstune.onrender.com`; `.github/workflows/account-deletion-retry.yml` sends the maintenance secret only to `https://brasstune.onrender.com`.
- Local guard verification passed with harmless dummy values: a root smoke run using `BRASSTUNE_API_BASE_URL=https://example.com` failed during configuration, and a browser-smoke launcher run using a dummy Vercel bypass secret with `E2E_BASE_URL=https://evil.example` failed before invoking Playwright.
- `npm run smoke:hosted` after the Supabase migration and host-allowlist update passed web root, CORS, WebSocket app-level response, query-token rejection, and bad-Origin rejection. It still failed exactly on stale Render `/api/ready` and `/api/version` returning 404.
