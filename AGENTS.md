# BrassTune Codex Instructions

## Project Purpose

BrassTune is a fullstack music practice and tuning app with a Python backend, a Vite/React TypeScript frontend, pitch/audio workflows, and Swift porting notes.

## Stack

- Backend: Python app under `backend/app`, with dependencies in `backend/requirements.txt` and pytest config in `backend/pytest.ini`.
- Frontend: Vite, React, TypeScript under `frontend/`.
- Fixtures: music and pitch math cases under `fixtures/`.
- Docs and generated screenshots: `docs/` and `docs/assets/`.

## Commands

- Frontend install: `cd frontend && npm install`
- Frontend dev: `cd frontend && npm run dev`
- Frontend build: `cd frontend && npm run build`
- Frontend tests: `cd frontend && npm test`
- Frontend preview: `cd frontend && npm run preview`
- Device simulation: `cd frontend && npm run simulate:devices`
- Backend install: `cd backend && python -m pip install -r requirements.txt`
- Backend tests: `cd backend && python -m pytest`
- Lightweight Python syntax check: `python -m compileall backend`

## Working Rules

- Keep audio, pitch, and transposition logic reproducible with fixtures when behavior changes.
- Do not hand-edit generated screenshots or large assets unless the task is explicitly visual documentation.
- Preserve the separation between backend app logic, frontend domain logic, and docs.
- For UI work, verify responsive layouts and browser audio permissions when practical.
- Do not introduce paid services, production deploys, or credential use without explicit approval.

## Codex Subagent Policy

- Codex should use parallel subagents for nontrivial work when there are independent workstreams.
- Fanout must be justified by independent workstreams; prefer 4-8 agents for normal tasks.
- Use 8-12 only for large independent modules, audits, migrations, data pipelines, or test/review sweeps.
- Do not spawn agents that edit the same file at the same time.
- Keep `max_depth = 1` unless the repo-specific config explains why `2` is justified.
- Always use a read-only scout before major edits.
- Always use independent tester/reviewer agents before claiming completion.
- Use CSV fanout for repeated independent tasks like fixture audits, page/component checks, endpoint reviews, or device-screenshot review.

## Recommended Roles

- `repo_scout` for mapping frontend/backend/docs boundaries.
- `architect` for cross-layer feature planning.
- `implementer` for bounded frontend or backend edits.
- `audio_pipeline_reviewer` for pitch, note, recording, and music-domain changes.
- `tester`, `reviewer`, and `release_manager` before final handoff.

## Definition of Done

- Relevant commands or targeted checks were run, or skipped with a clear reason.
- Fixture/schema implications were considered for audio and music behavior.
- Docs are updated when commands, architecture, or user-facing behavior changes.
- Git status is reviewed and unrelated user changes are left untouched.
