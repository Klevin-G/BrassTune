# Local Implementation Inventory

Date: 2026-06-20
Branch: `arya/release-readiness-hardening`
Starting pushed head: `cd37fee3ef927001e755cb4976cf5d52eb00af72`
Initial safety backup: `/tmp/brasstune-local-work-20260620-031847`
Current safety backup: `/tmp/brasstune-local-work-20260620-032819`
Current safety branch: `backup/local-before-integration-20260620-032819`
Local implementation commits: backend/security `33b9e8b`; web/metronome/score `080eb4f`
Local reconciliation commit: `bf3282a` merged `origin/main` and combined upstream Codex setup with BrassTune project agents

This inventory records local modified and untracked files that existed after the Markdown-only push. Backend and frontend source rows have since been committed locally and the branch has been reconciled with `origin/main`, but this is not proof of release readiness until the branch is pushed and verified on the exact pushed SHA. Each row marks whether the file is complete enough to commit, which claim it supports, and the remaining action before final release evidence.

## Source And Test Files

| Path | State | Purpose / Markdown Claim | Current Status | Risk / Next Action | Owner |
|---|---:|---|---|---|---|
| `.github/workflows/backend.yml` | Modified | Backend CI uses same dependency floor as local audit | Updated to install with `constraints.txt` | Verify GitHub Actions after push | Backend/CI |
| `.github/workflows/security.yml` | Modified | Security CI audits runtime and dev dependencies without broad ignores | Updated; old Starlette ignores removed | Verify GitHub Actions after push | Security/CI |
| `.env.example` | Modified | Documents explicit backend auth mode | Added `BRASSTUNE_AUTH_MODE=disabled` for local example | Ensure production docs explain `disabled` vs `supabase` | Deployment |
| `render.yaml` | Modified | Render env contract | Adds explicit `BRASSTUNE_AUTH_MODE=disabled` as the current production-safe account-disabled mode | Owner must switch to `supabase` only after provider secrets are configured | Deployment |
| `backend/requirements.txt` | Modified | Runtime dependency security floor | FastAPI/Starlette/python-dotenv upgraded for Python 3.11+ | CI must verify on pushed SHA | Backend/dependencies |
| `backend/requirements-dev.txt` | Modified | Dev/test/security dependency security floor | pytest, pip-audit, Bandit pinned to patched floor | CI must verify on pushed SHA | Backend/dependencies |
| `backend/constraints.txt` | Untracked | Resolver security floor | Added minimum patched constraints | Not a full lockfile; use with requirements in CI | Backend/dependencies |
| `backend/app/api/auth.py` | Modified | Production auth hardening; no local-auth fallback in production | Explicit `BRASSTUNE_AUTH_MODE=disabled|supabase`, deployed-env validation, service-key preflight | Account deletion durability remains separate blocker | Backend/security |
| `backend/app/api/websocket.py` | Modified | WebSocket origin gate, first-message auth, no query token, raw message cap | Implemented locally with tests pending rerun | Confirm close behavior in FastAPI/TestClient and browser client compatibility | Backend/security |
| `backend/app/main.py` | Modified | Startup auth preflight and centralized CORS origins | Lifespan startup uses auth preflight and seed/init | Keep CORS exact-origin docs aligned | Backend/security |
| `backend/app/schemas/schemas.py` | Modified | Bounded audio and pitch payloads | Implemented validation bounds and Pydantic v2 validators | Consider stricter canonical note recomputation later | Backend/security |
| `backend/app/services/audio_storage.py` | Modified | Clean Bandit suppression syntax | Runtime behavior unchanged; comments no longer create Bandit warning noise | Low risk | Backend/security |
| `backend/app/tests/test_hardening.py` | Modified | Regression tests for production startup, WebSocket auth/origin/size, payload caps, and ensemble report scoping | Expanded auth-mode matrix and pre-membership privacy coverage; `44 passed` targeted, `60 passed` full backend | CI must verify after push | Backend/testing |
| `backend/app/core/security.py` | Untracked | Shared environment/auth-mode/origin helper | Implements explicit deployed/local environment and auth-mode rules | Must be tracked with backend hardening | Backend/security |
| `backend/app/tests/conftest.py` | Untracked | Default local env for backend tests | Local disabled auth mode and CORS configured for tests | Must be tracked with backend tests | Backend/testing |
| `frontend/src/App.tsx` | Modified | Routes for `/metronome` and `/practice/score` plus bundle splitting | Implemented lazy route loading; main JS dropped to `382.33 kB` | Add CI bundle budget later | Web/product |
| `frontend/src/components/AppShell.tsx` | Modified | Navigation entries and guest-safe topbar/auth CTA | Implemented local UX changes | Verify no unavailable provider CTA appears in auth-disabled mode | Web/auth |
| `frontend/src/components/ui/AppPrimitives.tsx` | Modified | Accessibility fixes for selection chips and mobile nav | Implemented | Covered by axe routes after E2E rerun | Web/accessibility |
| `frontend/src/pages/AnalyticsPage.tsx` | Modified | Guest-safe/offline error state | Implemented local catch path | Add route-level tests for backend-down behavior | Web/product |
| `frontend/src/pages/AuthPage.tsx` | Modified | Hide auth switcher when providers are unavailable | Implemented | Provider doubles still needed for Google/Apple/email completion | Web/auth |
| `frontend/src/pages/CoachPage.tsx` | Modified | Guest-safe/offline error state | Implemented local catch path | Add route-level tests for backend-down behavior | Web/product |
| `frontend/src/pages/MorePage.tsx` | Modified | Secondary navigation includes metronome/score and guest-safe CTA | Implemented | Verify tiny-screen layout with device simulation | Web/product |
| `frontend/src/pages/PracticePage.tsx` | Modified | Links from live practice to metronome and score practice | Implemented | Does not prove integrated score/tuner/metronome recording timeline | Web/product |
| `frontend/src/pages/ProgressPage.tsx` | Modified | Guest-safe/offline error state | Implemented local catch path | Add route-level tests for backend-down behavior | Web/product |
| `frontend/src/pages/SessionReviewPage.tsx` | Modified | Not-found state instead of endless loading | Implemented | Add E2E or unit coverage for missing cloud/guest session | Web/product |
| `frontend/src/pages/SessionsPage.tsx` | Modified | Guest sessions show instrument context | Implemented | Low risk; verify visual fit on mobile cards | Web/product |
| `frontend/src/pages/SettingsPage.tsx` | Modified | Preserve guest sessions on preferences clear; guest export fallback; auth-disabled CTA | Implemented | Add tests for guest preservation/export behavior | Web/auth |
| `frontend/src/domain/metronome.ts` | Untracked | Pure metronome timing helpers | Foundation implemented | Need long-run timing harness, click-bleed tests, recording/page alignment evidence | Audio/metronome |
| `frontend/src/domain/metronome.test.ts` | Untracked | Unit tests for timing helpers | Implemented local unit coverage | Expand to 10-minute drift/jitter simulation and click-bleed scenarios | Audio/testing |
| `frontend/src/pages/MetronomePage.tsx` | Untracked | Web metronome UI with Web Audio scheduler | Foundation implemented | Native parity, background behavior, recording alignment, and measured evidence still incomplete | Audio/metronome |
| `frontend/src/domain/scorePractice.ts` | Untracked | Score import classification and quality heuristics | Adds active-header rejection, verified kind sniffing, decoded-pixel blocking, file-size limits | Still lacks full PDF page inspection and EXIF orientation extraction | Score practice |
| `frontend/src/domain/scorePractice.test.ts` | Untracked | Unit tests for score import basics | Covers spoofed SVG and decoded-pixel blocking; `5 passed` targeted, included in `29 passed` frontend suite | Add generated PDF/image fixture E2E later | Score testing |
| `frontend/src/pages/ScorePracticePage.tsx` | Untracked | Score PDF/image/camera import, preview, local IndexedDB confirmation | Adds camera stream attachment, image sanitization before save, saved document reload, and persisted delete | Not full score reader: lacks PDF.js rendering, page thumbnails/reorder/crop/timeline/review/export | Score practice |
| `frontend/e2e/accessibility.spec.ts` | Modified | Adds metronome and score routes to axe smoke | Implemented | Rerun full local E2E after all changes | QA/accessibility |
| `frontend/e2e/release-journeys.spec.ts` | Modified | Adds metronome and score routes to route smoke | Implemented | Extend journeys for score import, metronome timing, guest mic fallback | QA/web |
| `frontend/playwright.config.ts` | Modified | Local backend env for Playwright CORS/auth | Implemented | Revisit after explicit auth-mode config lands | QA/web |
| `frontend/scripts/device-simulation.mjs` | Modified | Device simulator visits metronome and score routes; sets backend local CORS env | Implemented | Rerun after layout changes; keep generated artifacts intentional | QA/device |
| `frontend/src/styles/components.css` | Modified | Metronome/score UI styling | Implemented | Visual review needed across mobile/tablet/desktop | Web/design |
| `frontend/src/styles/responsive.css` | Modified | Mobile/tiny-phone layout fixes for topbar, tabbar, settings, metronome, score | Implemented | Device simulation and screenshots required before final claim | Web/design |

