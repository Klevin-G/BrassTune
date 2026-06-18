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

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access is required for live tuning."
        case .networkUnavailable: return "BrassTune could not reach the server."
        case .malformedResponse: return "The server returned an unreadable response."
        case .timeout: return "The request timed out."
        case .appleSignInCancelled: return "Apple sign-in was cancelled."
        case .accountDeletionRequiresConfirmation: return "Type delete my account to confirm deletion."
        case .missingAuthConfiguration: return "Supabase authentication is not configured for this build."
        case .authenticationFailed: return "BrassTune could not complete authentication."
        }
    }
}
