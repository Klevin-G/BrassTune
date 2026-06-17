# Swift Migration Plan

Branch: `swift-migration`

The web app remains the primary product until microphone behavior, auth, audio playback, exports, and deployment are validated on real devices.

## Current Web Architecture

- FastAPI backend owns pitch persistence, session summaries, exports, auth validation, audio storage, and ensemble authorization.
- React/Vite frontend owns practice UX, microphone capture, MediaRecorder audio capture, onboarding, Supabase Auth client, and responsive layouts.
- Domain logic is concentrated in `backend/app/core` and `frontend/src/domain`.

## Portable Modules

Port first:

- Frequency to MIDI
- MIDI to frequency
- Cents deviation
- Concert/written transposition
- Tuning status
- Note event segmentation
- Note analytics
- Recommendation rules
- Session audio metadata

## Shared Fixtures

Fixtures live in `fixtures/`:

- `pitch_math_cases.json`
- `transposition_cases.json`
- `note_segmentation_cases.json`
- `analytics_cases.json`
- `recommendation_cases.json`
- `session_audio_metadata_cases.json`

Backend pytest reads these now. `swift/BrassTuneCore` reads pitch math and transposition fixtures now. Future XCTest should expand to all fixtures.

## Swift Package

Added:

```text
swift/BrassTuneCore
```

It currently implements:

- `frequencyToMidi`
- `midiToFrequency`
- `centsDeviation`
- `transposeConcertToWritten`
- `tuningStatus`

Run:

```bash
cd swift/BrassTuneCore
swift test
```

## iOS Audio Design

Use:

- `AVAudioEngine`
- `AVAudioPCMBuffer`
- `AVAudioFile` for relisten recordings
- Accelerate or a tested YIN implementation for pitch detection

Match web semantics:

- No lock: detector confidence too low
- Unstable pitch: confident lock but cents vary
- Recording-quality lock: confidence >= 95%

## Supabase on Swift

Use Supabase Auth for sign in/up. Prefer the FastAPI backend for protected analytics, exports, ensemble authorization, and signed audio URLs. Direct Supabase access is acceptable only for carefully designed Storage/Auth flows.

## Phases

1. Finish web production readiness and real-device mic validation.
2. Expand `BrassTuneCore` to segmentation, analytics, and recommendations.
3. Add XCTest fixture coverage for every JSON fixture.
4. Build SwiftUI tuner prototype.
5. Add AVAudioEngine capture and relisten recording.
6. Add Supabase Auth and backend API client.
7. Add sessions, analytics, coach, and ensemble screens.

## Not Started Yet

No iOS app skeleton replaces the web app in this sprint. That waits until the web mic/audio thresholds are proven on iPhone/iPad Safari.
