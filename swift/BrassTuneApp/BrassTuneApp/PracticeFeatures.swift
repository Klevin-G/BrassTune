import BrassTuneCore
import Foundation

// MARK: - Custom Play-Along exercises

enum CustomExerciseValidationError: LocalizedError, Equatable {
    case missingTitle
    case invalidNote(String)
    case invalidNoteCount

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return NativeLocalization.string("Give the exercise a short name.")
        case .invalidNote(let note):
            return NativeLocalization.format(
                "%@ isn't a supported note name. Use a note such as C, F sharp, or B flat.",
                note
            )
        case .invalidNoteCount:
            return NativeLocalization.string("An exercise needs between 1 and 32 notes.")
        }
    }
}

struct SavedPlayAlongExercise: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var writtenNotes: [String]
    let createdAt: Date

    init(id: UUID = UUID(), title: String, writtenNotes: [String], createdAt: Date = Date()) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw CustomExerciseValidationError.missingTitle }
        guard (1...32).contains(writtenNotes.count) else { throw CustomExerciseValidationError.invalidNoteCount }
        self.id = id
        self.title = String(cleanTitle.prefix(60))
        self.writtenNotes = try writtenNotes.map(Self.normalize(note:))
        self.createdAt = createdAt
    }

    var exercise: PlayAlongExercise {
        PlayAlongExercise(
            id: "custom:\(id.uuidString)",
            title: title,
            detail: NativeLocalization.format(
                "Your custom %@-note exercise",
                String(writtenNotes.count)
            ),
            difficulty: "Custom",
            category: .practicePattern,
            writtenNotes: writtenNotes
        )
    }

    static let noteChoices = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"]

    static func normalize(note: String) throws -> String {
        let value = note
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        let normalized = value.isEmpty
            ? value
            : value.prefix(1).uppercased() + value.dropFirst().lowercased()
        guard noteChoices.contains(normalized) else {
            throw CustomExerciseValidationError.invalidNote(note)
        }
        return normalized
    }
}

// MARK: - Metronome presets and shortcuts

struct MetronomePreset: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var settings: MetronomeSettings
    let createdAt: Date

    init(id: UUID = UUID(), name: String, settings: MetronomeSettings, createdAt: Date = Date()) {
        self.id = id
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        self.settings = settings
        self.createdAt = createdAt
    }
}

enum PracticeShortcutKind: String, Codable, CaseIterable {
    case playAlongExercise
    case guidedWarmup
    case practicePack
    case drone
}

struct PracticeShortcut: Codable, Equatable, Identifiable {
    var id: String { "\(kind.rawValue):\(referenceID)" }
    let kind: PracticeShortcutKind
    let referenceID: String
    var title: String
    var lastStartedAt: Date? = nil

    var displayTitle: String {
        switch kind {
        case .playAlongExercise:
            if let builtIn = PlayAlongExercise.library.first(where: { $0.id == referenceID }) {
                return builtIn.displayTitle
            }
        case .guidedWarmup:
            if referenceID == GuidedWarmupPlan.fiveMinute.id {
                return GuidedWarmupPlan.fiveMinute.displayTitle
            }
        case .practicePack:
            if let builtIn = PracticePack.builtIns.first(where: { $0.id == referenceID }) {
                return builtIn.displayName
            }
        case .drone:
            return NativeLocalization.string(title)
        }
        return title
    }
}

// MARK: - Guided warm-up

struct GuidedWarmupStep: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let instruction: String
    let durationSeconds: TimeInterval
    let exerciseID: String?

    var displayTitle: String { NativeLocalization.string(title) }
    var displayInstruction: String { NativeLocalization.string(instruction) }
}

struct GuidedWarmupPlan: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let steps: [GuidedWarmupStep]

    var displayTitle: String { NativeLocalization.string(title) }

    var durationSeconds: TimeInterval {
        steps.reduce(0) { $0 + $1.durationSeconds }
    }

    static let fiveMinute = GuidedWarmupPlan(
        id: "guided-five-minute",
        title: "Guided five-minute warm-up",
        steps: [
            GuidedWarmupStep(id: "breathe", title: "Easy breaths", instruction: "Breathe in quietly for 4 counts and release for 8. Keep shoulders loose.", durationSeconds: 45, exerciseID: nil),
            GuidedWarmupStep(id: "buzz", title: "Gentle buzz", instruction: "Buzz a comfortable pitch softly. Rest whenever the sound feels forced.", durationSeconds: 45, exerciseID: nil),
            GuidedWarmupStep(id: "long-tone", title: "Centered long tones", instruction: "Play an easy note with a smooth start and steady air.", durationSeconds: 75, exerciseID: "longtones"),
            GuidedWarmupStep(id: "slur", title: "Relaxed slurs", instruction: "Move between two comfortable notes without pressing the mouthpiece.", durationSeconds: 75, exerciseID: "intervals"),
            GuidedWarmupStep(id: "scale", title: "Easy scale", instruction: "Finish with one slow scale at an even volume.", durationSeconds: 60, exerciseID: "cmaj"),
        ]
    )
}

