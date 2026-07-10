import Foundation
import BrassTuneCore

enum NativeTestFixtures {
    static var areEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("UITEST_DEMO") || arguments.contains("UITEST_FIXTURES")
    }
}

func instrumentDisplayName(_ id: String) -> String {
    switch id {
    case "trumpet": return "Trumpet in Bb"
    case "horn": return "Horn in F"
    case "trombone": return "Trombone"
    case "euphonium": return "Euphonium"
    case "tuba": return "Tuba"
    default: return id.capitalized
    }
}

enum AppEnvironment: String, CaseIterable, Identifiable {
    case local
    case staging
    case production

    var id: String { rawValue }
}

struct AppConfig: Equatable {
    var environment: AppEnvironment
    var apiBaseURL: URL
    var supabaseURL: URL?
    var supabasePublishableKey: String?

    static func fromProcessEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> AppConfig {
        let apiBaseURL = environment["BRASSTUNE_API_BASE_URL"].flatMap(URL.init(string:)) ?? local.apiBaseURL
        return AppConfig(
            environment: environment["BRASSTUNE_ENV"].flatMap(AppEnvironment.init(rawValue:)) ?? .local,
            apiBaseURL: apiBaseURL,
            supabaseURL: environment["BRASSTUNE_SUPABASE_URL"].flatMap(URL.init(string:)),
            supabasePublishableKey: environment["BRASSTUNE_SUPABASE_PUBLISHABLE_KEY"]
        )
    }

    static let local = AppConfig(
        environment: .local,
        apiBaseURL: URL(string: "http://127.0.0.1:8000")!,
        supabaseURL: nil,
        supabasePublishableKey: nil
    )
}

struct PitchFrame: Codable, Equatable, Identifiable {
    var id: Int { timestampMs }
    let timestampMs: Int
    let frequencyHz: Double?
    let confidence: Double
    let rms: Double
    let centsDeviation: Double?
    let tuningStatus: TuningStatus
    let writtenNoteName: String?
    let writtenOctave: Int?
    let isValidForRecording: Bool

    static func fixture(index: Int, instrumentId: String = "trumpet", referencePitchHz: Double = 440.0) -> PitchFrame {
        let cents = Double([-7, -3, 0, 2, 8][index % 5])
        let concertMidi = fixtureConcertMidi(for: instrumentId)
        let writtenMidi = BrassTuneCore.transposeConcertToWritten(concertMidi, semitones: transpositionSemitones(for: instrumentId))
        let frequency = BrassTuneCore.midiToFrequency(Double(concertMidi), referencePitchHz: referencePitchHz) * pow(2.0, cents / 1200.0)
        return PitchFrame(
            timestampMs: index * 110,
            frequencyHz: frequency,
            confidence: 0.98,
            rms: 0.08,
            centsDeviation: cents,
            tuningStatus: BrassTuneCore.tuningStatus(cents: cents, confidence: 0.98, rms: 0.08),
            writtenNoteName: noteName(for: writtenMidi),
            writtenOctave: (writtenMidi / 12) - 1,
            isValidForRecording: true
        )
    }

    static func detected(
        timestampMs: Int,
        frequencyHz: Double?,
        confidence: Double,
        rms: Double,
        instrumentId: String,
        referencePitchHz: Double
    ) -> PitchFrame {
        let concertMidiFloat = frequencyHz.map { BrassTuneCore.frequencyToMidi($0, referencePitchHz: referencePitchHz) }
        let concertMidi = concertMidiFloat.map { Int($0.rounded()) }
        let cents = frequencyHz.flatMap { frequency -> Double? in
            guard let concertMidi else { return nil }
            return BrassTuneCore.centsDeviation(frequencyHz: frequency, nearestMidi: concertMidi, referencePitchHz: referencePitchHz)
        }
        let writtenMidi = concertMidi.map {
            BrassTuneCore.transposeConcertToWritten($0, semitones: transpositionSemitones(for: instrumentId))
        }
        let status = BrassTuneCore.tuningStatus(cents: cents, confidence: confidence, rms: rms)
        return PitchFrame(
            timestampMs: timestampMs,
            frequencyHz: frequencyHz,
            confidence: confidence,
            rms: rms,
            centsDeviation: cents,
            tuningStatus: status,
            writtenNoteName: writtenMidi.map(noteName(for:)),
            writtenOctave: writtenMidi.map { ($0 / 12) - 1 },
            isValidForRecording: [.flat, .inTune, .sharp].contains(status)
        )
    }

