import Foundation
import BrassTuneCore

enum NativeTestFixtures {
    static var areEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("UITEST_DEMO") || arguments.contains("UITEST_FIXTURES")
    }
}

func instrumentDisplayName(_ id: String) -> String {
    guard let profile = InstrumentProfiles.profile(for: id) else {
        return NativeLocalization.string("Unsupported instrument")
    }
    // Core profiles deliberately keep stable English identifiers for shared
    // pitch-domain fixtures. Native UI must resolve those identifiers through
    // the String Catalog instead of exposing the fixture copy to users.
    let localizationKey: String
    switch profile.id {
    case "trumpet": localizationKey = "Trumpet in B♭"
    case "cornet": localizationKey = "Cornet in B♭"
    case "flugelhorn": localizationKey = "Flugelhorn in B♭"
    case "c-trumpet": localizationKey = "Trumpet in C"
    case "horn": localizationKey = "French Horn in F"
    case "trombone": localizationKey = "Trombone"
    case "euphonium": localizationKey = "Euphonium (concert)"
    case "baritone-concert": localizationKey = "Baritone (concert)"
    case "baritone": localizationKey = "Baritone in B♭ (treble)"
    case "euphonium-treble": localizationKey = "Euphonium in B♭ (treble)"
    case "tuba": localizationKey = "Tuba"
    default: return NativeLocalization.string("Unsupported instrument")
    }
    return NativeLocalization.string(localizationKey)
}

struct InstrumentAcousticRange: Equatable {
    let minimumHz: Double
    let maximumHz: Double

    func contains(_ frequencyHz: Double) -> Bool {
        frequencyHz.isFinite && frequencyHz >= minimumHz && frequencyHz <= maximumHz
    }

    static func forInstrument(_ instrumentId: String) -> InstrumentAcousticRange {
        guard let profile = InstrumentProfiles.profile(for: instrumentId) else {
            // An empty interval makes unknown persisted IDs fail closed before pitch or recording state is authorized.
            return InstrumentAcousticRange(minimumHz: .infinity, maximumHz: -.infinity)
        }
        let detectorRange = profile.detectorFrequencyRange
        return InstrumentAcousticRange(
            minimumHz: detectorRange.minimumHz,
            maximumHz: detectorRange.maximumHz
        )
    }
}

enum AppEnvironment: String, CaseIterable, Identifiable {
    case local
    case staging
    case production

    var id: String { rawValue }
}

struct AppConfig: Equatable {
    static let approvedProductionAPIOrigin = URL(string: "https://brasstune-u8qj.onrender.com")!
    var environment: AppEnvironment
    var apiBaseURL: URL
    var supabaseURL: URL?
    var supabasePublishableKey: String?

    var hasUsableAPIConfiguration: Bool {
        guard apiBaseURL.user == nil,
              apiBaseURL.password == nil,
              apiBaseURL.query == nil,
              apiBaseURL.fragment == nil,
              let host = apiBaseURL.host?.lowercased(),
              !host.isEmpty else { return false }
        switch environment {
        case .local:
            return (apiBaseURL.scheme?.lowercased() == "http" && ["127.0.0.1", "localhost", "::1"].contains(host))
                || apiBaseURL.scheme?.lowercased() == "https"
        case .staging:
            return apiBaseURL.scheme?.lowercased() == "https" && !["127.0.0.1", "localhost", "::1"].contains(host)
        case .production:
            return apiBaseURL == Self.approvedProductionAPIOrigin
        }
    }

    var hasUsableSupabaseAuthConfiguration: Bool {
        guard let supabaseURL,
              supabaseURL.scheme?.lowercased() == "https",
              let host = supabaseURL.host,
              !host.isEmpty,
              supabaseURL.user == nil,
              supabaseURL.password == nil,
              supabaseURL.query == nil,
              supabaseURL.fragment == nil,
              let key = Self.runtimeValue(supabasePublishableKey),
              Self.isPublicClientKey(key) else {
            return false
        }
        if environment == .production, !host.lowercased().hasSuffix(".supabase.co") {
            return false
        }
        return true
    }

    var hasUsableAccountConfiguration: Bool {
        hasUsableAPIConfiguration && hasUsableSupabaseAuthConfiguration
    }

    static func fromProcessEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any]? = nil
    ) -> AppConfig {
        let info = bundleInfo ?? Bundle.main.infoDictionary ?? [:]
        let selectedEnvironment = environment["BRASSTUNE_ENV"].flatMap(AppEnvironment.init(rawValue:))
            ?? (info["BRASSTUNE_ENV"] as? String).flatMap(AppEnvironment.init(rawValue:))
            ?? .local
        let apiBaseURLValue = runtimeValue(environment["BRASSTUNE_API_BASE_URL"])
            ?? runtimeValue(info["BRASSTUNE_API_BASE_URL"] as? String)
        let defaultAPIURL = selectedEnvironment == .production ? approvedProductionAPIOrigin : local.apiBaseURL
        let apiBaseURL = apiBaseURLValue.flatMap(URL.init(string:)) ?? defaultAPIURL
        let supabaseURLValue = runtimeValue(environment["BRASSTUNE_SUPABASE_URL"])
            ?? runtimeValue(info["BRASSTUNE_SUPABASE_URL"] as? String)
        let publishableKey = runtimeValue(environment["BRASSTUNE_SUPABASE_PUBLISHABLE_KEY"])
            ?? runtimeValue(info["BRASSTUNE_SUPABASE_PUBLISHABLE_KEY"] as? String)
        return AppConfig(
            environment: selectedEnvironment,
            apiBaseURL: apiBaseURL,
            supabaseURL: supabaseURLValue.flatMap(URL.init(string:)),
            supabasePublishableKey: publishableKey
        )
    }

    private static func runtimeValue(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$("),
              !value.contains("${") else {
            return nil
        }
        return value
    }

    private static func isPublicClientKey(_ key: String) -> Bool {
        let lowercase = key.lowercased()
        guard !lowercase.hasPrefix("sb_secret_"),
              !lowercase.contains("service_role") else {
            return false
        }
        if lowercase.hasPrefix("sb_publishable_"), key.count > "sb_publishable_".count {
            return true
        }
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count >= 2,
           let payload = decodeBase64URL(String(parts[1])),
           let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let role = (object["role"] as? String)?.lowercased() {
            return role == "anon"
        }
        return false
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalized)
    }

    static let local = AppConfig(
        environment: .local,
        apiBaseURL: URL(string: "http://127.0.0.1:8000")!,
        supabaseURL: nil,
        supabasePublishableKey: nil
    )
}

