# Web Recovery Ownership Ledger

Date: 2026-06-25
Scope: React/Vite frontend, FastAPI backend, Supabase, Vercel, Render configuration, and GitHub automation only.

Swift/native boundary: no agent may read, modify, build, lint, test, document, or summarize files under `swift/**`. The only permitted Swift-related work is path-filter configuration that prevents Swift-only changes from triggering web pipelines.

Baseline captured: `HEAD` and `origin/main` both resolved to `1c998d5480f52b5fcf0e2c143f5078893caead66` after `git fetch origin` on 2026-06-25 at 19:03:59-04:00.

Working branch: `arya-s/web-production-recovery-20260625`.

Local Git note: Git is available in this PowerShell session. Commits, pushes, production deploys, destructive database changes, and production configuration mutations still require the explicit gates in `AGENTS.md` and the pasted recovery brief.

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
