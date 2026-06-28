# Web Recovery Ownership Ledger

Date: 2026-06-25
Scope: React/Vite frontend, FastAPI backend, Supabase, Vercel, Render configuration, GitHub automation, and the follow-on Swift/native parity work authorized on 2026-06-27.

Swift/native boundary: the original 2026-06-25 web-recovery pass prohibited Swift/native changes. The 2026-06-27 continuation supersedes that narrower boundary: prioritize backend/frontend and GitHub Actions recovery first, then implement Swift/native parity work under `swift/**` with simulator/build evidence. Production Apple signing, TestFlight, App Store Connect, and physical-device claims remain separately gated.

Baseline captured: `HEAD` and `origin/main` both resolved to `1c998d5480f52b5fcf0e2c143f5078893caead66` after `git fetch origin` on 2026-06-25 at 19:03:59-04:00.

Working branch: `arya-s/web-production-recovery-20260625`.

Local Git note: Git is available in this PowerShell session. Commits, pushes, production deploys, destructive database changes, and production configuration mutations still require the explicit gates in `AGENTS.md` and the pasted recovery brief.

## Explicit Production Authorization

The owner has authorized BrassTune production-recovery work for GitHub Actions administration, Vercel/Render/Supabase configuration inspection, and CI recovery within the safety limits below. This does not authorize printing secrets, changing paid billing settings, making destructive database changes, force-pushing, merging, tagging, or claiming release readiness without the required evidence.

## 4A. GitHub Account-Wide Actions Administration Authorization

The owner explicitly authorizes Codex to use the owner's authenticated GitHub account and GitHub administrative surfaces to resolve GitHub Actions capacity, runner, billing-policy, workflow, ruleset, environment, variable, and secret-configuration problems that are blocking BrassTune PR #7.

Primary GitHub identity:

- User/account: `aryasalem09`
- Primary recovery repository: `aryasalem09/BrassTune`
- Recovery PR: `#7`
- Recovery branch: `arya-s/web-production-recovery-20260625`
- Current recovery SHA at the start of this continuation: `4d258ce0a480c27b0c48b9a0321ccf7325c39487`

This authorization extends to every repository owned by `aryasalem09`, every GitHub organization where the authenticated owner has sufficient administrative permission, account-level Actions usage and billing diagnostics, organization-level Actions policies/runners/variables/usage, and repository-level Actions settings, workflow runs, workflows, runners, variables, environments, secrets, rulesets, and branch protection.

This is GitHub Actions operational authority only. Outside BrassTune, do not inspect or modify unrelated application source code except for the minimum necessary inspection of `.github/workflows/**`, workflow-support scripts, or repository Actions settings required to determine why Actions capacity is blocked. Do not copy code, secrets, private repository content, issue content, or unrelated metadata from another repository into BrassTune.

### 4A.1 Authenticate And Discover Available GitHub Control Planes

Before declaring GitHub administration unavailable, discover and use every already authorized control plane: GitHub connector or MCP, GitHub App installation, `gh auth status`, existing authenticated browser session, REST/GraphQL credentials already present in a protected environment, a sufficient GitHub Actions `GITHUB_TOKEN`, approved secret-store tokens, and owner/admin surfaces exposed through the current environment.

Never print authentication values. Never ask the owner to paste a token into chat. Never store a token in Git, `.env.example`, documentation, workflow YAML, PR comments, job output, screenshots, Playwright traces, shell history, or broad-permission temporary files.

When reauthorization is required, use GitHub's normal account-connection or device/browser authorization flow and request the least privileges necessary for repository metadata, Actions read/write, workflow read/write, repository administration, rulesets/branch protection, environments, Actions variables/secrets metadata and safe mutation, runner and runner-group administration, and billing/usage read access. Do not request unrelated account permissions.

### 4A.2 Account-Wide Actions Inventory

Build a safe account-wide Actions inventory before stopping anything. For every accessible repository, record only repository name, owner, visibility, archived status, default branch, Actions enablement, queued/in-progress runs, workflow name/ID, run ID, trigger, ref, SHA, start time, runner type/labels, concurrency group where visible, scheduled workflows, repeated failures, recent usage where visible, artifact/cache usage where relevant, whether the run is production/backup/migration/release/security-related, and whether it is needed for an active pull request.

