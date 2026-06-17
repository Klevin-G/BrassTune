# Swift Porting Notes

The future iOS app should preserve the backend core behavior while replacing the web audio and server pieces with native equivalents.

## Portable Modules

Port these modules first:

- `backend/app/core/music/theory.py`
- `backend/app/core/instruments/profiles.py`
- `backend/app/core/sessions/segmentation.py`
- `backend/app/core/analytics/stats.py`
- `backend/app/core/recommendations/rules.py`

They are intentionally written as plain data and pure functions where practical.

## Frequency and Cents

Swift equivalents:

```swift
func frequencyToMidi(_ frequency: Double, referenceA4: Double = 440) -> Double {
    69 + 12 * log2(frequency / referenceA4)
}

func midiToFrequency(_ midi: Double, referenceA4: Double = 440) -> Double {
    referenceA4 * pow(2, (midi - 69) / 12)
}

func centsDeviation(frequency: Double, target: Double) -> Double {
    1200 * log2(frequency / target)
}
```

## InstrumentProfile

Represent instrument profiles as Swift structs:

```swift
struct InstrumentProfile: Identifiable, Codable {
    let id: String
    let displayName: String
    let transpositionSemitones: Int
    let minFrequencyHz: Double
    let maxFrequencyHz: Double
    let preferredNoteSpellings: [String]
    let typicalRangeWritten: String
    let commonTuningTendencies: [String]
    let recommendationTemplates: [String: [String]]
    let futureSwiftNotes: String
}
```

## PitchFrame

Map the backend `PitchFrame` to a Swift `Codable` model:

```swift
struct PitchFrame: Codable {
    let timestampMs: Int
    let frequencyHz: Double?
    let confidence: Double
    let rms: Double
    let midiNoteFloat: Double?
    let nearestMidi: Int?
    let concertNoteName: String?
    let concertOctave: Int?
    let writtenNoteName: String?
    let writtenOctave: Int?
    let centsDeviation: Double?
    let tuningStatus: TuningStatus
    let instrumentId: String
    let referencePitchHz: Double
    let isValidForRecording: Bool
}
```

## NoteEvent

`NoteEvent` should remain a value type with duration-weighted stats:

```swift
struct NoteEvent: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    let instrumentId: String
    let writtenNote: String
    let writtenOctave: Int
    let concertNote: String
    let concertOctave: Int
    let startedAtMs: Int
    let endedAtMs: Int
    let durationMs: Int
    let sampleCount: Int
    let avgSignedCents: Double
    let avgAbsCents: Double
    let medianCents: Double
    let stddevCents: Double
    let inTunePercentage: Double
    let stabilityScore: Double
}
```

## iOS Audio

Replace browser Web Audio and backend WebSocket with:

- `AVAudioEngine` for microphone capture.
- `AVAudioPCMBuffer` to access mono float samples.
- `Accelerate` for efficient RMS, autocorrelation, FFT, or YIN-style calculations.
- A native pitch detection library if it gives better stability than a custom implementation.

Keep the output of native pitch detection identical to `PitchFrame` so session, analytics, heat map, and recommendations stay consistent.

## Persistence

SQLite can map to:

- SwiftData for modern SwiftUI persistence.
- Core Data if the app needs mature migration tooling.
- SQLite directly if cross-platform parity matters most.

Use the same conceptual tables:

- User
- InstrumentProfile
- PracticeSession
- PitchSample
- NoteEvent
- Group
- GroupMember
- Recommendation

## Keeping Behavior Identical

Build shared test fixtures:

- A4 440 Hz maps to A4 with 0 cents.
- 466.16 Hz maps to Bb4.
- Trumpet and horn written transposition match the backend.
- The same pitch frame list segments into the same note events.
- The same note events produce identical severity and recommendation categories.

Those fixtures should run in pytest now and XCTest later.

