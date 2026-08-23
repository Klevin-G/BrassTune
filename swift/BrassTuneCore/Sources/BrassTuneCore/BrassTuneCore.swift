import Foundation

public enum TuningStatus: String, Codable, Sendable {
    case flat
    case inTune = "in_tune"
    case sharp
    case noLock = "no_lock"
    case unstable
    case silence
}

public enum ClefPreference: String, Codable, Equatable, Sendable {
    case treble
    case bass
}

public enum NotationPreference: String, Codable, Equatable, Sendable {
    case transposed
    case concert
}

public struct MIDIRange: Codable, Equatable, Sendable {
    public let minimum: Int
    public let maximum: Int

    public init(minimum: Int, maximum: Int) {
        precondition(minimum <= maximum, "A MIDI range minimum must not exceed its maximum.")
        self.minimum = minimum
        self.maximum = maximum
    }

    public func contains(_ midi: Int) -> Bool {
        (minimum...maximum).contains(midi)
    }
}

public struct DetectorFrequencyRange: Codable, Equatable, Sendable {
    public let minimumHz: Double
    public let maximumHz: Double

    public init(minimumHz: Double, maximumHz: Double) {
        precondition(minimumHz.isFinite && minimumHz > 0, "A detector minimum must be finite and positive.")
        precondition(maximumHz.isFinite && maximumHz >= minimumHz, "A detector maximum must be finite and at least the minimum.")
        self.minimumHz = minimumHz
        self.maximumHz = maximumHz
    }

    public func contains(_ frequencyHz: Double) -> Bool {
        frequencyHz.isFinite && frequencyHz >= minimumHz && frequencyHz <= maximumHz
    }
}

public struct InstrumentProfile: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// The displayed transposition, for example `B♭` or `F`.
    public let displayNotation: String
    /// Positive values raise written MIDI above concert MIDI.
    public let transpositionSemitones: Int
    public let notationPreference: NotationPreference
    public let preferredClef: ClefPreference
    public let practicalWrittenRange: MIDIRange
    public let practicalSoundingRange: MIDIRange

    /// Broad capture window used by pitch detection. This is intentionally
    /// independent from the narrower practical register used by scale UI.
    public var detectorFrequencyRange: DetectorFrequencyRange {
        InstrumentProfiles.detectorFrequencyRange(for: id) ?? DetectorFrequencyRange(
            minimumHz: BrassTuneCore.midiToFrequency(Double(practicalSoundingRange.minimum)),
            maximumHz: BrassTuneCore.midiToFrequency(Double(practicalSoundingRange.maximum))
        )
    }

    /// Backwards-compatible initializer for callers that only know an ID and transposition.
    public init(id: String, transpositionSemitones: Int) {
        self.init(
            id: id,
            displayName: id,
            displayNotation: transpositionSemitones == 0 ? "C" : "B♭",
            transpositionSemitones: transpositionSemitones,
            notationPreference: transpositionSemitones == 0 ? .concert : .transposed,
            preferredClef: transpositionSemitones == 0 ? .bass : .treble,
            practicalWrittenRange: MIDIRange(minimum: 0, maximum: 127),
            practicalSoundingRange: MIDIRange(minimum: 0, maximum: 127)
        )
    }

    public init(
        id: String,
        displayName: String,
        displayNotation: String,
        transpositionSemitones: Int,
        notationPreference: NotationPreference,
        preferredClef: ClefPreference,
        practicalWrittenRange: MIDIRange,
        practicalSoundingRange: MIDIRange
    ) {
        self.id = id
        self.displayName = displayName
        self.displayNotation = displayNotation
        self.transpositionSemitones = transpositionSemitones
        self.notationPreference = notationPreference
        self.preferredClef = preferredClef
        self.practicalWrittenRange = practicalWrittenRange
        self.practicalSoundingRange = practicalSoundingRange
    }
}