Do not read unrelated repository source unless a workflow references a small helper script whose behavior must be understood before safely stopping it.

Inspect account and organization Actions settings for quota, budget, payment, policy, token-permission, runner, runner-group, queue, concurrency, and GitHub service-incident causes. Do not change a payment method, purchase Actions minutes, raise a paid budget, enable larger paid runners, or make any change that can incur new charges without separate explicit owner authorization naming the maximum spend.

### 4A.3 Authority To Cancel Runs In Other Repositories

Codex is authorized to cancel queued or in-progress GitHub Actions runs outside BrassTune only when the run is consuming shared GitHub-hosted Actions capacity, blocking a shared self-hosted runner, or continuously recreating new runs; is not required for production deployment, rollback, backup, restore, migration, security incident, package release, compliance, or current critical PR work; is duplicate, obsolete, superseded, abandoned, looping, or noncritical; cancellation materially helps restore BrassTune capacity; and evidence/reason are recorded before cancellation.

Safe candidates include superseded older-commit runs, duplicate matrix runs, repeated failed runs caused by known account-level blocks, closed/abandoned PR runs, stale preview deployments, noncritical scheduled jobs, runs queued for offline self-hosted runners, redundant native-only builds, bot-trigger loops, and archived/abandoned/test/fork/demo repository runs.

Before every cross-repository cancellation, record repository, workflow name/ID, run ID, commit/ref, status, why it is safe to cancel, how it affects BrassTune, and whether it needs rerun later. Do not cancel completed historical runs or imply deleting/canceling them restores already consumed monthly minutes.

### 4A.4 Authority To Temporarily Disable Other Workflows

Codex is authorized to temporarily disable individual workflows in other accessible repositories when they demonstrably consume shared Actions minutes unnecessarily, repeatedly fail and retrigger, occupy shared self-hosted runners, run unnecessary schedules, build inactive forks/abandoned branches, generate duplicate previews, or block BrassTune through account-wide or runner-wide pressure.

Use the least disruptive control: cancel duplicate/superseded runs; pause or disable one noncritical workflow; disable only its schedule trigger through a branch/PR; apply concurrency with `cancel-in-progress`; restrict unnecessary path triggers; or disable Actions for one inactive repository only when individual workflow controls are insufficient.

Do not disable account-wide or organization-wide Actions unless GitHub provides no narrower control, the action is immediately reversible, production/security workflows are excluded, and the owner separately approves account-wide disablement.

Never disable production deployments, rollbacks, backups, restore validation, database migrations, secret scanning, code scanning, dependency security updates, security incident response, compliance/audit workflows, package signing/publication, release publication, infrastructure reconciliation, data-retention jobs, production uptime/safety monitoring, billing/license compliance, or credential rotation without separate explicit authorization for that named repository and workflow.

Prefer GitHub's workflow disable/enable control for temporary suppression. If workflow-code changes are genuinely required elsewhere, create a dedicated branch, make only the minimum Actions-related change, open a PR, avoid default-branch pushes and app-source edits, record rollback, and do not merge unless normal review requirements pass.

### 4A.5 Restore Everything After BrassTune Capacity Is Recovered

Every temporarily disabled workflow must have a restoration record. After BrassTune's required CI checks have started successfully and runner capacity is stable, re-evaluate every disabled workflow, re-enable workflows paused only to free capacity, verify schedules and permissions were restored, avoid rerunning obsolete historical jobs automatically, rerun only current necessary jobs, and leave a workflow disabled permanently only when it is conclusively obsolete and owner intent is documented.

The final report must list every repository inspected, run canceled, workflow disabled/re-enabled, repository variable changed, runner or runner group changed, before/after state, reason, and rollback/restoration result.

### 4A.6 BrassTune-First Priority Order