struct GuidedWarmupCheckpoint: Codable, Equatable {
    let planID: String
    let firstStartedAt: Date
    var accumulatedSeconds: TimeInterval
    var runningSince: Date?
    var completed: Bool

    var isRunning: Bool { runningSince != nil && !completed }

    func elapsed(at now: Date, plan: GuidedWarmupPlan = .fiveMinute) -> TimeInterval {
        let live = runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return min(plan.durationSeconds, max(0, accumulatedSeconds + live))
    }

    func currentStep(at now: Date, plan: GuidedWarmupPlan = .fiveMinute) -> GuidedWarmupStep? {
        var remaining = elapsed(at: now, plan: plan)
        for step in plan.steps {
            if remaining < step.durationSeconds { return step }
            remaining -= step.durationSeconds
        }
        return plan.steps.last
    }

    func currentStepIndex(at now: Date, plan: GuidedWarmupPlan = .fiveMinute) -> Int {
        guard let current = currentStep(at: now, plan: plan) else { return 0 }
        return plan.steps.firstIndex(where: { $0.id == current.id }) ?? 0
    }
}

// MARK: - Goals, reflections, and Play-Along evidence

struct WeeklyPracticeGoal: Codable, Equatable {
    var targetMinutes: Int = 60
    var targetSessions: Int = 3

    mutating func validate() {
        targetMinutes = min(1_000, max(5, targetMinutes))
        targetSessions = min(21, max(1, targetSessions))
    }
}

enum PracticeReflectionMood: String, Codable, CaseIterable, Identifiable {
    case easy
    case focused
    case challenging

    var id: String { rawValue }
    var title: String { NativeLocalization.string(rawValue.capitalized) }
}

struct PracticeReflection: Codable, Equatable, Identifiable {
    let id: UUID
    let sessionID: PracticeSession.ID
    var mood: PracticeReflectionMood
    var note: String
    var updatedAt: Date

    init(id: UUID = UUID(), sessionID: PracticeSession.ID, mood: PracticeReflectionMood, note: String, updatedAt: Date = Date()) {
        self.id = id
        self.sessionID = sessionID
        self.mood = mood
        self.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
        self.updatedAt = updatedAt
    }
}

struct WeeklyPracticeProgress: Equatable {
    let minutes: Int
    let sessionCount: Int
    let startOfWeek: Date