    private static func fixtureConcertMidi(for instrumentId: String) -> Int {
        switch instrumentId {
        case "horn": return 55
        case "trombone", "euphonium": return 58
        case "tuba": return 46
        default: return 72
        }
    }

    private static func transpositionSemitones(for instrumentId: String) -> Int {
        switch instrumentId {
        case "trumpet": return 2
        case "horn": return 7
        default: return 0
        }
    }

    private static func noteName(for midi: Int) -> String {
        let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        return names[((midi % 12) + 12) % 12]
    }
}

enum MetronomeSubdivision: String, Codable, CaseIterable, Identifiable {
    case quarter
    case eighth
    case triplet
    case sixteenth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quarter: return "Quarter"
        case .eighth: return "Eighth"
        case .triplet: return "Triplet"
        case .sixteenth: return "Sixteenth"
        }
    }

    var ticksPerBeat: Int {
        switch self {
        case .quarter: return 1
        case .eighth: return 2
        case .triplet: return 3
        case .sixteenth: return 4
        }
    }
}

struct MetronomeSettings: Codable, Equatable {
    var bpm: Int = 92
    var beatsPerMeasure: Int = 4
    var beatUnit: Int = 4
    var subdivision: MetronomeSubdivision = .quarter
    var muted: Bool = false
    var visualOnly: Bool = false
    var hapticsEnabled: Bool = false
    var volume: Double = 0.6

    var meterLabel: String {
        "\(beatsPerMeasure)/\(beatUnit)"
    }

    var intervalSeconds: TimeInterval {
        60.0 / Double(max(30, min(240, bpm))) / Double(subdivision.ticksPerBeat)
    }
}

enum ScoreSourceKind: String, Codable, CaseIterable, Identifiable {
    case filesPDF
    case filesImage
    case photos
    case sample

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filesPDF: return "Files PDF"
        case .filesImage: return "Files image"
        case .photos: return "Photos"
        case .sample: return "Sample"
        }
    }

    static var allCases: [ScoreSourceKind] {
        NativeTestFixtures.areEnabled ? [.filesPDF, .filesImage, .photos, .sample] : [.filesPDF, .filesImage, .photos]
    }
}

enum PracticeSessionSource: String, Codable, CaseIterable, Identifiable {
    case live
    case sample

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return "Live mic"
        case .sample: return "UI test fixture"
        }
    }

    var sessionTitle: String {
        switch self {
        case .live: return "Recording"
        case .sample: return "Test recording"
        }
    }

    var exportLabel: String {
        switch self {
        case .live: return "live microphone"
        case .sample: return "UI test fixture"
        }
    }

    static var allCases: [PracticeSessionSource] {
        NativeTestFixtures.areEnabled ? [.live, .sample] : [.live]
    }
}

struct PlayAlongExercise: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let difficulty: String
    let writtenNotes: [String]

    static let library: [PlayAlongExercise] = [
        PlayAlongExercise(
            id: "cmaj",
            title: "C major scale",
            detail: "One octave, ascending",
            difficulty: "Beginner",
            writtenNotes: ["C", "D", "E", "F", "G", "A", "B", "C"]
        ),
        PlayAlongExercise(
            id: "fmaj",
            title: "F major scale",
            detail: "One octave, ascending",
            difficulty: "Beginner",
            writtenNotes: ["F", "G", "A", "Bb", "C", "D", "E", "F"]
        ),
        PlayAlongExercise(
            id: "gmaj",
            title: "G major scale",
            detail: "One octave, ascending",
            difficulty: "Beginner",
            writtenNotes: ["G", "A", "B", "C", "D", "E", "F#", "G"]
        ),
        PlayAlongExercise(
            id: "arpeggio",
            title: "C major arpeggio",
            detail: "C · E · G · C",
            difficulty: "Beginner",
            writtenNotes: ["C", "E", "G", "C"]
        ),
        PlayAlongExercise(
            id: "chromatic",
            title: "Chromatic run",
            detail: "C up to G",
            difficulty: "Challenge",
            writtenNotes: ["C", "C#", "D", "Eb", "E", "F", "F#", "G"]
        ),
        PlayAlongExercise(
            id: "longtones",
            title: "Long tones",
            detail: "C · G · C — hold each note",
            difficulty: "Beginner",
            writtenNotes: ["C", "G", "C"]
        ),
    ]

    static let defaultExercise = library[0]
}