Recover Actions in this order: cancel superseded/duplicate BrassTune runs; stop repeated BrassTune reruns that cannot start because of the account-level condition; verify Actions is enabled for BrassTune; verify GitHub-hosted runner quota, budgets, policy, and service health; verify existing self-hosted runners and runner groups; inspect other repositories for active noncritical usage; cancel safe cross-repository active runs; temporarily disable safe noisy schedules; configure BrassTune to use an eligible self-hosted runner; register a new owner-controlled self-hosted runner only when necessary and safe; rerun Backend, Frontend, Security, PostgreSQL integration, and hosted-preview checks; restore paused workflows after capacity is stable.

Do not spend time canceling unrelated runs when the root cause is a completely exhausted hosted-runner quota that cannot recover until billing resets. In that case, move BrassTune to a safe self-hosted runner or identify the exact owner billing action.

### 4A.7 Self-Hosted Runner Authorization

Codex is authorized to inspect, configure, label, and assign existing self-hosted runners available to the owner's GitHub account or organizations. It may inspect online/offline state and labels, inspect runner-group repository access, add BrassTune to an appropriate runner group, set repository Actions variables selecting the runner, route BrassTune jobs to a compatible runner, remove stale/offline registrations after confirming the machine is permanently unavailable, reassign idle runners from noncritical repositories temporarily, and restore runner-group access after recovery.

Relevant BrassTune repository variables:

```text
BRASSTUNE_BACKEND_RUNNER
BRASSTUNE_FRONTEND_RUNNER
BRASSTUNE_SECURITY_RUNNER
BRASSTUNE_PRODUCTION_SMOKE_RUNNER
BRASSTUNE_RENDER_KEEPALIVE_RUNNER
BRASSTUNE_DEPLOY_RUNNER
BRASSTUNE_ACCOUNT_DELETION_RETRY_RUNNER
BRASSTUNE_DEVICE_SIMULATION_RUNNER
```

The value must be valid JSON for `runs-on`, for example:

```text
["self-hosted","brasstune","linux"]
```

A workflow must retain a safe hosted default when its runner variable is absent.

Codex may register a new self-hosted runner only on an owner-controlled, explicitly available, securable machine with sufficient disk, memory, and network access that is not a personal workstation exposing unrelated secrets to untrusted workflow code. For the owner's Windows machine, prefer WSL2 Linux, a dedicated VM, or a dedicated container/runner host for Linux-oriented BrassTune workflows. Do not assume native Windows works for Bash, `rm`, `curl`, Playwright dependency installation, and PostgreSQL service-container workflows without deliberate adaptation and testing. Do not expose runner registration tokens or commit runner credentials. Do not allow untrusted fork PRs to execute on privileged self-hosted runners with secrets. Remove or disable emergency runners after recovery unless the owner elects to maintain them.

### 4A.8 BrassTune Actions Settings Authority

Codex is authorized to configure BrassTune Actions enablement, allowed Actions policy, default `GITHUB_TOKEN` permissions, fork PR policy, repository Actions variables/secrets, environments, environment reviewers/protection, self-hosted runner access, runner groups, workflow enable/disable state, branch protection, rulesets, required checks, required PR review, conversation resolution, force-push/deletion prevention, deployment environments, concurrency, artifact retention, and cache retention where configurable.

Secret values must come from approved provider secret stores or owner-authorized existing credentials. Do not replace an existing secret with an unknown, empty, placeholder, or guessed value. Do not reveal whether one secret value matches another; report only whether a required secret name exists and whether a controlled test succeeds.

