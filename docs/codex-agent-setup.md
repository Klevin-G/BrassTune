# Codex Agent Setup - BrassTune

## Classification

BrassTune is a fullstack release-oriented music practice app with a FastAPI backend, a Vite/React TypeScript frontend, audio/pitch logic, shared fixtures, Swift/iOS work, deployment workflows, and release-readiness documentation assets.

## Agent Settings

Project-local `.codex/config.toml` intentionally does not set the legacy `[agents]` runtime table.

This Codex install enables `features.multi_agent_v2` globally in `/Users/aryasalem/.codex/config.toml`. Its static parser accepts v1 project keys such as `agents.max_threads`, `agents.max_depth`, and `agents.job_max_runtime_seconds`, but a live `codex exec` thread-start probe rejected `agents.max_threads` with V2 enabled. This project omits all three legacy runtime keys as the safe compatibility policy.

Use the global v2 concurrency cap plus the repo-specific custom agents in `.codex/agents/*.toml`. Keep fanout justified by independent workstreams; do not recreate the old `[agents]` table unless a future Codex version documents a supported v2-compatible schema.

## Custom Agents

- Global agents: `repo_scout`, `architect`, `implementer`, `tester`, `reviewer`, `security_auditor`, `docs_writer`, `release_manager`.
- Project agents:
  - `release_integration_lead` for branch state, evidence matrix, and blocker tracking.
  - `web_auth_agent` for React/Supabase web auth and Playwright flow review.
  - `backend_security_agent` for FastAPI authorization, storage privacy, and backend security review.
  - `audio_pipeline_reviewer` for pitch detection, transposition, and audio-readiness checks.
  - `data_domain_parity_agent` for pitch/tuning fixtures across backend, frontend, and Swift.
  - `native_ios_agent` for SwiftUI/iOS app and BrassTuneCore verification.
  - `deployment_smoke_agent` for Vercel/Render/Supabase deployment and hosted-smoke mapping.
  - `artifact_hygiene_reviewer` for secrets, generated artifacts, and large-file review.

## Recommended Prompt Pattern

```text
Use parallel subagents.
Goal: [BrassTune task]
Start with a read-only repo scout, then split work into independent implementation, testing, security/review, docs, and release/git workstreams.
Keep agents from editing the same file concurrently.
Run targeted checks and review pitch/fixture implications before finalizing.
Report exact commands and evidence.
```

## CSV Fanout Candidates

- Fixture-by-fixture validation.
- Frontend route/component responsive review.
- Backend endpoint/security reviews.
- Release-readiness blocker sweeps.
- Cross-language fixture parity checks.
- Screenshot/documentation asset inventory.

## Tasks That Should Not Use Many Agents

- Small copy edits.
- Single fixture updates.
- One-file style fixes.

## Known Risks

- Production auth/storage/deploy work requires external credentials and explicit approval.
- Hosted WebSocket/Render/Supabase behavior must be verified live before release claims.
- Native app and Apple release evidence are distinct from web/backend evidence.
- Browser audio and microphone permissions can make local validation environment-sensitive.
- Generated screenshots and docs assets should not be churned accidentally.
- Pitch/math changes should be fixture-backed.

## Commands Discovered

- `cd frontend && npm run dev`
- `cd frontend && npm run build`
- `cd frontend && npm test`
- `cd frontend && npm run preview`
- `cd frontend && npm run simulate:devices`
- `cd backend && .venv/bin/python -m pytest`
- `cd backend && .venv-audit/bin/python -m pip_audit --local`
- `cd backend && .venv-audit/bin/python -m bandit -q -r app -x app/tests`
- `cd swift/BrassTuneCore && swift test`
- `xcodebuild -list -project swift/BrassTuneApp/BrassTuneApp.xcodeproj`

## Validation Performed

This setup reconciliation inspected repo structure, git status, project files, upstream tracked Codex setup, preserved local Codex setup, and BrassTune release instructions. Broader app validation is recorded in `docs/release-readiness/MASTER_FINDINGS.md`.

## 2026-07-12 Reassessment

- Bootstrap version: `2026-07`; Codex CLI: `0.144.1`.
- Classification remains multi-runtime full-stack plus native iOS.
- V2 session cap: 6; depth policy: 1. No depth-two gate passed because children are verified to inherit the parent route and shared fixtures/release evidence require coordinator ownership.
- Routing status: `VERIFIED_INHERITED`; custom-agent model fields remain intended routes only because authoritative child records showed Terra Medium inheritance rather than heterogeneous selection.
- Recommended fanout: backend/security, frontend/auth, audio/data parity, native iOS, and independent release validation when those lanes are actually in scope.
- Preserve the dirty Codex guidance and frontend ignore change; use isolated ownership for `fixtures/`, deployment files, and release evidence.
- Last assessed: 2026-07-12.
