import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig = .fromProcessEnvironment()
    @Published var authState: AuthState = .guest
    @Published var selectedInstrumentId = "trumpet" { didSet { persistLocalData() } }
    @Published var referencePitchHz = 440.0 { didSet { persistLocalData() } }
    @Published var sessions: [PracticeSession] = [] { didSet { persistLocalData() } }
    @Published var scores: [ImportedScore] = [] { didSet { persistLocalData() } }
    @Published var activeScoreID: ImportedScore.ID? { didSet { persistLocalData() } }
    @Published var recordingSource: PracticeSessionSource = NativeAudioEngine.defaultRecordingSource
    @Published var metronome = MetronomeSettings() { didSet { persistLocalData(); restartMetronomeIfNeeded() } }
    @Published private(set) var metronomeRunning = false
    @Published private(set) var metronomeTick = 0
    @Published var ensembles: [EnsembleSummary] = AppModel.demoEnsembles
    @Published var lastError: UserVisibleError?

    let audioEngine = NativeAudioEngine()
    let apiClient = APIClient()
    let authService = AuthService()
    private let persistenceStore: NativePersistenceStore
    private let scoreImporter: NativeScoreImportService
    private let metronomeOutput = NativeMetronomeOutput()
    private var isRestoringLocalState = false
    private var metronomeTimer: Timer?
    private var tapTempoEvents: [Date] = []

    init(
        persistenceStore: NativePersistenceStore = .live(),
        scoreStorageDirectory: URL? = nil
    ) {
        self.persistenceStore = persistenceStore
        self.scoreImporter = NativeScoreImportService(storageDirectory: scoreStorageDirectory ?? NativeScoreImportService.defaultStorageDirectory)
        restoreLocalData()
    }

    static let demoEnsembles = [
        EnsembleSummary(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Demo brass studio",
            role: "Demo student",
            activeMembers: 4,
            focus: "Center D5 before range expansion."
        )
    ]

    var analyticsSnapshot: AnalyticsSnapshot {
        AnalyticsSnapshot(sessions: sessions)
    }

    var activeScore: ImportedScore? {
        guard let activeScoreID else {
            return scores.first
        }
        return scores.first { $0.id == activeScoreID } ?? scores.first
    }

    var selectedScoreForPracticeLabel: String {
        activeScore?.title ?? "No score attached"
    }

    var accountFeaturesEnabled: Bool {
        config.supabaseURL != nil && !(config.supabasePublishableKey ?? "").isEmpty
    }

    var accountUnavailableMessage: String? {
        accountFeaturesEnabled ? nil : "Accounts are not enabled in this beta build yet. Guest practice still works on this device."
    }

    func resetForUITesting() {
        authService.deleteStoredAuth()
        authState = .guest
        selectedInstrumentId = "trumpet"
        referencePitchHz = 440.0
        clearLocalPracticeArtifacts()
        metronome = MetronomeSettings()
        stopMetronome()
        ensembles = Self.demoEnsembles
        lastError = nil
    }

    func enterGuestDemo() {
        authState = .guest
        if ensembles.isEmpty {
            ensembles = Self.demoEnsembles
        }
        lastError = nil
    }

    func signOut() {
        authService.signOut()
        authState = .signedOut
        ensembles.removeAll()
        lastError = nil
    }

    func restoreSession() async {
        do {
            if let session = try await authService.refreshStoredSession(config: config) {
                authState = .signedIn(email: session.email)
            }
        } catch {
            if let session = authService.restoreSession() {
                authState = .signedIn(email: session.email)
            }
        }
    }

    func signIn(email: String, password: String) async {
        do {
            let session = try await authService.signIn(email: email, password: password, config: config)
            authState = .signedIn(email: session.email)
        } catch {
            lastError = (error as? UserVisibleError) ?? .authenticationFailed
        }
    }

    func signUp(email: String, password: String) async {
        do {
            let session = try await authService.signUp(email: email, password: password, config: config)
            authState = .signedIn(email: session.email)
        } catch UserVisibleError.emailConfirmationRequired {
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
        } catch {
            lastError = (error as? UserVisibleError) ?? .authenticationFailed
        }
    }

    func deleteSession(id: PracticeSession.ID) {
        sessions.removeAll { $0.id == id }
    }

    func exportDataText() -> String {
        var lines = [
            "BrassTune local data export",
            "Account state: \(authState.displayTitle)",
            "Environment: \(config.environment.rawValue)",
            "Instrument: \(selectedInstrumentId)",
            "Reference pitch: \(String(format: "%.1f", referencePitchHz)) Hz",
            "Sessions: \(sessions.count)",
            "Scores: \(scores.count)",
            "Metronome: \(metronome.bpm) BPM, \(metronome.meterLabel), \(metronome.subdivision.title), \(metronome.visualOnly ? "visual only" : "speaker eligible")",
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
        if !scores.isEmpty {
            lines.append("")
            lines.append("Scores")
            lines.append(contentsOf: scores.map(\.exportText))
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
        clearLocalPracticeArtifacts()
        stopMetronome()
        ensembles.removeAll()
        authService.deleteStoredAuth()
        authState = .signedOut
        lastError = nil
    }

    func startDemoRecording() {
        recordingSource = .sample
        audioEngine.startFixtureRecording(instrumentId: selectedInstrumentId, referencePitchHz: referencePitchHz)
    }

    func stopDemoRecording() {
        let frames = audioEngine.stopFixtureRecording()
        saveRecordedSession(frames: frames, source: .sample)
    }

    func startRecording() async {
        lastError = nil
        switch recordingSource {
        case .sample:
            startDemoRecording()
        case .live:
            do {
                let started = try await audioEngine.startLiveRecording(instrumentId: selectedInstrumentId, referencePitchHz: referencePitchHz)
                if !started {
                    lastError = .microphoneDenied
                }
            } catch {
                lastError = .microphoneUnavailable
            }
        }
    }

    func stopRecording() {
        switch audioEngine.activeSource {
        case .live:
            let frames = audioEngine.stopLiveRecording()
            saveRecordedSession(frames: frames, source: .live)
        case .sample:
            stopDemoRecording()
        }
        // Stopping a take also stops the metronome so it never keeps ticking
        // without an inline control. It stays independently usable from the
        // Metronome screen and floating controls via startMetronome().
        stopMetronome()
    }

    func clearLocalPracticeData() {
        clearLocalPracticeArtifacts()
    }

    func startMetronome() {
        guard !metronomeRunning else { return }
        metronomeRunning = true
        metronomeTick = 0
        metronomeOutput.playTick(settings: metronome, accent: true)
        scheduleMetronomeTimer()
    }

    func stopMetronome() {
        metronomeRunning = false
        metronomeTimer?.invalidate()
        metronomeTimer = nil
        metronomeOutput.stop()
    }

    func toggleMetronome() {
        metronomeRunning ? stopMetronome() : startMetronome()
    }

    func adjustTempo(by delta: Int) {
        metronome.bpm = min(240, max(30, metronome.bpm + delta))
    }

    func setTempo(_ bpm: Int) {
        metronome.bpm = min(240, max(30, bpm))
    }

    func tapTempo(now: Date = Date()) {
        tapTempoEvents.append(now)
        tapTempoEvents = tapTempoEvents.suffix(5)
        guard tapTempoEvents.count >= 2 else { return }
        let intervals = zip(tapTempoEvents.dropFirst(), tapTempoEvents).map { current, previous in
            current.timeIntervalSince(previous)
        }.filter { $0 > 0.2 && $0 < 2.4 }
        guard !intervals.isEmpty else { return }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        setTempo(Int((60.0 / average).rounded()))
    }

    func setMeter(beats: Int, unit: Int = 4) {
        metronome.beatsPerMeasure = min(12, max(1, beats))
        metronome.beatUnit = [2, 4, 8].contains(unit) ? unit : 4
    }

    func toggleMetronomeMute() {
        setMetronomeVisualOnly(!metronome.visualOnly)
    }

    func setMetronomeVisualOnly(_ visualOnly: Bool) {
        metronome.visualOnly = visualOnly
        if visualOnly {
            metronome.muted = true
            metronome.volume = 0
        } else {
            metronome.muted = false
            metronome.volume = max(0.35, metronome.volume)
        }
    }

    func setMetronomeVolume(_ volume: Double) {
        let clamped = min(1, max(0, volume))
        metronome.volume = clamped
        metronome.muted = clamped == 0
        metronome.visualOnly = clamped == 0
    }

    func importSampleScore() {
        let score = scoreImporter.makeSampleScore()
        scores.insert(score, at: 0)
        activeScoreID = score.id
    }

    func importScore(from url: URL) throws {
        let score = try scoreImporter.importScore(from: url)
        scores.insert(score, at: 0)
        activeScoreID = score.id
    }

    func importPhotoScore(data: Data, preferredName: String = "Photo score") throws {
        let score = try scoreImporter.importImageData(data, preferredName: preferredName, sourceKind: .photos)
        scores.insert(score, at: 0)
        activeScoreID = score.id
    }

    func storedScoreFileURL(for score: ImportedScore) -> URL? {
        scoreImporter.storedFileURL(named: score.localFileName)
    }

    func deleteScore(id: ImportedScore.ID) {
        let deletedScore = scores.first { $0.id == id }
        if let score = deletedScore {
            scoreImporter.deleteStoredFile(named: score.localFileName)
        }
        scores.removeAll { $0.id == id }
        if activeScoreID == id {
            activeScoreID = scores.first?.id
        }
        sessions = sessions.map { session in
            var updated = session
            if updated.attachedScoreID == id {
                updated.attachedScoreID = nil
                if let deletedScore {
                    updated.practiceNotes = updated.practiceNotes
                        .replacingOccurrences(of: "Practiced with \(deletedScore.title).", with: "")
                        .replacingOccurrences(of: "Focus: \(deletedScore.annotation.focusMeasures).", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return updated
        }
    }

    func attachScoreToLatestSession(scoreID: ImportedScore.ID) {
        guard !sessions.isEmpty else { return }
        guard let score = scores.first(where: { $0.id == scoreID }) else { return }
        sessions[0].attachedScoreID = score.id
        sessions[0].practiceNotes = "Practiced with \(score.title). \(score.annotation.focusMeasures.isEmpty ? "" : "Focus: \(score.annotation.focusMeasures).")"
        activeScoreID = score.id
    }

    func selectScorePage(scoreID: ImportedScore.ID, pageID: ScorePage.ID) {
        updateScore(scoreID) { score in
            score.selectedPageID = pageID
        }
    }

    func rotateSelectedScorePage(scoreID: ImportedScore.ID) {
        updateSelectedPage(scoreID: scoreID) { page in
            page.rotationDegrees = (page.rotationDegrees + 90) % 360
        }
    }

    func setSelectedScorePageCrop(scoreID: ImportedScore.ID, crop: ScoreCropPreset) {
        updateSelectedPage(scoreID: scoreID) { page in
            page.cropPreset = crop
        }
    }

    func setSelectedScorePageEnhancement(scoreID: ImportedScore.ID, enhancement: ScoreEnhancement) {
        updateSelectedPage(scoreID: scoreID) { page in
            page.enhancement = enhancement
        }
    }

    func updateScoreAnnotation(
        scoreID: ImportedScore.ID,
        focusMeasures: String? = nil,
        notes: String? = nil,
        tempoTarget: Int? = nil,
        problemPassage: String? = nil
    ) {
        updateScore(scoreID) { score in
            if let focusMeasures { score.annotation.focusMeasures = focusMeasures }
            if let notes { score.annotation.notes = notes }
            if let tempoTarget { score.annotation.tempoTarget = min(240, max(30, tempoTarget)) }
            if let problemPassage { score.annotation.problemPassage = problemPassage }
        }
    }

    private func updateScore(_ scoreID: ImportedScore.ID, mutate: (inout ImportedScore) -> Void) {
        guard let index = scores.firstIndex(where: { $0.id == scoreID }) else { return }
        mutate(&scores[index])
    }

    private func updateSelectedPage(scoreID: ImportedScore.ID, mutate: (inout ScorePage) -> Void) {
        updateScore(scoreID) { score in
            let selectedID = score.selectedPageID ?? score.pages.first?.id
            guard let pageIndex = score.pages.firstIndex(where: { $0.id == selectedID }) else { return }
            mutate(&score.pages[pageIndex])
        }
    }

    private func scheduleMetronomeTimer() {
        metronomeTimer?.invalidate()
        guard metronomeRunning else { return }
        metronomeTimer = Timer.scheduledTimer(withTimeInterval: metronome.intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.metronomeRunning else { return }
                self.metronomeTick = (self.metronomeTick + 1) % max(1, self.metronome.beatsPerMeasure * self.metronome.subdivision.ticksPerBeat)
                self.metronomeOutput.playTick(settings: self.metronome, accent: self.metronomeTick == 0)
            }
        }
    }

    private func restartMetronomeIfNeeded() {
        guard metronomeRunning else { return }
        scheduleMetronomeTimer()
    }

    private func saveRecordedSession(frames: [PitchFrame], source: PracticeSessionSource) {
        guard !frames.isEmpty else {
            lastError = .microphoneUnavailable
            return
        }
        let endedAt = Date()
        let duration = source == .live ? Double(max(1, (frames.last?.timestampMs ?? 0) - (frames.first?.timestampMs ?? 0))) / 1000.0 : Double(frames.count) * 0.11
        let startedAt = endedAt.addingTimeInterval(-duration)
        let matchingSourceCount = sessions.filter { $0.source == source }.count + 1
        let session = PracticeSession(
            id: UUID(),
            name: matchingSourceCount == 1 ? source.sessionTitle : "\(source.sessionTitle) \(matchingSourceCount)",
            instrumentId: selectedInstrumentId,
            startedAt: startedAt,
            endedAt: endedAt,
            frames: frames,
            retainedRecordingURL: nil,
            attachedScoreID: activeScore?.id,
            practiceNotes: activeScore.map { "Practiced with \($0.title)." } ?? "",
            source: source
        )
        sessions.insert(session, at: 0)
    }

    private func clearLocalPracticeArtifacts() {
        scoreImporter.deleteAllStoredFiles()
        sessions.removeAll()
        scores.removeAll()
        activeScoreID = nil
        persistenceStore.clear()
    }

    private func restoreLocalData() {
        guard let snapshot = persistenceStore.load() else { return }
        isRestoringLocalState = true
        selectedInstrumentId = snapshot.selectedInstrumentId
        referencePitchHz = snapshot.referencePitchHz
        sessions = snapshot.sessions
        scores = snapshot.scores
        activeScoreID = snapshot.activeScoreID ?? snapshot.scores.first?.id
        metronome = snapshot.metronome
        isRestoringLocalState = false
    }

    private func persistLocalData() {
        guard !isRestoringLocalState else { return }
        let snapshot = NativeLocalSnapshot(
            selectedInstrumentId: selectedInstrumentId,
            referencePitchHz: referencePitchHz,
            sessions: sessions,
            scores: scores,
            activeScoreID: activeScoreID,
            metronome: metronome
        )
        persistenceStore.save(snapshot)
    }
}

private struct BackendDeletionResponse: Decodable {
    let deleted: Bool
}

struct NativePersistenceStore {
    let fileURL: URL

    static func live() -> NativePersistenceStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrassTune", isDirectory: true)
        return NativePersistenceStore(fileURL: directory.appendingPathComponent("native-local-state.json"))
    }

    static func ephemeral(fileURL: URL) -> NativePersistenceStore {
        NativePersistenceStore(fileURL: fileURL)
    }

    func load() -> NativeLocalSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NativeLocalSnapshot.self, from: data)
    }

    func save(_ snapshot: NativeLocalSnapshot) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Local persistence failures should not block practice in the beta app.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

struct NativeLocalSnapshot: Codable, Equatable {
    var selectedInstrumentId: String
    var referencePitchHz: Double
    var sessions: [PracticeSession]
    var scores: [ImportedScore]
    var activeScoreID: ImportedScore.ID?
    var metronome: MetronomeSettings
}

struct NativeScoreImportService {
    enum ImportError: LocalizedError, Equatable {
        case unsupportedType
        case unreadableFile
        case fileTooLarge
        case noPages

        var errorDescription: String? {
            switch self {
            case .unsupportedType: return "BrassTune can import PDF, JPEG, PNG, and HEIC score files."
            case .unreadableFile: return "BrassTune could not read that score file."
            case .fileTooLarge: return "This score is too large for the native beta importer."
            case .noPages: return "No score pages were found in that file."
            }
        }
    }

    static let defaultStorageDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BrassTune/ImportedScores", isDirectory: true)

    let storageDirectory: URL
    private let maxFileSizeBytes: Int64 = 30 * 1024 * 1024
    private let maxPages = 32

    func importScore(from url: URL) throws -> ImportedScore {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let fileSize = Int64(values.fileSize ?? 0)
        guard fileSize <= maxFileSizeBytes else { throw ImportError.fileTooLarge }

        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        let sourceKind: ScoreSourceKind
        if type?.conforms(to: .pdf) == true {
            sourceKind = .filesPDF
        } else if type?.conforms(to: .image) == true || ["jpg", "jpeg", "png", "heic"].contains(url.pathExtension.lowercased()) {
            sourceKind = .filesImage
        } else {
            throw ImportError.unsupportedType
        }

        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "score" : url.pathExtension)"
        let storedURL = storageDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: storedURL.path) {
            try FileManager.default.removeItem(at: storedURL)
        }
        try FileManager.default.copyItem(at: url, to: storedURL)

        do {
            switch sourceKind {
            case .filesPDF:
                return try makePDFScore(from: storedURL, localFileName: fileName, fileSize: fileSize)
            case .filesImage:
                return try makeImageScore(from: storedURL, localFileName: fileName, fileSize: fileSize, sourceKind: .filesImage)
            case .photos, .sample:
                throw ImportError.unsupportedType
            }
        } catch {
            deleteStoredFile(named: fileName)
            throw error
        }
    }

    func importImageData(_ data: Data, preferredName: String, sourceKind: ScoreSourceKind) throws -> ImportedScore {
        guard data.count <= maxFileSizeBytes else { throw ImportError.fileTooLarge }
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).png"
        let storedURL = storageDirectory.appendingPathComponent(fileName)
        try data.write(to: storedURL, options: [.atomic])
        do {
            var score = try makeImageScore(from: storedURL, localFileName: fileName, fileSize: Int64(data.count), sourceKind: sourceKind)
            score.title = preferredName
            return score
        } catch {
            deleteStoredFile(named: fileName)
            throw error
        }
    }

    func makeSampleScore() -> ImportedScore {
        let pages = (1...3).map { index in
            ScorePage(
                id: UUID(),
                pageNumber: index,
                titleSuggestion: index == 1 ? "Long-tone study" : nil,
                textSuggestions: index == 1 ? ["Long-tone study", "Quarter note = 92", "Phrase A"] : ["Phrase \(index)"],
                thumbnailPNGData: makeSyntheticThumbnail(page: index),
                suggestedRegions: [
                    ScoreRegion(id: UUID(), label: "Phrase \(index)", normalizedX: 0.12, normalizedY: 0.20, normalizedWidth: 0.76, normalizedHeight: 0.18),
                    ScoreRegion(id: UUID(), label: "Problem passage", normalizedX: 0.18, normalizedY: 0.52, normalizedWidth: 0.66, normalizedHeight: 0.16),
                ]
            )
        }
        return ImportedScore(
            id: UUID(),
            title: "Long-tone study",
            composer: "BrassTune sample",
            sourceKind: .sample,
            localFileName: nil,
            importedAt: Date(),
            pages: pages,
            selectedPageID: pages.first?.id,
            annotation: ScoreAnnotation(focusMeasures: "1-8", notes: "Start with steady air before adding metronome.", tempoTarget: 92, problemPassage: "Opening attacks"),
            originalFileSizeBytes: 0
        )
    }

    func deleteStoredFile(named fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: storageDirectory.appendingPathComponent(fileName))
    }

    func storedFileURL(named fileName: String?) -> URL? {
        guard let fileName else { return nil }
        let url = storageDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func deleteAllStoredFiles() {
        try? FileManager.default.removeItem(at: storageDirectory)
    }

    private func makePDFScore(from url: URL, localFileName: String, fileSize: Int64) throws -> ImportedScore {
        guard let document = PDFDocument(url: url) else { throw ImportError.unreadableFile }
        let pageCount = min(document.pageCount, maxPages)
        guard pageCount > 0 else { throw ImportError.noPages }
        let pages: [ScorePage] = (0..<pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let text = page.string ?? ""
            let suggestions = metadataLines(from: text)
            let thumbnail = page.thumbnail(of: CGSize(width: 220, height: 300), for: .mediaBox)
            return ScorePage(
                id: UUID(),
                pageNumber: index + 1,
                titleSuggestion: suggestions.first,
                textSuggestions: suggestions,
                thumbnailPNGData: thumbnail.pngData(),
                suggestedRegions: suggestedScoreRegions(pageNumber: index + 1)
            )
        }
        guard !pages.isEmpty else { throw ImportError.noPages }
        return ImportedScore(
            id: UUID(),
            title: pages.first?.titleSuggestion ?? url.deletingPathExtension().lastPathComponent,
            composer: composerSuggestion(from: pages.flatMap(\.textSuggestions)),
            sourceKind: .filesPDF,
            localFileName: localFileName,
            importedAt: Date(),
            pages: pages,
            selectedPageID: pages.first?.id,
            originalFileSizeBytes: fileSize
        )
    }

    private func makeImageScore(from url: URL, localFileName: String, fileSize: Int64, sourceKind: ScoreSourceKind) throws -> ImportedScore {
        // Decode the image through ImageIO downsampling so a high-megapixel photo
        // never gets fully expanded into an uncompressed bitmap in memory (which
        // can trip jetsam on device even under the file-size gate). The original
        // file on disk stays untouched; only the in-memory image is capped.
        guard let image = downsampledImage(at: url, maxPixelSize: 2400) else { throw ImportError.unreadableFile }
        let thumbnail = downsampledPNG(image: image)
        let page = ScorePage(
            id: UUID(),
            pageNumber: 1,
            titleSuggestion: url.deletingPathExtension().lastPathComponent,
            textSuggestions: ["Image import", "Review title/composer manually"],
            thumbnailPNGData: thumbnail,
            suggestedRegions: suggestedScoreRegions(pageNumber: 1)
        )
        return ImportedScore(
            id: UUID(),
            title: url.deletingPathExtension().lastPathComponent,
            composer: nil,
            sourceKind: sourceKind,
            localFileName: localFileName,
            importedAt: Date(),
            pages: [page],
            selectedPageID: page.id,
            originalFileSizeBytes: fileSize
        )
    }

    private func metadataLines(from text: String) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(5))
    }

    private func composerSuggestion(from lines: [String]) -> String? {
        lines.first { line in
            let lowercased = line.lowercased()
            return lowercased.contains("arr.") || lowercased.contains("composer") || lowercased.contains("by ")
        }
    }

    private func suggestedScoreRegions(pageNumber: Int) -> [ScoreRegion] {
        [
            ScoreRegion(id: UUID(), label: "Staff group \(pageNumber).1", normalizedX: 0.10, normalizedY: 0.18, normalizedWidth: 0.80, normalizedHeight: 0.18),
            ScoreRegion(id: UUID(), label: "Staff group \(pageNumber).2", normalizedX: 0.10, normalizedY: 0.44, normalizedWidth: 0.80, normalizedHeight: 0.18),
            ScoreRegion(id: UUID(), label: "Staff group \(pageNumber).3", normalizedX: 0.10, normalizedY: 0.70, normalizedWidth: 0.80, normalizedHeight: 0.18),
        ]
    }

    private func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func downsampledPNG(image: UIImage) -> Data? {
        let maxLength: CGFloat = 320
        let scale = min(1, maxLength / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.pngData()
    }

    private func makeSyntheticThumbnail(page: Int) -> Data? {
        let size = CGSize(width: 220, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.94, green: 0.79, blue: 0.44, alpha: 1).setStroke()
            for system in 0..<3 {
                let top = 42 + system * 72
                for line in 0..<5 {
                    let y = CGFloat(top + line * 7)
                    context.cgContext.move(to: CGPoint(x: 28, y: y))
                    context.cgContext.addLine(to: CGPoint(x: 192, y: y))
                }
            }
            context.cgContext.setLineWidth(1.2)
            context.cgContext.strokePath()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor(red: 0.94, green: 0.79, blue: 0.44, alpha: 1),
            ]
            "p.\(page)".draw(at: CGPoint(x: 82, y: 250), withAttributes: attributes)
        }
        return image.pngData()
    }
}
