# Codex Agent Setup

## Classification

BrassTune is a fullstack music practice app with a Python backend, a Vite/React TypeScript frontend, audio/pitch logic, fixtures, and documentation assets.

## Agent Settings

- `max_threads = 8`
- `max_depth = 1`
- `job_max_runtime_seconds = 2400`

Eight threads are useful for separating frontend UI, backend/API, audio-domain review, fixture checks, docs, testing, and release hygiene. Depth stays at `1` because recursive delegation is not needed for normal BrassTune work.

## Custom Agents

- Global agents: `repo_scout`, `architect`, `implementer`, `tester`, `reviewer`, `security_auditor`, `docs_writer`, `release_manager`.
- Project agent: `audio_pipeline_reviewer` for pitch detection, transposition, and audio-readiness checks.

## Recommended Prompt Pattern

```text
Use parallel subagents.
Goal: [BrassTune task]
Scout frontend/backend/docs boundaries first.
Keep edits bounded to assigned files.
Run targeted checks and review pitch/fixture implications before finalizing.
```

## CSV Fanout Candidates

- Fixture-by-fixture validation.
- Page/component responsive review.
- Endpoint or API contract checks.
- Screenshot/documentation asset inventory.

## Tasks That Should Not Use Many Agents

- Small copy edits.
- Single fixture updates.
- One-file style fixes.

## Known Risks

- Browser audio and microphone permissions can make local validation environment-sensitive.
- Generated screenshots and docs assets should not be churned accidentally.
- Pitch/math changes should be fixture-backed.

## Commands Discovered

- `cd frontend && npm run dev`
- `cd frontend && npm run build`
- `cd frontend && npm test`
- `cd frontend && npm run preview`
- `cd frontend && npm run simulate:devices`
- `cd backend && python -m pytest`
- `python -m compileall backend`

## Validation Performed

This setup pass inspected repo structure, git status, project files, and Codex docs. It did not run app builds or tests.