enum PlayAlongNoteRating: String, Codable, Equatable {
    case excellent
    case good
    case close
    case off
    case missed

    init(cents: Double?) {
        guard let cents, cents.isFinite else {
            self = .missed
            return
        }
        switch abs(cents) {
        case ...5: self = .excellent
        case ...15: self = .good
        case ...30: self = .close
        default: self = .off
        }
    }

    var title: String {
        switch self {
        case .excellent: return "Great"
        case .good: return "Good"
        case .close: return "Close"
        case .off: return "Try again"
        case .missed: return "Skipped"
        }
    }
}

struct PlayAlongNoteGrade: Codable, Equatable, Identifiable {
    let id: UUID
    let writtenNoteName: String
    let medianCents: Double?
    let sampleCount: Int
    let rating: PlayAlongNoteRating

    init(
        id: UUID = UUID(),
        writtenNoteName: String,
        medianCents: Double?,
        sampleCount: Int,
        rating: PlayAlongNoteRating? = nil
    ) {
        self.id = id
        self.writtenNoteName = writtenNoteName
        self.medianCents = medianCents
        self.sampleCount = sampleCount
        self.rating = rating ?? PlayAlongNoteRating(cents: medianCents)
    }
}

struct PlayAlongGrade: Codable, Equatable {
    let totalNotes: Int
    let notesPlayed: Int
    let inTuneNotes: Int
    let inTunePercentage: Int
    let averageAbsoluteCents: Double?
    let stars: Int
    let noteGrades: [PlayAlongNoteGrade]

    init(expectedNoteCount: Int, noteGrades: [PlayAlongNoteGrade]) {
        totalNotes = expectedNoteCount
        self.noteGrades = noteGrades
        let played = noteGrades.filter { $0.medianCents != nil }
        notesPlayed = played.count
        inTuneNotes = played.filter { [.excellent, .good].contains($0.rating) }.count
        inTunePercentage = expectedNoteCount > 0
            ? Int((Double(inTuneNotes) / Double(expectedNoteCount) * 100).rounded())
            : 0
        if played.isEmpty {
            averageAbsoluteCents = nil
        } else {
            let average = played.compactMap(\.medianCents).map(abs).reduce(0, +) / Double(played.count)
            averageAbsoluteCents = (average * 10).rounded() / 10
        }
        switch inTunePercentage {
        case 85...: stars = 3
        case 60...: stars = 2
        case 1...: stars = 1
        default: stars = notesPlayed > 0 ? 1 : 0
        }
    }
}

enum PlayAlongPhase: Equatable {
    case idle
    case running
    case completed
}

struct PlayAlongGrader: Equatable {
    let writtenNotes: [String]
    private(set) var currentNoteIndex = 0
    private(set) var detectedNoteName: String?
    private(set) var detectedCents: Double?
    private(set) var noteGrades: [PlayAlongNoteGrade] = []

    let holdDurationMs: Int
    let minimumConfidence: Double
    let minimumSamples: Int
    let attackTrimMs: Int
    let maximumDropoutMs: Int

    private var firstMatchTimestampMs: Int?
    private var lastMatchTimestampMs: Int?
    private var lastTimestampMs = 0
    private var centsSamples: [TimedCentsSample] = []

    init(
        writtenNotes: [String],
        holdDurationMs: Int = 450,
        minimumConfidence: Double = 0.65,
        minimumSamples: Int = 5,
        attackTrimMs: Int = 120,
        maximumDropoutMs: Int = 250
    ) {
        self.writtenNotes = writtenNotes
        self.holdDurationMs = max(100, holdDurationMs)
        self.minimumConfidence = min(1, max(0, minimumConfidence))
        self.minimumSamples = max(1, minimumSamples)
        self.attackTrimMs = max(0, attackTrimMs)
        self.maximumDropoutMs = max(0, maximumDropoutMs)
    }

    var isComplete: Bool {
        currentNoteIndex >= writtenNotes.count
    }