struct PitchFrame: Codable, Equatable, Identifiable, Sendable {
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
        guard let profile = InstrumentProfiles.profile(for: instrumentId) else {
            return PitchFrame(
                timestampMs: index * 110, frequencyHz: nil, confidence: 0, rms: 0,
                centsDeviation: nil, tuningStatus: .noLock, writtenNoteName: nil,
                writtenOctave: nil, isValidForRecording: false
            )
        }
        let concertMidi = fixtureConcertMidi(for: profile)
        let writtenMidi = BrassTuneCore.transposeConcertToWritten(concertMidi, semitones: profile.transpositionSemitones)
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
        let profile = InstrumentProfiles.profile(for: instrumentId)
        let acceptedFrequency = profile.flatMap { profile in
            frequencyHz.flatMap { InstrumentAcousticRange.forInstrument(profile.id).contains($0) ? $0 : nil }
        }
        let concertMidiFloat = acceptedFrequency.map { BrassTuneCore.frequencyToMidi($0, referencePitchHz: referencePitchHz) }
        let concertMidi = concertMidiFloat.map { Int($0.rounded()) }
        let cents = acceptedFrequency.flatMap { frequency -> Double? in
            guard let concertMidi else { return nil }
            return BrassTuneCore.centsDeviation(frequencyHz: frequency, nearestMidi: concertMidi, referencePitchHz: referencePitchHz)
        }
        let writtenMidi = concertMidi.flatMap { concertMidi in
            profile.map { BrassTuneCore.transposeConcertToWritten(concertMidi, semitones: $0.transpositionSemitones) }
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

    private static func fixtureConcertMidi(for profile: InstrumentProfile) -> Int {
        let preferred = profile.practicalSoundingRange.minimum + (profile.practicalSoundingRange.maximum - profile.practicalSoundingRange.minimum) / 2
        return preferred
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
        case .quarter: return NativeLocalization.string("Quarter")
        case .eighth: return NativeLocalization.string("Eighth")
        case .triplet: return NativeLocalization.string("Triplet")
        case .sixteenth: return NativeLocalization.string("Sixteenth")
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
    /// The downbeat is emphasized when enabled. Kept in the preset so a
    /// saved compound-meter setup returns exactly as it was practiced.
    var accentFirstBeat: Bool = true
    /// Number of audible preparation beats before a started metronome enters
    /// its regular measure. Zero intentionally means no count-in.
    var countInBeats: Int = 0

    var meterLabel: String {
        "\(beatsPerMeasure)/\(beatUnit)"
    }

    var intervalSeconds: TimeInterval {
        60.0 / Double(max(20, min(300, bpm))) / Double(subdivision.ticksPerBeat)
    }

    mutating func validate() {
        bpm = min(300, max(20, bpm))
        beatsPerMeasure = min(12, max(1, beatsPerMeasure))
        beatUnit = [2, 4, 8, 16].contains(beatUnit) ? beatUnit : 4
        countInBeats = min(16, max(0, countInBeats))
        volume = min(1, max(0, volume))
        if visualOnly || volume == 0 { muted = true }
    }

    private enum CodingKeys: String, CodingKey {
        case bpm, beatsPerMeasure, beatUnit, subdivision, muted, visualOnly, hapticsEnabled, volume, accentFirstBeat, countInBeats
    }

    init(
        bpm: Int = 92,
        beatsPerMeasure: Int = 4,
        beatUnit: Int = 4,
        subdivision: MetronomeSubdivision = .quarter,
        muted: Bool = false,
        visualOnly: Bool = false,
        hapticsEnabled: Bool = false,
        volume: Double = 0.6,
        accentFirstBeat: Bool = true,
        countInBeats: Int = 0
    ) {
        self.bpm = bpm
        self.beatsPerMeasure = beatsPerMeasure
        self.beatUnit = beatUnit
        self.subdivision = subdivision
        self.muted = muted
        self.visualOnly = visualOnly
        self.hapticsEnabled = hapticsEnabled
        self.volume = volume
        self.accentFirstBeat = accentFirstBeat
        self.countInBeats = countInBeats
        validate()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bpm: try container.decodeIfPresent(Int.self, forKey: .bpm) ?? 92,
            beatsPerMeasure: try container.decodeIfPresent(Int.self, forKey: .beatsPerMeasure) ?? 4,
            beatUnit: try container.decodeIfPresent(Int.self, forKey: .beatUnit) ?? 4,
            subdivision: try container.decodeIfPresent(MetronomeSubdivision.self, forKey: .subdivision) ?? .quarter,
            muted: try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false,
            visualOnly: try container.decodeIfPresent(Bool.self, forKey: .visualOnly) ?? false,
            hapticsEnabled: try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? false,
            volume: try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.6,
            accentFirstBeat: try container.decodeIfPresent(Bool.self, forKey: .accentFirstBeat) ?? true,
            countInBeats: try container.decodeIfPresent(Int.self, forKey: .countInBeats) ?? 0
        )
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
        case .filesPDF: return NativeLocalization.string("Files PDF")
        case .filesImage: return NativeLocalization.string("Files image")
        case .photos: return NativeLocalization.string("Photos")
        case .sample: return NativeLocalization.string("Sample")
        }
    }

    static var allCases: [ScoreSourceKind] {
        NativeTestFixtures.areEnabled ? [.filesPDF, .filesImage, .photos, .sample] : [.filesPDF, .filesImage, .photos]
    }
}

enum PracticeSessionSource: String, Codable, CaseIterable, Identifiable {
    case live
    case sample
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return NativeLocalization.string("Live mic")
        case .sample: return NativeLocalization.string("UI test fixture")
        case .manual: return NativeLocalization.string("Timed visual practice")
        }
    }

    var sessionTitle: String {
        switch self {
        case .live: return NativeLocalization.string("Recording")
        case .sample: return NativeLocalization.string("Test recording")
        case .manual: return NativeLocalization.string("Visual scale practice")
        }
    }

    var exportLabel: String {
        switch self {
        case .live: return NativeLocalization.string("live microphone")
        case .sample: return NativeLocalization.string("UI test fixture")
        case .manual: return NativeLocalization.string("timed visual practice")
        }
    }

    static var allCases: [PracticeSessionSource] {
        NativeTestFixtures.areEnabled ? [.live, .sample] : [.live]
    }
}

/// Describes what was actually practiced. This deliberately stays separate
/// from `source`: a real microphone is a source, while a warm-up or plan is
/// an activity that must not be represented as a recording.
enum PracticeSessionActivity: String, Codable, CaseIterable, Identifiable {
    case tuning
    case playAlong
    case guidedWarmup
    case scalePractice
    case visualScalePractice
    case practicePlan

    var id: String { rawValue }

    var contributesPitchMetrics: Bool {
        switch self {
        case .tuning, .playAlong, .scalePractice: return true
        case .guidedWarmup, .visualScalePractice, .practicePlan: return false
        }
    }

    var isRecordingActivity: Bool {
        contributesPitchMetrics
    }
}

enum PracticeSessionCompletion: String, Codable, CaseIterable {
    case completed
    case interrupted
    case discarded
}

enum PlayAlongExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case major
    case naturalMinor
    case harmonicMinor
    case melodicMinor
    case chromatic
    case practicePattern

    var id: String { rawValue }

    var title: String {
        switch self {
        case .major: return NativeLocalization.string("Major scales")
        case .naturalMinor: return NativeLocalization.string("Natural minor scales")
        case .harmonicMinor: return NativeLocalization.string("Harmonic minor scales")
        case .melodicMinor: return NativeLocalization.string("Melodic minor scales")
        case .chromatic: return NativeLocalization.string("Chromatic scales")
        case .practicePattern: return NativeLocalization.string("Other exercises")
        }
    }
}