Required Actions/provider secret names may include `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, `RENDER_API_KEY`, `RENDER_SERVICE_ID`, `RENDER_DEPLOY_HOOK_URL`, `SUPABASE_URL`, `SUPABASE_SECRET_KEY`, `SUPABASE_PUBLISHABLE_KEY`, `BRASSTUNE_DATABASE_URL`, `BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET`, and `BRASSTUNE_VERCEL_AUTOMATION_BYPASS_SECRET`. Do not use `SUPABASE_DB_URL` as a substitute unless code/workflows intentionally map it to `BRASSTUNE_DATABASE_URL` or `DATABASE_URL`. The backend's supported production database names are `BRASSTUNE_DATABASE_URL` and `DATABASE_URL`.

### 4A.9 Required GitHub Diagnostic Result

Do not finish with generic statements such as "GitHub Actions is unavailable," "logs cannot be downloaded," "workflows failed," or "owner action is required." Determine the most precise available cause, such as hosted-runner quota exhausted, budget exhausted, invalid payment state, Actions disabled, organization/repository policy block, no matching runner, self-hosted runner offline, runner-group access missing, account suspended, environment approval wait, concurrency lock, invalid workflow before execution, GitHub service incident, workflow token permission failure, secrets unavailable, or branch/ruleset conflict.

A `BlobNotFound` or missing-log result for zero-step jobs is not sufficient diagnosis by itself. When the cause is identified, fix it using this authorization or identify the exact irreducible billing/account action that cannot be completed without a new payment or paid-budget decision.

### 4A.10 Completion Gate For Account-Wide Actions Work

This phase is complete only when the root cause of zero-step Actions failures is proven; unnecessary active account-wide Actions consumption has been stopped safely; disabled workflows have restoration records; BrassTune has access to a working compatible runner; Backend, Frontend, Security, PostgreSQL integration, and required preview checks start and complete; logs/annotations are readable; required checks attach to PR #7; rulesets do not require impossible or obsolete checks; no unrelated production/security/backup workflow was damaged; all temporary cross-repository changes are restored or documented; and no Swift/native file is touched during the web-only recovery phase.

For this 2026-06-27 continuation, the final "no Swift/native file" clause applies only to the web-only recovery phase. After web/backend and Actions recovery work, Swift/native files may be changed for the separately authorized parity implementation.

Do not mark BrassTune CI green by removing required checks. Do not bypass legitimate failed tests. Do not disable Backend, Frontend, Security, PostgreSQL integration, or strict preview checks to make PR #7 mergeable. The goal is to make the real checks execute and pass.

### Blocked-State Rule

GitHub Actions capacity or runner failure is not an acceptable external-owner blocker until Codex has completed the account-wide Actions inventory, canceled safe noncritical active runs, temporarily disabled safe noisy schedules, inspected all eligible self-hosted runners, attempted the authorized runner-variable path, and identified a precise billing or permission action that cannot be performed without new paid authorization.

## First-Pass Agent Ownership

All first-pass agents are read-only auditors. No broad implementation starts until their findings are reconciled.

| Agent | Role | Initial ownership | Later write scope, if approved |
|---|---|---|---|
| 1 | Repository and web architecture auditor | Web/backend/docs/config inventory, duplicate/stale files, release-doc consistency | `docs/release-readiness/**`, root web/backend config docs |
| 2 | Frontend authentication and runtime configuration | Auth state, Supabase browser client, runtime URL/capability handling | `frontend/src/state/AuthContext.tsx`, `frontend/src/lib/supabase.ts`, `frontend/src/api/runtimeConfig.ts`, auth routes/components |
| 3 | Frontend practice, sessions, audio, imports, exports | Practice flows, guest/cloud session separation, browser media, exports | Practice/session/audio/export frontend modules and tests |
| 4 | FastAPI authentication and security | Auth validation, JWT/JWKS, CORS, WebSocket security, secure errors | `backend/app/api/auth.py`, backend auth/security tests |
| 5 | PostgreSQL, SQLAlchemy, and migrations | DB engine, models, migrations, schema drift, Postgres support | `backend/app/db/**`, `backend/app/models/**`, `backend/requirements*.txt`, `supabase/migrations/**`, DB tests |
| 6 | Supabase platform specialist | Project status, migrations, Auth, Storage, RLS/grants/advisors | Platform changes only; migration SQL coordinated with Agent 5 |
| 7 | Render deployment and runtime specialist | `render.yaml`, runtime env presence, health/readiness/version, deploy process | `render.yaml`, backend readiness/version deployment hooks/scripts |
| 8 | Vercel deployment specialist | Vercel project/config, aliases, preview protection, Node alignment, ignored builds | `vercel.json`, `frontend/vercel.json` if present, frontend deploy scripts/config |
| 9 | GitHub Actions and release engineering | `.github/workflows/**`, path filters, gates, secret handling, exact-SHA evidence | `.github/workflows/**`, CI helper scripts, release evidence automation |
| 10 | Product completeness and ensemble/account lifecycle | Ensemble/account/deletion/export feature surface and authorization | Backend/frontend ensemble, account lifecycle, export modules and tests |
| 11 | Browser E2E, accessibility, and Windows QA | Playwright, browser matrix, fake media, accessibility, PowerShell docs | `frontend/e2e/**`, test config, QA docs |
| 12 | Independent security, privacy, dependency, and performance audit | Secrets, dependency, CSP, privacy/data flow, bundle/performance | Security/performance docs and focused config fixes after review |

## Merge Rules

- Agents must not edit the same file concurrently.
- Backend database changes are sequenced before Render readiness and production-smoke gates.
- Frontend capability/auth UI changes are sequenced after backend capability API shape is agreed.
- Documentation updates happen after verified code/config state, except evidence ledgers like this one.
- No production deploy, secret mutation, destructive database operation, paid-service action, force push, or history rewrite may be performed without explicit owner authorization.

## First-Pass Reconciliation

All 12 first-level agents completed read-only first pass work. Consolidated P0/P1 blockers are tracked in `docs/release-readiness/WEB_RECOVERY_FINDINGS.md`.

Confirmed corrections to the pasted baseline:
- Supabase project `uvbcvqupelcrncyhqsrq` is currently `ACTIVE_HEALTHY`, not `INACTIVE`.
- The live Supabase schema is still behind the repository; `20260620_account_deletion_and_membership_windows` is not recorded live.
- Render management access is still unavailable from local CLI/MCP in this environment; public `/api/health` is reachable but not sufficient release evidence.
- Vercel production deployment `dpl_CWTdt7Fhs9P69H5tayyKWW3zDQm7` is ready on SHA `1c998d5480f52b5fcf0e2c143f5078893caead66`; newer Swift-branch previews still proved web deployment isolation was incomplete.

## 2026-06-27 Continuation Record

Authenticated GitHub control plane:

- `gh auth status` confirmed an authenticated `aryasalem09` session with `repo` and `workflow` scopes.
- Account billing usage API calls require an additional `user` scope; organization runner/policy APIs for `slhstsa` require `admin:org`.
- No token value was printed, copied into files, or stored in Git.

Actions inventory and interventions:

- Accessible `aryasalem09/*` and `slhstsa/*` repositories were inventoried for active queued, in-progress, waiting, requested, and pending workflow runs. No safe active cross-repository run was present to cancel.
- BrassTune Actions is enabled and not globally policy-blocked. PR #7 zero-step Backend, Frontend, and Security jobs had no runner name, no step records, and unavailable logs/artifacts, so they were treated as infrastructure scheduling failures rather than test failures.
- BrassTune has no repository-scoped self-hosted runners and no existing `BRASSTUNE_*_RUNNER` repository variables. The workflows now support JSON `runs-on` variables with hosted defaults so an eligible self-hosted runner can be selected without another workflow edit.
- The noncritical scheduled `Render Keepalive` workflow (`render-keepalive.yml`, workflow ID `299560762`) was temporarily disabled because it was repeatedly producing zero-step scheduled failures on `main`, then re-enabled after the billing/spending-limit root cause was proven. No workflow remains disabled.
- PR #7 was rerun on `f97a3054dfa266b5a2771f87c6bf923b10bf828c`. Backend, Frontend, Security, and Swift still failed before any runner step, and check-run annotations identify the precise cause: recent account payments have failed or the Actions spending limit needs to be increased. Resolving that Billing & plans issue is outside the no-spend authorization.

Implementation and verification summary:

- Backend/frontend were prioritized first: workflows, hosted smoke, Vercel deploy env flags, hosted deep-link auth setup, and backend SHA enforcement were updated before Swift/native work.
- Swift/native parity work then updated the iOS app toward the web cockpit: dark BrassTune palette, glass panels, bento metrics, five-tab primary navigation, More hub, Coach surface, native tuner emphasis, and deterministic post-record analytics/session paths.
- Local validation passed for backend pytest, frontend unit/build/E2E/audit, backend Bandit/local pip-audit, Swift package tests, native app build, native unit tests, and the native UI smoke path.
