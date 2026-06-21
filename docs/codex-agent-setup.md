# Codex Agent Setup - BrassTune

## Classification

BrassTune is a fullstack release-oriented music practice app with a FastAPI backend, a Vite/React TypeScript frontend, audio/pitch logic, shared fixtures, Swift/iOS work, deployment workflows, and release-readiness documentation assets.

## Agent Settings

- `max_threads = 8`
- `max_depth = 1`
- `job_max_runtime_seconds = 2400`

Eight threads are useful for separating frontend UI, backend/API, audio-domain review, fixture checks, docs, testing, security, native, and release hygiene without overloading browser, backend, or Xcode runs. Depth stays at `1` because recursive delegation is not needed for normal BrassTune work.

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