struct PlayAlongExercise: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let difficulty: String
    let category: PlayAlongExerciseCategory
    let writtenNotes: [String]
    /// Exact written targets for generated material.  Generic/custom exercises
    /// intentionally leave this absent and continue to grade pitch class only.
    let writtenMIDIs: [Int]?

    init(
        id: String,
        title: String,
        detail: String,
        difficulty: String,
        category: PlayAlongExerciseCategory,
        writtenNotes: [String],
        writtenMIDIs: [Int]? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.difficulty = difficulty
        self.category = category
        self.writtenNotes = writtenNotes
        self.writtenMIDIs = writtenMIDIs?.count == writtenNotes.count ? writtenMIDIs : nil
    }

    var isBuiltIn: Bool {
        Self.library.contains { $0.id == id }
    }

    var displayTitle: String {
        isBuiltIn ? NativeLocalization.string(title) : title
    }

    var displayDetail: String {
        isBuiltIn ? NativeLocalization.string(detail) : detail
    }

    var displayDifficulty: String {
        isBuiltIn ? NativeLocalization.string(difficulty) : difficulty
    }

    /// Pair the generated written spelling with its register wherever a scale
    /// is presented. This prevents an octave-free label from being mistaken
    /// for a pitch-class-only target.
    var writtenTargets: [String] {
        guard let writtenMIDIs, writtenMIDIs.count == writtenNotes.count else { return writtenNotes }
        return zip(writtenNotes, writtenMIDIs).map { note, midi in
            "\(note)\((midi / 12) - 1)"
        }
    }

    static let library: [PlayAlongExercise] = ScaleType.allCases.flatMap { type in
        ScaleRoot.allCases.enumerated().compactMap { index, root in
            let legacyID: String
            switch type {
            case .major: legacyID = ["cmaj", "dbmaj", "dmaj", "ebmaj", "emaj", "fmaj", "fsmaj", "gmaj", "abmaj", "amaj", "bbmaj", "bmaj"][index]
            case .naturalMinor: legacyID = ["cmin", "csmin", "dmin", "ebmin", "emin", "fmin", "fsmin", "gmin", "gsmin", "amin", "bbmin", "bmin"][index]
            case .harmonicMinor: legacyID = ["chmin", "dbhmin", "dhmin", "ebhmin", "ehmin", "fhmin", "fshmin", "ghmin", "abhmin", "ahmin", "bbhmin", "bhmin"][index]
            case .melodicMinor: legacyID = ["cmmin", "dbmmin", "dmmin", "ebmmin", "emmin", "fmmin", "fsmmin", "gmmin", "abmmin", "ammin", "bbmmin", "bmmin"][index]
            case .chromatic: legacyID = index == 0 ? "chromatic" : ["dbchromatic", "dchromatic", "ebchromatic", "echromatic", "fchromatic", "fschromatic", "gchromatic", "abchromatic", "achromatic", "bbchromatic", "bchromatic"][index - 1]
            }
            return scaleExercise(root: root, type: type, id: legacyID)
        }
    } + [
        PlayAlongExercise(id: "arpeggio", title: "C major arpeggio", detail: "C · E · G · C", difficulty: "Beginner", category: .practicePattern, writtenNotes: ["C", "E", "G", "C"]),
        PlayAlongExercise(id: "longtones", title: "Long tones", detail: "C · G · C — hold each note", difficulty: "Beginner", category: .practicePattern, writtenNotes: ["C", "G", "C"]),
    ]

    /// A Core-backed exercise factory keeps the catalog aligned with scale spelling, direction, and octave behavior.
    static func scaleExercise(
        root: ScaleRoot,
        type: ScaleType,
        direction: ScaleDirection = .ascending,
        octaves: ScaleOctaves = .one,
        profile: InstrumentProfile? = nil,
        id: String
    ) -> PlayAlongExercise? {
        // A three-octave request needs a known practical range. Do not present
        // an unbounded sequence for an unknown profile and later imply that it
        // is playable on the selected instrument.
        guard octaves != .three || profile != nil else { return nil }
        guard let scale = ScaleGenerator.generate(
            root: root,
            type: type,
            octaves: octaves,
            direction: direction,
            profile: profile
        ) else { return nil }
        return PlayAlongExercise(
            id: id,
            title: NativeLocalization.format(
                "%@ %@ scale",
                NativeLocalization.preserve(root.rawValue),
                NativeLocalization.string(type.displayName)
            ),
            detail: NativeLocalization.format(
                "%@, %@",
                NativeLocalization.string(octaves.displayName),
                NativeLocalization.string(direction.displayName)
            ),
            difficulty: type.displayName,
            category: type.category,
            writtenNotes: scale.notes.map(\.writtenName),
            writtenMIDIs: scale.notes.map(\.writtenMIDI)
        )
    }

    /// UI-facing availability check for the scale picker. Unknown instruments
    /// fail closed and insufficient ranges remain unavailable instead of
    /// clipping, reducing octave count, or inventing a practical register.
    static func isScaleAvailable(
        root: ScaleRoot,
        type: ScaleType,
        octaves: ScaleOctaves,
        direction: ScaleDirection,
        instrumentID: String
    ) -> Bool {
        guard let profile = InstrumentProfiles.profile(for: instrumentID) else { return false }
        return ScaleGenerator.generate(
            root: root,
            type: type,
            octaves: octaves,
            direction: direction,
            profile: profile,
            rangePolicy: .adapt
        ) != nil
    }

    static let defaultExercise = library[0]
}

extension ScaleOctaves {
    var displayName: String {
        switch self {
        case .one: return "One octave"
        case .two: return "Two octaves"
        case .three: return "Three octaves"
        }
    }
}

/// Serializable, non-audio context for a completed visual scale. It keeps the
/// exact generated exercise and timing settings available without inventing
/// microphone frames, a recording URL, or pitch metrics.
struct VisualScalePracticeConfiguration: Codable, Equatable {
    let exerciseID: String
    let instrumentID: String
    let root: ScaleRoot
    let type: ScaleType
    let octaves: ScaleOctaves
    let direction: ScaleDirection
    var tempoBPM: Int
    var loopCount: Int

    init(
        exerciseID: String,
        instrumentID: String,
        root: ScaleRoot,
        type: ScaleType,
        octaves: ScaleOctaves,
        direction: ScaleDirection,
        tempoBPM: Int,
        loopCount: Int = 0
    ) {
        self.exerciseID = exerciseID
        self.instrumentID = instrumentID
        self.root = root
        self.type = type
        self.octaves = octaves
        self.direction = direction
        self.tempoBPM = min(180, max(40, tempoBPM))
        self.loopCount = max(0, loopCount)
    }
}

struct VisualScalePracticeCompletion: Equatable {
    let activityInstanceID: UUID
    let configuration: VisualScalePracticeConfiguration
    let startedAt: Date
    let completedAt: Date