    var currentNoteName: String? {
        guard !isComplete else { return nil }
        return writtenNotes[currentNoteIndex]
    }

    var heldFraction: Double {
        guard let firstMatchTimestampMs else { return 0 }
        return min(1, max(0, Double(lastTimestampMs - firstMatchTimestampMs) / Double(holdDurationMs)))
    }

    mutating func feed(_ frame: PitchFrame) {
        guard !isComplete else { return }
        lastTimestampMs = max(lastTimestampMs, frame.timestampMs)
        detectedNoteName = frame.writtenNoteName
        detectedCents = frame.centsDeviation

        guard let target = currentNoteName else { return }
        let confident = frame.confidence >= minimumConfidence && frame.frequencyHz != nil
        let matchesTarget = confident
            && Self.pitchClass(frame.writtenNoteName) == Self.pitchClass(target)
            && frame.centsDeviation != nil

        if matchesTarget, let cents = frame.centsDeviation {
            if let lastMatchTimestampMs,
               frame.timestampMs - lastMatchTimestampMs > maximumDropoutMs {
                firstMatchTimestampMs = nil
                centsSamples.removeAll(keepingCapacity: true)
            }
            if firstMatchTimestampMs == nil {
                firstMatchTimestampMs = frame.timestampMs
            }
            lastMatchTimestampMs = frame.timestampMs
            centsSamples.append(TimedCentsSample(timestampMs: frame.timestampMs, cents: cents))
            if let firstMatchTimestampMs,
               frame.timestampMs - firstMatchTimestampMs >= holdDurationMs,
               centsSamples.count >= minimumSamples {
                finalizeCurrentNote(wasPlayed: true)
            }
        } else if confident,
                  let detected = frame.writtenNoteName,
                  Self.pitchClass(detected) != Self.pitchClass(target) {
            // A confidently played different note restarts this target. Brief
            // silence and low-confidence dropouts do not erase a good hold.
            firstMatchTimestampMs = nil
            lastMatchTimestampMs = nil
            centsSamples.removeAll(keepingCapacity: true)
        } else if !confident,
                  let lastMatchTimestampMs,
                  frame.timestampMs - lastMatchTimestampMs > maximumDropoutMs {
            firstMatchTimestampMs = nil
            self.lastMatchTimestampMs = nil
            centsSamples.removeAll(keepingCapacity: true)
        }
    }

    mutating func skipCurrentNote() {
        guard !isComplete else { return }
        finalizeCurrentNote(wasPlayed: false)
    }

    private mutating func finalizeCurrentNote(wasPlayed: Bool) {
        guard let target = currentNoteName else { return }
        let scoredCents: Double?
        if wasPlayed, let firstMatchTimestampMs, !centsSamples.isEmpty {
            let sustained = centsSamples.filter { $0.timestampMs - firstMatchTimestampMs >= attackTrimMs }
            let minimumTrustedSustainSamples = min(minimumSamples, 3)
            let source = sustained.count >= minimumTrustedSustainSamples ? sustained : centsSamples
            scoredCents = Self.median(source.map(\.cents))
        } else {
            scoredCents = nil
        }
        let roundedCents = scoredCents.map { ($0 * 10).rounded() / 10 }
        noteGrades.append(
            PlayAlongNoteGrade(
                writtenNoteName: target,
                medianCents: roundedCents,
                sampleCount: centsSamples.count
            )
        )
        currentNoteIndex += 1
        firstMatchTimestampMs = nil
        lastMatchTimestampMs = nil
        centsSamples.removeAll(keepingCapacity: true)
        if isComplete {
            detectedNoteName = nil
            detectedCents = nil
        }
    }

