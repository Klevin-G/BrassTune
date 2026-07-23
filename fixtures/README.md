# BrassTune Shared Fixtures

These JSON fixtures define behavior that should stay identical between the web MVP and a future Swift/iPad app.

- `pitch_math_cases.json`: frequency, MIDI, cents, and written-note expectations.
- `transposition_cases.json`: instrument transposition, acoustic range, and written-range expectations.
- `note_segmentation_cases.json`: pitch-frame groups and expected note events.
- `analytics_cases.json`: expected note-stat trend/severity behavior.
- `recommendation_cases.json`: analytics inputs and expected coaching categories.
- `play_along_contract.json`: centered/accepted cents windows, two-second hold, confidence, dropout, attack-trim, rating, and star definitions.
- `reference_tone_cases.json`: exact concert frequencies for written notes and the zero-detune oscillator contract.
- `drone_dyad_cases.json`: exact two-voice drone frequencies with zero detune on both oscillators.
- `metronome_cases.json`: denominator-beat BPM and subdivision timing shared by web and native metronomes.
- `pitch_quality_contract.json`: executable deterministic synthetic-tone quality thresholds; explicitly not physical-microphone evidence.
- `session_audio_metadata_cases.json`: expected relisten/audio metadata states.

The backend pytest and frontend Vitest suites read these fixtures now. The `swift/BrassTuneCore` package also reads the pitch math and transposition fixtures. Native XCTest loads the relevant scorer, reference-tone, drone, and metronome contracts directly. Expected values in JSON are the cross-platform contract, including midpoint rounding toward the higher MIDI note, zero oscillator detune, and BPM measured in the selected denominator beat.