## Generated Device Evidence

These images are intentional only if they correspond to a fresh `npm run simulate:devices` run on the final implementation. They require privacy and visual review before staging.

| Path | State | Purpose / Markdown Claim | Current Status | Risk / Next Action | Owner |
|---|---:|---|---|---|---|
| `docs/assets/device-simulation/audio-lab.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/desktop-analytics-dashboard.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/desktop-ensemble.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/desktop-home.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/desktop-practice.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/desktop-session-review.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/ipad-landscape-analytics.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/ipad-landscape-practice.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/ipad-portrait-practice.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/phone-analytics.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/phone-auth.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/phone-home.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/phone-onboarding.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/phone-practice.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/phone-session-playback.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/phone-session-review.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/tiny-phone-practice.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |
| `docs/assets/device-simulation/ultrawide-analytics-dashboard.png` | Modified | Device-simulation evidence | Generated local artifact | Review for stale UI/private data before staging | QA/device |

## Codex Setup And Documentation Files

| Path | State | Purpose / Markdown Claim | Current Status | Risk / Next Action | Owner |
|---|---:|---|---|---|---|
| `.codex/config.toml` | Untracked | Multi-agent config, `max_threads=8`, `max_depth=1` | Matches upstream intent from `origin/main` | Compare and merge after committing implementation; do not duplicate stale local setup | Release/git |
| `.codex/agents/artifact_hygiene_reviewer.toml` | Untracked | Project-scoped artifact reviewer | Local setup file | Compare with upstream tracked setup before staging | Release/git |
| `.codex/agents/backend_security_agent.toml` | Untracked | Project-scoped backend security reviewer | Local setup file | Compare with upstream tracked setup before staging | Release/git |
| `.codex/agents/data_domain_parity_agent.toml` | Untracked | Project-scoped domain parity reviewer | Local setup file | Compare with upstream tracked setup before staging | Release/git |
| `.codex/agents/deployment_smoke_agent.toml` | Untracked | Project-scoped deployment smoke reviewer | Local setup file | Compare with upstream tracked setup before staging | Release/git |
| `.codex/agents/native_ios_agent.toml` | Untracked | Project-scoped native iOS reviewer | Local setup file | Compare with upstream tracked setup before staging | Release/git |
| `.codex/agents/release_integration_lead.toml` | Untracked | Project-scoped release coordinator | Local setup file | Compare with upstream tracked setup before staging | Release/git |
| `.codex/agents/web_auth_agent.toml` | Untracked | Project-scoped web/auth reviewer | Local setup file | Compare with upstream tracked setup before staging | Release/git |
| `docs/codex-agent-setup.md` | Untracked | Documents Codex multi-agent setup | Local setup doc; upstream version exists on `origin/main` | Merge stronger BrassTune rules with upstream tracked doc after implementation commits | Release/docs |
| `docs/release-readiness/FAILURE_LOG.md` | Modified | Records preservation and recovery state | Updated with backup path and branch pointer | Keep current; include final SHA and any failed checks later | Release/docs |
| `docs/release-readiness/DOCS_INDEX.md` | Untracked | Canonical Markdown routing | Added current/supporting/historical doc map | Refresh after final validation | Release/docs |
| `docs/release-readiness/LOCAL_IMPLEMENTATION_INVENTORY.md` | Untracked | Required inventory for this recovery run | Current file | Update after new edits, commits, merge, and final validation | Release/docs |
| `docs/release-readiness/MASTER_FINDINGS.md` | Modified | Current release decision and blocker source of truth | Rewritten to separate dirty local, committed, CI/hosted, and blocker states | Refresh after push/CI | Release/docs |
| `docs/release-readiness/WORKSTREAM_OWNERSHIP.md` | Untracked | Multi-agent workstream map | Added workstream/agent/evidence/remaining blocker table | Refresh after final validation | Release/docs |

## Unsupported Or Incomplete Claims

- Web metronome exists locally as a foundation, but long-run timing, click-bleed rejection, recording/page alignment, and native parity are not complete.
- Score Practice exists locally as import/preview/local confirmation with safer active-header rejection, image sanitization, reload, and delete, but full PDF.js rendering, page count, EXIF orientation extraction, crop/reorder/timeline/review/export, and native parity are not complete.
- Guest-safe UI and auth-disabled UX are improved locally, but provider completion for Google/Apple/email live flows is not complete.
- Backend production auth hardening now includes the explicit `BRASSTUNE_AUTH_MODE=disabled|supabase` contract locally, but account deletion durability remains incomplete.
- Account deletion durability/outbox retry remains incomplete.
- Native live microphone code, native metronome, and native score practice are implemented locally but still need stronger device/performance validation; native provider auth and App Store/TestFlight readiness remain incomplete or externally blocked.