    private static func pitchClass(_ noteName: String?) -> Int? {
        guard let noteName else { return nil }
        let normalized = noteName
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        let pitchClasses = [
            "C": 0, "B#": 0,
            "C#": 1, "Db": 1,
            "D": 2,
            "D#": 3, "Eb": 3,
            "E": 4, "Fb": 4,
            "E#": 5, "F": 5,
            "F#": 6, "Gb": 6,
            "G": 7,
            "G#": 8, "Ab": 8,
            "A": 9,
            "A#": 10, "Bb": 10,
            "B": 11, "Cb": 11,
        ]
        return pitchClasses[normalized]
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

struct PlayAlongSession: Equatable {
    let exercise: PlayAlongExercise
    let startedAt: Date
    private(set) var completedAt: Date?
    private var grader: PlayAlongGrader

    init(
        exercise: PlayAlongExercise,
        startedAt: Date = Date(),
        holdDurationMs: Int = 450,
        minimumConfidence: Double = 0.65,
        minimumSamples: Int = 5,
        attackTrimMs: Int = 120
    ) {
        self.exercise = exercise
        self.startedAt = startedAt
        grader = PlayAlongGrader(
            writtenNotes: exercise.writtenNotes,
            holdDurationMs: holdDurationMs,
            minimumConfidence: minimumConfidence,
            minimumSamples: minimumSamples,
            attackTrimMs: attackTrimMs
        )
    }

    var currentNoteIndex: Int { grader.currentNoteIndex }
    var currentNoteName: String? { grader.currentNoteName }
    var heldFraction: Double { grader.heldFraction }
    var detectedNoteName: String? { grader.detectedNoteName }
    var detectedCents: Double? { grader.detectedCents }
    var noteGrades: [PlayAlongNoteGrade] { grader.noteGrades }
    var isComplete: Bool { grader.isComplete }

    var grade: PlayAlongGrade? {
        guard isComplete else { return nil }
        return PlayAlongGrade(expectedNoteCount: exercise.writtenNotes.count, noteGrades: noteGrades)
    }

    mutating func feed(_ frame: PitchFrame) {
        guard !isComplete else { return }
        grader.feed(frame)
        if grader.isComplete {
            completedAt = Date()
        }
    }

    mutating func skipCurrentNote() {
        guard !isComplete else { return }
        grader.skipCurrentNote()
        if grader.isComplete {
            completedAt = Date()
        }
    }
}

private struct TimedCentsSample: Equatable {
    let timestampMs: Int
    let cents: Double
}

enum ScoreEnhancement: String, Codable, CaseIterable, Identifiable {
    case original
    case grayscale
    case contrast
    case highContrast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .grayscale: return "Grayscale"
        case .contrast: return "Contrast"
        case .highContrast: return "High contrast"
        }
    }
}

enum ScoreCropPreset: String, Codable, CaseIterable, Identifiable {
    case fullPage
    case trimMargins
    case upperHalf
    case lowerHalf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullPage: return "Full page"
        case .trimMargins: return "Trim margins"
        case .upperHalf: return "Upper half"
        case .lowerHalf: return "Lower half"
        }
    }
}

struct ScoreRegion: Codable, Equatable, Identifiable {
    let id: UUID
    var label: String
    var normalizedX: Double
    var normalizedY: Double
    var normalizedWidth: Double
    var normalizedHeight: Double
}

struct ScoreAnnotation: Codable, Equatable {
    var focusMeasures: String = ""
    var notes: String = ""
    var tempoTarget: Int = 92
    var problemPassage: String = ""
}

struct ScorePage: Codable, Equatable, Identifiable {
    let id: UUID
    var pageNumber: Int
    var titleSuggestion: String?
    var textSuggestions: [String]
    var thumbnailPNGData: Data?
    var rotationDegrees: Int = 0
    var cropPreset: ScoreCropPreset = .fullPage
    var enhancement: ScoreEnhancement = .original
    var suggestedRegions: [ScoreRegion] = []
}

struct ImportedScore: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var composer: String?
    var sourceKind: ScoreSourceKind
    var localFileName: String?
    var importedAt: Date
    var pages: [ScorePage]
    var selectedPageID: ScorePage.ID?
    var annotation: ScoreAnnotation = ScoreAnnotation()
    var originalFileSizeBytes: Int64 = 0

    var selectedPage: ScorePage? {
        guard let selectedPageID else {
            return pages.first
        }
        return pages.first { $0.id == selectedPageID } ?? pages.first
    }

    var pageCountLabel: String {
        pages.count == 1 ? "1 page" : "\(pages.count) pages"
    }

    var exportText: String {
        var lines = [
            "BrassTune score metadata export",
            "Score: \(title)",
            "Source: \(sourceKind.title)",
            "Pages: \(pages.count)",
            "Imported: \(ISO8601DateFormatter().string(from: importedAt))",
            "Tempo target: \(annotation.tempoTarget) BPM",
        ]
        if let composer, !composer.isEmpty {
            lines.append("Composer/arranger: \(composer)")
        }
        if !annotation.focusMeasures.isEmpty {
            lines.append("Focus measures: \(annotation.focusMeasures)")
        }
        if !annotation.problemPassage.isEmpty {
            lines.append("Problem passage: \(annotation.problemPassage)")
        }
        if !annotation.notes.isEmpty {
            lines.append("Notes: \(annotation.notes)")
        }
        return lines.joined(separator: "\n")
    }
}