/// Canonical, fail-closed instrument definitions shared by native practice features.
public enum InstrumentProfiles {
    public static let all: [InstrumentProfile] = [
        bbSoprano(id: "trumpet", name: "Trumpet in B♭", writtenRange: MIDIRange(minimum: 54, maximum: 84)),
        bbSoprano(id: "cornet", name: "Cornet in B♭", writtenRange: MIDIRange(minimum: 54, maximum: 82)),
        bbSoprano(id: "flugelhorn", name: "Flugelhorn in B♭", writtenRange: MIDIRange(minimum: 52, maximum: 81)),
        InstrumentProfile(
            id: "c-trumpet", displayName: "Trumpet in C", displayNotation: "C", transpositionSemitones: 0,
            notationPreference: .concert, preferredClef: .treble,
            practicalWrittenRange: MIDIRange(minimum: 54, maximum: 84), practicalSoundingRange: MIDIRange(minimum: 54, maximum: 84)
        ),
        InstrumentProfile(
            id: "horn", displayName: "French Horn in F", displayNotation: "F", transpositionSemitones: 7,
            notationPreference: .transposed, preferredClef: .treble,
            practicalWrittenRange: MIDIRange(minimum: 53, maximum: 84), practicalSoundingRange: MIDIRange(minimum: 46, maximum: 77)
        ),
        InstrumentProfile(
            id: "trombone", displayName: "Trombone", displayNotation: "C", transpositionSemitones: 0,
            notationPreference: .concert, preferredClef: .bass,
            practicalWrittenRange: MIDIRange(minimum: 40, maximum: 70), practicalSoundingRange: MIDIRange(minimum: 40, maximum: 70)
        ),
        InstrumentProfile(
            id: "euphonium", displayName: "Euphonium (concert)", displayNotation: "C", transpositionSemitones: 0,
            notationPreference: .concert, preferredClef: .bass,
            practicalWrittenRange: MIDIRange(minimum: 40, maximum: 70), practicalSoundingRange: MIDIRange(minimum: 40, maximum: 70)
        ),
        InstrumentProfile(
            id: "baritone-concert", displayName: "Baritone (concert)", displayNotation: "C", transpositionSemitones: 0,
            notationPreference: .concert, preferredClef: .bass,
            practicalWrittenRange: MIDIRange(minimum: 40, maximum: 70), practicalSoundingRange: MIDIRange(minimum: 40, maximum: 70)
        ),
        bbTrebleLowBrass(id: "baritone", name: "Baritone in B♭ (treble)", writtenRange: MIDIRange(minimum: 52, maximum: 82)),
        bbTrebleLowBrass(id: "euphonium-treble", name: "Euphonium in B♭ (treble)", writtenRange: MIDIRange(minimum: 52, maximum: 82)),
        InstrumentProfile(
            id: "tuba", displayName: "Tuba", displayNotation: "C", transpositionSemitones: 0,
            notationPreference: .concert, preferredClef: .bass,
            practicalWrittenRange: MIDIRange(minimum: 26, maximum: 65), practicalSoundingRange: MIDIRange(minimum: 26, maximum: 65)
        )
    ]

    private static let aliases = ["french-horn": "horn", "c_trumpet": "c-trumpet", "euphonium-tc": "euphonium-treble"]
    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func profile(for id: String) -> InstrumentProfile? {
        byID[aliases[id] ?? id]
    }

    public static func detectorFrequencyRange(for id: String) -> DetectorFrequencyRange? {
        switch aliases[id] ?? id {
        case "trumpet", "cornet", "flugelhorn", "c-trumpet":
            return DetectorFrequencyRange(minimumHz: 130, maximumHz: 1_500)
        case "horn":
            return DetectorFrequencyRange(minimumHz: 80, maximumHz: 1_200)
        case "trombone":
            return DetectorFrequencyRange(minimumHz: 50, maximumHz: 700)
        case "euphonium", "baritone-concert", "baritone", "euphonium-treble":
            return DetectorFrequencyRange(minimumHz: 55, maximumHz: 800)
        case "tuba":
            return DetectorFrequencyRange(minimumHz: 30, maximumHz: 500)
        default:
            return nil
        }
    }

    private static func bbSoprano(id: String, name: String, writtenRange: MIDIRange) -> InstrumentProfile {
        InstrumentProfile(
            id: id, displayName: name, displayNotation: "B♭", transpositionSemitones: 2,
            notationPreference: .transposed, preferredClef: .treble,
            practicalWrittenRange: writtenRange,
            practicalSoundingRange: MIDIRange(minimum: writtenRange.minimum - 2, maximum: writtenRange.maximum - 2)
        )
    }

    private static func bbTrebleLowBrass(id: String, name: String, writtenRange: MIDIRange) -> InstrumentProfile {
        InstrumentProfile(
            id: id, displayName: name, displayNotation: "B♭", transpositionSemitones: 14,
            notationPreference: .transposed, preferredClef: .treble,
            practicalWrittenRange: writtenRange,
            practicalSoundingRange: MIDIRange(minimum: writtenRange.minimum - 14, maximum: writtenRange.maximum - 14)
        )
    }
}