    static func calculate(
        sessions: [PracticeSession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyPracticeProgress {
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
        let start = interval?.start ?? calendar.startOfDay(for: now)
        let end = interval?.end ?? now.addingTimeInterval(7 * 86_400)
        let included = sessions.filter { $0.startedAt >= start && $0.startedAt < end }
        let minutes = Int((included.reduce(0) { $0 + $1.durationSeconds } / 60).rounded())
        return WeeklyPracticeProgress(minutes: minutes, sessionCount: included.count, startOfWeek: start)
    }
}

struct PlayAlongAttemptSummary: Codable, Equatable, Identifiable {
    let id: UUID
    let exerciseID: String
    let exerciseTitle: String
    let completedAt: Date
    let noteGrades: [PlayAlongNoteGrade]

    init(id: UUID = UUID(), exercise: PlayAlongExercise, completedAt: Date = Date(), noteGrades: [PlayAlongNoteGrade]) {
        self.id = id
        exerciseID = exercise.id
        exerciseTitle = exercise.title
        self.completedAt = completedAt
        self.noteGrades = noteGrades
    }
}

struct WeakTransitionInsight: Equatable {
    let fromNote: String
    let toNote: String
    let evidenceCount: Int
    let weaknessScore: Double

    var explanation: String {
        NativeLocalization.format(
            "%@ to %@ was the least steady transition across %@ attempts.",
            fromNote,
            toNote,
            String(evidenceCount)
        )
    }

    var exercise: PlayAlongExercise {
        PlayAlongExercise(
            id: "generated:\(PracticePitchMath.pitchClass(for: fromNote) ?? 0)-\(PracticePitchMath.pitchClass(for: toNote) ?? 0)",
            title: NativeLocalization.format("%@–%@ transition drill", fromNote, toNote),
            detail: NativeLocalization.string("Generated from your saved Play-Along results"),
            difficulty: NativeLocalization.string("Personal drill"),
            category: .practicePattern,
            writtenNotes: [fromNote, toNote, fromNote, toNote, fromNote, toNote]
        )
    }
}

enum WeakTransitionAnalyzer {
    private struct Aggregate {
        var fromNote: String
        var toNote: String
        var scores: [Double]
    }

    static func insight(from attempts: [PlayAlongAttemptSummary], minimumEvidence: Int = 3) -> WeakTransitionInsight? {
        var values: [String: Aggregate] = [:]
        for attempt in attempts {
            guard attempt.noteGrades.count >= 2 else { continue }
            for index in 1..<attempt.noteGrades.count {
                let from = attempt.noteGrades[index - 1]
                let to = attempt.noteGrades[index]
                guard let fromClass = PracticePitchMath.pitchClass(for: from.writtenNoteName),
                      let toClass = PracticePitchMath.pitchClass(for: to.writtenNoteName) else { continue }
                let key = "\(fromClass)>\(toClass)"
                let ratingWeight: Double
                switch to.rating {
                case .excellent: ratingWeight = 0
                case .good: ratingWeight = 1
                case .close: ratingWeight = 2
                case .off: ratingWeight = 3
                case .missed: ratingWeight = 4
                }
                let centsWeight = min(1, abs(to.medianCents ?? 50) / 50)
                var aggregate = values[key] ?? Aggregate(fromNote: from.writtenNoteName, toNote: to.writtenNoteName, scores: [])
                aggregate.scores.append(ratingWeight + centsWeight)
                values[key] = aggregate
            }
        }

        return values
            .filter { $0.value.scores.count >= max(1, minimumEvidence) }
            .map { key, value in
                WeakTransitionInsight(
                    fromNote: value.fromNote,
                    toNote: value.toNote,
                    evidenceCount: value.scores.count,
                    weaknessScore: value.scores.reduce(0, +) / Double(value.scores.count)
                )
            }
            .sorted {
                if $0.weaknessScore != $1.weaknessScore { return $0.weaknessScore > $1.weaknessScore }
                let left = "\($0.fromNote)>\($0.toNote)"
                let right = "\($1.fromNote)>\($1.toNote)"
                return left.localizedStandardCompare(right) == .orderedAscending
            }
            .first
    }
}

// MARK: - Drone and interval practice

enum TuningInterval: Int, Codable, CaseIterable, Identifiable {
    case unison = 0
    // Retained for backward decoding only. The parity picker intentionally
    // exposes the same five intervals as the web app.
    case majorSecond = 2
    case majorThird = 4
    case perfectFourth = 5
    case perfectFifth = 7
    case octave = 12

    static let allCases: [TuningInterval] = [.unison, .majorThird, .perfectFourth, .perfectFifth, .octave]

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .unison: return NativeLocalization.string("Unison")
        case .majorSecond: return NativeLocalization.string("Major second")
        case .majorThird: return NativeLocalization.string("Major third")
        case .perfectFourth: return NativeLocalization.string("Perfect fourth")
        case .perfectFifth: return NativeLocalization.string("Perfect fifth")
        case .octave: return NativeLocalization.string("Octave")
        }
    }
}

struct DroneSettings: Codable, Equatable {
    var writtenMIDINote: Int = 60
    var interval: TuningInterval = .unison
    var volume: Double = 0.22

    mutating func validate() {
        writtenMIDINote = min(84, max(36, writtenMIDINote))
        volume = min(0.5, max(0.05, volume))
    }
}

enum PracticePitchMath {
    static func transpositionSemitones(for instrumentID: String) -> Int? {
        switch instrumentID {
        case "trumpet", "cornet", "flugelhorn", "baritone": return 2
        case "horn", "french-horn": return 7
        case "trombone", "euphonium", "tuba": return 0
        default: return nil
        }
    }

    static func concertMIDI(forWrittenMIDI writtenMIDI: Int, instrumentID: String) -> Int? {
        guard let semitones = transpositionSemitones(for: instrumentID) else { return nil }
        return writtenMIDI - semitones
    }

