# Metronome Validation

Updated: 2026-06-20 UTC.

## Implemented

- Web route: `/metronome`
- Web Audio `AudioContext.currentTime` lookahead scheduler.
- User-gesture start/stop.
- BPM bounds: 20 to 300.
- Time signatures: 2/4, 3/4, 4/4, 5/4, 6/8, 7/8, and custom.
- Subdivisions: quarter, eighth, triplet, sixteenth.
- One-bar count-in.
- Downbeat accent.
- Tap tempo.
- Optional tempo ramp with bars-per-step.
- Separate mute/volume state.
- Visual beat and subdivision indicators.

## Automated Evidence

- `frontend/src/domain/metronome.test.ts` covers BPM bounds, signature normalization, tick scheduling, subdivision timing, tap tempo, ramp behavior, and timing-stat calculation.
- `cd frontend && npm test` passed: `9` test files, `34` tests.
- `cd frontend && npm run build` passed.
- Full local E2E and device simulation passed after mobile overlap fixes.
- Rendered browser spot check verified Tap tempo updates BPM/status with no console errors or framework overlay.

## Not Yet Measured

- 10-minute foreground timing drift.
- Physical device acoustic click timing.
- Recording timestamp alignment during metronome playback.
- Mic bleed false-positive rate with real brass input.
- Background tab throttling behavior.
- Bluetooth speaker/headphone latency.
- Native metronome parity.

## Release Claim

It is valid to say the web beta includes a local Web Audio metronome with count-in, subdivisions, time signatures, and tempo ramp controls. It is not valid to claim professional metronome accuracy, no audio bleed, or native parity until measured timing and physical-device tests are complete.
