import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig = .fromProcessEnvironment()
    @Published var launchState: AppLaunchState = .restoring
    @Published var authState: AuthState = .signedOut
    @Published var selectedInstrumentId = "trumpet"
    @Published var referencePitchHz = 440.0
    @Published var sessions: [PracticeSession] = []
    @Published var scoreDocuments: [ScorePracticeDocument] = []
    @Published var metronomeSettings = MetronomeSettings()
    @Published var ensembles: [EnsembleSummary] = []
    @Published var lastError: UserVisibleError?

    let audioEngine = NativeAudioEngine()
    let metronome = NativeMetronomeEngine()
    let apiClient = APIClient()
    let authService = AuthService()
    private let localStore = LocalPracticeStore()

    var analyticsSnapshot: AnalyticsSnapshot {
        AnalyticsSnapshot(sessions: sessions)
    }

    var accountFeaturesEnabled: Bool {
        config.supabaseURL != nil && !(config.supabasePublishableKey ?? "").isEmpty
    }

    var accountUnavailableMessage: String? {
        accountFeaturesEnabled ? nil : "Accounts are not enabled in this release yet. Guest practice is fully available."
    }

    func resetForUITesting() {
        authService.deleteStoredAuth()
        localStore.clear()
        launchState = .app
        authState = .guest
        selectedInstrumentId = "trumpet"
        referencePitchHz = 440.0
        sessions.removeAll()
        scoreDocuments.removeAll()
        ensembles.removeAll()
        metronomeSettings = MetronomeSettings()
        lastError = nil
    }

    func continueAsGuest() {
        launchState = .app
        authState = .guest
        lastError = nil
    }

    func signOut() {
        authService.signOut()
        launchState = .gateway
        authState = .signedOut
        ensembles.removeAll()
        lastError = nil
    }

    func restoreSession() async {
        sessions = localStore.loadSessions()
        scoreDocuments = localStore.loadScoreDocuments()
        metronomeSettings = localStore.loadMetronomeSettings()
        do {
            if let session = try await authService.refreshStoredSession(config: config) {
                authState = .signedIn(email: session.email)
                launchState = .app
                return
            }
        } catch {
            if let session = authService.restoreSession() {
                authState = .signedIn(email: session.email)
                launchState = .app
                return
            }
        }
        authState = .signedOut
        launchState = .gateway
    }

    func signIn(email: String, password: String) async {
        do {
            let session = try await authService.signIn(email: email, password: password, config: config)
            authState = .signedIn(email: session.email)
            launchState = .app
        } catch {
            lastError = (error as? UserVisibleError) ?? .authenticationFailed
        }
    }

    func signUp(email: String, password: String) async {
        do {
            let session = try await authService.signUp(email: email, password: password, config: config)
            authState = .signedIn(email: session.email)
            launchState = .app
        } catch UserVisibleError.authenticationFailed {
            authState = .emailConfirmationRequired(email: email)
        } catch {
            lastError = (error as? UserVisibleError) ?? .authenticationFailed
        }
    }

    func requestPasswordReset(email: String) async {
        do {
            try await authService.requestPasswordReset(email: email, config: config)
        } catch {
            lastError = (error as? UserVisibleError) ?? .authenticationFailed
        }
    }

    func completeAppleSignIn(identityToken: Data, rawNonce: String) async {
        do {
            let session = try await authService.signInWithApple(identityToken: identityToken, rawNonce: rawNonce, config: config)
            authState = .signedIn(email: session.email)
            launchState = .app
        } catch {
            lastError = (error as? UserVisibleError) ?? .authenticationFailed
        }
    }

    func deleteSession(id: PracticeSession.ID) {
        if let session = sessions.first(where: { $0.id == id }),
           let retainedRecordingURL = session.retainedRecordingURL {
            try? FileManager.default.removeItem(at: retainedRecordingURL)
        }
        sessions.removeAll { $0.id == id }
        localStore.saveSessions(sessions)
    }

    func updateMetronomeSettings(_ settings: MetronomeSettings) {
        var cleaned = settings
        cleaned.clamp()
        metronomeSettings = cleaned
        localStore.saveMetronomeSettings(cleaned)
        if metronome.running {
            metronome.configure(cleaned)
        }
    }

    func addScoreDocument(kind: ScoreSourceKind) {
        addScoreDocument(name: "\(kind.title) practice \(scoreDocuments.count + 1)", kind: kind, pageCount: kind == .pdf ? 2 : 1)
    }

    func addScoreDocument(name: String, kind: ScoreSourceKind, pageCount: Int) {
        let nextIndex = scoreDocuments.count + 1
        let document = ScorePracticeDocument(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(kind.title) practice \(nextIndex)" : name,
            sourceKind: kind,
            pageCount: max(1, min(pageCount, 64)),
            importedAt: Date(),
            currentPage: 1,
            markers: ["Start", "Review"],
            reviewNote: "Pitch flags are linked to page and time only after a recorded take."
        )
        scoreDocuments.insert(document, at: 0)
        localStore.saveScoreDocuments(scoreDocuments)
    }

    func deleteScoreDocument(id: ScorePracticeDocument.ID) {
        scoreDocuments.removeAll { $0.id == id }
        localStore.saveScoreDocuments(scoreDocuments)
    }

    func recordScoreMarker(documentID: ScorePracticeDocument.ID, marker: String) {
        guard let index = scoreDocuments.firstIndex(where: { $0.id == documentID }) else { return }
        let cleaned = marker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        scoreDocuments[index].markers.append(cleaned)
        localStore.saveScoreDocuments(scoreDocuments)
    }

    func exportDataText() -> String {
        var lines = [
            "BrassTune local data export",
            "Account state: \(authState.displayTitle)",
            "Environment: \(config.environment.rawValue)",
            "Instrument: \(selectedInstrumentId)",
            "Reference pitch: \(String(format: "%.1f", referencePitchHz)) Hz",
            "Sessions: \(sessions.count)",
            "Account features: \(accountFeaturesEnabled ? "configured" : "disabled")",
        ]
        let analytics = analyticsSnapshot
        if analytics.hasSessions {
            lines.append("Average absolute cents: \(String(format: "%.1f", analytics.averageAbsCents))")
            lines.append("Average in-tune percentage: \(String(format: "%.0f", analytics.averageInTunePercentage))%")
            lines.append("")
            lines.append("Sessions")
            lines.append(contentsOf: sessions.map(\.exportText))
        } else {
            lines.append("No local practice sessions have been recorded.")
        }
        return lines.joined(separator: "\n")
    }

    func deleteAccount(confirmation: String) async {
        guard confirmation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "delete my account" else {
            lastError = .accountDeletionRequiresConfirmation
            return
        }
        if let token = authService.accessToken() {
            do {
                let body = try JSONSerialization.data(withJSONObject: ["confirmation": "delete my account"])
                _ = try await apiClient.request(
                    BackendDeletionResponse.self,
                    path: "/api/users/me",
                    method: "DELETE",
                    body: body,
                    config: config,
                    bearerToken: token
                )
            } catch {
                lastError = (error as? UserVisibleError) ?? .networkUnavailable
                return
            }
        }
        sessions.removeAll()
        ensembles.removeAll()
        scoreDocuments.removeAll()
        localStore.clear()
        authService.deleteStoredAuth()
        authState = .signedOut
        launchState = .gateway
        lastError = nil
    }

    func startPracticeRecording(testInjection: Bool = false) async {
        do {
            try await audioEngine.startRecording(
                instrumentId: selectedInstrumentId,
                referencePitchHz: referencePitchHz,
                deterministicTestInput: testInjection
            )
            lastError = nil
        } catch {
            lastError = (error as? UserVisibleError) ?? .microphoneDenied
        }
    }

    func stopPracticeRecording() {
        let result = audioEngine.stopRecording()
        let frames = result.frames
        guard !frames.isEmpty else {
            lastError = .noRecordedPitch
            return
        }
        let endedAt = Date()
        let startedAt = result.startedAt ?? endedAt.addingTimeInterval(-Double(frames.count) * 0.11)
        let takeIndex = sessions.count + 1
        let session = PracticeSession(
            id: UUID(),
            name: takeIndex == 1 ? "Practice take" : "Practice take \(takeIndex)",
            instrumentId: selectedInstrumentId,
            startedAt: startedAt,
            endedAt: endedAt,
            frames: frames,
            retainedRecordingURL: result.recordingURL
        )
        sessions.insert(session, at: 0)
        localStore.saveSessions(sessions)
    }
}