    static func frequency(
        writtenMIDI: Int,
        interval: TuningInterval = .unison,
        instrumentID: String,
        referencePitchHz: Double
    ) -> Double? {
        let targetWrittenMIDI = writtenMIDI + interval.rawValue
        guard let concertMIDI = concertMIDI(forWrittenMIDI: targetWrittenMIDI, instrumentID: instrumentID) else { return nil }
        return BrassTuneCore.midiToFrequency(Double(concertMIDI), referencePitchHz: referencePitchHz)
    }

    static func frequencies(
        writtenMIDI: Int,
        interval: TuningInterval,
        instrumentID: String,
        referencePitchHz: Double
    ) -> [Double]? {
        guard let base = frequency(
            writtenMIDI: writtenMIDI,
            interval: .unison,
            instrumentID: instrumentID,
            referencePitchHz: referencePitchHz
        ) else { return nil }
        guard interval != .unison else { return [base] }
        guard let upper = frequency(
            writtenMIDI: writtenMIDI,
            interval: interval,
            instrumentID: instrumentID,
            referencePitchHz: referencePitchHz
        ) else { return nil }
        return [base, upper]
    }

    static func noteLabel(writtenMIDI: Int) -> String {
        let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        let pitch = ((writtenMIDI % 12) + 12) % 12
        return "\(names[pitch])\((writtenMIDI / 12) - 1)"
    }

    static func pitchClass(for note: String) -> Int? {
        let normalized = note
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        return [
            "C": 0, "B#": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
            "E": 4, "Fb": 4, "E#": 5, "F": 5, "F#": 6, "Gb": 6, "G": 7,
            "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11, "Cb": 11,
        ][normalized]
    }

    static func matchesPitchClass(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs,
              let lhsClass = pitchClass(for: lhs),
              let rhsClass = pitchClass(for: rhs) else { return false }
        return lhsClass == rhsClass
    }
}

// MARK: - Offline practice packs and focused workspace

enum PracticePackBlockKind: String, Codable, CaseIterable {
    case instruction
    case playAlong
    case metronome
    case drone

    var title: String { NativeLocalization.string(rawValue.capitalized) }
}

struct PracticePackBlock: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var instruction: String
    var kind: PracticePackBlockKind
    var durationSeconds: TimeInterval
    var exercise: PlayAlongExercise?
    var metronome: MetronomeSettings?
    var drone: DroneSettings?

    init(
        id: UUID = UUID(),
        title: String,
        instruction: String,
        kind: PracticePackBlockKind,
        durationSeconds: TimeInterval,
        exercise: PlayAlongExercise? = nil,
        metronome: MetronomeSettings? = nil,
        drone: DroneSettings? = nil
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.kind = kind
        self.durationSeconds = max(5, durationSeconds)
        self.exercise = exercise
        self.metronome = metronome
        self.drone = drone
    }
}

struct PracticePack: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var detail: String
    var blocks: [PracticePackBlock]
    var isBuiltIn: Bool

    var displayName: String { isBuiltIn ? NativeLocalization.string(name) : name }
    var displayDetail: String { isBuiltIn ? NativeLocalization.string(detail) : detail }

    func displayTitle(for block: PracticePackBlock) -> String {
        isBuiltIn ? NativeLocalization.string(block.title) : block.title
    }

    func displayInstruction(for block: PracticePackBlock) -> String {
        isBuiltIn ? NativeLocalization.string(block.instruction) : block.instruction
    }

    static let builtIns: [PracticePack] = [
        PracticePack(
            id: "pack-daily-foundations",
            name: "Daily foundations",
            detail: "Breath, long tones, steady pulse, and a scale — available offline.",
            blocks: [
                PracticePackBlock(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, title: "Breathe", instruction: "Take relaxed four-count breaths.", kind: .instruction, durationSeconds: 30),
                PracticePackBlock(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, title: "Long tones", instruction: "Play each highlighted note with steady air.", kind: .playAlong, durationSeconds: 90, exercise: PlayAlongExercise.library.first(where: { $0.id == "longtones" }) ?? .defaultExercise),
                PracticePackBlock(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, title: "Steady pulse", instruction: "Play comfortable notes with the click.", kind: .metronome, durationSeconds: 60, metronome: MetronomeSettings(bpm: 72, beatsPerMeasure: 4, beatUnit: 4, subdivision: .quarter, muted: false, visualOnly: false, hapticsEnabled: false, volume: 0.45)),
                PracticePackBlock(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, title: "Scale", instruction: "Finish with a slow C major scale.", kind: .playAlong, durationSeconds: 90, exercise: .defaultExercise),
            ],
            isBuiltIn: true
        ),
        PracticePack(
            id: "pack-intonation-reset",
            name: "Intonation reset",
            detail: "A short drone and interval routine with no network required.",
            blocks: [
                PracticePackBlock(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, title: "Listen", instruction: "Listen to the reference before playing.", kind: .drone, durationSeconds: 45, drone: DroneSettings(writtenMIDINote: 60, interval: .unison, volume: 0.18)),
                PracticePackBlock(id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!, title: "Match a fifth", instruction: "Hear the space between the reference and the fifth.", kind: .drone, durationSeconds: 45, drone: DroneSettings(writtenMIDINote: 60, interval: .perfectFifth, volume: 0.18)),
                PracticePackBlock(id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!, title: "Play and listen", instruction: "Use headphones when possible, then match the tone gently.", kind: .instruction, durationSeconds: 30),
            ],
            isBuiltIn: true
        ),
    ]
}