public enum ScaleRoot: String, CaseIterable, Codable, Equatable, Sendable {
    case c = "C", db = "D♭", d = "D", eb = "E♭", e = "E", f = "F", fs = "F♯", g = "G", ab = "A♭", a = "A", bb = "B♭", b = "B"

    public var pitchClass: Int {
        switch self {
        case .c: return 0
        case .db: return 1
        case .d: return 2
        case .eb: return 3
        case .e: return 4
        case .f: return 5
        case .fs: return 6
        case .g: return 7
        case .ab: return 8
        case .a: return 9
        case .bb: return 10
        case .b: return 11
        }
    }
}

public enum ScaleType: String, CaseIterable, Codable, Equatable, Sendable {
    case major
    case naturalMinor = "natural_minor"
    case harmonicMinor = "harmonic_minor"
    case melodicMinor = "melodic_minor"
    case chromatic
}

public enum ScaleDirection: String, CaseIterable, Codable, Equatable, Sendable {
    case ascending
    case descending
    case both
}

public enum ScaleOctaves: Int, CaseIterable, Codable, Equatable, Sendable {
    case one = 1
    case two = 2
    case three = 3
}

public enum ScaleRangePolicy: String, Codable, Equatable, Sendable {
    /// Return no scale if the requested root octave cannot fit the complete scale.
    case reject
    /// Move the root by whole octaves to the closest practical register that fits the complete scale.
    case adapt
}

public struct ScaleNote: Codable, Equatable, Sendable {
    public let writtenMIDI: Int
    public let soundingMIDI: Int
    public let writtenName: String
    public let soundingName: String

    public var writtenOctave: Int { (writtenMIDI / 12) - 1 }
    public var soundingOctave: Int { (soundingMIDI / 12) - 1 }
}

public struct GeneratedScale: Codable, Equatable, Sendable {
    public let root: ScaleRoot
    public let type: ScaleType
    public let direction: ScaleDirection
    public let octaves: ScaleOctaves
    public let notes: [ScaleNote]
}

public enum ScaleGenerator {
    /// Generates a written scale. When a profile is supplied, MIDI values are adapted or rejected against its practical written range.
    public static func generate(
        root: ScaleRoot,
        type: ScaleType,
        octaves: ScaleOctaves = .one,
        direction: ScaleDirection = .both,
        profile: InstrumentProfile? = nil,
        rangePolicy: ScaleRangePolicy = .adapt
    ) -> GeneratedScale? {
        let span = 12 * octaves.rawValue
        guard let baseMIDI = resolvedBaseMIDI(root: root, span: span, profile: profile, policy: rangePolicy) else { return nil }
        let ascending = ascendingOffsets(type: type, octaves: octaves)
        let descending = descendingOffsets(type: type, octaves: octaves)
        let entries: [(offset: Int, ascending: Bool)]
        switch direction {
        case .ascending: entries = ascending.map { ($0, true) }
        case .descending: entries = descending.map { ($0, false) }
        case .both: entries = ascending.map { ($0, true) } + descending.dropFirst().map { ($0, false) }
        }
        return GeneratedScale(
            root: root, type: type, direction: direction, octaves: octaves,
            notes: entries.map { entry in
                let offset = entry.offset
                let writtenMIDI = baseMIDI + offset
                let soundingMIDI = writtenMIDI - (profile?.transpositionSemitones ?? 0)
                return ScaleNote(
                    writtenMIDI: writtenMIDI,
                    soundingMIDI: soundingMIDI,
                    writtenName: name(for: root, type: type, offset: offset, ascending: entry.ascending),
                    soundingName: chromaticName(for: soundingMIDI, preferSharps: root == .fs)
                )
            }
        )
    }

    private static func resolvedBaseMIDI(root: ScaleRoot, span: Int, profile: InstrumentProfile?, policy: ScaleRangePolicy) -> Int? {
        let requested = 60 + root.pitchClass
        guard let profile else { return requested }
        if profile.practicalWrittenRange.contains(requested), profile.practicalWrittenRange.contains(requested + span) { return requested }
        guard policy == .adapt else { return nil }
        let candidates = (-8...8).map { requested + ($0 * 12) }.filter {
            profile.practicalWrittenRange.contains($0) && profile.practicalWrittenRange.contains($0 + span)
        }
        return candidates.min { abs($0 - requested) < abs($1 - requested) }
    }

