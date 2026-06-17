# BrassTune Shared Fixtures

These JSON fixtures define behavior that should stay identical between the web MVP and a future Swift/iPad app.

- `pitch_math_cases.json`: frequency, MIDI, cents, and written-note expectations.
- `transposition_cases.json`: instrument transposition expectations.
- `note_segmentation_cases.json`: pitch-frame groups and expected note events.
- `analytics_cases.json`: expected note-stat trend/severity behavior.
- `recommendation_cases.json`: analytics inputs and expected coaching categories.
- `session_audio_metadata_cases.json`: expected relisten/audio metadata states.

The backend pytest suite reads these fixtures now. The `swift/BrassTuneCore` package also reads the pitch math and transposition fixtures. Future XCTest targets should load this same directory to verify Swift pitch math, segmentation, analytics, session audio metadata, and recommendation behavior against the web implementation.