struct FocusedWorkspaceCheckpoint: Codable, Equatable {
    let pack: PracticePack
    var blockIndex: Int
    let firstStartedAt: Date
    var blockAccumulatedSeconds: TimeInterval
    var blockRunningSince: Date?
    var completed: Bool

    var currentBlock: PracticePackBlock? {
        guard pack.blocks.indices.contains(blockIndex) else { return nil }
        return pack.blocks[blockIndex]
    }

    var isRunning: Bool { blockRunningSince != nil && !completed }

    func elapsedInBlock(at now: Date) -> TimeInterval {
        let live = blockRunningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return min(currentBlock?.durationSeconds ?? 0, max(0, blockAccumulatedSeconds + live))
    }
}

// Every field is decoded independently so snapshots created by earlier app
// versions remain usable as the local practice toolbox grows.
struct PracticeFeatureState: Codable, Equatable {
    var schemaVersion: Int = 1
    var customExercises: [SavedPlayAlongExercise] = []
    var metronomePresets: [MetronomePreset] = []
    var favorites: [PracticeShortcut] = []
    var recents: [PracticeShortcut] = []
    var weeklyGoal = WeeklyPracticeGoal()
    var reflections: [PracticeReflection] = []
    var playAlongAttempts: [PlayAlongAttemptSummary] = []
    var warmupCheckpoint: GuidedWarmupCheckpoint?
    var customPacks: [PracticePack] = []
    var workspaceCheckpoint: FocusedWorkspaceCheckpoint?
    var droneSettings = DroneSettings()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, customExercises, metronomePresets, favorites, recents
        case weeklyGoal, reflections, playAlongAttempts, warmupCheckpoint
        case customPacks, workspaceCheckpoint, droneSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        customExercises = try container.decodeIfPresent([SavedPlayAlongExercise].self, forKey: .customExercises) ?? []
        metronomePresets = try container.decodeIfPresent([MetronomePreset].self, forKey: .metronomePresets) ?? []
        favorites = try container.decodeIfPresent([PracticeShortcut].self, forKey: .favorites) ?? []
        recents = try container.decodeIfPresent([PracticeShortcut].self, forKey: .recents) ?? []
        weeklyGoal = try container.decodeIfPresent(WeeklyPracticeGoal.self, forKey: .weeklyGoal) ?? WeeklyPracticeGoal()
        reflections = try container.decodeIfPresent([PracticeReflection].self, forKey: .reflections) ?? []
        playAlongAttempts = try container.decodeIfPresent([PlayAlongAttemptSummary].self, forKey: .playAlongAttempts) ?? []
        warmupCheckpoint = try container.decodeIfPresent(GuidedWarmupCheckpoint.self, forKey: .warmupCheckpoint)
        customPacks = try container.decodeIfPresent([PracticePack].self, forKey: .customPacks) ?? []
        workspaceCheckpoint = try container.decodeIfPresent(FocusedWorkspaceCheckpoint.self, forKey: .workspaceCheckpoint)
        droneSettings = try container.decodeIfPresent(DroneSettings.self, forKey: .droneSettings) ?? DroneSettings()
    }
}

// MARK: - AppModel feature coordination

@MainActor
extension AppModel {
    var weakTransitionInsight: WeakTransitionInsight? {
        WeakTransitionAnalyzer.insight(from: practiceFeatures.playAlongAttempts)
    }

    var practicePacks: [PracticePack] {
        PracticePack.builtIns + practiceFeatures.customPacks
    }