    private static func ascendingOffsets(type: ScaleType, octaves: ScaleOctaves) -> [Int] {
        let single: [Int]
        switch type {
        case .major: single = [0, 2, 4, 5, 7, 9, 11, 12]
        case .naturalMinor: single = [0, 2, 3, 5, 7, 8, 10, 12]
        case .harmonicMinor: single = [0, 2, 3, 5, 7, 8, 11, 12]
        case .melodicMinor: single = [0, 2, 3, 5, 7, 9, 11, 12]
        case .chromatic: single = Array(0...12)
        }
        return expanded(single, octaves: octaves)
    }

    private static func descendingOffsets(type: ScaleType, octaves: ScaleOctaves) -> [Int] {
        if type == .melodicMinor {
            return Array(expanded([0, 2, 3, 5, 7, 8, 10, 12], octaves: octaves).reversed())
        }
        return Array(ascendingOffsets(type: type, octaves: octaves).reversed())
    }

    private static func expanded(_ offsets: [Int], octaves: ScaleOctaves) -> [Int] {
        (0..<octaves.rawValue).flatMap { octave in offsets.dropLast().map { $0 + (octave * 12) } } + [12 * octaves.rawValue]
    }

    private static func name(for root: ScaleRoot, type: ScaleType, offset: Int, ascending: Bool) -> String {
        guard type != .chromatic else { return chromaticName(for: root.pitchClass + offset, preferSharps: root == .fs || root == .b) }
        let degreeOffsets: [Int]
        switch type {
        case .major: degreeOffsets = [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: degreeOffsets = [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: degreeOffsets = [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor: degreeOffsets = ascending ? [0, 2, 3, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10]
        case .chromatic: degreeOffsets = []
        }
        let pitchInOctave = ((offset % 12) + 12) % 12
        let degree = degreeOffsets.firstIndex(of: pitchInOctave) ?? 0
        let letter = ["C", "D", "E", "F", "G", "A", "B"][(rootLetterIndex(root) + degree) % 7]
        let target = (root.pitchClass + offset) % 12
        let natural = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][letter]!
        let delta = ((target - natural + 18) % 12) - 6
        let accidental = switch delta { case -2: "♭♭"; case -1: "♭"; case 0: ""; case 1: "♯"; case 2: "♯♯"; default: "" }
        return letter + accidental
    }

    private static func rootLetterIndex(_ root: ScaleRoot) -> Int {
        switch root {
        case .c: return 0
        case .db, .d: return 1
        case .eb, .e: return 2
        case .f, .fs: return 3
        case .g: return 4
        case .ab, .a: return 5
        case .bb, .b: return 6
        }
    }

    private static func chromaticName(for midi: Int, preferSharps: Bool) -> String {
        let pitchClass = ((midi % 12) + 12) % 12
        let flats = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
        let sharps = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return (preferSharps ? sharps : flats)[pitchClass]
    }
}

public enum BrassTuneCore {
    public static let minimumRecordingConfidence = 0.95
    public static let silenceRMSThreshold = 0.01

    public static func frequencyToMidi(_ frequencyHz: Double, referencePitchHz: Double = 440.0) -> Double {
        69.0 + 12.0 * log2(frequencyHz / referencePitchHz)
    }

    public static func midiToFrequency(_ midi: Double, referencePitchHz: Double = 440.0) -> Double {
        referencePitchHz * pow(2.0, (midi - 69.0) / 12.0)
    }

    public static func centsDeviation(frequencyHz: Double, nearestMidi: Int, referencePitchHz: Double = 440.0) -> Double {
        1200.0 * log2(frequencyHz / midiToFrequency(Double(nearestMidi), referencePitchHz: referencePitchHz))
    }

    public static func transposeConcertToWritten(_ concertMidi: Int, semitones: Int) -> Int { concertMidi + semitones }
    public static func transposeWrittenToConcert(_ writtenMidi: Int, semitones: Int) -> Int { writtenMidi - semitones }
    public static func instrumentProfile(for id: String) -> InstrumentProfile? { InstrumentProfiles.profile(for: id) }

    public static func tuningStatus(cents: Double?, confidence: Double, rms: Double) -> TuningStatus {
        guard rms >= silenceRMSThreshold else { return .silence }
        guard let cents else { return .noLock }
        guard confidence >= minimumRecordingConfidence else { return .unstable }
        if cents < -5 { return .flat }
        if cents > 5 { return .sharp }
        return .inTune
    }
}
