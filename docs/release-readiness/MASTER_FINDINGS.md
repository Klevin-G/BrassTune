# Master Findings

Updated: 2026-06-20 UTC
Branch: `arya/release-readiness-hardening`
Pushed head at recovery start: `cd37fee3ef927001e755cb4976cf5d52eb00af72`
Current implementation state: backend/frontend implementation committed locally through `080eb4fb12bfb38b1b3c4e894ae6b204a311eed6`; release docs, `origin/main` reconciliation, push, CI, and hosted exact-SHA verification remain pending

## Current Source Of Truth

Use this file with `LOCAL_IMPLEMENTATION_INVENTORY.md` until the implementation is pushed and verified. Older evidence tables in `FINAL_REPORT.md`, `TEST_MATRIX.md`, `BASELINE.md`, `WEB_E2E_REPORT.md`, and `IOS_SIMULATOR_REPORT.md` may describe earlier heads such as `91ca605...` or the Markdown-only `cd37fee...` state.

| ID | Area | Severity | Claim | Implementation State | Evidence | Release Status | Next Action |
|---|---|---:|---|---|---|---|---|
| MF-001 | Worktree recovery | P0 | Local implementation is preserved. | Preserved twice: `/tmp/brasstune-local-work-20260620-031847` and current `/tmp/brasstune-local-work-20260620-032819`; backup branch pointers created. | Checksums and reverse patch check passed for the current bundle. | Recoverable and partially committed. | Keep backup until branch is pushed and CI has run. |
| MF-002 | Git integration | P0 | Branch is merge-ready. | False. Backend and frontend implementation are committed locally, but branch still needs release-doc commit, `origin/main` merge, `.codex`/docs setup reconciliation, push, and exact-SHA CI. | Local commits: `33b9e8b`, `080eb4f`; `origin/main` merge not yet performed. | Not mergeable yet. | Commit evidence/docs, then merge `origin/main` and resolve `.codex`/docs setup. |
| MF-003 | Backend auth mode | P0 | Production auth behavior is explicit. | Implemented in local commit `33b9e8b` with `BRASSTUNE_AUTH_MODE=disabled|supabase`, deployed-env validation, disabled-mode fail-closed private routes, and Supabase service-key startup requirement. | `cd backend && .venv-audit/bin/python -m pytest -q`: `59 passed`. | Local committed evidence only. | Verify CI on pushed SHA. |
| MF-004 | WebSocket hardening | P1 | WebSocket query-token auth is disabled and origins/messages are bounded. | Implemented locally. | Backend hardening tests cover query-token rejection, bad origin, first-message auth, and oversized raw frames. | Local evidence only. | Add WS control-message schema tests later. |
| MF-005 | Dependency advisories | P0 | pip-audit is green without broad ignores. | Runtime/dev requirements upgraded to Python 3.11+ security floor: FastAPI `>=0.138`, Starlette `>=1.3.1`, python-dotenv `>=1.2.2`, pytest `>=9.0.3`; Starlette ignores removed from CI. | `.venv-audit/bin/python -m pip_audit --local`: no known vulnerabilities; JSON saved to `/tmp/brasstune-pip-audit.json`. | Local committed evidence only. | CI must audit exact pushed SHA. |
| MF-006 | Backend deprecations | P2 | Repository-actionable FastAPI/Pydantic warnings are addressed. | Pydantic validators migrated to `field_validator`; startup moved to FastAPI lifespan. | Python 3.9 and 3.12 backend tests pass. | Local evidence only. | Track remaining Python 3.12 `datetime.utcnow` warnings separately. |
| MF-007 | Score Practice | P1 | Web score practice is a real reader/practice workflow. | Partially true. Import, camera capture, preview, sanitized image save, local restore/delete, route/device smoke, and basic validation exist in local commit `080eb4f`. Full PDF.js rendering, page extraction, crop/reorder/timeline/review/export, and native parity are not complete. | `cd frontend && npm test`: `29 passed`; `npm run build`: passed; `CI=true npm run e2e:local`: `75 passed`; `npm run simulate:devices`: passed. | Web foundation only. | Do not claim full Score Practice complete; add PDF.js/page/timeline work later. |
| MF-008 | Metronome | P1 | Web metronome exists and is validated. | Web Audio foundation exists in local commit `080eb4f` with helper tests, route, nav, and lazy chunk. Long-run measured timing, click-bleed, recording/page alignment, and native parity are not complete. | Frontend tests/build/E2E/device simulation pass; metronome audit found timing evidence is scheduled-target only. | Web foundation only. | Keep release language scoped; add timing harness later. |
| MF-009 | Bundle performance | P2 | Heavy routes are split from initial load. | Implemented route-level lazy loading in local commit `080eb4f`. | `npm run build`: main JS dropped from about `907 kB` to `382.33 kB`; score/metronome chunks split. | Local committed evidence only. | Add formal budget to CI later. |
| MF-010 | Guest mic | P0 | Unsigned guest live mic works without cloud auth. | False. Guided demo and guest local sessions work, but live mic still depends on WebSocket/auth. | Web mic audit found unsigned production mic receives auth-required behavior. | Blocker for guest live mic claim. | Implement local pitch detection or disable live mic until signed in. |
| MF-011 | Native parity | P0 | Native metronome/score/live mic/provider parity is complete. | False. Native simulator tests pass, but live mic, metronome, score practice, provider-ready auth, signed archive, and physical-device evidence are incomplete. | Native audit: Xcode 26.2 build/unit/UI smoke/Release build passed; gaps remain. | Native engineering parity in progress. | Keep final status scoped; do not claim native complete. |
| MF-012 | Account deletion durability | P1 | Account deletion is durable and retryable. | False. Existing deletion is not an outbox/retry saga and can split across external/local failures. | Backend/security audits. | Blocker remains. | Implement tombstone/outbox/retry before durable deletion claim. |
| MF-013 | Hosted/CI evidence | P0 | Latest pushed SHA is green and hosted. | False. `cd37fee...` is Markdown-only; current implementation is unpushed. | No CI/hosted exact-SHA evidence yet. | Pending. | Commit, merge main, push, verify GitHub Actions and current preview. |

## Current Local Validation

- `cd backend && .venv/bin/python -m pytest app/tests/test_hardening.py -q`: `43 passed`
- `cd backend && .venv/bin/python -m pytest -q`: `59 passed`
- `cd backend && .venv-audit/bin/python -m pytest -q`: `59 passed`
- `cd backend && .venv-audit/bin/python -m pip_audit --local`: no known vulnerabilities
- `cd backend && .venv-audit/bin/python -m bandit -q -r app -x app/tests`: passed
- `cd frontend && npm test`: `29 passed`
- `cd frontend && npm run build`: passed; initial JS split to `382.33 kB`
- `cd frontend && CI=true npm run e2e:local`: `75 passed`
- `cd frontend && npm run simulate:devices`: passed; report updated at `docs/device-simulation-report.md`

## Release Decision

Current status: `web closed-beta candidate; native engineering parity in progress; external provider/App Store/device gates remaining`.

Do not use `release ready`, `native complete`, `merge ready`, `CI green`, or `hosted verified` until the implementation is committed, merged with current `main`, pushed, and verified on the exact pushed SHA.
