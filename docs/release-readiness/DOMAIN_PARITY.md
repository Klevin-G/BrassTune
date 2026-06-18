# Domain Parity

## Current Shared Domain State

- Backend owns full pitch/session/analytics/recommendation behavior.
- Frontend consumes backend outputs and includes client-side display logic for tuner state, charts, heat maps, and reports.
- `swift/BrassTuneCore` exposes portable pitch helpers used by the native app.
- `swift/BrassTuneApp` imports `BrassTuneCore` and verifies that native app code can call shared tuning status logic.

## Verified Fixtures/Checks

| Case | Backend | Frontend | Swift |
|---|---|---|---|
| Pitch status from cents/confidence/rms | Covered by backend tests | Rendered in tuner components | `testCoreTuningStatusIsAvailableToApp` |
| Invalid/oversized PCM | `test_websocket_pcm_frame_size_is_limited` | N/A | Not yet mirrored |
| Batch frame limit | `test_batch_pitch_frame_size_is_limited` | N/A | N/A |
| Deterministic fixture recording | Backend demo data and browser journeys | Playwright record/stop review | `testFixtureRecordingCreatesDeterministicSession` |
| Reference pitch display | API/client model | UI settings/practice | Native settings/onboarding |
| Export/session ownership | Backend tests | Settings/session surfaces | Native ShareLink surface for fixture exports |

## Gaps

- The required full shared fixture matrix is not complete across backend, frontend, and Swift for every edge case.
- Portable Swift implementations still need expansion for transposition, note segmentation, duration-weighted analytics, heat-map inputs, progress metrics, recommendation rules, explicit date parsing, and error models.
- Existing Swift package tests are a parity smoke, not full domain equivalence.

## Required Next Work

- Add canonical JSON fixtures for invalid frequencies, reference pitch changes, transposing instruments, silence/no-lock, unstable pitch, note boundaries, short events, sparse data, and floating-point tolerance.
- Run each fixture through backend pytest, frontend Vitest where relevant, and Swift XCTest.
- Record backend/frontend/Swift output hashes or normalized JSON comparisons in this file.
