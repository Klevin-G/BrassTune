import Foundation
import BrassTuneCore

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

    static func fixture(index: Int, referencePitchHz: Double = 440.0) -> PitchFrame {
        let cents = Double([-7, -3, 0, 2, 8][index % 5])
        let frequency = BrassTuneCore.midiToFrequency(69, referencePitchHz: referencePitchHz) * pow(2.0, cents / 1200.0)
        return PitchFrame(
            timestampMs: index * 110,
            frequencyHz: frequency,
            confidence: 0.98,
            rms: 0.08,
            centsDeviation: cents,
            tuningStatus: BrassTuneCore.tuningStatus(cents: cents, confidence: 0.98, rms: 0.08),
            writtenNoteName: "A",
            writtenOctave: 4,
            isValidForRecording: true
        )
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

    var averageAbsCents: Double {
        let values = frames.compactMap(\.centsDeviation).map { abs($0) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var inTunePercentage: Double {
        let values = frames.compactMap(\.centsDeviation)
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
        guard !noteNames.isEmpty else { return "No locked notes" }
        return noteNames.sorted().joined(separator: ", ")
    }

    var exportText: String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "BrassTune session export",
            "Session: \(name)",
            "Instrument: \(instrumentId)",
            "Started: \(formatter.string(from: startedAt))",
            "Ended: \(endedAt.map { formatter.string(from: $0) } ?? "Not ended")",
            "Duration: \(String(format: "%.0f", durationSeconds)) seconds",
            "Frames: \(frames.count)",
            "Valid frames: \(validFrameCount)",
            "Average absolute cents: \(String(format: "%.1f", averageAbsCents))",
            "In-tune percentage: \(String(format: "%.0f", inTunePercentage))%",
            "Pitch coverage: \(pitchCoverageLabel)",
        ]
        let centsPreview = frames.compactMap(\.centsDeviation).prefix(12).map { String(format: "%+.1f", $0) }
        if !centsPreview.isEmpty {
            lines.append("Cents preview: \(centsPreview.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}

enum AppLaunchState: Equatable {
    case restoring
    case gateway
    case app
}

enum NativeFeature: String, CaseIterable, Identifiable {
    case home
    case practice
    case score
    case sessions
    case metronome
    case analytics
    case progress
    case coach
    case ensemble
    case settings
    case account
    case privacy
    case terms
    case support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .practice: return "Practice"
        case .score: return "Score"
        case .sessions: return "Sessions"
        case .metronome: return "Metronome"
        case .analytics: return "Analytics"
        case .progress: return "Progress"
        case .coach: return "Coach"
        case .ensemble: return "Ensemble"
        case .settings: return "Settings"
        case .account: return "Account"
        case .privacy: return "Privacy"
        case .terms: return "Terms"
        case .support: return "Support"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .practice: return "gauge.with.dots.needle.67percent"
        case .score: return "doc.viewfinder"
        case .sessions: return "music.note.list"
        case .metronome: return "metronome"
        case .analytics: return "chart.bar.xaxis"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .coach: return "lightbulb"
        case .ensemble: return "person.3"
        case .settings: return "gearshape"
        case .account: return "person.crop.circle"
        case .privacy: return "hand.raised"
        case .terms: return "doc.text"
        case .support: return "questionmark.circle"
        }
    }
}

struct MetronomeSettings: Codable, Equatable {
    var bpm = 96
    var beatsPerMeasure = 4
    var beatUnit = 4
    var subdivision = 1
    var volume = 0.7
    var accentFirstBeat = true
    var countInMeasures = 1
    var muted = false
    var rampEnabled = false
    var rampTargetBPM = 120
    var rampSeconds = 120

    mutating func clamp() {
        bpm = min(300, max(20, bpm))
        beatsPerMeasure = min(12, max(1, beatsPerMeasure))
        beatUnit = [2, 4, 8].contains(beatUnit) ? beatUnit : 4
        subdivision = min(8, max(1, subdivision))
        volume = min(1, max(0, volume))
        rampTargetBPM = min(300, max(20, rampTargetBPM))
        rampSeconds = min(3600, max(10, rampSeconds))
    }
}

enum ScoreSourceKind: String, Codable, CaseIterable, Identifiable {
    case pdf
    case image
    case camera
    case photos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .image: return "Image"
        case .camera: return "Camera"
        case .photos: return "Photos"
        }
    }
}

struct ScorePracticeDocument: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var sourceKind: ScoreSourceKind
    var pageCount: Int
    var importedAt: Date
    var currentPage: Int
    var markers: [String]
    var reviewNote: String
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

    var recommendation: String {
        guard hasSessions else {
            return "Record a guided take to unlock local practice recommendations."
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

        let allCents = sessions.flatMap { $0.frames.compactMap(\.centsDeviation) }
        if allCents.isEmpty {
            averageAbsCents = 0
            averageInTunePercentage = 0
        } else {
            averageAbsCents = allCents.map { abs($0) }.reduce(0, +) / Double(allCents.count)
            let inTuneCount = allCents.filter { abs($0) <= 5 }.count
            averageInTunePercentage = Double(inTuneCount) / Double(allCents.count) * 100
        }

        let bestSession = sessions.min { lhs, rhs in
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
    case noRecordedPitch

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access is required for live tuning."
        case .networkUnavailable: return "Cloud sync is unavailable right now."
        case .malformedResponse: return "Cloud sync returned an unreadable response."
        case .timeout: return "The request timed out."
        case .appleSignInCancelled: return "Apple sign-in was cancelled."
        case .accountDeletionRequiresConfirmation: return "Type delete my account to confirm deletion."
        case .missingAuthConfiguration: return "Accounts are not enabled in this release yet. Guest practice is fully available."
        case .authenticationFailed: return "BrassTune could not complete authentication."
        case .noRecordedPitch: return "No stable pitch was recorded. Try again with a longer held note."
        }
    }
}