    init(
        activityInstanceID: UUID = UUID(),
        configuration: VisualScalePracticeConfiguration,
        startedAt: Date,
        completedAt: Date
    ) {
        self.activityInstanceID = activityInstanceID
        self.configuration = configuration
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// Local-only context for a score-led timer. It intentionally records only
/// user-entered score metadata and the selected tempo; score images are never
/// OCR'd and this configuration cannot claim detected notes or audio capture.
struct ScoreGuidedPracticeConfiguration: Codable, Equatable {
    let scoreID: ImportedScore.ID
    let instrumentID: String
    let pageNumber: Int
    let tempoBPM: Int
    let focusMeasures: String
    let problemPassage: String
    let practiceNotes: String

    init(
        scoreID: ImportedScore.ID,
        instrumentID: String,
        pageNumber: Int,
        tempoBPM: Int,
        focusMeasures: String,
        problemPassage: String,
        practiceNotes: String
    ) {
        self.scoreID = scoreID
        self.instrumentID = instrumentID
        self.pageNumber = max(1, pageNumber)
        self.tempoBPM = min(240, max(30, tempoBPM))
        self.focusMeasures = focusMeasures.trimmingCharacters(in: .whitespacesAndNewlines)
        self.problemPassage = problemPassage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.practiceNotes = practiceNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A started score-guided timer that the UI can hold until the user finishes
/// or exits. The identity makes completion idempotent across view redraws.
struct ScoreGuidedPracticeRun: Equatable {
    let activityInstanceID: UUID
    let configuration: ScoreGuidedPracticeConfiguration
    let startedAt: Date
}

struct ScoreGuidedPracticeCompletion: Equatable {
    let activityInstanceID: UUID
    let configuration: ScoreGuidedPracticeConfiguration
    let startedAt: Date
    let completedAt: Date
    /// Exact elapsed active time supplied by the local timer when available.
    /// `nil` retains compatibility with callers that only have timestamps.
    let activeDurationSeconds: TimeInterval?

    init(
        activityInstanceID: UUID,
        configuration: ScoreGuidedPracticeConfiguration,
        startedAt: Date,
        completedAt: Date,
        activeDurationSeconds: TimeInterval? = nil
    ) {
        self.activityInstanceID = activityInstanceID
        self.configuration = configuration
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.activeDurationSeconds = activeDurationSeconds.map { max(0, $0) }
    }
}

/// Pure elapsed-time state for manual score practice. Time is accumulated only
/// while running, so pausing for an interruption or background transition does
/// not inflate the finished practice duration.
struct ScoreGuidedPracticeTimerState: Equatable {
    private(set) var accumulatedActiveSeconds: TimeInterval = 0
    private(set) var activeSegmentStartedAt: Date?

    var isRunning: Bool { activeSegmentStartedAt != nil }

    mutating func start(at date: Date) {
        guard activeSegmentStartedAt == nil else { return }
        activeSegmentStartedAt = date
    }

    mutating func pause(at date: Date) {
        guard let activeSegmentStartedAt else { return }
        accumulatedActiveSeconds += max(0, date.timeIntervalSince(activeSegmentStartedAt))
        self.activeSegmentStartedAt = nil
    }

    mutating func resume(at date: Date) {
        start(at: date)
    }

    mutating func finish(at date: Date) -> TimeInterval {
        pause(at: date)
        return accumulatedActiveSeconds
    }

    func activeDuration(at date: Date) -> TimeInterval {
        guard let activeSegmentStartedAt else { return accumulatedActiveSeconds }
        return accumulatedActiveSeconds + max(0, date.timeIntervalSince(activeSegmentStartedAt))
    }
}

extension ScaleType {
    var category: PlayAlongExerciseCategory {
        switch self {
        case .major: return .major
        case .naturalMinor: return .naturalMinor
        case .harmonicMinor: return .harmonicMinor
        case .melodicMinor: return .melodicMinor
        case .chromatic: return .chromatic
        }
    }

    var displayName: String {
        switch self {
        case .major: return "Major"
        case .naturalMinor: return "Natural minor"
        case .harmonicMinor: return "Harmonic minor"
        case .melodicMinor: return "Melodic minor"
        case .chromatic: return "Chromatic"
        }
    }
}

private extension ScaleDirection {
    var displayName: String {
        switch self {
        case .ascending: return "ascending"
        case .descending: return "descending"
        case .both: return "ascending and descending"
        }
    }
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
        case ...15: self = .close
        default: self = .off
        }
    }

    var isCentered: Bool { self == .excellent }
    var isAccepted: Bool { self == .excellent || self == .close }

    var title: String {
        switch self {
        case .excellent: return NativeLocalization.string("Great")
        case .good: return NativeLocalization.string("Good")
        case .close: return NativeLocalization.string("Close")
        case .off: return NativeLocalization.string("Try again")
        case .missed: return NativeLocalization.string("Skipped")
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
        inTuneNotes = played.filter { $0.rating.isCentered }.count
        inTunePercentage = expectedNoteCount > 0
            ? Int((Double(inTuneNotes) / Double(expectedNoteCount) * 100).rounded())
            : 0
        if played.isEmpty {
            averageAbsoluteCents = nil
        } else {
            let average = played.compactMap(\.medianCents).map(abs).reduce(0, +) / Double(played.count)
            averageAbsoluteCents = (average * 10).rounded() / 10
        }
        stars = Self.starRating(inTunePercentage: Double(inTunePercentage))
    }

    static func starRating(inTunePercentage: Double?) -> Int {
        guard let inTunePercentage, inTunePercentage.isFinite else { return 0 }
        switch inTunePercentage {
        case 95...: return 3
        case 85...: return 2
        case 70...: return 1
        default: return 0
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
    let writtenMIDIs: [Int]?
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
    private var previousFrameTimestampMs: Int?
    private var previousFrameMatched = false
    private var confirmedHoldDurationMs = 0
    private var centsSamples: [TimedCentsSample] = []

    init(
        writtenNotes: [String],
        writtenMIDIs: [Int]? = nil,
        holdDurationMs: Int = 2_000,
        minimumConfidence: Double = 0.95,
        minimumSamples: Int = 5,
        attackTrimMs: Int = 120,
        maximumDropoutMs: Int = 250
    ) {
        self.writtenNotes = writtenNotes
        self.writtenMIDIs = writtenMIDIs?.count == writtenNotes.count ? writtenMIDIs : nil
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

    private var currentWrittenMIDI: Int? {
        guard !isComplete else { return nil }
        return writtenMIDIs?[currentNoteIndex]
    }

    var heldFraction: Double {
        guard firstMatchTimestampMs != nil else { return 0 }
        return min(1, max(0, Double(confirmedHoldDurationMs) / Double(holdDurationMs)))
    }

    mutating func feed(_ frame: PitchFrame) {
        guard !isComplete else { return }
        guard let target = currentNoteName else { return }
        let confident = frame.confidence >= minimumConfidence
            && frame.frequencyHz != nil
            && frame.isValidForRecording
            && [.flat, .inTune, .sharp].contains(frame.tuningStatus)
        detectedNoteName = confident ? frame.writtenNoteName : nil
        detectedCents = confident ? frame.centsDeviation : nil
        let matchesPitchClass = PracticePitchMath.matchesPitchClass(frame.writtenNoteName, target)
        let matchesOctave = currentWrittenMIDI.map { expectedMIDI in
            frame.writtenOctave == (expectedMIDI / 12) - 1
        } ?? true
        let matchesTarget = confident && matchesPitchClass && matchesOctave && frame.centsDeviation != nil

        if matchesTarget, let cents = frame.centsDeviation {
            if let lastMatchTimestampMs,
               frame.timestampMs - lastMatchTimestampMs > maximumDropoutMs {
                resetCurrentHold()
            }
            if firstMatchTimestampMs == nil {
                firstMatchTimestampMs = frame.timestampMs
            }
            if previousFrameMatched, let previousFrameTimestampMs {
                confirmedHoldDurationMs += max(0, frame.timestampMs - previousFrameTimestampMs)
            }
            lastMatchTimestampMs = frame.timestampMs
            previousFrameTimestampMs = frame.timestampMs
            previousFrameMatched = true
            centsSamples.append(TimedCentsSample(timestampMs: frame.timestampMs, cents: cents))
            if confirmedHoldDurationMs >= holdDurationMs,
               centsSamples.count >= minimumSamples {
                let scoredCents = scoredMedianCents()
                if PlayAlongNoteRating(cents: scoredCents).isAccepted {
                    finalizeCurrentNote(wasPlayed: true, scoredCents: scoredCents)
                } else {
                    // Reaching the time gate is not enough: an out-of-tune
                    // median must retry the same target instead of advancing.
                    resetCurrentHold()
                }
            }
        } else if confident,
                  let detected = frame.writtenNoteName,
                  (!PracticePitchMath.matchesPitchClass(detected, target) || !matchesOctave) {
            // A confidently played different note restarts this target. Brief
            // silence and low-confidence dropouts do not erase a good hold.
            resetCurrentHold()
        } else {
            // Silence and low-confidence frames pause confirmed hold time. They
            // preserve progress inside the grace window but never fill the ring.
            previousFrameTimestampMs = frame.timestampMs
            previousFrameMatched = false
            if let lastMatchTimestampMs,
               frame.timestampMs - lastMatchTimestampMs > maximumDropoutMs {
                resetCurrentHold()
            }
        }
    }

    mutating func skipCurrentNote() {
        guard !isComplete else { return }
        finalizeCurrentNote(wasPlayed: false, scoredCents: nil)
    }

    private func scoredMedianCents() -> Double? {
        guard let firstMatchTimestampMs, !centsSamples.isEmpty else { return nil }
        let sustained = centsSamples.filter { $0.timestampMs - firstMatchTimestampMs >= attackTrimMs }
        let minimumTrustedSustainSamples = min(minimumSamples, 3)
        let source = sustained.count >= minimumTrustedSustainSamples ? sustained : centsSamples
        return Self.median(source.map(\.cents))
    }

    private mutating func finalizeCurrentNote(wasPlayed: Bool, scoredCents: Double?) {
        guard let target = currentNoteName else { return }
        let roundedCents = wasPlayed ? scoredCents.map { ($0 * 10).rounded() / 10 } : nil
        noteGrades.append(
            PlayAlongNoteGrade(
                writtenNoteName: target,
                medianCents: roundedCents,
                sampleCount: centsSamples.count
            )
        )
        currentNoteIndex += 1
        resetCurrentHold()
        if isComplete {
            detectedNoteName = nil
            detectedCents = nil
        }
    }

    private mutating func resetCurrentHold() {
        firstMatchTimestampMs = nil
        lastMatchTimestampMs = nil
        previousFrameTimestampMs = nil
        previousFrameMatched = false
        confirmedHoldDurationMs = 0
        centsSamples.removeAll(keepingCapacity: true)
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
        holdDurationMs: Int = 2_000,
        minimumConfidence: Double = 0.95,
        minimumSamples: Int = 5,
        attackTrimMs: Int = 120
    ) {
        self.exercise = exercise
        self.startedAt = startedAt
        grader = PlayAlongGrader(
            writtenNotes: exercise.writtenNotes,
            writtenMIDIs: exercise.writtenMIDIs,
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
        case .original: return NativeLocalization.string("Original")
        case .grayscale: return NativeLocalization.string("Grayscale")
        case .contrast: return NativeLocalization.string("Contrast")
        case .highContrast: return NativeLocalization.string("High contrast")
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
        case .fullPage: return NativeLocalization.string("Full page")
        case .trimMargins: return NativeLocalization.string("Trim margins")
        case .upperHalf: return NativeLocalization.string("Upper half")
        case .lowerHalf: return NativeLocalization.string("Lower half")
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
        NativeLocalization.pageCountLabel(pages.count)
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

struct NativeNoteEvent: Equatable {
    let writtenNote: String
    let writtenOctave: Int
    let startedAtMs: Int
    let endedAtMs: Int
    let durationMs: Int
    let sampleCount: Int
    let averageSignedCents: Double
    let averageAbsoluteCents: Double
    let medianCents: Double
    let standardDeviationCents: Double
    let minimumCents: Double
    let maximumCents: Double
    let inTunePercentage: Double
    let stabilityScore: Double
}

struct NativeNoteStatistics: Equatable {
    let writtenNote: String
    let writtenOctave: Int
    let noteLabel: String
    let averageSignedCents: Double
    let averageAbsoluteCents: Double
    let medianCents: Double
    let standardDeviationCents: Double
    let inTunePercentage: Double
    let durationMs: Double
    let sampleCount: Int
    let eventCount: Int
    let stabilityScore: Double
    let trend: String
    let severity: String
    let problemSeverity: Double

    var displayTrend: String { NativeLocalization.string(trend) }
    var displaySeverity: String { NativeLocalization.string(severity) }
}

struct NativePracticeRecommendation: Equatable {
    let category: String
    let relatedNote: String

    var displayCategory: String { NativeLocalization.string(category) }
}

enum NativePitchAnalytics {
    static let maximumMergeGapMs = 340
    static let minimumEventDurationMs = 120
    static let centeredCentsLimit = 5.0

    static func segmentNoteEvents(
        frames: [PitchFrame],
        maximumMergeGapMs: Int = maximumMergeGapMs,
        minimumDurationMs: Int = minimumEventDurationMs
    ) -> [NativeNoteEvent] {
        let ordered = frames.sorted { $0.timestampMs < $1.timestampMs }
        var events: [NativeNoteEvent] = []
        var current: [PitchFrame] = []
        var currentLabel: String?
        var lastValidTimestamp: Int?

        func label(for frame: PitchFrame) -> String? {
            guard let note = frame.writtenNoteName, let octave = frame.writtenOctave else { return nil }
            return "\(note)\(octave)"
        }

        func event(from frames: [PitchFrame]) -> NativeNoteEvent? {
            let valid = frames.filter { $0.isValidForRecording && $0.centsDeviation != nil }
            guard let first = valid.first,
                  let last = valid.last,
                  let note = first.writtenNoteName,
                  let octave = first.writtenOctave else { return nil }
            let cents = valid.compactMap(\.centsDeviation)
            let gaps = zip(valid.dropFirst(), valid).map { current, previous in
                current.timestampMs - previous.timestampMs
            }
            let inferredTail = gaps.isEmpty ? 0 : max(60, min(Int(median(gaps.map(Double.init))), 180))
            let duration = max(0, last.timestampMs - first.timestampMs) + inferredTail
            let mean = average(cents)
            let deviation = populationStandardDeviation(cents)
            let inTuneCount = valid.filter { $0.tuningStatus == .inTune }.count
            return NativeNoteEvent(
                writtenNote: note,
                writtenOctave: octave,
                startedAtMs: first.timestampMs,
                endedAtMs: last.timestampMs,
                durationMs: duration,
                sampleCount: valid.count,
                averageSignedCents: mean,
                averageAbsoluteCents: average(cents.map(abs)),
                medianCents: median(cents),
                standardDeviationCents: deviation,
                minimumCents: cents.min() ?? 0,
                maximumCents: cents.max() ?? 0,
                inTunePercentage: Double(inTuneCount) / Double(valid.count) * 100,
                stabilityScore: max(0, min(100, 100 - deviation * 5))
            )
        }

        func flush() {
            guard let value = event(from: current), value.durationMs >= minimumDurationMs else {
                current.removeAll(keepingCapacity: true)
                return
            }
            events.append(value)
            current.removeAll(keepingCapacity: true)
        }

        for frame in ordered {
            let valid = frame.isValidForRecording && frame.centsDeviation != nil && label(for: frame) != nil
            guard valid else {
                if !current.isEmpty,
                   let lastValidTimestamp,
                   frame.timestampMs - lastValidTimestamp > maximumMergeGapMs {
                    flush()
                    currentLabel = nil
                }
                continue
            }
            let frameLabel = label(for: frame)
            if current.isEmpty {
                current = [frame]
                currentLabel = frameLabel
                lastValidTimestamp = frame.timestampMs
                continue
            }
            let gap = frame.timestampMs - (lastValidTimestamp ?? frame.timestampMs)
            if frameLabel != currentLabel || gap > maximumMergeGapMs {
                flush()
            }
            currentLabel = frameLabel
            current.append(frame)
            lastValidTimestamp = frame.timestampMs
        }
        flush()
        return events
    }

    static func calculateNoteStatistics(events: [NativeNoteEvent]) -> [NativeNoteStatistics] {
        Dictionary(grouping: events) { "\($0.writtenNote)\($0.writtenOctave)" }
            .values
            .compactMap { items in
                guard let first = items.first else { return nil }
                let totalDuration = items.reduce(0.0) { $0 + max(0, Double($1.durationMs)) }
                let denominator = totalDuration > 0 ? totalDuration : Double(items.count)
                func weight(_ event: NativeNoteEvent) -> Double {
                    totalDuration > 0 ? max(0, Double(event.durationMs)) : 1
                }
                let averageSigned = items.reduce(0.0) { $0 + $1.averageSignedCents * weight($1) } / denominator
                let averageAbsolute = items.reduce(0.0) { $0 + $1.averageAbsoluteCents * weight($1) } / denominator
                let inTune = items.reduce(0.0) { $0 + $1.inTunePercentage * weight($1) } / denominator
                let stability = items.reduce(0.0) { $0 + $1.stabilityScore * weight($1) } / denominator
                let deviation = items.count > 1
                    ? durationWeightedPopulationStandardDeviation(items, value: \.averageSignedCents)
                    : first.standardDeviationCents
                let trend = classifyTrend(averageSignedCents: averageSigned, standardDeviationCents: deviation, stabilityScore: stability)
                let severity = classifyProblem(averageAbsoluteCents: averageAbsolute, inTunePercentage: inTune)
                let problem = roundedHundredth(averageAbsolute * 2 + deviation + max(0, 80 - inTune) * 0.25)
                return NativeNoteStatistics(
                    writtenNote: first.writtenNote,
                    writtenOctave: first.writtenOctave,
                    noteLabel: "\(first.writtenNote)\(first.writtenOctave)",
                    averageSignedCents: averageSigned,
                    averageAbsoluteCents: averageAbsolute,
                    medianCents: durationWeightedMedian(items, value: \.medianCents),
                    standardDeviationCents: deviation,
                    inTunePercentage: inTune,
                    durationMs: totalDuration,
                    sampleCount: items.reduce(0) { $0 + $1.sampleCount },
                    eventCount: items.count,
                    stabilityScore: stability,
                    trend: trend,
                    severity: severity,
                    problemSeverity: problem
                )
            }
            .sorted { lhs, rhs in
                lhs.writtenOctave == rhs.writtenOctave
                    ? lhs.writtenNote < rhs.writtenNote
                    : lhs.writtenOctave < rhs.writtenOctave
            }
    }

    private static func durationWeightedEntries(
        _ items: [NativeNoteEvent],
        value: KeyPath<NativeNoteEvent, Double>
    ) -> [(value: Double, weight: Double)] {
        let entries = items.map {
            (value: $0[keyPath: value], weight: max(0, Double($0.durationMs)))
        }
        if entries.contains(where: { $0.weight > 0 }) {
            return entries.filter { $0.weight > 0 }
        }
        return entries.map { (value: $0.value, weight: 1) }
    }

    private static func durationWeightedMedian(
        _ items: [NativeNoteEvent],
        value: KeyPath<NativeNoteEvent, Double>
    ) -> Double {
        let entries = durationWeightedEntries(items, value: value)
            .sorted { $0.value < $1.value }
        guard !entries.isEmpty else { return 0 }
        let halfway = entries.reduce(0.0) { $0 + $1.weight } / 2
        var cumulative = 0.0
        for index in entries.indices {
            cumulative += entries[index].weight
            if abs(cumulative - halfway) <= 1e-12 {
                return index + 1 < entries.count
                    ? (entries[index].value + entries[index + 1].value) / 2
                    : entries[index].value
            }
            if cumulative > halfway {
                return entries[index].value
            }
        }
        return entries.last?.value ?? 0
    }

    private static func durationWeightedPopulationStandardDeviation(
        _ items: [NativeNoteEvent],
        value: KeyPath<NativeNoteEvent, Double>
    ) -> Double {
        let entries = durationWeightedEntries(items, value: value)
        guard !entries.isEmpty else { return 0 }
        let totalWeight = entries.reduce(0.0) { $0 + $1.weight }
        let center = entries.reduce(0.0) { $0 + $1.value * $1.weight } / totalWeight
        let variance = entries.reduce(0.0) {
            $0 + $1.weight * pow($1.value - center, 2)
        } / totalWeight
        return sqrt(max(0, variance))
    }

    static func recommendation(for stats: NativeNoteStatistics) -> NativePracticeRecommendation {
        let category: String
        if stats.durationMs / 1_000 < 3 {
            category = "Insufficient data"
        } else if stats.trend == "Unstable" {
            category = "Inconsistent pitch"
        } else if stats.trend == "Mostly sharp" {
            category = "Sharp tendency"
        } else if stats.trend == "Mostly flat" {
            category = "Flat tendency"
        } else if stats.severity == "severe issue" {
            category = "Severe problem note"
        } else {
            category = "Good progress"
        }
        return NativePracticeRecommendation(category: category, relatedNote: stats.noteLabel)
    }

    static func classifyTrend(
        averageSignedCents: Double,
        standardDeviationCents: Double,
        stabilityScore: Double
    ) -> String {
        if standardDeviationCents >= 12 || stabilityScore < 50 { return "Unstable" }
        if averageSignedCents > centeredCentsLimit { return "Mostly sharp" }
        if averageSignedCents < -centeredCentsLimit { return "Mostly flat" }
        return "Centered"
    }

    static func classifyProblem(averageAbsoluteCents: Double, inTunePercentage: Double) -> String {
        if averageAbsoluteCents <= 5, inTunePercentage >= 80 { return "excellent" }
        if averageAbsoluteCents <= 8 { return "good" }
        if averageAbsoluteCents <= 15 { return "moderate issue" }
        return "severe issue"
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private static func populationStandardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let center = average(values)
        return sqrt(average(values.map { pow($0 - center, 2) }))
    }

    private static func roundedHundredth(_ value: Double) -> Double {
        // Problem severity is nonnegative; Swift's default rule is half away
        // from zero, which is the shared two-decimal half-up contract here.
        (value * 100).rounded() / 100
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
    /// A persistent identity for the activity invocation. Session IDs are
    /// retained for compatibility; this gives resumable activity records a
    /// stable identity even if their payload evolves.
    var activityInstanceID: UUID
    var activity: PracticeSessionActivity
    var completion: PracticeSessionCompletion
    /// Present only for a completed visual scale. Its absence preserves the
    /// legacy audio session schema and avoids treating visual practice as pitch capture.
    var visualScaleConfiguration: VisualScalePracticeConfiguration?
    /// Present only for a manually timed score-guided practice session.
    /// It contains no OCR, pitch frames, or recording URL.
    var scoreGuidedPracticeConfiguration: ScoreGuidedPracticeConfiguration?

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
        source: PracticeSessionSource = .live,
        activityInstanceID: UUID? = nil,
        activity: PracticeSessionActivity = .tuning,
        completion: PracticeSessionCompletion = .completed,
        visualScaleConfiguration: VisualScalePracticeConfiguration? = nil,
        scoreGuidedPracticeConfiguration: ScoreGuidedPracticeConfiguration? = nil
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
        self.activityInstanceID = activityInstanceID ?? id
        self.activity = activity
        self.completion = completion
        self.visualScaleConfiguration = visualScaleConfiguration
        self.scoreGuidedPracticeConfiguration = scoreGuidedPracticeConfiguration
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
        case activityInstanceID
        case activity
        case completion
        case visualScaleConfiguration
        case scoreGuidedPracticeConfiguration
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
        // Legacy snapshots only contained microphone-style sessions. Migrate
        // those conservatively as completed tuning activity and use their
        // existing stable session ID for the new activity identity.
        activityInstanceID = try container.decodeIfPresent(UUID.self, forKey: .activityInstanceID) ?? id
        activity = try container.decodeIfPresent(PracticeSessionActivity.self, forKey: .activity) ?? .tuning
        completion = try container.decodeIfPresent(PracticeSessionCompletion.self, forKey: .completion) ?? .completed
        visualScaleConfiguration = try container.decodeIfPresent(VisualScalePracticeConfiguration.self, forKey: .visualScaleConfiguration)
        scoreGuidedPracticeConfiguration = try container.decodeIfPresent(ScoreGuidedPracticeConfiguration.self, forKey: .scoreGuidedPracticeConfiguration)
    }

    var averageAbsCents: Double {
        let values = frames.filter(\.isValidForRecording).compactMap(\.centsDeviation).map { abs($0) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var noteEvents: [NativeNoteEvent] {
        NativePitchAnalytics.segmentNoteEvents(frames: frames)
    }

    var noteStatistics: [NativeNoteStatistics] {
        NativePitchAnalytics.calculateNoteStatistics(events: noteEvents)
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
        guard activity.contributesPitchMetrics else { return 0 }
        return frames.filter(\.isValidForRecording).count
    }

    var isMeaningfulCapturedPractice: Bool {
        activity.contributesPitchMetrics
            && completion == .completed
            && validFrameCount >= 8
            && durationSeconds >= 1.5
    }

    var contributesPracticeTime: Bool {
        completion == .completed && durationSeconds >= 1
    }

    var pitchCoverageLabel: String {
        let noteNames = Set(frames.compactMap { frame -> String? in
            guard let note = frame.writtenNoteName, let octave = frame.writtenOctave else { return nil }
            return "\(note)\(octave)"
        })
        guard !noteNames.isEmpty else { return NativeLocalization.string("No notes detected") }
        return noteNames.sorted().joined(separator: ", ")
    }

    var exportText: String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "BrassTune session export",
            "Session: \(name)",
            "Instrument: \(instrumentDisplayName(instrumentId))",
            "Source: \(source.exportLabel)",
            "Activity: \(activity.rawValue)",
            "Completion: \(completion.rawValue)",
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
    let recordingSessionCount: Int

    var hasSessions: Bool {
        sessionCount > 0
    }

    var hasUsableEvidence: Bool {
        validFrameCount >= 8
    }

    var recommendation: String {
        guard hasSessions else {
            return NativeLocalization.string("Record your first note to see a practice tip.")
        }
        guard hasUsableEvidence else {
            return NativeLocalization.string("Play a little longer so BrassTune can suggest what to practice next.")
        }
        if averageAbsCents > 8 {
            return NativeLocalization.string("Start with drone matching and slow attacks before extending range.")
        }
        if averageInTunePercentage < 75 {
            return NativeLocalization.string("Repeat stable long tones and hold each pitch through the release.")
        }
        return NativeLocalization.string("Intonation is settling. Add a repertoire excerpt after the next long-tone pass.")
    }

    init(sessions: [PracticeSession]) {
        let completedSessions = sessions.filter { $0.completion == .completed }
        // Older snapshots may contain short captures that predate the save
        // gate. Keep their honest observed pitch data readable, while new
        // capture saves must pass `isMeaningfulCapturedPractice`.
        let pitchSessions = completedSessions.filter {
            $0.activity.contributesPitchMetrics && $0.validFrameCount > 0
        }
        sessionCount = completedSessions.count
        recordingSessionCount = pitchSessions.count
        totalFrameCount = pitchSessions.reduce(0) { $0 + $1.frames.count }
        validFrameCount = pitchSessions.reduce(0) { $0 + $1.validFrameCount }
        totalPracticeSeconds = completedSessions.filter(\.contributesPracticeTime).reduce(0) { $0 + $1.durationSeconds }

        let validFrames = pitchSessions.flatMap { $0.frames.filter(\.isValidForRecording) }
        let allCents = validFrames.compactMap(\.centsDeviation)
        if allCents.isEmpty {
            averageAbsCents = 0
            averageInTunePercentage = 0
        } else {
            averageAbsCents = allCents.map { abs($0) }.reduce(0, +) / Double(allCents.count)
            let inTuneCount = allCents.filter { abs($0) <= 5 }.count
            averageInTunePercentage = Double(inTuneCount) / Double(allCents.count) * 100
        }

        let eligibleSessions = pitchSessions
        let bestSession = eligibleSessions.min { lhs, rhs in
            lhs.averageAbsCents < rhs.averageAbsCents
        }
        bestSessionName = bestSession?.name

        let latestSession = completedSessions.max { lhs, rhs in
            lhs.startedAt < rhs.startedAt
        }
        latestSessionName = latestSession?.name
        latestSessionInTunePercentage = latestSession?.inTunePercentage ?? 0
    }
}

/// Stable machine-readable export contract. Keep this intentionally local and
/// versioned so a future importer can distinguish it from an app snapshot.
struct NativePracticeHistoryExport: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let selectedInstrumentID: String
    let referencePitchHz: Double
    let sessions: [PracticeSession]
    let scores: [ImportedScore]

    init(
        exportedAt: Date = Date(),
        selectedInstrumentID: String,
        referencePitchHz: Double,
        sessions: [PracticeSession],
        scores: [ImportedScore]
    ) {
        self.schemaVersion = Self.schemaVersion
        self.exportedAt = exportedAt
        self.selectedInstrumentID = selectedInstrumentID
        self.referencePitchHz = referencePitchHz
        self.sessions = sessions.sorted {
            $0.startedAt == $1.startedAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.startedAt < $1.startedAt
        }
        self.scores = scores.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

struct EnsembleSummary: Codable, Equatable, Identifiable {
    let id: Int
    var name: String
    var directorUserID: Int?
    var joinCode: String?
    var viewerRole: String
    var viewerCanLeave: Bool
    var viewerCanManage: Bool
    var members: [EnsembleMember]? = nil
    var rosterScope: String? = nil
    // Backend timestamps are informational here and may include fractional
    // seconds without a timezone, so retain them without fragile date parsing.
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case directorUserID = "director_user_id"
        case joinCode = "join_code"
        case viewerRole = "viewer_role"
        case viewerCanLeave = "viewer_can_leave"
        case viewerCanManage = "viewer_can_manage"
        case members
        case rosterScope = "roster_scope"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var canLeave: Bool { viewerCanLeave }

    var viewerRoleLabel: String {
        switch viewerRole {
        case "owner": return NativeLocalization.string("Class owner")
        case "assistant": return NativeLocalization.string("Assistant")
        case "admin_observer": return NativeLocalization.string("Administrator observer")
        default: return NativeLocalization.string("Student")
        }
    }
}

struct EnsembleMember: Codable, Equatable, Identifiable {
    let id: Int
    let groupID: Int
    let userID: Int?
    let username: String?
    let displayName: String?
    let instrumentID: String
    let roleInGroup: String
    let status: String
    let isCurrentUser: Bool?
    let activeSince: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case instrumentID = "instrument_id"
        case roleInGroup = "role_in_group"
        case status
        case isCurrentUser = "is_current_user"
        case activeSince = "active_since"
        case createdAt = "created_at"
    }

    var displayLabel: String {
        if isCurrentUser == true { return NativeLocalization.string("You") }
        if let username, !username.isEmpty { return NativeLocalization.preserve("@\(username)") }
        if let displayName, !displayName.isEmpty { return NativeLocalization.preserve(displayName) }
        return NativeLocalization.string("Student")
    }
}

struct EnsembleInvitationList: Codable, Equatable {
    let invitations: [EnsembleInvitation]
}

struct EnsembleInvitation: Codable, Equatable, Identifiable {
    var id: Int { memberID }
    let memberID: Int
    let groupID: Int
    let groupName: String
    let instrumentID: String
    let roleInGroup: String
    let invitedAt: String?
    let directorName: String?

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case groupID = "group_id"
        case groupName = "group_name"
        case instrumentID = "instrument_id"
        case roleInGroup = "role_in_group"
        case invitedAt = "invited_at"
        case directorName = "director_name"
    }
}

struct EnsembleRoster: Codable, Equatable {
    let groupID: Int
    let students: [EnsembleRosterStudent]

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case students
    }
}

struct EnsembleRosterStudent: Codable, Equatable, Identifiable {
    var id: Int { memberID }
    let memberID: Int
    let username: String?
    let displayName: String?
    let instrumentID: String
    let status: String
    let roleInGroup: String
    let sessionsCount: Int
    let practiceMinutes: Double
    let averageAbsCents: Double?
    let inTunePercentage: Double?
    let lastPracticeAt: String?

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case username
        case displayName = "display_name"
        case instrumentID = "instrument_id"
        case status
        case roleInGroup = "role_in_group"
        case sessionsCount = "sessions_count"
        case practiceMinutes = "practice_minutes"
        case averageAbsCents = "average_abs_cents"
        case inTunePercentage = "in_tune_percentage"
        case lastPracticeAt = "last_practice_at"
    }

    var displayLabel: String {
        if let username, !username.isEmpty { return NativeLocalization.preserve("@\(username)") }
        if let displayName, !displayName.isEmpty { return NativeLocalization.preserve(displayName) }
        return NativeLocalization.string("Student")
    }
}

struct EnsembleAggregateSummary: Codable, Equatable {
    let groupID: Int
    let sessionCount: Int
    let sections: [EnsembleSectionSummary]
    let overall: EnsembleSectionSummary

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case sessionCount = "session_count"
        case sections, overall
    }
}

struct EnsembleSectionSummary: Codable, Equatable, Identifiable {
    var id: String { instrumentID }
    let instrumentID: String
    let sessionCount: Int
    let practiceMinutes: Double
    let averageAbsCents: Double

    enum CodingKeys: String, CodingKey {
        case instrumentID = "instrument_id"
        case sessionCount = "session_count"
        case practiceMinutes = "practice_minutes"
        case averageAbsCents = "average_abs_cents"
    }
}

struct EnsembleCreatedResponse: Codable, Equatable {
    let id: Int
    let name: String
    let directorUserID: Int?
    let joinCode: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case directorUserID = "director_user_id"
        case joinCode = "join_code"
    }
}

struct EnsembleJoinCodeResponse: Codable, Equatable {
    let groupID: Int
    let joinCode: String

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case joinCode = "join_code"
    }
}

struct EnsembleInvitationDecisionResponse: Codable, Equatable {
    let accepted: Bool?
    let declined: Bool?
    let groupID: Int?

    enum CodingKeys: String, CodingKey {
        case accepted, declined
        case groupID = "group_id"
    }
}

struct EnsembleMemberRemovalResponse: Codable, Equatable {
    let removed: Bool
}

enum AuthState: Equatable {
    case signedOut
    case guest
    case signedIn(email: String)
    case emailConfirmationRequired(email: String)

    var displayTitle: String {
        switch self {
        case .signedOut: return NativeLocalization.string("Signed out")
        case .guest: return NativeLocalization.string("Guest practice")
        case .signedIn(let email): return NativeLocalization.preserve(email)
        case .emailConfirmationRequired(let email): return NativeLocalization.format("Confirm %@", email)
        }
    }

    var usesRemoteAccount: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

enum GuestAccountUpgradeChoice: Equatable {
    case merge
    case keepSeparate
    case cancel
}

struct GuestAccountUpgradePrompt: Equatable {
    let email: String
    let canMerge: Bool
    let containsFileBackedData: Bool
}

enum UserVisibleError: LocalizedError, Equatable {
    case microphoneDenied
    case networkUnavailable
    case malformedResponse
    case timeout
    case appleSignInCancelled
    case googleSignInCancelled
    case oauthCallbackInvalid
    case oauthProviderUnavailable
    case accountDeletionRequiresConfirmation
    case missingAuthConfiguration
    case authenticationFailed
    case secureStorageUnavailable
    case secureStorageReadFailed
    case secureStorageCorrupt
    case secureStorageSaveFailed
    case secureStorageDeletionFailed
    case emailConfirmationRequired
    case microphoneUnavailable
    case apiRequestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return NativeLocalization.string("Microphone access is off. Allow it in Settings, then try again.")
        case .networkUnavailable: return NativeLocalization.string("The account service is unavailable right now.")
        case .malformedResponse: return NativeLocalization.string("The account service returned an unreadable response.")
        case .timeout: return NativeLocalization.string("The request timed out.")
        case .appleSignInCancelled: return NativeLocalization.string("Apple sign-in was cancelled.")
        case .googleSignInCancelled: return NativeLocalization.string("Google sign-in was cancelled.")
        case .oauthCallbackInvalid: return NativeLocalization.string("The sign-in callback could not be verified. Start sign-in again.")
        case .oauthProviderUnavailable: return NativeLocalization.string("That sign-in provider is not available right now. Try another sign-in method or keep practicing as a guest.")
        case .accountDeletionRequiresConfirmation: return NativeLocalization.string("Please confirm deletion and try again.")
        case .missingAuthConfiguration: return NativeLocalization.string("Account sign-in isn't available right now. You can keep practicing as a guest.")
        case .authenticationFailed: return NativeLocalization.string("BrassTune could not complete authentication.")
        case .secureStorageUnavailable: return NativeLocalization.string("BrassTune couldn't access secure sign-in storage on this device. Restart the app and try again.")
        case .secureStorageReadFailed: return NativeLocalization.string("BrassTune couldn't read your saved sign-in on this device. Your sign-in was left unchanged; restart the app and try again.")
        case .secureStorageCorrupt: return NativeLocalization.string("BrassTune found an unreadable saved sign-in on this device. Your sign-in was left unchanged; restart the app and try again.")
        case .secureStorageSaveFailed: return NativeLocalization.string("BrassTune couldn't securely save your sign-in on this device. Check device storage and try again.")
        case .secureStorageDeletionFailed: return NativeLocalization.string("BrassTune couldn't remove the saved sign-in from this device. Restart the app to retry before using a shared device.")
        case .emailConfirmationRequired: return NativeLocalization.string("Check your email to confirm this BrassTune account before signing in.")
        case .microphoneUnavailable: return NativeLocalization.string("BrassTune could not hear the microphone. Check your audio input and try again.")
        case .apiRequestFailed(_, let message): return message
        }
    }
}

enum NativeReleaseFeatureFlags {
    static let classes = false
    static let offlinePacks = false
    static let cloudBackup = false
}
