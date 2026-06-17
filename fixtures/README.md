# BrassTune Shared Fixtures

These JSON fixtures define behavior that should stay identical between the web MVP and a future Swift/iPad app.

- `pitch_math_cases.json`: frequency, MIDI, cents, and written-note expectations.
- `transposition_cases.json`: instrument transposition expectations.
- `note_segmentation_cases.json`: pitch-frame groups and expected note events.
- `recommendation_cases.json`: analytics inputs and expected coaching categories.

The backend pytest suite reads these fixtures now. A future XCTest target can load the same files to verify Swift pitch math, segmentation, analytics, and recommendation behavior against the web implementation.
