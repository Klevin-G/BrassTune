# Master Findings

Updated: 2026-06-21T00:16:54Z
Branch: `arya/release-readiness-hardening`
Base SHA for this local pass: `eef7f865085859d877703c7652b941aaf6815134`

## Source Of Truth

Use this file, `LOCKED_RELEASE_SCOPE.md`, `release-evidence.json`, and `FAILURE_LOG.md` for the current state. Older reports are historical unless they name the current pass and validation commands below.

## Current Findings

| ID | Area | Severity | Status | Evidence | Release impact |
|---|---|---:|---|---|---|
| MF-001 | Pitch-frame trust boundary | P1 | Fixed locally | Backend now canonicalizes saved pitch samples from frequency, session instrument, and reference pitch; forged label regression passed. | Requires exact-SHA CI after push. |
| MF-002 | Session instrument mismatch | P1 | Fixed locally | Sample endpoints reject frame instruments that differ from the session instrument. | Requires exact-SHA CI after push. |
| MF-003 | Guest/local instrument ranges | P1 | Fixed locally | Frontend domain now enforces selected instrument frequency ranges; local pitch/music tests passed. | Guest practice remains backend-independent. |
| MF-004 | Account deletion durability/order | P1 | Fixed locally | Account deletion jobs record cleanup stage/status; local cleanup failure does not call external identity deletion; success calls external cleanup after local user deletion. | Live Supabase cleanup proof remains provider-gated. |
| MF-005 | Ensemble membership intervals | P1 | Fixed locally | Active-membership windows now reset on reactivation; removed-interval sessions are excluded from ensemble summaries. | Requires exact-SHA CI after push. |
| MF-006 | Auth error safety | P1 | Fixed locally | Supabase/provider/env/URL/stack-like errors are mapped to concise product messages. | Live provider tests remain externally gated. |
| MF-007 | Microphone lifecycle | P1 | Fixed locally | Failed signed-in recording start stops an opened mic stream. | Physical microphone quality not claimed. |
| MF-008 | Score Practice PDF reader | P1 | Fixed locally | Iframe-only PDF preview replaced with lazy PDF.js canvas rendering, page navigation, zoom, and rotation. | Manual score practice only; printed-note comparison remains disabled until OMR/alignment is proven. |
| MF-009 | Metronome wording/live settings | P1 | Fixed locally | Running accent/ramp settings use refs; UI now labels queue stats instead of acoustic measurements. | Acoustic timing/bleed validation remains unproven. |
| MF-010 | Native parity | P1 | Red gate | Native audit found fixture-backed mic/practice and missing native metronome/score/auth parity. Swift package tests passed only for existing core fixtures. | Do not claim native production parity or App Store readiness. |
| MF-011 | Hosted production | P0 | Red gate | `npm run smoke:hosted` against production failed: Vercel production lacks current Audio Lab content and hosted browser projects logged fetch failures. | Do not merge/release until production is redeployed and smoke passes. |
| MF-012 | Exact-SHA CI/preview | P0 | Red gate | Local changes are not yet committed/pushed in this evidence snapshot; previous GitHub/Vercel evidence covered older SHAs. | Must re-check PR head, CI, preview, and mergeability immediately before merge. |
| MF-013 | Artifact/secret hygiene | P1 | Clean tracked scope | `git diff --check` passed; tracked secret-pattern scan returned no matches; only expected ignored local env/data/test artifacts are present. | Stage explicit files only. |

## Current Validation

- `cd backend && PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m pytest app/tests/test_hardening.py -q`: passed, `53` tests.
- `cd backend && PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m pytest -q`: passed, `69` tests.
- `cd backend && .venv/bin/python -m bandit -r app -x app/tests`: passed, no issues.
- `cd backend && .venv/bin/python -m pip_audit -r requirements.txt -r requirements-dev.txt`: blocked by local Python 3.9 versus FastAPI/Python floor.
- `cd backend && uv pip compile --python /Users/aryasalem/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 requirements-dev.txt -o /tmp/... && .venv-audit/bin/python -m pip_audit --no-deps --disable-pip -r /tmp/...`: passed, no known vulnerabilities.
- `cd frontend && npm test -- --run src/domain/music.test.ts src/domain/localPitchDetection.test.ts`: passed, `9` tests.
- `cd frontend && npm test`: passed, `38` tests.
- `cd frontend && npm run build`: passed.
- `cd frontend && npm audit --omit=dev`: passed, `0 vulnerabilities`.
- `cd frontend && CI=true npm run e2e:local`: passed, `75` tests.
- `cd swift/BrassTuneCore && swift test`: passed, `3` Swift tests.
- `cd frontend && BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app BRASSTUNE_WEB_ACCESS_URL=https://brass-tune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted`: failed, `22` passed, `8` failed, `5` skipped.
- `git diff --check`: passed.
- Tracked high-confidence secret-pattern scan: no matches.

## Release Decision

Current status: local repository hardening is green, but merge/release gates are red. Do not merge PR #2 to `main`, tag, release, or invite testers until the local changes are committed and pushed, exact-SHA CI/preview are green, production Vercel and Render are redeployed to the final SHA, and hosted smoke passes.