struct PracticeSession: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var instrumentId: String
    var startedAt: Date
    var endedAt: Date?
    var frames: [PitchFrame]
    var retainedRecordingURL: URL?
    var attachedScoreID: ImportedScore.ID? = nil
    var practiceNotes: String = ""
    var source: PracticeSessionSource = .live

    init(
        id: UUID,
        name: String,
        instrumentId: String,
        startedAt: Date,
        endedAt: Date?,
        frames: [PitchFrame],
        retainedRecordingURL: URL?,
        attachedScoreID: ImportedScore.ID? = nil,
        practiceNotes: String = "",
        source: PracticeSessionSource = .live
    ) {
        self.id = id
        self.name = name
        self.instrumentId = instrumentId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.frames = frames
        self.retainedRecordingURL = retainedRecordingURL
        self.attachedScoreID = attachedScoreID
        self.practiceNotes = practiceNotes
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case instrumentId
        case startedAt
        case endedAt
        case frames
        case retainedRecordingURL
        case attachedScoreID
        case practiceNotes
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        instrumentId = try container.decode(String.self, forKey: .instrumentId)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        frames = try container.decode([PitchFrame].self, forKey: .frames)
        retainedRecordingURL = try container.decodeIfPresent(URL.self, forKey: .retainedRecordingURL)
        attachedScoreID = try container.decodeIfPresent(ImportedScore.ID.self, forKey: .attachedScoreID)
        practiceNotes = try container.decodeIfPresent(String.self, forKey: .practiceNotes) ?? ""
        // Sessions written before the source field existed came from the old
        // fixture-first flow. Keep them quarantined as fixtures instead of
        // silently relabeling fabricated readings as microphone recordings.
        source = try container.decodeIfPresent(PracticeSessionSource.self, forKey: .source) ?? .sample
    }

    var averageAbsCents: Double {
        let values = frames.filter(\.isValidForRecording).compactMap(\.centsDeviation).map { abs($0) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var inTunePercentage: Double {
        let values = frames.filter(\.isValidForRecording).compactMap(\.centsDeviation)
        guard !values.isEmpty else { return 0 }
        let inTune = values.filter { abs($0) <= 5 }.count
        return Double(inTune) / Double(values.count) * 100
    }

    var durationSeconds: TimeInterval {
        max(0, (endedAt ?? startedAt).timeIntervalSince(startedAt))
    }

    var validFrameCount: Int {
        frames.filter(\.isValidForRecording).count
    }

    var pitchCoverageLabel: String {
        let noteNames = Set(frames.compactMap { frame -> String? in
            guard let note = frame.writtenNoteName, let octave = frame.writtenOctave else { return nil }
            return "\(note)\(octave)"
        })
        guard !noteNames.isEmpty else { return "No notes detected" }
        return noteNames.sorted().joined(separator: ", ")
    }

    var exportText: String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "BrassTune session export",
            "Session: \(name)",
            "Instrument: \(instrumentDisplayName(instrumentId))",
            "Source: \(source.exportLabel)",
            "Started: \(formatter.string(from: startedAt))",
            "Ended: \(endedAt.map { formatter.string(from: $0) } ?? "Not ended")",
            "Duration: \(String(format: "%.0f", durationSeconds)) seconds",
            "Pitch samples: \(frames.count)",
            "Notes heard: \(validFrameCount)",
            "Average absolute cents: \(String(format: "%.1f", averageAbsCents))",
            "In-tune percentage: \(String(format: "%.0f", inTunePercentage))%",
            "Pitch coverage: \(pitchCoverageLabel)",
        ]
        if let attachedScoreID {
            lines.append("Attached score: \(attachedScoreID.uuidString)")
        }
        if !practiceNotes.isEmpty {
            lines.append("Practice notes: \(practiceNotes)")
        }
        let centsPreview = frames.compactMap(\.centsDeviation).prefix(12).map { String(format: "%+.1f", $0) }
        if !centsPreview.isEmpty {
            lines.append("Cents preview: \(centsPreview.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}

struct AnalyticsSnapshot: Equatable {
    let sessionCount: Int
    let totalFrameCount: Int
    let validFrameCount: Int
    let averageAbsCents: Double
    let averageInTunePercentage: Double
    let bestSessionName: String?
    let latestSessionName: String?
    let latestSessionInTunePercentage: Double
    let totalPracticeSeconds: TimeInterval

    var hasSessions: Bool {
        sessionCount > 0
    }

    var hasUsableEvidence: Bool {
        validFrameCount >= 8
    }

    var recommendation: String {
        guard hasSessions else {
            return "Record your first note to see a practice tip."
        }
        guard hasUsableEvidence else {
            return "Play a little longer so BrassTune can suggest what to practice next."
        }
        if averageAbsCents > 8 {
            return "Start with drone matching and slow attacks before extending range."
        }
        if averageInTunePercentage < 75 {
            return "Repeat stable long tones and hold each pitch through the release."
        }
        return "Intonation is settling. Add a repertoire excerpt after the next long-tone pass."
    }

    init(sessions: [PracticeSession]) {
        sessionCount = sessions.count
        totalFrameCount = sessions.reduce(0) { $0 + $1.frames.count }
        validFrameCount = sessions.reduce(0) { $0 + $1.validFrameCount }
        totalPracticeSeconds = sessions.reduce(0) { $0 + $1.durationSeconds }

        let validFrames = sessions.flatMap { $0.frames.filter(\.isValidForRecording) }
        let allCents = validFrames.compactMap(\.centsDeviation)
        if allCents.isEmpty {
            averageAbsCents = 0
            averageInTunePercentage = 0
        } else {
            averageAbsCents = allCents.map { abs($0) }.reduce(0, +) / Double(allCents.count)
            let inTuneCount = allCents.filter { abs($0) <= 5 }.count
            averageInTunePercentage = Double(inTuneCount) / Double(allCents.count) * 100
        }

        let eligibleSessions = sessions.filter { $0.validFrameCount > 0 }
        let bestSession = eligibleSessions.min { lhs, rhs in
            lhs.averageAbsCents < rhs.averageAbsCents
        }
        bestSessionName = bestSession?.name

        let latestSession = sessions.max { lhs, rhs in
            lhs.startedAt < rhs.startedAt
        }
        latestSessionName = latestSession?.name
        latestSessionInTunePercentage = latestSession?.inTunePercentage ?? 0
    }
}

struct EnsembleSummary: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var role: String
    var activeMembers: Int
    var focus: String
}

enum AuthState: Equatable {
    case signedOut
    case guest
    case signedIn(email: String)
    case emailConfirmationRequired(email: String)

    var displayTitle: String {
        switch self {
        case .signedOut: return "Signed out"
        case .guest: return "Guest practice"
        case .signedIn(let email): return email
        case .emailConfirmationRequired(let email): return "Confirm \(email)"
        }
    }

    var usesRemoteAccount: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

enum UserVisibleError: LocalizedError, Equatable {
    case microphoneDenied
    case networkUnavailable
    case malformedResponse
    case timeout
    case appleSignInCancelled
    case accountDeletionRequiresConfirmation
    case missingAuthConfiguration
    case authenticationFailed
    case emailConfirmationRequired
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access is off. Allow it in Settings, then try again."
        case .networkUnavailable: return "The account service is unavailable right now."
        case .malformedResponse: return "The account service returned an unreadable response."
        case .timeout: return "The request timed out."
        case .appleSignInCancelled: return "Apple sign-in was cancelled."
        case .accountDeletionRequiresConfirmation: return "Please confirm deletion and try again."
        case .missingAuthConfiguration: return "Account sign-in isn't available right now. You can keep practicing as a guest."
        case .authenticationFailed: return "BrassTune could not complete authentication."
        case .emailConfirmationRequired: return "Check your email to confirm this BrassTune account before signing in."
        case .microphoneUnavailable: return "BrassTune could not hear the microphone. Check your audio input and try again."
        }
    }
}