    var weeklyPracticeProgress: WeeklyPracticeProgress {
        WeeklyPracticeProgress.calculate(sessions: sessions)
    }

    var currentWarmupCheckpoint: GuidedWarmupCheckpoint? {
        practiceFeatures.warmupCheckpoint
    }

    var currentWorkspaceCheckpoint: FocusedWorkspaceCheckpoint? {
        practiceFeatures.workspaceCheckpoint
    }

    @discardableResult
    func saveCustomExercise(title: String, notes: [String]) -> Result<SavedPlayAlongExercise, CustomExerciseValidationError> {
        do {
            let exercise = try SavedPlayAlongExercise(title: title, writtenNotes: notes)
            practiceFeatures.customExercises.append(exercise)
            selectedPlayAlongExerciseID = exercise.exercise.id
            return .success(exercise)
        } catch let error as CustomExerciseValidationError {
            return .failure(error)
        } catch {
            return .failure(.invalidNoteCount)
        }
    }

    func deleteCustomExercise(id: SavedPlayAlongExercise.ID) {
        let exerciseID = "custom:\(id.uuidString)"
        practiceFeatures.customExercises.removeAll { $0.id == id }
        practiceFeatures.favorites.removeAll { $0.kind == .playAlongExercise && $0.referenceID == exerciseID }
        practiceFeatures.recents.removeAll { $0.kind == .playAlongExercise && $0.referenceID == exerciseID }
        if selectedPlayAlongExerciseID == exerciseID {
            selectedPlayAlongExerciseID = PlayAlongExercise.defaultExercise.id
        }
    }

    @discardableResult
    func saveMetronomePreset(name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !practiceFeatures.metronomePresets.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else {
            return false
        }
        practiceFeatures.metronomePresets.append(MetronomePreset(name: clean, settings: metronome))
        return true
    }

    func applyMetronomePreset(id: MetronomePreset.ID) {
        guard let preset = practiceFeatures.metronomePresets.first(where: { $0.id == id }) else { return }
        metronome = preset.settings
    }