private struct BackendDeletionResponse: Decodable {
    let deleted: Bool
}

private final class LocalPracticeStore {
    private let sessionsURL: URL
    private let scoreDocumentsURL: URL
    private let metronomeURL: URL

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BrassTune", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        sessionsURL = directory.appendingPathComponent("sessions-v1.json")
        scoreDocumentsURL = directory.appendingPathComponent("score-documents-v1.json")
        metronomeURL = directory.appendingPathComponent("metronome-v1.json")
    }

    func loadSessions() -> [PracticeSession] {
        load([PracticeSession].self, from: sessionsURL) ?? []
    }

    func saveSessions(_ sessions: [PracticeSession]) {
        save(sessions, to: sessionsURL)
    }

    func loadScoreDocuments() -> [ScorePracticeDocument] {
        load([ScorePracticeDocument].self, from: scoreDocumentsURL) ?? []
    }

    func saveScoreDocuments(_ documents: [ScorePracticeDocument]) {
        save(documents, to: scoreDocumentsURL)
    }

    func loadMetronomeSettings() -> MetronomeSettings {
        load(MetronomeSettings.self, from: metronomeURL) ?? MetronomeSettings()
    }

    func saveMetronomeSettings(_ settings: MetronomeSettings) {
        save(settings, to: metronomeURL)
    }

    func clear() {
        try? FileManager.default.removeItem(at: sessionsURL)
        try? FileManager.default.removeItem(at: scoreDocumentsURL)
        try? FileManager.default.removeItem(at: metronomeURL)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
