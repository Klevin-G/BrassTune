# Workstream Ownership

Date: 2026-06-20
Branch: `arya/release-readiness-hardening`

This file records the multi-agent workstreams used for the implementation recovery run. Agents were read-only unless explicitly noted by the coordinator.

| Workstream | Agent / Role | Scope | Result | Remaining Blocker |
|---|---|---|---|---|
| Coordination and preservation | Coordinator plus release manager | Preserve dirty tree, create backup bundles, avoid destructive Git operations, plan commit/merge sequence | Current-state backup: `/tmp/brasstune-local-work-20260620-032819`; backup branch: `backup/local-before-integration-20260620-032819`; backend/web implementation committed locally | Commit evidence/docs, then merge `origin/main` |
| Git/release hygiene | Release manager agent | Divergence, Codex setup overlap, artifact/secret/large-file risk | Confirmed branch is behind `origin/main` and `.codex` setup must be reconciled after commits | PR mergeability and CI exact-SHA verification pending |
| Documentation audit | Docs writer agent | Markdown inventory, stale claims, duplicate docs | Found 60 Markdown files and stale evidence claims; `MASTER_FINDINGS.md` and inventory are current source of truth | Broader docs need final SHA refresh after push |
| Dependency/security audit | Security auditor agent | Python advisories, Bandit, package migration plan | Migrated to Python 3.11+ dependency floor; local 3.12 pip-audit and Bandit pass | CI must verify pushed SHA |
| Backend security | Backend security agent | Auth mode, WebSocket auth/origins, payload bounds, deletion durability | Auth/WebSocket/payload hardening improved with tests | Durable account deletion/outbox remains |
| Web auth and mic | Web auth agent | Guest mic, auth-disabled UX, fallback states | Auth-disabled CTAs are safer; guest live mic remains cloud-auth dependent | Implement local pitch detection or gate live mic |
| Metronome/audio | Data-domain parity agent | Metronome implementation, timing evidence, native parity | Web metronome foundation exists; lazy route chunk built | Long-run timing, click-bleed, recording alignment, native parity remain |
| Score practice | Reviewer agent | PDF/image/camera import, file safety, lifecycle | Added safer magic-header checks, image sanitization, local restore/delete | PDF.js reader, page timeline, crop/reorder/export, native parity remain |
| Native iOS | Native iOS agent | Swift/Xcode/native parity | Xcode 26.2 simulator package/build/unit/UI/Release checks passed | Live mic, metronome, score practice, provider auth, signing, physical devices remain |
| Deployment smoke | Deployment smoke agent | Vercel/Render production smoke mapping | Prior production smoke showed current production availability, not this unpushed implementation | Hosted preview and CI need exact pushed SHA |
| Artifact hygiene | Artifact reviewer agent | Screenshots, env files, ignored/generated artifacts | No large-file/LFS issue; env/build/cache artifacts ignored | Device screenshots require final rerun/review before staging |

## Commit Ownership Status

1. Backend/security/dependencies: committed locally as `33b9e8b`.
2. Web product/performance: committed locally as `080eb4f`.
3. Device evidence/docs: pending evidence/docs commit after regenerated `npm run simulate:devices` artifacts are staged.
4. Codex setup reconciliation: merge upstream `.codex` setup with local project-scoped agents after `origin/main` is merged.

No workstream is allowed to claim hosted, CI, native, provider, or physical-device completion without evidence tied to the final pushed SHA.