    @discardableResult
    func renameMetronomePreset(id: MetronomePreset.ID, name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !practiceFeatures.metronomePresets.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(clean) == .orderedSame }),
              let index = practiceFeatures.metronomePresets.firstIndex(where: { $0.id == id }) else { return false }
        practiceFeatures.metronomePresets[index].name = String(clean.prefix(40))
        return true
    }

    func deleteMetronomePreset(id: MetronomePreset.ID) {
        practiceFeatures.metronomePresets.removeAll { $0.id == id }
    }

    func isFavorite(_ shortcut: PracticeShortcut) -> Bool {
        practiceFeatures.favorites.contains { $0.id == shortcut.id }
    }

    func toggleFavorite(_ shortcut: PracticeShortcut) {
        if let index = practiceFeatures.favorites.firstIndex(where: { $0.id == shortcut.id }) {
            practiceFeatures.favorites.remove(at: index)
        } else {
            var favorite = shortcut
            favorite.lastStartedAt = nil
            practiceFeatures.favorites.append(favorite)
        }
    }

    func recordPracticeStart(_ shortcut: PracticeShortcut, now: Date = Date()) {
        var started = shortcut
        started.lastStartedAt = now
        practiceFeatures.recents.removeAll { $0.id == started.id }
        practiceFeatures.recents.insert(started, at: 0)
        practiceFeatures.recents = Array(practiceFeatures.recents.prefix(10))
    }

    @discardableResult
    func launchShortcut(_ shortcut: PracticeShortcut) async -> Bool {
        switch shortcut.kind {
        case .playAlongExercise:
            guard playAlongExercises.contains(where: { $0.id == shortcut.referenceID }) else { return false }
            await startPlayAlong(exerciseID: shortcut.referenceID)
            return playAlongPhase == .running
        case .guidedWarmup:
            startOrResumeWarmup()
            return currentWarmupCheckpoint?.isRunning == true
        case .practicePack:
            guard let pack = practicePacks.first(where: { $0.id == shortcut.referenceID }) else { return false }
            startWorkspace(pack: pack)
            return true
        case .drone:
            startDrone()
            return audioEngine.tonePlaying
        }
    }

    func updateWeeklyGoal(minutes: Int, sessions: Int) {
        var goal = WeeklyPracticeGoal(targetMinutes: minutes, targetSessions: sessions)
        goal.validate()
        practiceFeatures.weeklyGoal = goal
    }

    func reflection(for sessionID: PracticeSession.ID) -> PracticeReflection? {
        practiceFeatures.reflections.first { $0.sessionID == sessionID }
    }

    func saveReflection(sessionID: PracticeSession.ID, mood: PracticeReflectionMood, note: String, now: Date = Date()) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        let reflection = PracticeReflection(sessionID: sessionID, mood: mood, note: note, updatedAt: now)
        if let index = practiceFeatures.reflections.firstIndex(where: { $0.sessionID == sessionID }) {
            practiceFeatures.reflections[index] = reflection
        } else {
            practiceFeatures.reflections.insert(reflection, at: 0)
        }
    }

    func deleteReflection(sessionID: PracticeSession.ID) {
        practiceFeatures.reflections.removeAll { $0.sessionID == sessionID }
    }

    func startOrResumeWarmup(now: Date = Date()) {
        stopFeatureAudio()
        var checkpoint = practiceFeatures.warmupCheckpoint
        if checkpoint == nil || checkpoint?.completed == true {
            checkpoint = GuidedWarmupCheckpoint(
                planID: GuidedWarmupPlan.fiveMinute.id,
                firstStartedAt: now,
                accumulatedSeconds: 0,
                runningSince: nil,
                completed: false
            )
        }
        guard var checkpoint else { return }
        checkpoint.runningSince = now
        practiceFeatures.warmupCheckpoint = checkpoint
        recordPracticeStart(
            PracticeShortcut(kind: .guidedWarmup, referenceID: GuidedWarmupPlan.fiveMinute.id, title: GuidedWarmupPlan.fiveMinute.title),
            now: now
        )
    }

    func pauseWarmup(now: Date = Date()) {
        guard var checkpoint = practiceFeatures.warmupCheckpoint, checkpoint.isRunning else { return }
        checkpoint.accumulatedSeconds = checkpoint.elapsed(at: now)
        checkpoint.runningSince = nil
        practiceFeatures.warmupCheckpoint = checkpoint
        stopFeatureAudio()
    }

    func advanceWarmup(now: Date = Date()) {
        guard let checkpoint = practiceFeatures.warmupCheckpoint,
              checkpoint.isRunning,
              checkpoint.elapsed(at: now) >= GuidedWarmupPlan.fiveMinute.durationSeconds else { return }
        completeWarmup(now: now)
    }

    func resetWarmup() {
        stopFeatureAudio()
        practiceFeatures.warmupCheckpoint = nil
    }

    private func completeWarmup(now: Date) {
        guard var checkpoint = practiceFeatures.warmupCheckpoint, !checkpoint.completed else { return }
        checkpoint.accumulatedSeconds = GuidedWarmupPlan.fiveMinute.durationSeconds
        checkpoint.runningSince = nil
        checkpoint.completed = true
        practiceFeatures.warmupCheckpoint = checkpoint
        sessions.insert(
            PracticeSession(
                id: UUID(),
                name: GuidedWarmupPlan.fiveMinute.title,
                instrumentId: selectedInstrumentId,
                startedAt: checkpoint.firstStartedAt,
                endedAt: max(now, checkpoint.firstStartedAt.addingTimeInterval(GuidedWarmupPlan.fiveMinute.durationSeconds)),
                frames: [],
                retainedRecordingURL: nil,
                practiceNotes: "Completed the guided five-minute warm-up.",
                source: .live
            ),
            at: 0
        )
    }

    func updateDroneSettings(_ settings: DroneSettings, restartIfPlaying: Bool = true) {
        var validated = settings
        validated.validate()
        practiceFeatures.droneSettings = validated
        if restartIfPlaying && audioEngine.tonePlaying {
            startDrone()
        }
    }

    func startDrone() {
        stopFeatureAudio(exceptTone: true)
        let settings = practiceFeatures.droneSettings
        guard let frequencies = PracticePitchMath.frequencies(
            writtenMIDI: settings.writtenMIDINote,
            interval: settings.interval,
            instrumentID: selectedInstrumentId,
            referencePitchHz: referencePitchHz
        ) else {
            audioEngine.setExternalAudioNotice(NativeLocalization.string("This instrument doesn't have a verified written-to-concert transposition, so BrassTune did not play a tone."))
            return
        }
        do {
            try audioEngine.startTone(frequenciesHz: frequencies, volume: settings.volume)
            recordPracticeStart(PracticeShortcut(kind: .drone, referenceID: "drone", title: "Drone and interval tuning"))
        } catch {
            audioEngine.setExternalAudioNotice(NativeLocalization.string("BrassTune couldn't start the reference tone. Check your audio output and try again."))
        }
    }

    func stopDrone() {
        audioEngine.stopTone()
    }

    func startWorkspace(pack: PracticePack, now: Date = Date()) {
        stopFeatureAudio()
        practiceFeatures.workspaceCheckpoint = FocusedWorkspaceCheckpoint(
            pack: pack,
            blockIndex: 0,
            firstStartedAt: now,
            blockAccumulatedSeconds: 0,
            blockRunningSince: nil,
            completed: false
        )
        recordPracticeStart(PracticeShortcut(kind: .practicePack, referenceID: pack.id, title: pack.name), now: now)
    }

    func beginWorkspaceCurrentBlock(now: Date = Date()) async {
        guard var checkpoint = practiceFeatures.workspaceCheckpoint,
              !checkpoint.completed,
              let block = checkpoint.currentBlock else { return }
        stopFeatureAudio()
        checkpoint.blockRunningSince = now
        practiceFeatures.workspaceCheckpoint = checkpoint
        switch block.kind {
        case .instruction:
            break
        case .playAlong:
            if let exercise = block.exercise,
               playAlongExercises.contains(where: { $0.id == exercise.id }) {
                await startPlayAlong(exerciseID: exercise.id)
            }
        case .metronome:
            if let settings = block.metronome {
                metronome = settings
            }
            startMetronome()
        case .drone:
            if let settings = block.drone {
                updateDroneSettings(settings, restartIfPlaying: false)
            }
            startDrone()
        }
    }

    func pauseWorkspace(now: Date = Date()) {
        guard var checkpoint = practiceFeatures.workspaceCheckpoint, checkpoint.isRunning else { return }
        checkpoint.blockAccumulatedSeconds = checkpoint.elapsedInBlock(at: now)
        checkpoint.blockRunningSince = nil
        practiceFeatures.workspaceCheckpoint = checkpoint
        stopFeatureAudio()
    }

    func advanceWorkspaceClock(now: Date = Date()) {
        guard let checkpoint = practiceFeatures.workspaceCheckpoint,
              checkpoint.isRunning,
              let block = checkpoint.currentBlock,
              checkpoint.elapsedInBlock(at: now) >= block.durationSeconds else { return }
        pauseWorkspace(now: now)
    }

    func moveWorkspace(by offset: Int, now: Date = Date()) {
        guard var checkpoint = practiceFeatures.workspaceCheckpoint, !checkpoint.completed else { return }
        pauseWorkspace(now: now)
        guard let refreshed = practiceFeatures.workspaceCheckpoint else { return }
        checkpoint = refreshed
        let target = min(checkpoint.pack.blocks.count - 1, max(0, checkpoint.blockIndex + offset))
        checkpoint.blockIndex = target
        checkpoint.blockAccumulatedSeconds = 0
        checkpoint.blockRunningSince = nil
        practiceFeatures.workspaceCheckpoint = checkpoint
    }

    func finishWorkspace(now: Date = Date()) {
        guard var checkpoint = practiceFeatures.workspaceCheckpoint, !checkpoint.completed else { return }
        stopFeatureAudio()
        checkpoint.blockRunningSince = nil
        checkpoint.completed = true
        practiceFeatures.workspaceCheckpoint = checkpoint
        sessions.insert(
            PracticeSession(
                id: UUID(),
                name: checkpoint.pack.name,
                instrumentId: selectedInstrumentId,
                startedAt: checkpoint.firstStartedAt,
                endedAt: max(now, checkpoint.firstStartedAt.addingTimeInterval(1)),
                frames: [],
                retainedRecordingURL: nil,
                practiceNotes: NativeLocalization.format(
                    "Completed offline practice pack: %@.",
                    checkpoint.pack.name
                ),
                source: .live
            ),
            at: 0
        )
    }

    func discardWorkspace() {
        stopFeatureAudio()
        practiceFeatures.workspaceCheckpoint = nil
    }

    func handlePracticeBackground(now: Date = Date()) {
        pauseWarmup(now: now)
        pauseWorkspace(now: now)
        stopFeatureAudio()
    }

    func stopFeatureAudio(exceptTone: Bool = false) {
        if playAlongPhase == .running || playAlongStartInProgress {
            stopPlayAlong()
        }
        stopMetronome()
        if !exceptTone {
            stopDrone()
        }
    }
}
