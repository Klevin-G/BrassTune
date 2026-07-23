import XCTest
@testable import BrassTuneApp
import BrassTuneCore
import PDFKit
import Security
import UIKit

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let response: HTTPURLResponse
        let data: Data
        var delayNanoseconds: UInt64 = 0
    }

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Stub)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let stub = try handler(request)
            if stub.delayNanoseconds > 0 {
                Thread.sleep(forTimeInterval: Double(stub.delayNanoseconds) / 1_000_000_000)
            }
            client?.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class InMemoryAuthSessionStore: @unchecked Sendable {
    var payload: String?
}

private final class PersistenceThreadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func recordWasMainThread(_ value: Bool) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var observedMainThreadWrite: Bool {
        lock.lock()
        defer { lock.unlock() }
        return values.contains(true)
    }

    var writeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }
}

@MainActor
private final class DeferredMicrophonePermission {
    private var requestObservedContinuation: CheckedContinuation<Void, Never>?
    private var permissionContinuation: CheckedContinuation<Bool, Never>?
    private(set) var requested = false

    func request() async -> Bool {
        requested = true
        requestObservedContinuation?.resume()
        requestObservedContinuation = nil
        return await withCheckedContinuation { continuation in
            permissionContinuation = continuation
        }
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { continuation in
            requestObservedContinuation = continuation
        }
    }

    func resolve(granted: Bool) {
        permissionContinuation?.resume(returning: granted)
        permissionContinuation = nil
    }
}

final class BrassTuneAppTests: XCTestCase {
    // MARK: - Shipping defaults and local model behavior

    @MainActor
    func testToneOwnershipCancelsPendingTunerStartBeforeStoppingActiveRecording() {
        var events: [String] = []
        var isRecording = true

        AppAudioOwnershipHandoff.prepareForTonePlayback(
            cancelPendingRecordingStart: { events.append("cancel pending tuner start") },
            isRecording: { isRecording },
            stopRecording: {
                events.append("stop and save tuner recording")
                isRecording = false
            }
        )

        XCTAssertFalse(isRecording)
        XCTAssertEqual(events, ["cancel pending tuner start", "stop and save tuner recording"])
    }

    @MainActor
    func testToneOwnershipCancelsPendingTunerStartWithoutInventingARecording() {
        var events: [String] = []

        AppAudioOwnershipHandoff.prepareForTonePlayback(
            cancelPendingRecordingStart: { events.append("cancel pending tuner start") },
            isRecording: { false },
            stopRecording: { events.append("stop tuner recording") }
        )

        XCTAssertEqual(events, ["cancel pending tuner start"])
    }

    @MainActor
    func testFreshPracticeGoalAndPendingClassDestinationUseGrowthDefaults() {
        let model = AppModel(
            persistenceStore: .ephemeral(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            )
        )
        model.enterGuestDemo(presentTutorial: false)

        XCTAssertEqual(
            model.practiceFeatures.weeklyGoal,
            WeeklyPracticeGoal(targetMinutes: 15, targetSessions: 3)
        )
        model.requestClassDestination()
        XCTAssertEqual(model.pendingDestination, .classes)
        XCTAssertEqual(model.consumePendingDestination(), .classes)
        XCTAssertNil(model.pendingDestination)
    }

    @MainActor
    func testSnapshotEncodingAndWriteRunOffInteractiveMainThread() {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let observation = PersistenceThreadObservation()
        let store = NativePersistenceStore.ephemeral(
            fileURL: stateURL,
            writeData: { data, url in
                observation.recordWasMainThread(Thread.isMainThread)
                try data.write(to: url, options: [.atomic])
            }
        )
        let model = AppModel(persistenceStore: store)
        model.enterGuestDemo(presentTutorial: false)
        model.sessions = [makeSession(name: "Background persistence", cents: [0])]
        model.flushPendingPersistence()

        XCTAssertGreaterThan(observation.writeCount, 0)
        XCTAssertFalse(observation.observedMainThreadWrite)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
    }

    @MainActor
    func testGuestSafetyPromptAppearsOnlyAfterFirstPersistedSuccessAndStaysHandled() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(persistenceStore: store)
        model.enterGuestDemo(presentTutorial: false)
        XCTAssertFalse(model.guestProgressSafetyPromptEligible)

        model.sessions = [makeSession(name: "First persisted result", cents: [0])]
        model.flushPendingPersistence()
        for _ in 0..<50 where !model.guestProgressSafetyPromptEligible {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.guestProgressSafetyPromptEligible)
        XCTAssertEqual(model.persistedPracticeSuccessSequence, 1)

        model.markGuestProgressSafetyPromptHandled()
        model.flushPendingPersistence()
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertFalse(model.guestProgressSafetyPromptEligible)

        model.sessions.append(makeSession(name: "Second persisted result", cents: [0]))
        model.flushPendingPersistence()
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertFalse(model.guestProgressSafetyPromptEligible)

        let restored = AppModel(persistenceStore: store)
        restored.enterGuestDemo(presentTutorial: false)
        XCTAssertFalse(restored.guestProgressSafetyPromptEligible, "A handled prompt must not reappear at launch.")
        restored.sessions.append(makeSession(name: "Third persisted result", cents: [0]))
        restored.flushPendingPersistence()
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertFalse(restored.guestProgressSafetyPromptEligible)
    }

    func testSuccessFeedbackRespectsPreferenceAndReduceMotion() {
        XCTAssertTrue(nativeSuccessFeedbackAllowed(enabled: true, reduceMotion: false))
        XCTAssertFalse(nativeSuccessFeedbackAllowed(enabled: false, reduceMotion: false))
        XCTAssertFalse(nativeSuccessFeedbackAllowed(enabled: true, reduceMotion: true))
    }

    func testBuiltHostAppDeclaresFullScreenLaunchMetadata() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["UIRequiresFullScreen"] as? Bool, true)
        XCTAssertNotNil(info["UILaunchScreen"] as? [String: Any])
    }

    @MainActor
    func testLateMicrophoneGrantCannotReplaceDroneToneOrSaveHiddenRecording() async {
        let permission = DeferredMicrophonePermission()
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { XCTFail("A canceled microphone start must not acquire the audio session.") },
            deactivateSession: { }
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: permission.request,
            simulateTonePlayback: true
        )
        let model = makeModel(audioEngine: engine, audioSessionCoordinator: coordinator)

        let pendingRecording = Task { @MainActor in
            await model.startRecording()
        }
        await permission.waitUntilRequested()
        XCTAssertTrue(model.recordingStartInProgress)
        XCTAssertFalse(engine.recording)

        model.startDrone()
        let droneFrequencies = engine.toneFrequenciesHz
        XCTAssertTrue(engine.tonePlaying)
        XCTAssertFalse(droneFrequencies.isEmpty)
        XCTAssertFalse(
            model.recordingStartInProgress,
            "Drone ownership must synchronously invalidate the pending tuner start."
        )

        permission.resolve(granted: true)
        await pendingRecording.value

        XCTAssertTrue(engine.tonePlaying, "A late microphone grant must not stop the tone that owns the audio engine.")
        XCTAssertEqual(engine.toneFrequenciesHz, droneFrequencies)
        XCTAssertFalse(engine.recording, "The canceled tuner request must not become a hidden capture.")
        XCTAssertFalse(model.recordingStartInProgress)
        XCTAssertTrue(model.sessions.isEmpty, "A canceled pending start has no take to save.")
        XCTAssertNil(model.lastError)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
    }

    @MainActor
    func testLeavingActiveSceneCancelsPendingTunerStartBeforeReleasingPracticeAudio() {
        var events: [String] = []

        AppSceneAudioLifecycle.handleTransition(
            from: .active,
            to: .inactive,
            cancelTunerStart: { events.append("cancel tuner start") },
            isTunerRecording: { false },
            stopTunerRecording: { events.append("stop tuner recording") },
            releasePracticeAudio: { events.append("release practice audio") }
        )

        XCTAssertEqual(events, ["cancel tuner start", "release practice audio"])
    }

    @MainActor
    func testLeavingActiveSceneStopsActiveTunerBeforeReleasingPracticeAudio() {
        var events: [String] = []
        var tunerIsRecording = true

        AppSceneAudioLifecycle.handleTransition(
            from: .active,
            to: .background,
            cancelTunerStart: { events.append("cancel tuner start") },
            isTunerRecording: { tunerIsRecording },
            stopTunerRecording: {
                events.append("stop tuner recording")
                tunerIsRecording = false
            },
            releasePracticeAudio: { events.append("release practice audio") }
        )

        XCTAssertFalse(tunerIsRecording)
        XCTAssertEqual(events, ["cancel tuner start", "stop tuner recording", "release practice audio"])
    }

    @MainActor
    func testNonactiveSceneTransitionsDoNotRepeatAudioCleanup() {
        var cleanupCount = 0

        AppSceneAudioLifecycle.handleTransition(
            from: .inactive,
            to: .background,
            cancelTunerStart: { cleanupCount += 1 },
            isTunerRecording: { true },
            stopTunerRecording: { cleanupCount += 1 },
            releasePracticeAudio: { cleanupCount += 1 }
        )

        XCTAssertEqual(cleanupCount, 0)
    }

    @MainActor
    func testShippingDefaultsUseLiveMicrophoneAndAudibleMetronome() {
        XCTAssertFalse(NativeTestFixtures.areEnabled)
        XCTAssertEqual(NativeAudioEngine.defaultRecordingSource, .live)
        XCTAssertEqual(PracticeSessionSource.allCases, [.live])
        XCTAssertFalse(ScoreSourceKind.allCases.contains(.sample))

        let settings = MetronomeSettings()
        XCTAssertFalse(settings.muted)
        XCTAssertFalse(settings.visualOnly)
        XCTAssertEqual(settings.volume, 0.6, accuracy: 0.001)
    }

    func testMetronomeContractClampsRangeAndMigratesLegacySettings() throws {
        var settings = MetronomeSettings(bpm: 999, beatsPerMeasure: 99, beatUnit: 3, volume: 4, countInBeats: 99)
        XCTAssertEqual(settings.bpm, 300)
        XCTAssertEqual(settings.beatUnit, 4)
        XCTAssertEqual(settings.countInBeats, 16)
        settings.bpm = 1
        settings.validate()
        XCTAssertEqual(settings.bpm, 20)

        let legacy = Data(#"{"bpm":72,"beatsPerMeasure":3,"beatUnit":8,"subdivision":"eighth","muted":false,"visualOnly":false,"hapticsEnabled":true,"volume":0.4}"#.utf8)
        let decoded = try JSONDecoder().decode(MetronomeSettings.self, from: legacy)
        XCTAssertTrue(decoded.accentFirstBeat)
        XCTAssertEqual(decoded.countInBeats, 0)
        XCTAssertEqual(decoded.beatUnit, 8)
    }

    @MainActor
    func testMetronomeUsesCountInAndRespectsAccentToggle() {
        let model = makeModel()
        model.metronome = MetronomeSettings(
            bpm: 20,
            beatsPerMeasure: 3,
            beatUnit: 8,
            subdivision: .quarter,
            muted: true,
            visualOnly: true,
            volume: 0,
            accentFirstBeat: false,
            countInBeats: 2
        )
        model.startMetronome()
        XCTAssertEqual(model.metronomeCountInRemaining, 1)
        XCTAssertEqual(model.metronomeTick, 0)
        XCTAssertFalse(model.metronomeLastPulseWasAccented)

        model.advanceMetronomeClock()
        XCTAssertEqual(model.metronomeCountInRemaining, 0)
        XCTAssertEqual(model.metronomeTick, 0)
        model.advanceMetronomeClock()
        XCTAssertEqual(model.metronomeTick, 1)
        XCTAssertFalse(model.metronomeLastPulseWasAccented)
        model.stopMetronome()

        model.metronome.accentFirstBeat = true
        model.metronome.countInBeats = 0
        model.startMetronome()
        XCTAssertTrue(model.metronomeLastPulseWasAccented)
        model.stopMetronome()
    }

    func testFeatureStateMigrationPreservesFavoriteOrderAndSortsRecentFirstOccurrences() throws {
        let json = #"""
        {
          "favorites": [
            {"kind":"drone","referenceID":"one","title":"First"},
            {"kind":"drone","referenceID":"one","title":"Duplicate"},
            {"kind":"drone","referenceID":"two","title":"Second"}
          ],
          "recents": [
            {"kind":"drone","referenceID":"old","title":"First old","lastStartedAt":100},
            {"kind":"drone","referenceID":"old","title":"Duplicate newer","lastStartedAt":900},
            {"kind":"drone","referenceID":"new","title":"New","lastStartedAt":500}
          ]
        }
        """#
        let state = try JSONDecoder().decode(PracticeFeatureState.self, from: Data(json.utf8))
        XCTAssertEqual(state.favorites.map(\.title), ["First", "Second"])
        XCTAssertEqual(state.recents.map(\.title), ["New", "First old"])
    }

    @MainActor
    func testFeatureContractsBoundShortcutsGoalsAndCascadeCustomExercise() throws {
        let model = makeModel()
        model.updateWeeklyGoal(minutes: 9_999, sessions: 99)
        XCTAssertEqual(model.practiceFeatures.weeklyGoal, WeeklyPracticeGoal(targetMinutes: 600, targetSessions: 21))

        for index in 0..<20 {
            model.toggleFavorite(PracticeShortcut(kind: .drone, referenceID: "drone-\(index)", title: "Drone \(index)"))
        }
        XCTAssertEqual(model.practiceFeatures.favorites.count, 16)
        model.toggleFavorite(try XCTUnwrap(model.practiceFeatures.favorites.first))

        let saved = try model.saveCustomExercise(title: "Intervals", notes: ["C", "D"]).get()
        let shortcut = PracticeShortcut(kind: .playAlongExercise, referenceID: saved.exercise.id, title: saved.title)
        model.toggleFavorite(shortcut)
        model.recordPracticeStart(shortcut)
        let updated = try model.updateCustomExercise(id: saved.id, title: "Edited intervals", notes: ["D", "Eb"]).get()
        XCTAssertEqual(updated.title, "Edited intervals")
        XCTAssertTrue(model.practiceFeatures.favorites.contains { $0.referenceID == saved.exercise.id && $0.title == "Edited intervals" })
        model.deleteCustomExercise(id: saved.id)
        XCTAssertFalse(model.practiceFeatures.favorites.contains { $0.referenceID == saved.exercise.id })
        XCTAssertFalse(model.practiceFeatures.recents.contains { $0.referenceID == saved.exercise.id })
    }

    func testWeakTransitionsNormalizeEnharmonicsOctavesAndRankDestinationCents() {
        func attempt(_ from: String, _ to: String, _ cents: Double) -> PlayAlongAttemptSummary {
            let exercise = PlayAlongExercise(id: UUID().uuidString, title: "Test", detail: "", difficulty: "", category: .practicePattern, writtenNotes: [from, to])
            return PlayAlongAttemptSummary(exercise: exercise, noteGrades: [
                PlayAlongNoteGrade(writtenNoteName: from, medianCents: 0, sampleCount: 5, rating: .excellent),
                PlayAlongNoteGrade(writtenNoteName: to, medianCents: cents, sampleCount: 5, rating: .good),
            ])
        }
        let attempts = [
            attempt("C4", "D♭5", 18), attempt("B#3", "C#4", -24), attempt("C", "Db", 30),
            attempt("D", "Eb", 12), attempt("D4", "D4", 99), attempt("not-a-note", "E", 90),
        ]
        let insight = WeakTransitionAnalyzer.insight(from: attempts)
        XCTAssertEqual(insight?.fromNote, "C")
        XCTAssertEqual(insight?.toNote, "C#")
        XCTAssertEqual(insight?.evidenceCount, 3)
        XCTAssertEqual(try XCTUnwrap(insight?.weaknessScore), 24, accuracy: 0.0001)
        XCTAssertEqual(insight?.exercise.writtenNotes, ["C", "C#", "C", "C#", "C", "C#"])
    }

    func testWeakTransitionNumericTieBreakDoesNotSortTenBeforeTwo() {
        func attempt(_ from: String, _ to: String) -> PlayAlongAttemptSummary {
            let exercise = PlayAlongExercise(id: UUID().uuidString, title: "Tie", detail: "", difficulty: "", category: .practicePattern, writtenNotes: [from, to])
            return PlayAlongAttemptSummary(exercise: exercise, noteGrades: [
                PlayAlongNoteGrade(writtenNoteName: from, medianCents: 0, sampleCount: 5, rating: .excellent),
                PlayAlongNoteGrade(writtenNoteName: to, medianCents: 20, sampleCount: 5, rating: .off),
            ])
        }
        let attempts = Array(repeating: attempt("D", "Bb"), count: 3) + Array(repeating: attempt("Bb", "D"), count: 3)
        let insight = WeakTransitionAnalyzer.insight(from: attempts)
        XCTAssertEqual(insight?.fromNote, "D")
        XCTAssertEqual(insight?.toNote, "Bb")
    }

    @MainActor
    func testPracticePacksRequireExecutableBlocksAndWorkspacePersistsPause() async throws {
        let invalid = PracticePack(id: "invalid", name: "Invalid", detail: "", blocks: [
            PracticePackBlock(title: "Missing", instruction: "", kind: .drone, durationSeconds: 30),
        ], isBuiltIn: false)
        XCTAssertFalse(invalid.isValid)
        XCTAssertThrowsError(try invalid.validate())

        let model = makeModel()
        let pack = PracticePack.builtIns[0]
        let started = Date(timeIntervalSinceReferenceDate: 100)
        model.startWorkspace(pack: pack, now: started)
        await model.beginWorkspaceCurrentBlock(now: started)
        model.handlePracticeBackground(now: started.addingTimeInterval(9))
        XCTAssertFalse(model.currentWorkspaceCheckpoint?.isRunning ?? true)
        XCTAssertEqual(try XCTUnwrap(model.currentWorkspaceCheckpoint?.blockAccumulatedSeconds), 9, accuracy: 0.001)
        XCTAssertEqual(model.currentWorkspaceCheckpoint?.blockIndex, 0)
    }

    @MainActor
    func testFixtureEntryPointsDoNothingWithoutUITestLaunchFlag() {
        let model = makeModel()

        model.startDemoRecording()
        model.stopDemoRecording()
        model.importSampleScore()

        XCTAssertEqual(model.recordingSource, .live)
        XCTAssertFalse(model.audioEngine.recording)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty)
    }

    @MainActor
    func testNoArgumentAccountDeletionClearsLocalState() async {
        let model = makeModel()
        model.sessions = [makeSession(name: "Test recording", cents: [-2, 0, 3])]

        await model.deleteAccount()

        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertNil(model.lastError)
    }

    @MainActor
    func testSessionDeletionRemovesOnlySelectedSession() {
        let model = makeModel()
        let first = makeSession(name: "First", cents: [-2, 1, 6])
        let second = makeSession(name: "Second", cents: [9, 10, 11])
        model.sessions = [first, second]

        model.deleteSession(id: first.id)

        XCTAssertEqual(model.sessions, [second])
    }

    @MainActor
    func testLocalExportIncludesPracticeMetricsAndImportedScore() throws {
        let model = makeModel()
        model.sessions = [makeSession(name: "Exportable recording", cents: [-4, 0, 7])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Warm-up score")

        let export = model.exportDataText()

        XCTAssertTrue(export.contains("BrassTune local data export"))
        XCTAssertTrue(export.contains("Sessions: 1"))
        XCTAssertTrue(export.contains("Exportable recording"))
        XCTAssertTrue(export.contains("Average absolute cents"))
        XCTAssertTrue(export.contains("Cents preview"))
        XCTAssertTrue(export.contains("Scores: 1"))
        XCTAssertTrue(export.contains("Warm-up score"))
    }

    @MainActor
    func testAnalyticsSnapshotDerivesFromLocalSessions() {
        let model = makeModel()
        model.sessions = [
            makeSession(name: "Accurate", cents: [-2, 0, 3]),
            makeSession(name: "Sharp", cents: [9, 11, 7]),
        ]

        let analytics = model.analyticsSnapshot

        XCTAssertEqual(analytics.sessionCount, 2)
        XCTAssertEqual(analytics.validFrameCount, 6)
        XCTAssertEqual(analytics.bestSessionName, "Accurate")
        XCTAssertGreaterThan(analytics.averageAbsCents, 0)
        XCTAssertLessThan(analytics.averageInTunePercentage, 100)
    }

    @MainActor
    func testAccountFeaturesAreDisabledWithoutSupabaseConfig() {
        let model = makeModel()

        XCTAssertFalse(model.accountFeaturesEnabled)
        XCTAssertEqual(
            model.accountUnavailableMessage,
            "Online accounts aren't configured in this build. You can still practice as a guest, and your data stays on this device."
        )
    }

    @MainActor
    func testRuntimeAccountConfigFailsClosedUnlessURLAndPublishableKeyAreBothPresent() {
        let model = makeModel()
        let apiURL = AppConfig.approvedProductionAPIOrigin
        let supabaseURL = URL(string: "https://project.supabase.co")!

        model.config = AppConfig(environment: .production, apiBaseURL: apiURL, supabaseURL: supabaseURL, supabasePublishableKey: nil)
        XCTAssertFalse(model.accountFeaturesEnabled)
        XCTAssertNotNil(model.accountUnavailableMessage)

        model.config = AppConfig(environment: .production, apiBaseURL: apiURL, supabaseURL: nil, supabasePublishableKey: "sb_publishable_test")
        XCTAssertFalse(model.accountFeaturesEnabled)

        model.config = AppConfig(environment: .production, apiBaseURL: apiURL, supabaseURL: supabaseURL, supabasePublishableKey: "sb_publishable_test")
        XCTAssertTrue(model.accountFeaturesEnabled)
        XCTAssertNil(model.accountUnavailableMessage)
    }

    @MainActor
    func testRuntimeConfigReadsPublicArchiveInfoAndRejectsUnresolvedOrSecretValues() {
        let valid = AppConfig.fromProcessEnvironment(
            [:],
            bundleInfo: [
                "BRASSTUNE_SUPABASE_URL": "https://project.supabase.co",
                "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
            ]
        )
        XCTAssertEqual(valid.supabaseURL, URL(string: "https://project.supabase.co"))
        XCTAssertEqual(valid.supabasePublishableKey, "sb_publishable_test")
        XCTAssertTrue(valid.hasUsableSupabaseAuthConfiguration)

        let unresolved = AppConfig.fromProcessEnvironment(
            [:],
            bundleInfo: [
                "BRASSTUNE_SUPABASE_URL": "$(BRASSTUNE_SUPABASE_URL)",
                "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "$(BRASSTUNE_SUPABASE_PUBLISHABLE_KEY)",
            ]
        )
        XCTAssertNil(unresolved.supabaseURL)
        XCTAssertNil(unresolved.supabasePublishableKey)
        XCTAssertFalse(unresolved.hasUsableSupabaseAuthConfiguration)

        let secretLike = AppConfig(
            environment: .production,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabasePublishableKey: "sb_secret_forbidden"
        )
        XCTAssertFalse(secretLike.hasUsableSupabaseAuthConfiguration)

        let environmentOverride = AppConfig.fromProcessEnvironment(
            [
                "BRASSTUNE_SUPABASE_URL": "https://override.supabase.co",
                "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_override",
            ],
            bundleInfo: [
                "BRASSTUNE_SUPABASE_URL": "https://bundle.supabase.co",
                "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_bundle",
            ]
        )
        XCTAssertEqual(environmentOverride.supabaseURL, URL(string: "https://override.supabase.co"))
        XCTAssertEqual(environmentOverride.supabasePublishableKey, "sb_publishable_override")
    }

    func testProductionConfigurationRequiresExactImmutableOriginsAndJointAccountReadiness() {
        let supabase = URL(string: "https://project.supabase.co")!
        let key = "sb_publishable_test"
        let approved = AppConfig(
            environment: .production,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: supabase,
            supabasePublishableKey: key
        )
        XCTAssertTrue(approved.hasUsableAPIConfiguration)
        XCTAssertTrue(approved.hasUsableAccountConfiguration)

        for rejected in [
            "http://brasstune-u8qj.onrender.com",
            "https://localhost",
            "https://user:password@brasstune-u8qj.onrender.com",
            "https://api.example.test",
            "https://brasstune-u8qj.onrender.com?redirect=evil",
            "https://brasstune-u8qj.onrender.com.evil.test",
        ] {
            var config = approved
            config.apiBaseURL = URL(string: rejected)!
            XCTAssertFalse(config.hasUsableAPIConfiguration, rejected)
            XCTAssertFalse(config.hasUsableAccountConfiguration, rejected)
        }

        var missingAPI = approved
        missingAPI.apiBaseURL = URL(string: "https://api.example.test")!
        XCTAssertTrue(missingAPI.hasUsableSupabaseAuthConfiguration)
        XCTAssertFalse(missingAPI.hasUsableAccountConfiguration)

        var missingSupabase = approved
        missingSupabase.supabaseURL = nil
        XCTAssertTrue(missingSupabase.hasUsableAPIConfiguration)
        XCTAssertFalse(missingSupabase.hasUsableAccountConfiguration)
    }

    func testStringCatalogsCoverProductionLocalesPluralInterpolationMicCopyAndRTLHook() throws {
        let expectedLocales = Set(["ar", "de", "en", "es", "fr", "ja", "ko", "pt-BR", "ru", "vi", "zh-Hans", "zh-Hant"])
        XCTAssertEqual(Set(AppLanguage.allCases.dropFirst().map(\.rawValue)), expectedLocales)
        XCTAssertTrue(AppLanguage.arabic.isRightToLeft)
        XCTAssertFalse(AppLanguage.english.isRightToLeft)

        let resourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BrassTuneApp/Resources", isDirectory: true)
        let localizableData = try Data(contentsOf: resourceDirectory.appendingPathComponent("Localizable.xcstrings"))
        let localizable = try XCTUnwrap(JSONSerialization.jsonObject(with: localizableData) as? [String: Any])
        let strings = try XCTUnwrap(localizable["strings"] as? [String: Any])
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            XCTAssertEqual(Set(localizations.keys), expectedLocales, "Missing production locale in \(key)")
            let expectedObjectPlaceholders = key.components(separatedBy: "%@").count - 1
            for (locale, rawLocalization) in localizations {
                guard let localization = rawLocalization as? [String: Any],
                      let unit = localization["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String else { continue }
                XCTAssertEqual(
                    value.components(separatedBy: "%@").count - 1,
                    expectedObjectPlaceholders,
                    "Placeholder mismatch for \(locale): \(key)"
                )
            }
        }
        let appSourceDirectory = resourceDirectory.deletingLastPathComponent()
        let sourceEnumerator = FileManager.default.enumerator(at: appSourceDirectory, includingPropertiesForKeys: nil)
        let expression = try NSRegularExpression(pattern: #"(?:String\(localized:|NativeLocalization\.(?:string|format)\()\s*\"([^\"]+)\""#)
        while let sourceURL = sourceEnumerator?.nextObject() as? URL {
            guard sourceURL.pathExtension == "swift", let source = try? String(contentsOf: sourceURL, encoding: .utf8) else { continue }
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                let rawKey = String(source[keyRange])
                let key = rawKey.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%lld", options: .regularExpression)
                XCTAssertNotNil(strings[key], "Runtime-localized key missing from catalog: \(key)")
            }
        }
        let systemDefault = try XCTUnwrap(strings["System Default"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(systemDefault["localizations"] as? [String: Any]).keys), expectedLocales)
        let plural = try XCTUnwrap(strings["%lld practice sessions"] as? [String: Any])
        let pluralLocalizations = try XCTUnwrap(plural["localizations"] as? [String: Any])
        XCTAssertEqual(Set(pluralLocalizations.keys), expectedLocales)
        let arabicPlural = try XCTUnwrap(pluralLocalizations["ar"] as? [String: Any])
        let arabicVariations = try XCTUnwrap(arabicPlural["variations"] as? [String: Any])
        let arabicForms = try XCTUnwrap(arabicVariations["plural"] as? [String: Any])
        XCTAssertEqual(Set(arabicForms.keys), Set(["zero", "one", "two", "few", "many", "other"]))
        XCTAssertEqual(AppLanguage.english.practiceSessionCountLabel(1), "1 practice session")
        XCTAssertEqual(AppLanguage.english.practiceSessionCountLabel(2), "2 practice sessions")
        let pagesPlural = try XCTUnwrap(strings["%lld pages"] as? [String: Any])
        let pagesLocalizations = try XCTUnwrap(pagesPlural["localizations"] as? [String: Any])
        XCTAssertEqual(Set(pagesLocalizations.keys), expectedLocales)
        let originalLanguage = NativeLocalization.language
        defer { NativeLocalization.language = originalLanguage }
        NativeLocalization.language = .english
        XCTAssertEqual(NativeLocalization.pageCountLabel(1), "1 page")
        XCTAssertEqual(NativeLocalization.pageCountLabel(2), "2 pages")

        func value(_ key: String, _ locale: String) throws -> String {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            let localization = try XCTUnwrap(localizations[locale] as? [String: Any], "\(locale): \(key)")
            let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any], "\(locale): \(key)")
            return try XCTUnwrap(unit["value"] as? String, "\(locale): \(key)")
        }
        XCTAssertEqual(try value("Class", "zh-Hans"), "班级")
        XCTAssertEqual(try value("Class", "zh-Hant"), "班級")
        XCTAssertEqual(try value("Class", "ko"), "클래스")
        XCTAssertEqual(try value("Start listening", "ja"), "測定を開始")
        XCTAssertEqual(try value("Find the center", "zh-Hans"), "找准音高")
        XCTAssertEqual(try value("Practice history", "fr"), "Historique des séances")
        XCTAssertEqual(try value("Stop and save recording", "de"), "Stoppen und speichern")
        XCTAssertEqual(try value("Relaxed slurs", "es"), "Ligaduras relajadas")
        XCTAssertEqual(try value("Drone and intervals", "zh-Hans"), "持续音与音程")
        XCTAssertEqual(try value("%@ cents", "pt-BR"), "%@ cents")
        XCTAssertEqual(try value("Score Practice", "pt-BR"), "Prática de partituras")
        XCTAssertEqual(try value("Advanced rhythm", "ar"), "إيقاع متقدم")
        XCTAssertEqual(try value("Beat unit", "de"), "Notenwert")
        XCTAssertEqual(try value("Accent first beat", "es"), "Acentuar el primer pulso")
        XCTAssertEqual(try value("Count-in", "zh-Hant"), "預備拍")

        let infoData = try Data(contentsOf: resourceDirectory.appendingPathComponent("InfoPlist.xcstrings"))
        let info = try XCTUnwrap(JSONSerialization.jsonObject(with: infoData) as? [String: Any])
        let infoStrings = try XCTUnwrap(info["strings"] as? [String: Any])
        let mic = try XCTUnwrap(infoStrings["NSMicrophoneUsageDescription"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(mic["localizations"] as? [String: Any]).keys), expectedLocales)
    }

    func testRuntimeLocalizationFollowsExplicitArabicSelectionAfterEnglish() {
        let originalLanguage = NativeLocalization.language
        defer { NativeLocalization.language = originalLanguage }

        NativeLocalization.language = .english
        XCTAssertEqual(NativeLocalization.string("Flat"), "Flat")
        NativeLocalization.language = .arabic
        XCTAssertEqual(NativeLocalization.string("Flat"), AppLanguage.arabic.localized("Flat"))
        XCTAssertNotEqual(NativeLocalization.string("Flat"), "Flat")
        XCTAssertEqual(
            UserVisibleError.microphoneDenied.errorDescription,
            AppLanguage.arabic.localized("Microphone access is off. Allow it in Settings, then try again.")
        )
    }

    func testKeychainSessionUsesThisDeviceOnlyAccessibility() {
        XCTAssertEqual(KeychainStore.sessionAccessibility, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    @MainActor
    func testUnreadableAuthPayloadIsDistinguishedFromMissingAndPreservedForRecovery() {
        let store = InMemoryAuthSessionStore()
        store.payload = #"{"accessToken":"legacy-token","refreshToken":"legacy-refresh","email":"legacy@example.com"}"#
        let service = AuthService(
            session: makeStubSession(),
            readSessionPayload: { store.payload },
            saveSessionPayload: { store.payload = $0 },
            deleteSessionPayload: { store.payload = nil }
        )

        XCTAssertThrowsError(try service.restoreSessionOrThrow()) { error in
            XCTAssertEqual(error as? UserVisibleError, .secureStorageUnavailable)
        }
        XCTAssertNotNil(store.payload, "An unreadable Keychain item must not be erased as though it were absent.")
    }

    @MainActor
    func testKeychainReadFailureLocksStorageAndSurfacesRecoveryError() async {
        let authService = AuthService(
            session: makeStubSession(),
            readSessionPayload: { throw UserVisibleError.secureStorageUnavailable }
        )
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            authService: authService
        )

        await model.restoreSession()

        XCTAssertEqual(model.persistenceAccessState, .lockedSignedOut)
        XCTAssertFalse(model.gatewayCompleted)
        XCTAssertEqual(model.lastError, .secureStorageUnavailable)
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testUnreadableKeychainBlocksLocalDeletionBeforePracticeDataIsCleared() async {
        let authService = AuthService(
            session: makeStubSession(),
            readSessionPayload: { throw UserVisibleError.secureStorageUnavailable }
        )
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            authService: authService
        )
        let session = makeSession(name: "Keep while credentials are unreadable", cents: [0])
        model.sessions = [session]

        await model.deleteAccount()

        XCTAssertEqual(model.sessions, [session])
        XCTAssertEqual(model.lastError, .secureStorageUnavailable)
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testUnreadableKeychainDuringSignOutPreservesCredentialAndPendingRemovalMarker() async {
        var payload: String?
        var failReads = false
        var pendingDigests: [String] = []
        let authService = AuthService(
            session: makeStubSession(),
            readSessionPayload: {
                if failReads { throw UserVisibleError.secureStorageUnavailable }
                return payload
            },
            saveSessionPayload: { payload = $0 },
            deleteSessionPayload: { payload = nil }
        )
        let model = AppModel(
            persistenceStore: .ephemeral(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            ),
            pendingCredentialRemovalStore: PendingDigestStore(
                load: { pendingDigests },
                save: { pendingDigests = $0 }
            ),
            authService: authService
        )
        model.config = makeAuthConfig()
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"access-a","refresh_token":"refresh-a","expires_in":3600,"user":{"id":"user-a","email":"a@example.com"}}"#.utf8)
            )
        }
        await model.signIn(email: "a@example.com", password: "password")
        failReads = true

        await model.signOut()

        XCTAssertNotNil(payload)
        XCTAssertEqual(pendingDigests.count, 1)
        XCTAssertEqual(model.persistenceAccessState, .lockedSignedOut)
        XCTAssertEqual(model.lastError, .secureStorageUnavailable)
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testCorruptSnapshotLocksStorageAndIsNeverOverwrittenWithEmptyState() async throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-corrupt-\(UUID().uuidString).json")
        let corruptData = Data(#"{"snapshot":"truncated""#.utf8)
        try corruptData.write(to: stateURL)
        let authService = AuthService(
            session: makeStubSession(),
            readSessionPayload: { nil }
        )
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            authService: authService
        )

        await model.restoreSession()
        model.selectedInstrumentId = "tuba"

        XCTAssertEqual(model.persistenceAccessState, .lockedSignedOut)
        XCTAssertFalse(model.gatewayCompleted)
        XCTAssertNotNil(model.persistenceErrorMessage)
        XCTAssertEqual(try Data(contentsOf: stateURL), corruptData)
    }

    @MainActor
    func testTutorialCompletionPersistsAndExplicitGuestEntryRequestsReplay() {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(persistenceStore: store)
        model.enterGuestDemo(presentTutorial: false)

        XCTAssertFalse(model.tutorialCompleted)
        model.completeTutorial()
        model.flushPendingPersistence()

        let restored = AppModel(persistenceStore: store)
        restored.enterGuestDemo(presentTutorial: false)
        XCTAssertTrue(restored.tutorialCompleted)
        XCTAssertEqual(restored.tutorialPresentationRequest, 0)

        restored.enterGuestDemo()
        XCTAssertEqual(restored.authState, .guest)
        XCTAssertEqual(restored.tutorialPresentationRequest, 1)
        XCTAssertTrue(restored.tutorialCompleted, "Replaying the tutorial must not erase prior completion.")
    }

    @MainActor
    func testPasswordResetClearsStaleErrorShowsSuccessAndGuardsDuplicateSubmission() async throws {
        let session = makeStubSession()
        let authService = AuthService(session: session)
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = AppConfig(
            environment: .production,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabasePublishableKey: "sb_publishable_test"
        )
        model.lastError = .authenticationFailed
        nonisolated(unsafe) var requestCount = 0
        StubURLProtocol.handler = { request in
            requestCount += 1
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data("{}".utf8),
                delayNanoseconds: 150_000_000
            )
        }

        async let first: Void = model.requestPasswordReset(email: "player@example.com")
        try await Task.sleep(nanoseconds: 20_000_000)
        async let duplicate: Void = model.requestPasswordReset(email: "player@example.com")
        _ = await (first, duplicate)

        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(model.authOperationInProgress)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.authNotice, "Password reset email sent. Check your inbox.")
        XCTAssertFalse(model.authNoticeIsError)
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testNewAccountAwaitingConfirmationStaysAtRecoverableLockedGateway() async {
        let session = makeStubSession()
        let authService = AuthService(session: session)
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = AppConfig(
            environment: .production,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabasePublishableKey: "sb_publishable_test"
        )
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"user":{"email":"new@example.com"}}"#.utf8)
            )
        }

        await model.signUp(email: "new@example.com", password: "long-enough-password")

        XCTAssertEqual(model.authState, .emailConfirmationRequired(email: "new@example.com"))
        XCTAssertEqual(model.persistenceAccessState, .lockedSignedOut)
        XCTAssertFalse(model.gatewayCompleted)
        XCTAssertEqual(model.tutorialPresentationRequest, 0)
        model.completeTutorial()
        XCTAssertFalse(model.tutorialCompleted, "A locked confirmation flow must not be able to complete onboarding.")
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.authNotice, "Check your email to confirm this BrassTune account before signing in.")
        StubURLProtocol.handler = nil
    }

    func testPhotoLibraryUsageDescriptionIsTranslatedAcrossAllSupportedLocales() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BrassTuneApp/Resources/InfoPlist.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings["NSPhotoLibraryUsageDescription"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])

        XCTAssertEqual(
            Set(localizations.keys),
            Set(["ar", "de", "en", "es", "fr", "ja", "ko", "pt-BR", "ru", "vi", "zh-Hans", "zh-Hant"])
        )
    }

    @MainActor
    func testSignedInRemoteDeletionWithoutUsableTokenFailsClosed() async {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        defer {
            try? authService.signOut()
            StubURLProtocol.handler = nil
        }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let localSession = makeSession(name: "Keep me", cents: [-2, 0, 3])
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = makeAuthConfig()
        model.authState = .signedIn(email: "player@example.com")
        model.sessions = [localSession]
        nonisolated(unsafe) var requestCount = 0
        StubURLProtocol.handler = { request in
            requestCount += 1
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"deleted":true}"#.utf8)
            )
        }

        await model.deleteAccount()

        XCTAssertEqual(requestCount, 0, "Deletion must not reach the backend without a usable account token.")
        XCTAssertEqual(model.authState, .signedIn(email: "player@example.com"))
        XCTAssertEqual(model.sessions, [localSession])
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(statusCode: 401, message: "Your sign-in expired. Sign in again before deleting your account.")
        )
        XCTAssertEqual(model.authNotice, "Your sign-in expired. Sign in again before deleting your account.")
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testSignOutRevokesSupabaseSessionAndAlwaysClearsLocalCredential() async throws {
        for shouldFailOffline in [false, true] {
            let authService = makeIsolatedAuthService(session: makeStubSession())
            let config = makeAuthConfig()
            defer {
                try? authService.signOut()
                StubURLProtocol.handler = nil
            }
            nonisolated(unsafe) var logoutRequest: URLRequest?
            StubURLProtocol.handler = { request in
                if request.url?.path == "/auth/v1/logout" {
                    logoutRequest = request
                    if shouldFailOffline { throw URLError(.notConnectedToInternet) }
                    return .init(
                        response: HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                        data: Data()
                    )
                }
                return .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data: Data(#"{"access_token":"access-a","refresh_token":"refresh-a","expires_in":3600,"user":{"id":"user-a","email":"a@example.com"}}"#.utf8)
                )
            }
            _ = try await authService.signIn(email: "a@example.com", password: "password", config: config)
            XCTAssertNotNil(authService.restoreSession())

            if shouldFailOffline {
                do {
                    try await authService.signOut(config: config)
                    XCTFail("Expected offline logout to report a recoverable error")
                } catch {
                    XCTAssertEqual(error as? UserVisibleError, .networkUnavailable)
                }
            } else {
                try await authService.signOut(config: config)
            }

            XCTAssertNil(authService.restoreSession(), "Local credentials must clear even when server revocation is offline.")
            let request = try XCTUnwrap(logoutRequest)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-a")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        }
    }

    @MainActor
    func testAccountNamespacesPreventGuestOrCrossUserInheritanceAndDeletionSurvivesRelaunch() async throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-namespace-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-namespace-scores-\(UUID().uuidString)", isDirectory: true)
        let authService = makeIsolatedAuthService(session: makeStubSession())
        let config = makeAuthConfig()
        defer {
            try? authService.signOut()
            StubURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: NativeStorageNamespace.account(userID: "user-a").stateFile(basedAt: stateURL))
            try? FileManager.default.removeItem(at: NativeStorageNamespace.account(userID: "user-b").stateFile(basedAt: stateURL))
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path == "/auth/v1/logout" {
                return .init(response: response, data: Data())
            }
            if request.url?.host == AppConfig.approvedProductionAPIOrigin.host {
                return .init(response: response, data: Data(#"{"deleted":true}"#.utf8))
            }
            let body = requestBodyData(request) ?? Data()
            let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: String]
            let email = payload?["email"] ?? "a@example.com"
            let userID = email.hasPrefix("b") ? "user-b" : "user-a"
            let data = try JSONSerialization.data(withJSONObject: [
                "access_token": "access-\(userID)",
                "refresh_token": "refresh-\(userID)",
                "expires_in": 3_600,
                "user": ["id": userID, "email": email],
            ])
            return .init(response: response, data: data)
        }

        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        model.enterGuestDemo(presentTutorial: false)
        model.config = config
        let guestSession = makeSession(name: "Guest only", cents: [0])
        model.sessions = [guestSession]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Guest score")

        await model.signIn(email: "a@example.com", password: "password")
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty, "Account A must not inherit guest scores.")
        let accountASession = makeSession(name: "Account A only", cents: [1])
        model.sessions = [accountASession]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Account A score")

        await model.signOut()
        XCTAssertEqual(model.persistenceAccessState, .lockedSignedOut)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty)
        model.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(model.sessions.map(\.id), [guestSession.id])
        XCTAssertEqual(model.scores.map(\.title), ["Guest score"])

        await model.signIn(email: "b@example.com", password: "password")
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty, "Account B must not inherit account A or guest scores.")
        model.sessions = [makeSession(name: "Account B only", cents: [2])]

        await model.signOut()
        XCTAssertTrue(model.sessions.isEmpty)
        await model.signIn(email: "a@example.com", password: "password")
        XCTAssertEqual(model.sessions.map(\.id), [accountASession.id])
        XCTAssertEqual(model.scores.map(\.title), ["Account A score"])

        let relaunched = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        relaunched.config = config
        await relaunched.restoreSession()
        XCTAssertEqual(relaunched.sessions.map(\.id), [accountASession.id])
        XCTAssertEqual(relaunched.scores.map(\.title), ["Account A score"])

        let accountAFile = NativeStorageNamespace.account(userID: "user-a").stateFile(basedAt: stateURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: accountAFile.path))
        await relaunched.deleteAccount()
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountAFile.path))
        XCTAssertEqual(relaunched.persistenceAccessState, .lockedSignedOut)
        XCTAssertTrue(relaunched.sessions.isEmpty)
        XCTAssertTrue(relaunched.scores.isEmpty)
        relaunched.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(relaunched.sessions.map(\.id), [guestSession.id])
        XCTAssertEqual(relaunched.scores.map(\.title), ["Guest score"])

        let afterDeletionRelaunch = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        afterDeletionRelaunch.config = config
        XCTAssertEqual(afterDeletionRelaunch.persistenceAccessState, .restoringIdentity)
        XCTAssertTrue(afterDeletionRelaunch.sessions.isEmpty)
        await afterDeletionRelaunch.restoreSession()
        XCTAssertEqual(afterDeletionRelaunch.sessions.map(\.id), [guestSession.id])
        await afterDeletionRelaunch.signIn(email: "a@example.com", password: "password")
        XCTAssertTrue(afterDeletionRelaunch.sessions.isEmpty, "A deleted account namespace must stay deleted after relaunch.")
        XCTAssertTrue(afterDeletionRelaunch.scores.isEmpty)
    }

    @MainActor
    func testTerminalRefreshFailureClearsExpiredStoredSessionAndSignsOut() async throws {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        defer {
            try? authService.signOut()
            StubURLProtocol.handler = nil
        }
        let config = makeAuthConfig()
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"expired-token","refresh_token":"refresh-token","expires_in":-60,"user":{"id":"player-a","email":"player@example.com"}}"#.utf8)
            )
        }
        _ = try await authService.signIn(email: "player@example.com", password: "password", config: config)

        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"message":"refresh token is no longer valid"}"#.utf8)
            )
        }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = config

        await model.restoreSession()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertEqual(model.persistenceAccessState, .lockedSignedOut)
        XCTAssertFalse(model.gatewayCompleted)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertNil(authService.restoreSession())
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(statusCode: 401, message: "Your sign-in expired. Sign in again, then retry.")
        )
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testCachedRemoteSessionIsRejectedAndClearedBeforeUseWhenRuntimeConfigIsInvalid() async throws {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        defer {
            try? authService.signOut()
            StubURLProtocol.handler = nil
        }
        let validConfig = makeAuthConfig()
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"cached-token","refresh_token":"refresh-token","expires_in":3600,"user":{"id":"cached-user","email":"cached@example.com"}}"#.utf8)
            )
        }
        _ = try await authService.signIn(email: "cached@example.com", password: "password", config: validConfig)
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = .local

        await model.restoreSession()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertNil(authService.restoreSession())
        XCTAssertEqual(model.lastError, .missingAuthConfiguration)
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testRetryableRefreshResponsesPreserveStoredSessionButKeepUIFailClosed() async throws {
        for statusCode in [429, 503] {
            let networkSession = makeStubSession()
            let authService = makeIsolatedAuthService(session: networkSession)
            let config = makeAuthConfig()
            StubURLProtocol.handler = { request in
                .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data: Data(#"{"access_token":"expired-token","refresh_token":"refresh-token","expires_in":-60,"user":{"id":"retry-user","email":"retry@example.com"}}"#.utf8)
                )
            }
            _ = try await authService.signIn(email: "retry@example.com", password: "password", config: config)
            StubURLProtocol.handler = { request in
                .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!,
                    data: Data()
                )
            }
            let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
            model.config = config

            await model.restoreSession()

            XCTAssertEqual(model.authState, .signedOut)
            XCTAssertEqual(model.persistenceAccessState, .lockedSignedOut)
            XCTAssertTrue(model.sessions.isEmpty)
            XCTAssertTrue(model.scores.isEmpty)
            XCTAssertNotNil(authService.restoreSession(), "Retryable \(statusCode) failures must remain resumable.")
            XCTAssertEqual(
                model.lastError,
                .apiRequestFailed(
                    statusCode: statusCode,
                    message: "The account service couldn't refresh your sign-in right now. Your saved session will be retried later."
                )
            )
            XCTAssertTrue(model.authNoticeIsError)
            try? authService.signOut()
        }
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testOfflineRefreshFallbackRequiresProvablyUnexpiredAccessToken() async throws {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        defer {
            try? authService.signOut()
            StubURLProtocol.handler = nil
        }
        let config = makeAuthConfig()
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"still-live-token","refresh_token":"refresh-token","expires_in":30,"user":{"id":"offline-user","email":"offline@example.com"}}"#.utf8)
            )
        }
        _ = try await authService.signIn(email: "offline@example.com", password: "password", config: config)
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = config

        await model.restoreSession()

        XCTAssertEqual(model.authState, .signedIn(email: "offline@example.com"))
        XCTAssertTrue(model.gatewayCompleted, "A valid restored session must bypass the welcome gateway.")
        XCTAssertNotNil(authService.restoreSession())
        XCTAssertEqual(model.lastError, .networkUnavailable)
        XCTAssertEqual(
            model.authNotice,
            "You're offline. BrassTune kept your unexpired sign-in for local practice; online account features may be unavailable."
        )
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testExpiredOfflineRefreshPreservesRetryableSessionButStaysSignedOut() async throws {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        defer {
            try? authService.signOut()
            StubURLProtocol.handler = nil
        }
        let config = makeAuthConfig()
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"expired-token","refresh_token":"refresh-token","expires_in":-30,"user":{"id":"offline-user","email":"offline@example.com"}}"#.utf8)
            )
        }
        _ = try await authService.signIn(email: "offline@example.com", password: "password", config: config)
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = config

        await model.restoreSession()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertEqual(model.persistenceAccessState, .lockedSignedOut)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNotNil(authService.restoreSession())
        XCTAssertEqual(model.lastError, .networkUnavailable)
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testAppleIdentityAgeControlsTutorialWithoutInterruptingKnownReturningUsers() async {
        let timestamps: [(created: String?, last: String?, expectedRequest: Int, expectedNotice: String)] = [
            (
                "2026-07-16T19:00:00.000Z",
                "2026-07-16T19:00:00.000Z",
                1,
                "Signed in with Apple."
            ),
            (
                "2026-06-01T19:00:00.000Z",
                "2026-07-16T19:00:00.000Z",
                0,
                "Signed in with Apple."
            ),
            (
                nil,
                nil,
                1,
                "Signed in with Apple."
            ),
        ]

        for expectation in timestamps {
            let networkSession = makeStubSession()
            let authService = makeIsolatedAuthService(session: networkSession)
            let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
            model.config = makeAuthConfig()
            var user: [String: String] = ["id": "apple-user", "email": "apple@example.com"]
            user["created_at"] = expectation.created
            user["last_sign_in_at"] = expectation.last
            let payload: [String: Any] = [
                "access_token": "apple-access-token",
                "refresh_token": "apple-refresh-token",
                "expires_in": 3_600,
                "user": user,
            ]
            StubURLProtocol.handler = { request in
                .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data: try JSONSerialization.data(withJSONObject: payload)
                )
            }

            await model.completeAppleSignIn(identityToken: Data("apple-id-token".utf8), rawNonce: "nonce")

            XCTAssertEqual(model.authState, .signedIn(email: "apple@example.com"))
            XCTAssertEqual(model.tutorialPresentationRequest, expectation.expectedRequest)
            XCTAssertEqual(model.authNotice, expectation.expectedNotice)
            XCTAssertNil(model.lastError)
            try? authService.signOut()
        }
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testMetronomeUserSettingsRemainAudibleAndPersistable() {
        let model = makeModel()

        XCTAssertFalse(model.metronomeTemporarilyMutedForRecording)
        model.setTempo(100)
        model.setMetronomeVolume(0.72)

        XCTAssertEqual(model.metronome.bpm, 100)
        XCTAssertFalse(model.metronome.muted)
        XCTAssertFalse(model.metronome.visualOnly)
        XCTAssertEqual(model.metronome.volume, 0.72, accuracy: 0.001)
    }

    @MainActor
    func testTapTempoClampsAndUpdatesBPM() {
        let model = makeModel()
        let start = Date(timeIntervalSince1970: 10)

        model.tapTempo(now: start)
        model.tapTempo(now: start.addingTimeInterval(0.5))
        model.tapTempo(now: start.addingTimeInterval(1.0))

        XCTAssertEqual(model.metronome.bpm, 120)
        model.setTempo(10)
        XCTAssertEqual(model.metronome.bpm, 20)
        model.setTempo(999)
        XCTAssertEqual(model.metronome.bpm, 300)
    }

    @MainActor
    func testScoreAnnotationAttachAndDelete() throws {
        let model = makeModel()
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Local score")
        let score = try XCTUnwrap(model.scores.first)
        model.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]

        model.updateScoreAnnotation(
            scoreID: score.id,
            focusMeasures: "9-16",
            notes: "Tune releases",
            tempoTarget: 104,
            problemPassage: "second phrase"
        )
        model.attachScoreToLatestSession(scoreID: score.id)

        XCTAssertEqual(model.activeScoreID, score.id)
        XCTAssertEqual(model.scores[0].annotation.focusMeasures, "9-16")
        XCTAssertEqual(model.sessions[0].attachedScoreID, score.id)

        model.deleteScore(id: score.id)

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertNil(model.sessions[0].attachedScoreID)
        XCTAssertFalse(model.sessions[0].practiceNotes.contains("Local score"))
        XCTAssertFalse(model.sessions[0].practiceNotes.contains("9-16"))
    }

    @MainActor
    func testScoreDeleteFailureKeepsFileRecordAndSessionReference() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(
            persistenceStore: store,
            scoreStorageDirectory: scoreDirectory,
            scoreFileRemover: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        model.enterGuestDemo(presentTutorial: false)
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Protected score")
        let score = try XCTUnwrap(model.scores.first)
        let storedURL = try XCTUnwrap(model.storedScoreFileURL(for: score))
        model.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]
        model.attachScoreToLatestSession(scoreID: score.id)

        model.deleteScore(id: score.id)

        XCTAssertEqual(model.scores.first?.id, score.id)
        XCTAssertEqual(model.activeScoreID, score.id)
        XCTAssertEqual(model.sessions.first?.attachedScoreID, score.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't remove the local score file, so the score was kept. Try again."
            )
        )

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        restored.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(restored.scores.first?.id, score.id, "Failed file removal must roll the persisted deletion back.")
        XCTAssertEqual(restored.sessions.first?.attachedScoreID, score.id)
    }

    @MainActor
    func testScoreDeletePersistsCompletePostDeleteStateAcrossRelaunch() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        model.enterGuestDemo(presentTutorial: false)
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Disposable score")
        let score = try XCTUnwrap(model.scores.first)
        let storedURL = try XCTUnwrap(model.storedScoreFileURL(for: score))
        model.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]
        model.attachScoreToLatestSession(scoreID: score.id)

        model.deleteScore(id: score.id)

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertNil(model.sessions.first?.attachedScoreID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        restored.enterGuestDemo(presentTutorial: false)
        XCTAssertTrue(restored.scores.isEmpty)
        XCTAssertNil(restored.sessions.first?.attachedScoreID)
    }

    @MainActor
    func testScoreDeleteSaveFailureKeepsPreDeleteStateAcrossRelaunch() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let durableStore = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let seedModel = AppModel(persistenceStore: durableStore, scoreStorageDirectory: scoreDirectory)
        seedModel.enterGuestDemo(presentTutorial: false)
        try seedModel.importPhotoScore(data: makeTinyPNGData(), preferredName: "Durable score")
        let score = try XCTUnwrap(seedModel.scores.first)
        seedModel.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]
        seedModel.attachScoreToLatestSession(scoreID: score.id)
        seedModel.flushPendingPersistence()

        let failingStore = NativePersistenceStore.ephemeral(
            fileURL: stateURL,
            writeData: { _, _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        let model = AppModel(persistenceStore: failingStore, scoreStorageDirectory: scoreDirectory)
        model.enterGuestDemo(presentTutorial: false)
        let storedURL = try XCTUnwrap(model.scores.first.flatMap { model.storedScoreFileURL(for: $0) })

        model.deleteScore(id: score.id)

        XCTAssertEqual(model.scores.first?.id, score.id)
        XCTAssertEqual(model.sessions.first?.attachedScoreID, score.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't save the score deletion, so the score and file were kept. Try again."
            )
        )
        let restored = AppModel(persistenceStore: durableStore, scoreStorageDirectory: scoreDirectory)
        restored.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(restored.scores.first?.id, score.id)
        XCTAssertEqual(restored.sessions.first?.attachedScoreID, score.id)
    }

    @MainActor
    func testScoreDeleteRollbackFailureKeepsOpenModelAndReportsRecoveryRisk() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let durableStore = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let seedModel = AppModel(persistenceStore: durableStore, scoreStorageDirectory: scoreDirectory)
        seedModel.enterGuestDemo(presentTutorial: false)
        try seedModel.importPhotoScore(data: makeTinyPNGData(), preferredName: "Rollback score")
        let score = try XCTUnwrap(seedModel.scores.first)
        seedModel.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]
        seedModel.attachScoreToLatestSession(scoreID: score.id)
        seedModel.flushPendingPersistence()

        var writeCount = 0
        let transactionalStore = NativePersistenceStore.ephemeral(
            fileURL: stateURL,
            writeData: { data, url in
                writeCount += 1
                if writeCount == 3 {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        let model = AppModel(
            persistenceStore: transactionalStore,
            scoreStorageDirectory: scoreDirectory,
            scoreFileRemover: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        model.enterGuestDemo(presentTutorial: false)
        let storedURL = try XCTUnwrap(model.scores.first.flatMap { model.storedScoreFileURL(for: $0) })

        model.deleteScore(id: score.id)

        XCTAssertEqual(writeCount, 3)
        XCTAssertEqual(model.scores.first?.id, score.id)
        XCTAssertEqual(model.sessions.first?.attachedScoreID, score.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't remove the local score file or restore its saved state. The score is still open; export your data before closing the app."
            )
        )
    }

    @MainActor
    func testClearingLocalPracticeDataRemovesImportedScoreFiles() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)

        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Local score")
        let fileName = try XCTUnwrap(model.scores.first?.localFileName)
        let storedURL = scoreDirectory.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        model.clearLocalPracticeData()

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scoreDirectory.path))
    }

    @MainActor
    func testFailedPhotoImportRemovesCopiedScoreFile() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)

        XCTAssertThrowsError(try model.importPhotoScore(data: Data("not an image".utf8), preferredName: "Broken score"))

        XCTAssertTrue(model.scores.isEmpty)
        let storedFiles = (try? FileManager.default.contentsOfDirectory(at: scoreDirectory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(storedFiles.isEmpty)
    }

    @MainActor
    func testPDFOverPageLimitIsRejectedWithoutLeavingCopiedFile() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneOversized-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        let pdfData = makePDFData(pageCount: 33)
        try pdfData.write(to: sourceURL, options: [.atomic])
        XCTAssertEqual(PDFDocument(data: pdfData)?.pageCount, 33, "Regression fixture must be a real 33-page PDF.")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)

        XCTAssertThrowsError(try model.importScore(from: sourceURL)) { error in
            XCTAssertEqual(error as? NativeScoreImportService.ImportError, .tooManyPages(maximum: 32))
        }

        XCTAssertTrue(model.scores.isEmpty)
        let storedFiles = (try? FileManager.default.contentsOfDirectory(at: scoreDirectory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(storedFiles.isEmpty, "Rejected PDFs must be removed from imported-score storage.")
    }

    @MainActor
    func testPDFOverPageLimitReportsCleanupFailureWhenCopiedFileCannotBeRemoved() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneOversized-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        try makePDFData(pageCount: 33).write(to: sourceURL, options: [.atomic])
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            scoreFileRemover: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        model.enterGuestDemo(presentTutorial: false)

        XCTAssertThrowsError(try model.importScore(from: sourceURL)) { error in
            XCTAssertEqual(error as? NativeScoreImportService.ImportError, .cleanupFailed)
            XCTAssertTrue(error.localizedDescription.contains("copied file remains"))
        }

        XCTAssertTrue(model.scores.isEmpty)
        let storedFiles = (try? FileManager.default.contentsOfDirectory(at: scoreDirectory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertEqual(storedFiles.count, 1, "The failed removal is surfaced instead of being reported as successful cleanup.")
    }

    @MainActor
    func testClearLocalPracticeDataFailureKeepsModelAndFile() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(
            persistenceStore: store,
            scoreStorageDirectory: scoreDirectory,
            scoreFileRemover: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        model.enterGuestDemo(presentTutorial: false)
        model.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Protected score")
        let storedURL = try XCTUnwrap(model.scores.first.flatMap { model.storedScoreFileURL(for: $0) })

        model.clearLocalPracticeData()

        XCTAssertEqual(model.scores.count, 1)
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't remove your imported score files, so your local practice data was kept. Try again."
            )
        )

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        restored.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(restored.scores.count, 1, "A score-cleanup failure must restore the snapshot cleared earlier in the transaction.")
        XCTAssertEqual(restored.sessions.count, 1)
    }

    @MainActor
    func testPersistenceClearFailureKeepsModelFilesAndRestorableSnapshot() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let store = NativePersistenceStore.ephemeral(
            fileURL: stateURL,
            removeItem: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        let model = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        model.enterGuestDemo(presentTutorial: false)
        model.sessions = [makeSession(name: "Persistent recording", cents: [-2, 0, 3])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Persistent score")
        let score = try XCTUnwrap(model.scores.first)
        let storedURL = try XCTUnwrap(model.storedScoreFileURL(for: score))
        model.flushPendingPersistence()
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))

        model.clearLocalPracticeData()

        XCTAssertEqual(model.scores.first?.id, score.id)
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't clear its saved local data, so your practice data was kept. Try again."
            )
        )

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        restored.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(restored.scores.first?.id, score.id, "Failed clear must not claim success before stale state can reappear on launch.")
        XCTAssertEqual(restored.sessions.count, 1)
    }

    @MainActor
    func testAccountDeletionRemovesImportedScoreFiles() async throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            authService: AuthService(session: makeStubSession(), readSessionPayload: { nil })
        )
        model.enterGuestDemo(presentTutorial: false)

        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Disposable score")
        let fileName = try XCTUnwrap(model.scores.first?.localFileName)
        let storedURL = scoreDirectory.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        await model.deleteAccount()

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scoreDirectory.path))
    }

    @MainActor
    func testLocalPersistenceRestoresLiveSessionsSettingsScoresAndMetronome() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        model.enterGuestDemo(presentTutorial: false)

        model.selectedInstrumentId = "horn"
        model.referencePitchHz = 442.0
        model.setTempo(108)
        model.setMetronomeVolume(0.7)
        model.sessions = [makeSession(name: "Saved recording", cents: [-2, 0, 3])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Saved score")
        model.flushPendingPersistence()

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        restored.enterGuestDemo(presentTutorial: false)

        XCTAssertEqual(restored.selectedInstrumentId, "horn")
        XCTAssertEqual(restored.referencePitchHz, 442.0)
        XCTAssertEqual(restored.metronome.bpm, 108)
        XCTAssertEqual(restored.metronome.volume, 0.7, accuracy: 0.001)
        XCTAssertFalse(restored.metronome.muted)
        XCTAssertFalse(restored.metronome.visualOnly)
        XCTAssertEqual(restored.sessions.count, 1)
        XCTAssertEqual(restored.sessions.first?.source, .live)
        XCTAssertEqual(restored.scores.count, 1)
        XCTAssertEqual(restored.scores.first?.sourceKind, .photos)
        XCTAssertEqual(restored.activeScoreID, restored.scores.first?.id)
    }

    @MainActor
    func testLegacySilentMetronomeDefaultsMigrateToAudibleDefaults() {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        var legacyMetronome = MetronomeSettings()
        legacyMetronome.muted = true
        legacyMetronome.visualOnly = true
        legacyMetronome.volume = 0
        store.save(
            NativeLocalSnapshot(
                selectedInstrumentId: "trumpet",
                referencePitchHz: 440,
                sessions: [],
                scores: [],
                activeScoreID: nil,
                metronome: legacyMetronome,
                metronomeDefaultsVersion: 1
            )
        )

        let restored = AppModel(persistenceStore: store)
        restored.enterGuestDemo(presentTutorial: false)

        XCTAssertFalse(restored.metronome.muted)
        XCTAssertFalse(restored.metronome.visualOnly)
        XCTAssertEqual(restored.metronome.volume, 0.6, accuracy: 0.001)
    }

    @MainActor
    func testShippingRestoreQuarantinesLegacyFixtureSessionsAndScores() {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let sampleSession = makeSession(name: "Old test recording", cents: [0], source: .sample)
        let sampleScore = makeSampleScore()
        store.save(
            NativeLocalSnapshot(
                selectedInstrumentId: "trumpet",
                referencePitchHz: 440,
                sessions: [sampleSession],
                scores: [sampleScore],
                activeScoreID: sampleScore.id,
                metronome: MetronomeSettings(),
                metronomeDefaultsVersion: 2
            )
        )

        let restored = AppModel(persistenceStore: store)
        restored.enterGuestDemo(presentTutorial: false)

        XCTAssertTrue(restored.sessions.isEmpty)
        XCTAssertTrue(restored.scores.isEmpty)
        XCTAssertNil(restored.activeScoreID)
    }

    // MARK: - Play-Along web parity

    func testPlayAlongUsesTwoSecondDefaultAndDoesNotAdvanceEarly() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"])

        XCTAssertEqual(grader.holdDurationMs, 2_000)
        for timestamp in stride(from: 0, through: 1_750, by: 250) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: timestamp))
        }
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 1_999))

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
        XCTAssertEqual(grader.heldFraction, 1_999.0 / 2_000.0, accuracy: 0.000_1)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 2_000))
        XCTAssertEqual(grader.noteGrades.count, 1)
        XCTAssertEqual(grader.currentNoteName, "D")
    }

    func testPlayAlongRatingUsesWebCentsThresholds() {
        XCTAssertEqual(PlayAlongNoteRating(cents: 5), .excellent)
        XCTAssertEqual(PlayAlongNoteRating(cents: -5), .excellent)
        XCTAssertEqual(PlayAlongNoteRating(cents: 15), .close)
        XCTAssertEqual(PlayAlongNoteRating(cents: -15), .close)
        XCTAssertEqual(PlayAlongNoteRating(cents: 15.1), .off)
        XCTAssertEqual(PlayAlongNoteRating(cents: -30), .off)
        XCTAssertEqual(PlayAlongNoteRating(cents: nil), .missed)
        XCTAssertEqual(PlayAlongNoteRating(cents: .nan), .missed)
    }

    func testWeakTransitionAnalyzerSkipsRepeatedAndEnharmonicUnisons() {
        for notes in [
            ["C", "C", "C", "C"],
            ["F", "E#", "F", "E#"],
            ["C#", "Db", "C#", "Db"],
            ["F♯", "Gb", "F♯", "Gb"],
        ] {
            let attempt = makePlayAlongAttempt(notes: notes, rating: .missed)
            XCTAssertNil(
                WeakTransitionAnalyzer.insight(from: [attempt], minimumEvidence: 1),
                "Repeated or enharmonic-equivalent pitch classes must not become transition candidates: \(notes)"
            )
        }
    }

    func testWeakTransitionAnalyzerStillBuildsRealTransitionDrill() throws {
        let attempts = (0..<3).map { _ in
            makePlayAlongAttempt(notes: ["C", "D"], rating: .off)
        }

        let insight = try XCTUnwrap(WeakTransitionAnalyzer.insight(from: attempts))
        XCTAssertEqual(insight.fromNote, "C")
        XCTAssertEqual(insight.toNote, "D")
        XCTAssertEqual(insight.evidenceCount, 3)
        XCTAssertEqual(insight.exercise.writtenNotes, ["C", "D", "C", "D", "C", "D"])
    }

    func testSharedPlayAlongContractFixtureMatchesNativeScorer() throws {
        let data = try Data(contentsOf: try sharedFixtureURL(named: "play_along_contract.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let policy = try XCTUnwrap(root["policy"] as? [String: Any])
        let grader = PlayAlongGrader(writtenNotes: ["C"])
        XCTAssertEqual(grader.holdDurationMs, policy["hold_ms"] as? Int)
        XCTAssertEqual(grader.minimumConfidence, policy["minimum_confidence"] as? Double)
        XCTAssertEqual(grader.minimumSamples, policy["minimum_samples"] as? Int)
        XCTAssertEqual(grader.attackTrimMs, policy["attack_trim_ms"] as? Int)
        XCTAssertEqual(grader.maximumDropoutMs, policy["maximum_dropout_ms"] as? Int)

        for item in try XCTUnwrap(root["rating_cases"] as? [[String: Any]]) {
            let cents = item["cents"] is NSNull ? nil : item["cents"] as? Double
            let rating = PlayAlongNoteRating(cents: cents)
            XCTAssertEqual(rating.rawValue, item["expected_rating"] as? String, item["name"] as? String ?? "rating")
            XCTAssertEqual(rating.isCentered, item["expected_centered"] as? Bool)
            XCTAssertEqual(rating.isAccepted, item["expected_accepted"] as? Bool)
        }

        for item in try XCTUnwrap(root["star_cases"] as? [[String: Any]]) {
            let percent = item["in_tune_percent"] is NSNull ? nil : item["in_tune_percent"] as? Double
            XCTAssertEqual(PlayAlongGrade.starRating(inTunePercentage: percent), item["expected_stars"] as? Int)
        }

        for item in try XCTUnwrap(root["summary_cases"] as? [[String: Any]]) {
            let ratings = try XCTUnwrap(item["ratings"] as? [[String: Any]])
            let grades = ratings.enumerated().map { index, rating -> PlayAlongNoteGrade in
                let cents = rating["cents"] is NSNull ? nil : rating["cents"] as? Double
                let expectedRating = PlayAlongNoteRating(rawValue: rating["rating"] as? String ?? "")
                return PlayAlongNoteGrade(
                    writtenNoteName: "N\(index)",
                    medianCents: cents,
                    sampleCount: cents == nil ? 0 : 5,
                    rating: expectedRating
                )
            }
            let summary = PlayAlongGrade(expectedNoteCount: item["expected_total"] as? Int ?? 0, noteGrades: grades)
            XCTAssertEqual(summary.totalNotes, item["expected_total"] as? Int)
            XCTAssertEqual(summary.notesPlayed, item["expected_hit"] as? Int)
            XCTAssertEqual(summary.inTuneNotes, item["expected_in_tune"] as? Int)
            XCTAssertEqual(summary.inTunePercentage, item["expected_in_tune_percent"] as? Int)
            XCTAssertEqual(summary.averageAbsoluteCents, item["expected_average_abs_cents"] as? Double)
            XCTAssertEqual(summary.stars, item["expected_stars"] as? Int)
        }

        for item in try XCTUnwrap(root["temporal_cases"] as? [[String: Any]]) {
            let name = item["name"] as? String ?? "temporal case"
            let notes = try XCTUnwrap(item["notes"] as? [String])
            let frames = try XCTUnwrap(item["frames"] as? [[String: Any]])
            let checkpoints = try XCTUnwrap(item["checkpoints"] as? [[String: Any]])
            var grader = PlayAlongGrader(writtenNotes: notes)

            for (index, frame) in frames.enumerated() {
                let note = frame["written_note"] is NSNull ? nil : frame["written_note"] as? String
                let cents = frame["cents"] is NSNull ? nil : (frame["cents"] as? NSNumber)?.doubleValue
                grader.feed(makePlayAlongFrame(
                    note: note,
                    cents: cents,
                    timestampMs: try XCTUnwrap(frame["timestamp_ms"] as? Int),
                    confidence: try XCTUnwrap((frame["confidence"] as? NSNumber)?.doubleValue),
                    frequencyHz: note == nil ? nil : 440
                ))

                for checkpoint in checkpoints where checkpoint["after_frame_index"] as? Int == index {
                    let expectedNote = checkpoint["expected_current_note"] is NSNull ? nil : checkpoint["expected_current_note"] as? String
                    XCTAssertEqual(grader.currentNoteName, expectedNote, name)
                    XCTAssertEqual(
                        grader.heldFraction * Double(grader.holdDurationMs),
                        try XCTUnwrap((checkpoint["expected_held_ms"] as? NSNumber)?.doubleValue),
                        accuracy: 0.001,
                        name
                    )
                    XCTAssertEqual(grader.noteGrades.count, checkpoint["expected_result_count"] as? Int, name)
                    XCTAssertEqual(grader.isComplete, checkpoint["expected_done"] as? Bool, name)
                }
            }

            let expectedResults = try XCTUnwrap(item["expected_results"] as? [[String: Any]])
            XCTAssertEqual(grader.noteGrades.count, expectedResults.count, name)
            for (actual, expected) in zip(grader.noteGrades, expectedResults) {
                XCTAssertEqual(actual.writtenNoteName, expected["name"] as? String, name)
                XCTAssertEqual(actual.medianCents, (expected["median_cents"] as? NSNumber)?.doubleValue, name)
                XCTAssertEqual(actual.sampleCount, expected["sample_count"] as? Int, name)
                XCTAssertEqual(actual.rating.rawValue, expected["rating"] as? String, name)
            }
        }
    }

    func testPlayAlongOnlyAdvancesWhenPostAttackMedianIsAccepted() {
        var edge = PlayAlongGrader(writtenNotes: ["C", "D"], holdDurationMs: 300, minimumSamples: 3, attackTrimMs: 0)
        for timestamp in stride(from: 0, through: 300, by: 100) {
            edge.feed(makePlayAlongFrame(note: "C", cents: 15, timestampMs: timestamp))
        }
        XCTAssertEqual(edge.currentNoteName, "D")
        XCTAssertEqual(edge.noteGrades.first?.rating, .close)

        var outside = PlayAlongGrader(writtenNotes: ["C", "D"], holdDurationMs: 300, minimumSamples: 3, attackTrimMs: 0)
        for timestamp in stride(from: 0, through: 300, by: 100) {
            outside.feed(makePlayAlongFrame(note: "C", cents: 15.1, timestampMs: timestamp))
        }
        XCTAssertEqual(outside.currentNoteName, "C")
        XCTAssertTrue(outside.noteGrades.isEmpty)
        XCTAssertEqual(outside.heldFraction, 0)

        for timestamp in stride(from: 1_000, through: 1_300, by: 100) {
            outside.feed(makePlayAlongFrame(note: "C", cents: 0, timestampMs: timestamp))
        }
        XCTAssertEqual(outside.currentNoteName, "D")
        XCTAssertEqual(outside.noteGrades.count, 1)
        XCTAssertEqual(outside.noteGrades.first?.rating, .excellent)
    }

    func testSharedReferenceToneDroneAndTranspositionFixturesMatchNativeMath() throws {
        let referenceData = try Data(contentsOf: try sharedFixtureURL(named: "reference_tone_cases.json"))
        let referenceCases = try XCTUnwrap(JSONSerialization.jsonObject(with: referenceData) as? [[String: Any]])
        for item in referenceCases {
            let midi = try writtenMIDI(from: try XCTUnwrap(item["written_note"] as? String))
            let semitones = try XCTUnwrap(item["interval_semitones"] as? Int)
            let interval = try XCTUnwrap(TuningInterval(rawValue: semitones))
            let frequency = try XCTUnwrap(PracticePitchMath.frequency(
                writtenMIDI: midi,
                interval: interval,
                instrumentID: try XCTUnwrap(item["instrument_id"] as? String),
                referencePitchHz: try XCTUnwrap(item["reference_pitch_hz"] as? Double)
            ))
            XCTAssertEqual(frequency, try XCTUnwrap(item["expected_frequency_hz"] as? Double), accuracy: 0.000_1)
        }

        let droneData = try Data(contentsOf: try sharedFixtureURL(named: "drone_dyad_cases.json"))
        let droneCases = try XCTUnwrap(JSONSerialization.jsonObject(with: droneData) as? [[String: Any]])
        for item in droneCases {
            let frequencies = try XCTUnwrap(PracticePitchMath.frequencies(
                writtenMIDI: try writtenMIDI(from: try XCTUnwrap(item["written_note"] as? String)),
                interval: try XCTUnwrap(TuningInterval(rawValue: try XCTUnwrap(item["interval_semitones"] as? Int))),
                instrumentID: try XCTUnwrap(item["instrument_id"] as? String),
                referencePitchHz: try XCTUnwrap(item["reference_pitch_hz"] as? Double)
            ))
            let expected = try XCTUnwrap(item["expected_frequencies_hz"] as? [Double])
            XCTAssertEqual(frequencies.count, expected.count)
            for (actual, target) in zip(frequencies, expected) {
                XCTAssertEqual(actual, target, accuracy: 0.000_1)
            }
        }

        let transpositionData = try Data(contentsOf: try sharedFixtureURL(named: "transposition_cases.json"))
        let transpositionCases = try XCTUnwrap(JSONSerialization.jsonObject(with: transpositionData) as? [[String: Any]])
        for item in transpositionCases {
            let instrumentID = try XCTUnwrap(item["instrument_id"] as? String)
            let expectedWritten = try XCTUnwrap(item["expected_written_midi"] as? Int)
            XCTAssertEqual(
                PracticePitchMath.concertMIDI(forWrittenMIDI: expectedWritten, instrumentID: instrumentID),
                item["concert_midi"] as? Int
            )
            let range = InstrumentAcousticRange.forInstrument(instrumentID)
            XCTAssertEqual(range.minimumHz, try XCTUnwrap(item["expected_min_frequency_hz"] as? Double))
            XCTAssertEqual(range.maximumHz, try XCTUnwrap(item["expected_max_frequency_hz"] as? Double))
        }
    }

    func testAllSelectedInstrumentRangesGatePitchBeforeNoteAndRecordingState() {
        let expected: [String: InstrumentAcousticRange] = [
            "trumpet": .init(minimumHz: 130, maximumHz: 1_500),
            "horn": .init(minimumHz: 80, maximumHz: 1_200),
            "trombone": .init(minimumHz: 50, maximumHz: 700),
            "euphonium": .init(minimumHz: 55, maximumHz: 800),
            "tuba": .init(minimumHz: 30, maximumHz: 500),
        ]
        for (instrument, range) in expected {
            XCTAssertEqual(InstrumentAcousticRange.forInstrument(instrument), range)
            XCTAssertEqual(NativePitchDetector.acousticRange(for: instrument), range)
            for rejectedFrequency in [range.minimumHz.nextDown, range.maximumHz.nextUp] {
                let frame = PitchFrame.detected(
                    timestampMs: 0,
                    frequencyHz: rejectedFrequency,
                    confidence: 0.99,
                    rms: 0.1,
                    instrumentId: instrument,
                    referencePitchHz: 440
                )
                XCTAssertNil(frame.writtenNoteName, "\(instrument) at \(rejectedFrequency)")
                XCTAssertNil(frame.writtenOctave)
                XCTAssertNil(frame.centsDeviation)
                XCTAssertFalse(frame.isValidForRecording)
            }
            for acceptedFrequency in [range.minimumHz, range.maximumHz] {
                let frame = PitchFrame.detected(
                    timestampMs: 0,
                    frequencyHz: acceptedFrequency,
                    confidence: 0.99,
                    rms: 0.1,
                    instrumentId: instrument,
                    referencePitchHz: 440
                )
                XCTAssertNotNil(frame.writtenNoteName, "\(instrument) at \(acceptedFrequency)")
                XCTAssertNotNil(frame.centsDeviation)
                XCTAssertTrue(frame.isValidForRecording)
            }
        }
    }

    func testSharedNoteSegmentationFixtureMatchesNativeEvents() throws {
        let data = try Data(contentsOf: try sharedFixtureURL(named: "note_segmentation_cases.json"))
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        for item in cases {
            let frames = try XCTUnwrap(item["frames"] as? [[String: Any]]).map(makePitchFrame(from:))
            let events = NativePitchAnalytics.segmentNoteEvents(frames: frames)
            let expected = try XCTUnwrap(item["expected_events"] as? [[String: Any]])
            XCTAssertEqual(events.count, expected.count, item["name"] as? String ?? "segmentation")
            for (actual, target) in zip(events, expected) {
                XCTAssertEqual(actual.writtenNote, target["written_note"] as? String)
                XCTAssertEqual(actual.writtenOctave, target["written_octave"] as? Int)
                XCTAssertEqual(actual.durationMs, target["duration_ms"] as? Int)
                XCTAssertEqual(actual.sampleCount, target["sample_count"] as? Int)
                XCTAssertEqual(actual.averageSignedCents, try XCTUnwrap(target["avg_signed_cents"] as? Double), accuracy: 0.000_001)
                XCTAssertEqual(actual.medianCents, try XCTUnwrap(target["median_cents"] as? Double), accuracy: 0.000_001)
                XCTAssertEqual(actual.standardDeviationCents, try XCTUnwrap(target["stddev_cents"] as? Double), accuracy: 0.000_001)
                XCTAssertEqual(actual.inTunePercentage, try XCTUnwrap(target["in_tune_percentage"] as? Double), accuracy: 0.000_001)
                XCTAssertEqual(actual.stabilityScore, try XCTUnwrap(target["stability_score"] as? Double), accuracy: 0.000_001)
            }
        }
    }

    func testSharedDurationWeightedAnalyticsAndRecommendationsMatchNativeRules() throws {
        let analyticsData = try Data(contentsOf: try sharedFixtureURL(named: "analytics_cases.json"))
        let analyticsCases = try XCTUnwrap(JSONSerialization.jsonObject(with: analyticsData) as? [[String: Any]])
        for item in analyticsCases {
            let label = try XCTUnwrap(item["note_label"] as? String)
            let (note, octave) = try noteAndOctave(from: label)
            let events = try XCTUnwrap(item["events"] as? [[String: Any]]).map { event in
                NativeNoteEvent(
                    writtenNote: note,
                    writtenOctave: octave,
                    startedAtMs: 0,
                    endedAtMs: event["duration_ms"] as? Int ?? 0,
                    durationMs: event["duration_ms"] as? Int ?? 0,
                    sampleCount: 10,
                    averageSignedCents: event["avg_signed_cents"] as? Double ?? 0,
                    averageAbsoluteCents: event["avg_abs_cents"] as? Double ?? 0,
                    medianCents: event["avg_signed_cents"] as? Double ?? 0,
                    standardDeviationCents: event["stddev_cents"] as? Double ?? 0,
                    minimumCents: event["avg_signed_cents"] as? Double ?? 0,
                    maximumCents: event["avg_signed_cents"] as? Double ?? 0,
                    inTunePercentage: event["in_tune_percentage"] as? Double ?? 0,
                    stabilityScore: event["stability_score"] as? Double ?? 90
                )
            }
            let stats = try XCTUnwrap(NativePitchAnalytics.calculateNoteStatistics(events: events).first)
            XCTAssertEqual(stats.trend, item["expected_trend"] as? String)
            if let minimum = item["expected_problem_severity_min"] as? Double {
                XCTAssertGreaterThanOrEqual(stats.problemSeverity, minimum)
            }
            if let maximum = item["expected_problem_severity_max"] as? Double {
                XCTAssertLessThanOrEqual(stats.problemSeverity, maximum)
            }
        }

        let recommendationData = try Data(contentsOf: try sharedFixtureURL(named: "recommendation_cases.json"))
        let recommendationCases = try XCTUnwrap(JSONSerialization.jsonObject(with: recommendationData) as? [[String: Any]])
        for item in recommendationCases {
            let values = try XCTUnwrap(item["note_stats"] as? [String: Any])
            let label = try XCTUnwrap(values["note_label"] as? String)
            let (note, octave) = try noteAndOctave(from: label)
            let signed = values["avg_signed_cents"] as? Double ?? 0
            let absolute = values["avg_abs_cents"] as? Double ?? 0
            let deviation = values["stddev_cents"] as? Double ?? 0
            let inTune = values["in_tune_percentage"] as? Double ?? 0
            let stability = values["stability_score"] as? Double ?? 100
            let durationSeconds = values["duration_seconds"] as? Double ?? 0
            let trend = NativePitchAnalytics.classifyTrend(
                averageSignedCents: signed,
                standardDeviationCents: deviation,
                stabilityScore: stability
            )
            let severity = NativePitchAnalytics.classifyProblem(
                averageAbsoluteCents: absolute,
                inTunePercentage: inTune
            )
            let stats = NativeNoteStatistics(
                writtenNote: note,
                writtenOctave: octave,
                noteLabel: label,
                averageSignedCents: signed,
                averageAbsoluteCents: absolute,
                medianCents: signed,
                standardDeviationCents: deviation,
                inTunePercentage: inTune,
                durationMs: durationSeconds * 1_000,
                sampleCount: 10,
                eventCount: 1,
                stabilityScore: stability,
                trend: trend,
                severity: severity,
                problemSeverity: 0
            )
            let recommendation = NativePitchAnalytics.recommendation(for: stats)
            XCTAssertEqual(recommendation.category, item["expected_category"] as? String)
            XCTAssertEqual(recommendation.relatedNote, item["expected_related_note"] as? String)
        }
    }

    func testPitchTrendAndRecommendationUseInclusiveFiveCentCenteredBoundary() {
        let cases: [(cents: Double, trend: String, recommendation: String)] = [
            (-5.01, "Mostly flat", "Flat tendency"),
            (-5.0, "Centered", "Good progress"),
            (5.0, "Centered", "Good progress"),
            (5.01, "Mostly sharp", "Sharp tendency"),
        ]

        for item in cases {
            let trend = NativePitchAnalytics.classifyTrend(
                averageSignedCents: item.cents,
                standardDeviationCents: 0,
                stabilityScore: 100
            )
            XCTAssertEqual(trend, item.trend, "Unexpected trend at \(item.cents) cents")
            let stats = NativeNoteStatistics(
                writtenNote: "C",
                writtenOctave: 4,
                noteLabel: "C4",
                averageSignedCents: item.cents,
                averageAbsoluteCents: abs(item.cents),
                medianCents: item.cents,
                standardDeviationCents: 0,
                inTunePercentage: 100,
                durationMs: 3_000,
                sampleCount: 10,
                eventCount: 1,
                stabilityScore: 100,
                trend: trend,
                severity: "excellent",
                problemSeverity: 0
            )
            XCTAssertEqual(
                NativePitchAnalytics.recommendation(for: stats).category,
                item.recommendation,
                "Unexpected recommendation at \(item.cents) cents"
            )
        }
    }

    func testPitchStatisticsIgnoreNonpositiveDurationsUnlessEveryEventNeedsFallback() throws {
        func event(durationMs: Int, signed: Double, absolute: Double? = nil) -> NativeNoteEvent {
            NativeNoteEvent(
                writtenNote: "C",
                writtenOctave: 4,
                startedAtMs: 0,
                endedAtMs: durationMs,
                durationMs: durationMs,
                sampleCount: 1,
                averageSignedCents: signed,
                averageAbsoluteCents: absolute ?? abs(signed),
                medianCents: signed,
                standardDeviationCents: 0,
                minimumCents: signed,
                maximumCents: signed,
                inTunePercentage: 100,
                stabilityScore: 100
            )
        }

        let mixed = try XCTUnwrap(NativePitchAnalytics.calculateNoteStatistics(events: [
            event(durationMs: 1_000, signed: 10),
            event(durationMs: 0, signed: 90),
            event(durationMs: -500, signed: -90),
        ]).first)
        XCTAssertEqual(mixed.averageSignedCents, 10, accuracy: 0.000_001)
        XCTAssertEqual(mixed.averageAbsoluteCents, 10, accuracy: 0.000_001)
        XCTAssertEqual(mixed.durationMs, 1_000, accuracy: 0.000_001)

        let fallback = try XCTUnwrap(NativePitchAnalytics.calculateNoteStatistics(events: [
            event(durationMs: 0, signed: 10),
            event(durationMs: 0, signed: 30),
        ]).first)
        XCTAssertEqual(fallback.averageSignedCents, 20, accuracy: 0.000_001)
        XCTAssertEqual(fallback.averageAbsoluteCents, 20, accuracy: 0.000_001)
        XCTAssertEqual(fallback.durationMs, 0, accuracy: 0.000_001)
    }

    func testProblemScoreRoundingMatchesSharedHalfUpCases() throws {
        let data = try Data(contentsOf: try sharedFixtureURL(named: "problem_score_rounding_cases.json"))
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        for item in cases {
            let values = try XCTUnwrap(item["note_stats"] as? [String: Any])
            let averageAbsolute = try XCTUnwrap((values["avg_abs_cents"] as? NSNumber)?.doubleValue)
            let deviation = try XCTUnwrap((values["stddev_cents"] as? NSNumber)?.doubleValue)
            let inTune = try XCTUnwrap((values["in_tune_percentage"] as? NSNumber)?.doubleValue)
            let event = NativeNoteEvent(
                writtenNote: "C",
                writtenOctave: 4,
                startedAtMs: 0,
                endedAtMs: 1_000,
                durationMs: 1_000,
                sampleCount: 10,
                averageSignedCents: averageAbsolute,
                averageAbsoluteCents: averageAbsolute,
                medianCents: averageAbsolute,
                standardDeviationCents: deviation,
                minimumCents: averageAbsolute,
                maximumCents: averageAbsolute,
                inTunePercentage: inTune,
                stabilityScore: 100
            )
            let stats = try XCTUnwrap(NativePitchAnalytics.calculateNoteStatistics(events: [event]).first)
            XCTAssertEqual(
                stats.problemSeverity,
                try XCTUnwrap((item["expected_problem_severity"] as? NSNumber)?.doubleValue),
                accuracy: 0.000_001,
                item["name"] as? String ?? "rounding case"
            )
        }
    }

    func testPlayAlongExerciseCatalogIncludesAllGroupedScalesAndPracticePatterns() {
        let major = PlayAlongExercise.library.filter { $0.category == .major }
        let minor = PlayAlongExercise.library.filter { $0.category == .naturalMinor }
        let patterns = PlayAlongExercise.library.filter { $0.category == .practicePattern }
        XCTAssertEqual(PlayAlongExercise.defaultExercise.id, "cmaj")
        XCTAssertEqual(major.count, 12)
        XCTAssertEqual(minor.count, 12)
        XCTAssertEqual(patterns.count, 3)
        XCTAssertEqual(PlayAlongExercise.library.count, 27)
        XCTAssertEqual(Set(PlayAlongExercise.library.map(\.id)).count, PlayAlongExercise.library.count)
        XCTAssertTrue(["cmaj", "fmaj", "gmaj", "arpeggio", "chromatic", "longtones"].allSatisfy { id in
            PlayAlongExercise.library.contains { $0.id == id }
        })
        XCTAssertFalse(PlayAlongExercise.library.contains { $0.writtenNotes.isEmpty })
    }

    func testPlayAlongScaleIntervalsMatchMajorAndNaturalMinorPatterns() throws {
        let expected: [PlayAlongExerciseCategory: [Int]] = [
            .major: [0, 2, 4, 5, 7, 9, 11, 0],
            .naturalMinor: [0, 2, 3, 5, 7, 8, 10, 0],
        ]
        for exercise in PlayAlongExercise.library where exercise.category != .practicePattern {
            let tonic = try XCTUnwrap(testPitchClass(exercise.writtenNotes[0]), exercise.title)
            let intervals = try exercise.writtenNotes.map { note in
                let pitchClass = try XCTUnwrap(testPitchClass(note), "Unsupported note spelling \(note) in \(exercise.title)")
                return (pitchClass - tonic + 12) % 12
            }
            XCTAssertEqual(intervals, expected[exercise.category], exercise.title)
            XCTAssertEqual(exercise.writtenNotes.first, exercise.writtenNotes.last, exercise.title)
        }
    }

    func testEnsembleSummaryUsesExplicitViewerCapabilitiesWithoutJoinCodeInference() throws {
        let decoder = JSONDecoder()
        let owner = try decoder.decode(
            EnsembleSummary.self,
            from: Data(#"{"id":1,"name":"Wind Ensemble","director_user_id":42,"join_code":null,"viewer_role":"owner","viewer_can_leave":false,"viewer_can_manage":true,"created_at":"2026-07-12T12:00:00.123456","updated_at":"2026-07-12T12:00:00.123456"}"#.utf8)
        )
        let member = try decoder.decode(
            EnsembleSummary.self,
            from: Data(#"{"id":2,"name":"Brass Choir","join_code":"VISIBLE-BUT-NOT-AUTHZ","viewer_role":"assistant","viewer_can_leave":true,"viewer_can_manage":false,"created_at":"2026-07-12T12:00:00","updated_at":"2026-07-12T12:00:00"}"#.utf8)
        )

        XCTAssertFalse(owner.canLeave)
        XCTAssertTrue(member.canLeave)
        XCTAssertEqual(owner.viewerRoleLabel, "Class owner")
        XCTAssertEqual(member.viewerRoleLabel, "Assistant")
    }

    func testAPIClientNormalizesBackendValidationMessagesAndPreservesCancellation() async throws {
        let session = makeStubSession()
        let client = APIClient(session: session)
        let baseURL = AppConfig.approvedProductionAPIOrigin
        let config = AppConfig(environment: .staging, apiBaseURL: baseURL, supabaseURL: nil, supabasePublishableKey: nil)

        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"detail":[{"loc":["body","code"],"msg":"Class code must contain 4-16 characters","type":"value_error"},{"loc":["body","instrument_id"],"msg":"Instrument is not supported","type":"value_error"}]}"#.utf8)
            return .init(response: response, data: data)
        }
        do {
            let _: TestAPIResponse = try await client.request(TestAPIResponse.self, path: "/api/ensemble/join", config: config)
            XCTFail("Expected validation failure")
        } catch let error as UserVisibleError {
            XCTAssertEqual(
                error,
                .apiRequestFailed(
                    statusCode: 422,
                    message: NativeLocalization.string("The class service could not complete this request.")
                )
            )
        }

        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        do {
            let _: TestAPIResponse = try await client.request(TestAPIResponse.self, path: "/api/ensemble/groups", config: config)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: view-lifecycle cancellation is not surfaced as a network error.
        }
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testClassJoinAndLeaveUseExpectedAPIContractAndBearer() async throws {
        let session = makeStubSession()
        let client = APIClient(session: session)
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            apiClient: client,
            classAccessTokenProvider: { _ in "fresh-token" }
        )
        model.config = AppConfig(
            environment: .staging,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: nil,
            supabasePublishableKey: nil
        )
        nonisolated(unsafe) var capturedRequests: [CapturedRequest] = []
        StubURLProtocol.handler = { request in
            capturedRequests.append(
                CapturedRequest(
                    method: request.httpMethod ?? "GET",
                    path: request.url?.path ?? "",
                    authorization: request.value(forHTTPHeaderField: "Authorization"),
                    body: requestBodyData(request)
                )
            )
            let path = request.url!.path
            let data: Data
            if request.httpMethod == "POST" {
                data = Data(#"{"joined":true,"group_id":7,"group_name":"Jazz Band"}"#.utf8)
            } else if request.httpMethod == "DELETE" {
                data = Data(#"{"left":true,"group_id":7}"#.utf8)
            } else if path == "/api/ensemble/groups" {
                data = Data(#"[{"id":7,"name":"Jazz Band","viewer_role":"student","viewer_can_leave":true,"viewer_can_manage":false}]"#.utf8)
            } else {
                data = Data()
            }
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: data
            )
        }

        let joined = await model.joinEnsemble(code: " ab cd ")
        XCTAssertTrue(joined)
        XCTAssertEqual(model.ensembles.map(\.id), [7])
        let left = await model.leaveEnsemble(id: 7)
        XCTAssertTrue(left)
        XCTAssertTrue(model.ensembles.isEmpty)

        let post = try XCTUnwrap(capturedRequests.first { $0.method == "POST" })
        XCTAssertEqual(post.path, "/api/ensemble/join")
        XCTAssertEqual(post.authorization, "Bearer fresh-token")
        let body = try XCTUnwrap(post.body)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(payload["code"], "ABCD")
        XCTAssertEqual(payload["instrument_id"], "trumpet")
        let delete = try XCTUnwrap(capturedRequests.first { $0.method == "DELETE" })
        XCTAssertEqual(delete.path, "/api/ensemble/groups/7/membership")
        XCTAssertEqual(delete.authorization, "Bearer fresh-token")
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testClass401LocksPriorAccountDataUntilExplicitGuestEntry() async throws {
        let authService = makeIsolatedAuthService(session: makeStubSession())
        let config = makeAuthConfig()
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-class-expiry-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-class-expiry-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? authService.signOut()
            StubURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: NativeStorageNamespace.account(userID: "class-user").stateFile(basedAt: stateURL))
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        StubURLProtocol.handler = { request in
            let data = Data(#"{"access_token":"class-token","refresh_token":"class-refresh","expires_in":3600,"user":{"id":"class-user","email":"class@example.com"}}"#.utf8)
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: data
            )
        }
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            authService: authService,
            classAccessTokenProvider: { _ in
                throw UserVisibleError.apiRequestFailed(statusCode: 401, message: "expired")
            }
        )
        model.config = config
        model.enterGuestDemo(presentTutorial: false)
        let guestSession = makeSession(name: "Guest session", cents: [0])
        model.sessions = [guestSession]

        await model.signIn(email: "class@example.com", password: "password")
        model.sessions = [makeSession(name: "Private account session", cents: [2])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Private account score")

        await model.loadEnsembles()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertEqual(model.persistenceAccessState, .lockedSignedOut)
        XCTAssertFalse(model.gatewayCompleted)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty)
        model.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(model.persistenceAccessState, .guest)
        XCTAssertEqual(model.sessions.map(\.id), [guestSession.id])
        XCTAssertTrue(model.scores.isEmpty)
    }

    @MainActor
    func testOlderClassLoadCannotOverwritePostJoinAuthoritativeRefresh() async throws {
        let session = makeStubSession()
        let client = APIClient(session: session)
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            apiClient: client,
            classAccessTokenProvider: { _ in "fresh-token" }
        )
        model.config = AppConfig(
            environment: .staging,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: nil,
            supabasePublishableKey: nil
        )
        nonisolated(unsafe) var getCount = 0
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "POST" {
                return .init(response: response, data: Data(#"{"joined":true,"group_id":2,"group_name":"New Class"}"#.utf8))
            }
            getCount += 1
            if getCount == 1 {
                return .init(
                    response: response,
                    data: Data(#"[{"id":1,"name":"Stale Class","viewer_role":"student","viewer_can_leave":true,"viewer_can_manage":false}]"#.utf8),
                    delayNanoseconds: 250_000_000
                )
            }
            return .init(
                response: response,
                data: Data(#"[{"id":2,"name":"New Class","viewer_role":"student","viewer_can_leave":true,"viewer_can_manage":false}]"#.utf8)
            )
        }

        async let staleLoad: Void = model.loadEnsembles()
        try await Task.sleep(nanoseconds: 40_000_000)
        let joined = await model.joinEnsemble(code: "ABCD")
        XCTAssertTrue(joined)
        await staleLoad

        XCTAssertEqual(model.ensembles.map(\.id), [2])
        XCTAssertEqual(model.selectedEnsembleID, 2)
        StubURLProtocol.handler = nil
    }

    func testPlayAlongAdvancesAfterSustainedCorrectWrittenPitchClass() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"], holdDurationMs: 400, minimumSamples: 3, attackTrimMs: 0)

        for timestamp in stride(from: 0, through: 500, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 10, timestampMs: timestamp))
        }

        XCTAssertEqual(grader.noteGrades.count, 1)
        XCTAssertEqual(grader.noteGrades[0].writtenNoteName, "C")
        XCTAssertEqual(grader.noteGrades[0].medianCents ?? .nan, 10, accuracy: 0.001)
        XCTAssertEqual(grader.noteGrades[0].rating, .close)
        XCTAssertEqual(grader.currentNoteName, "D")
    }

    func testPlayAlongDoesNotAdvanceOnBriefTouch() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 100))

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
        XCTAssertEqual(grader.heldFraction, 0.25, accuracy: 0.001)
    }

    func testPlayAlongWrongConfidentNoteResetsHold() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 100))
        grader.feed(makePlayAlongFrame(note: "E", cents: 5, timestampMs: 200))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 300))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 400))

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
        XCTAssertEqual(grader.heldFraction, 0.25, accuracy: 0.001)
    }

    func testPlayAlongToleratesBriefLowConfidenceSilence() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: nil, cents: nil, timestampMs: 100, confidence: 0.1, frequencyHz: nil))
        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 200))
        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 440))
        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 640))

        XCTAssertTrue(grader.isComplete)
        XCTAssertEqual(grader.noteGrades.first?.rating, .close)
    }

    func testPlayAlongPausesVisibleProgressDuringBriefDropout() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 100))
        let beforeDropout = grader.heldFraction
        grader.feed(makePlayAlongFrame(note: nil, cents: nil, timestampMs: 200, confidence: 0.1, frequencyHz: nil))
        let duringDropout = grader.heldFraction
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 250))

        XCTAssertEqual(beforeDropout, 0.25, accuracy: 0.001)
        XCTAssertEqual(duringDropout, beforeDropout, accuracy: 0.001)
        XCTAssertEqual(grader.heldFraction, beforeDropout, accuracy: 0.001)
        XCTAssertTrue(grader.noteGrades.isEmpty)
    }

    func testPlayAlongVoiceOverAnnouncementNamesNextNoteAndCompletion() {
        let exercise = PlayAlongExercise(
            id: "announcement-test",
            title: "Announcement test",
            detail: "Two notes",
            difficulty: "Test",
            category: .practicePattern,
            writtenNotes: ["C", "D"]
        )
        var session = PlayAlongSession(exercise: exercise, holdDurationMs: 100, minimumSamples: 2, attackTrimMs: 0)
        session.feed(makePlayAlongFrame(note: "C", cents: 0, timestampMs: 0))
        session.feed(makePlayAlongFrame(note: "C", cents: 0, timestampMs: 100))

        XCTAssertEqual(playAlongAdvanceAnnouncement(for: session), "Next note is D. Hold it steady for two seconds.")

        session.feed(makePlayAlongFrame(note: "D", cents: 0, timestampMs: 200))
        session.feed(makePlayAlongFrame(note: "D", cents: 0, timestampMs: 300))
        XCTAssertEqual(playAlongAdvanceAnnouncement(for: session), "Exercise complete. Your results are ready.")
    }

    func testInstrumentSetupHasAStableVoiceOverFocusAnnouncement() {
        let announcement = instrumentSetupAccessibilityAnnouncement()
        XCTAssertTrue(announcement.contains("Choose your instrument"))
        XCTAssertTrue(announcement.contains("written notes"))
        XCTAssertFalse(announcement.contains("Step"))
    }

    func testPlayAlongLongSilenceResetsHoldAfterDropoutGrace() {
        var grader = PlayAlongGrader(
            writtenNotes: ["C"],
            holdDurationMs: 400,
            minimumSamples: 3,
            maximumDropoutMs: 250
        )

        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 100))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 500))

        XCTAssertEqual(grader.heldFraction, 0, accuracy: 0.001)

        for timestamp in stride(from: 600, through: 800, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: timestamp))
        }

        XCTAssertFalse(grader.isComplete)
        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
    }

    func testPlayAlongTrimsBrassAttackTransient() {
        var grader = PlayAlongGrader(
            writtenNotes: ["C"],
            holdDurationMs: 400,
            minimumSamples: 3,
            attackTrimMs: 120
        )

        grader.feed(makePlayAlongFrame(note: "C", cents: 45, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 30, timestampMs: 80))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 200))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 320))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 450))

        XCTAssertEqual(grader.noteGrades.first?.medianCents ?? .nan, 4, accuracy: 0.001)
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testPlayAlongMedianRejectsSingleDetectorOutlier() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3, attackTrimMs: 0)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 120))
        grader.feed(makePlayAlongFrame(note: "C", cents: 60, timestampMs: 240))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 360))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 480))

        XCTAssertEqual(grader.noteGrades.first?.medianCents ?? .nan, 5, accuracy: 0.001)
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testPlayAlongIgnoresFramesBelowConfidenceGate() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 300, minimumSamples: 3)

        for timestamp in stride(from: 0, through: 600, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: timestamp, confidence: 0.4))
        }

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
    }

    func testPlayAlongRejectsInvalidOrUnstableCenteredFrames() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 300, minimumSamples: 3)

        for timestamp in stride(from: 0, through: 300, by: 100) {
            let invalidFrame = makePlayAlongFrame(
                note: "C",
                cents: 3,
                timestampMs: timestamp,
                confidence: 0.99,
                isValidForRecording: false
            )
            XCTAssertFalse(invalidFrame.isValidForRecording)
            grader.feed(invalidFrame)
        }

        XCTAssertNil(grader.detectedNoteName)
        XCTAssertNil(grader.detectedCents)
        XCTAssertEqual(grader.heldFraction, 0)
        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")

        for timestamp in stride(from: 1_000, through: 1_300, by: 100) {
            let unstableFrame = makePlayAlongFrame(
                note: "C",
                cents: 0,
                timestampMs: timestamp,
                confidence: 0.99,
                isValidForRecording: true,
                tuningStatus: .unstable
            )
            XCTAssertTrue(unstableFrame.isValidForRecording)
            XCTAssertEqual(unstableFrame.tuningStatus, .unstable)
            grader.feed(unstableFrame)
        }

        XCTAssertNil(grader.detectedNoteName)
        XCTAssertNil(grader.detectedCents)
        XCTAssertEqual(grader.heldFraction, 0)
        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
    }

    func testPlayAlongSkipMarksMissedAndAdvances() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"])

        grader.skipCurrentNote()

        XCTAssertEqual(grader.noteGrades.count, 1)
        XCTAssertEqual(grader.noteGrades[0].rating, .missed)
        XCTAssertNil(grader.noteGrades[0].medianCents)
        XCTAssertEqual(grader.currentNoteName, "D")
    }

    func testPlayAlongCompletesAndSummarizesLikeWebGrader() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"], holdDurationMs: 300, minimumSamples: 3, attackTrimMs: 0)

        for timestamp in stride(from: 0, through: 400, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: timestamp))
        }
        for timestamp in stride(from: 1_000, through: 1_400, by: 100) {
            grader.feed(makePlayAlongFrame(note: "D", cents: 12, timestampMs: timestamp))
        }

        XCTAssertTrue(grader.isComplete)
        let summary = PlayAlongGrade(expectedNoteCount: 2, noteGrades: grader.noteGrades)
        XCTAssertEqual(summary.totalNotes, 2)
        XCTAssertEqual(summary.notesPlayed, 2)
        XCTAssertEqual(summary.inTuneNotes, 1)
        XCTAssertEqual(summary.inTunePercentage, 50)
        XCTAssertEqual(summary.averageAbsoluteCents ?? .nan, 8, accuracy: 0.001)
        XCTAssertEqual(summary.stars, 0)
    }

    func testPlayAlongMatchesWrittenPitchClassAcrossEnharmonicSpellingAndOctave() {
        var grader = PlayAlongGrader(writtenNotes: ["Bb"], holdDurationMs: 300, minimumSamples: 3, attackTrimMs: 0)

        for timestamp in stride(from: 0, through: 300, by: 100) {
            grader.feed(makePlayAlongFrame(note: "A#", cents: 2, timestampMs: timestamp, writtenOctave: 6))
        }

        XCTAssertTrue(grader.isComplete)
        XCTAssertEqual(grader.noteGrades.first?.writtenNoteName, "Bb")
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testDetectedFramesApplyWrittenPitchTranspositionForTrumpetAndHorn() {
        let trumpet = PitchFrame.detected(
            timestampMs: 0,
            frequencyHz: 233.081_880_8,
            confidence: 0.99,
            rms: 0.08,
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        let horn = PitchFrame.detected(
            timestampMs: 0,
            frequencyHz: 174.614_115_7,
            confidence: 0.99,
            rms: 0.08,
            instrumentId: "horn",
            referencePitchHz: 440
        )

        XCTAssertEqual(trumpet.writtenNoteName, "C")
        XCTAssertEqual(trumpet.writtenOctave, 4)
        XCTAssertEqual(horn.writtenNoteName, "C")
        XCTAssertEqual(horn.writtenOctave, 4)
    }

    // MARK: - Pitch detector and BrassTuneCore integration

    func testFixtureFramesReflectInstrumentTransposition() {
        let trumpet = PitchFrame.fixture(index: 0, instrumentId: "trumpet")
        let horn = PitchFrame.fixture(index: 0, instrumentId: "horn")

        XCTAssertEqual(trumpet.writtenNoteName, "D")
        XCTAssertEqual(trumpet.writtenOctave, 5)
        XCTAssertEqual(horn.writtenNoteName, "D")
        XCTAssertEqual(horn.writtenOctave, 4)
    }

    func testCoreTuningStatusIsAvailableToApp() {
        XCTAssertEqual(BrassTuneCore.tuningStatus(cents: 7, confidence: 0.98, rms: 0.1), .sharp)
        XCTAssertEqual(BrassTuneCore.tuningStatus(cents: nil, confidence: 0.99, rms: 0.1), .noLock)
    }

    func testNativePitchDetectorLocksSyntheticSineAndAppliesReferencePitch() {
        let sampleRate = 44_100.0
        let frequency = 442.0
        let samples = (0..<4096).map { index in
            Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.2)
        }

        let frame = NativePitchDetector.frame(
            samples: samples,
            sampleRate: sampleRate,
            timestampMs: 120,
            instrumentId: "trumpet",
            referencePitchHz: 442.0
        )

        XCTAssertEqual(frame.tuningStatus, .inTune)
        XCTAssertEqual(frame.writtenNoteName, "B")
        XCTAssertEqual(frame.writtenOctave, 4)
        XCTAssertTrue(frame.isValidForRecording)
        XCTAssertEqual(frame.frequencyHz ?? 0, 442.0, accuracy: 3.0)
        XCTAssertGreaterThan(frame.confidence, 0.95)
    }

    func testNativePitchDetectorReportsSilenceAndNoLock() {
        let silent = NativePitchDetector.frame(
            samples: Array(repeating: Float(0), count: 4096),
            sampleRate: 44_100,
            timestampMs: 1,
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        XCTAssertEqual(silent.tuningStatus, .silence)
        XCTAssertFalse(silent.isValidForRecording)

        var seed: UInt64 = 0xBADC0DE
        let noise = (0..<4096).map { _ -> Float in
            seed = seed &* 6364136223846793005 &+ 1
            let unit = Double((seed >> 33) & 0xFFFF) / 65_535.0
            return Float((unit * 2.0 - 1.0) * 0.025)
        }
        let noLock = NativePitchDetector.frame(
            samples: noise,
            sampleRate: 44_100,
            timestampMs: 2,
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        XCTAssertEqual(noLock.tuningStatus, .noLock)
        XCTAssertFalse(noLock.isValidForRecording)
    }

    func testDesignSystemCopyLocalizesLiteralsAndPreservesUserText() {
        let previous = NativeLocalization.language
        defer { NativeLocalization.language = previous }
        NativeLocalization.language = .arabic

        let localized: BTCopy = "Tuner"
        XCTAssertEqual(localized.resolved, "الموالف")
        XCTAssertEqual(BTCopy.verbatim("Arya's C# étude").resolved, "Arya's C# étude")
        let announcement = instrumentSetupAccessibilityAnnouncement()
        XCTAssertTrue(announcement.contains(AppLanguage.arabic.localized("Choose your instrument")))
        XCTAssertFalse(announcement.contains("Choose your instrument"))
    }

    @MainActor
    func testAudioSessionCoordinatorDeactivatesOnlyAfterFinalOwner() throws {
        var activationCount = 0
        var deactivationCount = 0
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { activationCount += 1 },
            deactivateSession: { deactivationCount += 1 }
        )

        try coordinator.acquire(.capture) { }
        try coordinator.acquire(.metronome) { }
        XCTAssertEqual(activationCount, 1)
        coordinator.release(.capture)
        XCTAssertEqual(deactivationCount, 0)
        coordinator.release(.metronome)
        XCTAssertEqual(deactivationCount, 1)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)

        XCTAssertThrowsError(
            try coordinator.acquire(.capture, configure: { }, setup: {
                throw NativeAudioEngineError.inputUnavailable
            })
        )
        XCTAssertTrue(coordinator.activeOwners.isEmpty, "Failed capture setup must not strand audio-session ownership.")
        XCTAssertEqual(deactivationCount, 2)

        let metronomeOutput = NativeMetronomeOutput(audioSessionCoordinator: coordinator)
        try coordinator.acquire(.capture) { }
        metronomeOutput.playTick(settings: MetronomeSettings(), accent: false)
        XCTAssertEqual(coordinator.activeOwners, [.capture], "A metronome timer must not acquire or reconfigure the session while capture owns measurement mode.")
        coordinator.release(.capture)
        XCTAssertEqual(deactivationCount, 3)

        let engine = NativeAudioEngine(audioSessionCoordinator: coordinator)
        try coordinator.acquire(.capture) { }
        engine.stopAndResetAudioEngine()
        XCTAssertEqual(deactivationCount, 4, "Stopping capture must release and deactivate its final session owner.")

        try coordinator.acquire(.metronome) { }
        metronomeOutput.stop()
        XCTAssertEqual(deactivationCount, 5, "Stopping the metronome must release and deactivate its final session owner.")

        try coordinator.acquire(.metronome) { }
        var mutedSettings = MetronomeSettings()
        mutedSettings.muted = true
        metronomeOutput.playTick(settings: mutedSettings, accent: false)
        XCTAssertTrue(coordinator.activeOwners.isEmpty, "Switching to muted output must release metronome ownership immediately.")
        XCTAssertEqual(deactivationCount, 6)

        try coordinator.acquire(.metronome) { }
        var visualSettings = MetronomeSettings()
        visualSettings.visualOnly = true
        metronomeOutput.playTick(settings: visualSettings, accent: false)
        XCTAssertTrue(coordinator.activeOwners.isEmpty, "Switching to visual-only output must release metronome ownership immediately.")
        XCTAssertEqual(deactivationCount, 7)
    }

    func testPlayAlongHidesLowConfidenceFeedbackAndAcceptsEnharmonics() {
        let exercise = PlayAlongExercise(
            id: "enharmonic-test",
            title: "Enharmonic test",
            detail: "Test",
            difficulty: "Beginner",
            category: .practicePattern,
            writtenNotes: ["F"]
        )
        var session = PlayAlongSession(exercise: exercise, holdDurationMs: 300, minimumSamples: 3, attackTrimMs: 0)
        session.feed(makePlayAlongFrame(note: "F", cents: 0, timestampMs: 0, confidence: 0.2, frequencyHz: 349))
        XCTAssertNil(session.detectedNoteName)
        XCTAssertNil(session.detectedCents)
        XCTAssertEqual(session.heldFraction, 0)
        XCTAssertEqual(playAlongFeedback(session), NativeLocalization.format("Play %@", "F"))

        for timestamp in stride(from: 0, through: 300, by: 100) {
            session.feed(makePlayAlongFrame(note: "E#", cents: 2, timestampMs: timestamp, confidence: 0.99, frequencyHz: 349))
        }
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.noteGrades.first?.writtenNoteName, "F")
        XCTAssertEqual(session.noteGrades.first?.rating, .excellent)
    }

    func testSharedSyntheticPitchQualityContractMatchesNativeDetector() throws {
        // This is deterministic synthetic harmonic/onset evidence only. It is
        // not physical microphone, audio-I/O, or real-player attack evidence.
        let data = try Data(contentsOf: try sharedFixtureURL(named: "pitch_quality_contract.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sampleRate = try XCTUnwrap((root["sample_rate_hz"] as? NSNumber)?.doubleValue)
        let frameSize = try XCTUnwrap(root["frame_size"] as? Int)
        let harmonics = try XCTUnwrap(root["harmonic_amplitudes"] as? [NSNumber]).map(\.doubleValue)
        let thresholds = try XCTUnwrap(root["thresholds"] as? [String: Any])
        let benchmarkPolicy = try XCTUnwrap(root["benchmark_policy"] as? [String: Any])
        let benchmarkSemantics = try XCTUnwrap(root["benchmark_semantics_cases"] as? [[String: Any]])
        let onsetPolicy = try XCTUnwrap(root["synthetic_onset_protocol"] as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        let grossErrorCents = try XCTUnwrap(
            (benchmarkPolicy["gross_octave_error_cents_inclusive"] as? NSNumber)?.doubleValue
        )
        XCTAssertEqual(
            benchmarkPolicy["accuracy_definition"] as? String,
            "nearest_midi_half_up_equals_expected_midi"
        )
        var absoluteErrors: [Double] = []
        var crossPlatformDeltas: [Double] = []
        var onsetTimesMs: [Double] = []
        var accurateNotes = 0
        var grossOctaveErrors = 0

        func isAccurate(detectedMIDI: Double, expectedMIDI: Int) -> Bool {
            Int(floor(detectedMIDI + 0.5)) == expectedMIDI
        }

        func isGrossOctaveError(detectedMIDI: Double, expectedMIDI: Int) -> Bool {
            abs(detectedMIDI - Double(expectedMIDI)) * 100 >= grossErrorCents
        }

        for item in benchmarkSemantics {
            let detectedMIDI = try XCTUnwrap((item["detected_midi"] as? NSNumber)?.doubleValue)
            let expectedMIDI = try XCTUnwrap(item["expected_midi"] as? Int)
            XCTAssertEqual(
                isAccurate(detectedMIDI: detectedMIDI, expectedMIDI: expectedMIDI),
                item["expected_accurate"] as? Bool,
                item["name"] as? String ?? "benchmark accuracy semantics"
            )
            XCTAssertEqual(
                isGrossOctaveError(detectedMIDI: detectedMIDI, expectedMIDI: expectedMIDI),
                item["expected_gross_octave_error"] as? Bool,
                item["name"] as? String ?? "gross octave semantics"
            )
        }

        func harmonicTone(frequency: Double, multiplier: Double) -> [Float] {
            (0..<frameSize).map { index in
                let time = Double(index) / sampleRate
                let sample = harmonics.enumerated().reduce(0.0) { partial, item in
                    partial + item.element * sin(2 * .pi * frequency * Double(item.offset + 1) * time)
                }
                return Float(sample * multiplier)
            }
        }

        for item in cases {
            let note = item["note"] as? String ?? "pitch case"
            let target = try XCTUnwrap((item["frequency_hz"] as? NSNumber)?.doubleValue)
            let expectedMIDI = try XCTUnwrap(item["midi"] as? Int)
            let expectedPython = try XCTUnwrap((item["expected_python_signed_cents_error"] as? NSNumber)?.doubleValue)
            let frame = NativePitchDetector.frame(
                samples: harmonicTone(frequency: target, multiplier: 1),
                sampleRate: sampleRate,
                timestampMs: 0,
                instrumentId: "fixture-wide-range",
                referencePitchHz: 440
            )
            let detected = try XCTUnwrap(frame.frequencyHz, "Native detector did not lock \(note)")
            let signedError = 1_200 * log2(detected / target)
            let detectedMIDI = 69 + 12 * log2(detected / 440)
            absoluteErrors.append(abs(signedError))
            crossPlatformDeltas.append(abs(signedError - expectedPython))
            if isAccurate(detectedMIDI: detectedMIDI, expectedMIDI: expectedMIDI) { accurateNotes += 1 }
            if isGrossOctaveError(detectedMIDI: detectedMIDI, expectedMIDI: expectedMIDI) {
                grossOctaveErrors += 1
            }

            let amplitudes = try XCTUnwrap(item["onset_amplitude_multipliers"] as? [NSNumber]).map(\.doubleValue)
            let onsetIndex = try XCTUnwrap(amplitudes.firstIndex(where: { $0 > 0 }))
            let lockIndex = try XCTUnwrap(amplitudes.indices.first { index in
                let onsetFrame = NativePitchDetector.frame(
                    samples: harmonicTone(frequency: target, multiplier: amplitudes[index]),
                    sampleRate: sampleRate,
                    timestampMs: index,
                    instrumentId: "fixture-wide-range",
                    referencePitchHz: 440
                )
                guard let locked = onsetFrame.frequencyHz else { return false }
                let lockError = abs(1_200 * log2(locked / target))
                return onsetFrame.confidence >= ((onsetPolicy["lock_confidence_min"] as? NSNumber)?.doubleValue ?? 0.55)
                    && lockError <= ((onsetPolicy["lock_frequency_tolerance_cents_max"] as? NSNumber)?.doubleValue ?? 50)
            }, "Native detector never locked synthetic onset \(note)")
            onsetTimesMs.append(Double(lockIndex - onsetIndex + 1) * Double(frameSize) / sampleRate * 1_000)
        }

        XCTAssertGreaterThanOrEqual(
            Double(accurateNotes) / Double(cases.count) * 100,
            (thresholds["steady_note_octave_accuracy_min_percent"] as? NSNumber)?.doubleValue ?? 99
        )
        XCTAssertLessThanOrEqual(
            Double(grossOctaveErrors) / Double(cases.count) * 100,
            (thresholds["gross_octave_error_max_percent"] as? NSNumber)?.doubleValue ?? 0.5
        )
        XCTAssertLessThanOrEqual(median(absoluteErrors), (thresholds["median_abs_cents_error_max"] as? NSNumber)?.doubleValue ?? 3)
        XCTAssertLessThanOrEqual(percentile95(absoluteErrors), (thresholds["p95_abs_cents_error_max"] as? NSNumber)?.doubleValue ?? 8)
        XCTAssertLessThanOrEqual(percentile95(crossPlatformDeltas), (thresholds["cross_platform_p95_cents_delta_max"] as? NSNumber)?.doubleValue ?? 5)
        XCTAssertLessThanOrEqual(percentile95(onsetTimesMs), (thresholds["onset_p95_ms_max"] as? NSNumber)?.doubleValue ?? 300)
    }

    func testSyntheticPitchQualityMedianGateRejectsThreeToEightCentOnlyErrors() {
        let errors = [3.1, 3.8, 4.6, 5.4, 6.3, 7.2, 7.9]
        XCTAssertLessThanOrEqual(percentile95(errors), 8, "The p95 gate alone would allow this regression.")
        XCTAssertGreaterThan(median(errors), 3, "The median gate must reject a detector that is consistently 3–8 cents wrong.")
    }

    @MainActor
    func testQueuedRemoteDeletionPurgesLocallySignsOutAndNeverRetriesDelete() async throws {
        let authService = makeIsolatedAuthService(session: makeStubSession())
        defer { try? authService.signOut(); StubURLProtocol.handler = nil }
        var backendDeleteCount = 0
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.host == AppConfig.approvedProductionAPIOrigin.host {
                backendDeleteCount += 1
                return .init(response: response, data: Data(#"{"deleted":false,"deletion_status":"external_cleanup_queued"}"#.utf8))
            }
            return .init(
                response: response,
                data: Data(#"{"access_token":"access-user-a","refresh_token":"refresh-user-a","expires_in":3600,"user":{"id":"user-a","email":"a@example.com"}}"#.utf8)
            )
        }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreBaseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        var pendingPurgeDigests: [String] = []
        var pendingCredentialDigests: [String] = []
        let purgeStore = PendingDigestStore(load: { pendingPurgeDigests }, save: { pendingPurgeDigests = $0 })
        let credentialStore = PendingDigestStore(load: { pendingCredentialDigests }, save: { pendingCredentialDigests = $0 })
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreBaseDirectory,
            pendingAccountPurgeStore: purgeStore,
            pendingCredentialRemovalStore: credentialStore,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        model.config = makeAuthConfig()
        await model.signIn(email: "a@example.com", password: "password")
        let session = makeSession(name: "Keep until confirmed", cents: [0])
        model.sessions = [session]
        let namespace = NativeStorageNamespace.account(userID: "user-a")
        let accountFile = namespace.stateFile(basedAt: stateURL)
        let accountScoreDirectory = namespace.scoreDirectory(basedAt: scoreBaseDirectory)
        try FileManager.default.createDirectory(at: accountScoreDirectory, withIntermediateDirectories: true)
        try Data("score".utf8).write(to: accountScoreDirectory.appendingPathComponent("score.pdf"))

        await model.deleteAccount()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNil(authService.restoreSession())
        XCTAssertTrue(model.authNotice?.localizedCaseInsensitiveContains("queued") == true)
        XCTAssertFalse(model.authNoticeIsError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountScoreDirectory.path))
        XCTAssertTrue(pendingPurgeDigests.isEmpty)
        XCTAssertTrue(pendingCredentialDigests.isEmpty)
        XCTAssertEqual(backendDeleteCount, 1)

        let relaunchedModel = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreBaseDirectory,
            pendingAccountPurgeStore: purgeStore,
            pendingCredentialRemovalStore: credentialStore,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        relaunchedModel.config = makeAuthConfig()
        await relaunchedModel.restoreSession()

        XCTAssertEqual(relaunchedModel.authState, .guest)
        XCTAssertNil(authService.restoreSession())
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountScoreDirectory.path))
        XCTAssertTrue(pendingPurgeDigests.isEmpty)
        XCTAssertTrue(pendingCredentialDigests.isEmpty)
        XCTAssertEqual(backendDeleteCount, 1, "The backend owns queued provider cleanup; the client must not issue an unreachable second DELETE.")
    }

    @MainActor
    func testQueuedRemoteDeletionRetriesFailedCredentialRemovalWithoutRestoringAccountData() async throws {
        let authStore = InMemoryAuthSessionStore()
        var failCredentialDeletion = true
        let authService = AuthService(
            session: makeStubSession(),
            service: "com.brasstune.tests.\(UUID().uuidString)",
            account: "current-session",
            readSessionPayload: { authStore.payload },
            saveSessionPayload: { authStore.payload = $0 },
            deleteSessionPayload: {
                if failCredentialDeletion { throw UserVisibleError.secureStorageDeletionFailed }
                authStore.payload = nil
            }
        )
        defer { failCredentialDeletion = false; try? authService.signOut(); StubURLProtocol.handler = nil }
        var backendDeleteCount = 0
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.host == AppConfig.approvedProductionAPIOrigin.host {
                backendDeleteCount += 1
                return .init(response: response, data: Data(#"{"deleted":false,"deletion_status":"external_cleanup_queued"}"#.utf8))
            }
            return .init(
                response: response,
                data: Data(#"{"access_token":"access-user-a","refresh_token":"refresh-user-a","expires_in":3600,"user":{"id":"user-a","email":"a@example.com"}}"#.utf8)
            )
        }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreBaseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        var pendingCredentialDigests: [String] = []
        let credentialStore = PendingDigestStore(load: { pendingCredentialDigests }, save: { pendingCredentialDigests = $0 })
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreBaseDirectory,
            pendingCredentialRemovalStore: credentialStore,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        model.config = makeAuthConfig()
        await model.signIn(email: "a@example.com", password: "password")
        model.sessions = [makeSession(name: "Must not return", cents: [0])]
        let namespace = NativeStorageNamespace.account(userID: "user-a")
        let accountFile = namespace.stateFile(basedAt: stateURL)

        await model.deleteAccount()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertNotNil(authService.restoreSession(), "The injected Keychain deletion failure must be observable, not silently treated as success.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountFile.path))
        XCTAssertEqual(pendingCredentialDigests.count, 1)
        XCTAssertTrue(pendingCredentialDigests.allSatisfy { $0.count == 64 && $0.allSatisfy(\.isHexDigit) })
        XCTAssertTrue(model.authNotice?.localizedCaseInsensitiveContains("queued") == true)
        XCTAssertTrue(model.authNotice?.localizedCaseInsensitiveContains("saved sign-in") == true)
        XCTAssertTrue(model.authNoticeIsError)

        failCredentialDeletion = false
        let relaunchedModel = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreBaseDirectory,
            pendingCredentialRemovalStore: credentialStore,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        relaunchedModel.config = makeAuthConfig()
        await relaunchedModel.restoreSession()

        XCTAssertEqual(relaunchedModel.authState, .signedOut)
        XCTAssertNil(authService.restoreSession())
        XCTAssertTrue(relaunchedModel.sessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountFile.path))
        XCTAssertTrue(pendingCredentialDigests.isEmpty)
        XCTAssertEqual(backendDeleteCount, 1)
    }

    @MainActor
    func testRemoteDeletionRetriesDigestOnlyPurgeOnRelaunch() async throws {
        let authService = makeIsolatedAuthService(session: makeStubSession())
        defer { try? authService.signOut(); StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.host == AppConfig.approvedProductionAPIOrigin.host {
                return .init(response: response, data: Data(#"{"deleted":true}"#.utf8))
            }
            return .init(
                response: response,
                data: Data(#"{"access_token":"access-user-a","refresh_token":"refresh-user-a","expires_in":3600,"user":{"id":"user-a","email":"a@example.com"}}"#.utf8)
            )
        }

        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreBaseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        var failRemoval = true
        var pendingDigests: [String] = []
        let store = NativePersistenceStore.ephemeral(
            fileURL: stateURL,
            removeItem: { url in
                if failRemoval { throw CocoaError(.fileWriteUnknown) }
                try FileManager.default.removeItem(at: url)
            }
        )
        let pendingStore = PendingDigestStore(
            load: { pendingDigests },
            save: { pendingDigests = $0 }
        )
        let model = AppModel(
            persistenceStore: store,
            scoreStorageDirectory: scoreBaseDirectory,
            pendingAccountPurgeStore: pendingStore,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        model.config = makeAuthConfig()
        await model.signIn(email: "a@example.com", password: "password")
        model.sessions = [makeSession(name: "Delete eventually", cents: [1])]
        let accountFile = NativeStorageNamespace.account(userID: "user-a").stateFile(basedAt: stateURL)
        let accountScoreDirectory = NativeStorageNamespace.account(userID: "user-a").scoreDirectory(basedAt: scoreBaseDirectory)
        try FileManager.default.createDirectory(at: accountScoreDirectory, withIntermediateDirectories: true)
        try Data("score".utf8).write(to: accountScoreDirectory.appendingPathComponent("score.pdf"))
        model.flushPendingPersistence()
        XCTAssertTrue(FileManager.default.fileExists(atPath: accountFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: accountScoreDirectory.path))

        await model.deleteAccount()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertNil(authService.restoreSession())
        XCTAssertTrue(FileManager.default.fileExists(atPath: accountFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: accountScoreDirectory.path))
        XCTAssertEqual(pendingDigests.count, 1)
        XCTAssertTrue(pendingDigests.allSatisfy { $0.count == 64 && $0.allSatisfy(\.isHexDigit) })

        failRemoval = false
        _ = AppModel(
            persistenceStore: store,
            scoreStorageDirectory: scoreBaseDirectory,
            pendingAccountPurgeStore: pendingStore,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountScoreDirectory.path))
        XCTAssertTrue(pendingDigests.isEmpty)
    }

    // MARK: - Helpers

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return .infinity }
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }

    private func percentile95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return .infinity }
        return sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
    }

    @MainActor
    private func makeModel(
        audioEngine: NativeAudioEngine? = nil,
        audioSessionCoordinator: NativeAudioSessionCoordinator = .shared
    ) -> AppModel {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            authService: AuthService(session: makeStubSession(), readSessionPayload: { nil }),
            audioSessionCoordinator: audioSessionCoordinator,
            audioEngine: audioEngine
        )
        model.enterGuestDemo(presentTutorial: false)
        return model
    }

    @MainActor
    private func makeIsolatedAuthService(session: URLSession) -> AuthService {
        let store = InMemoryAuthSessionStore()
        return AuthService(
            session: session,
            service: "com.brasstune.tests.\(UUID().uuidString)",
            account: "current-session",
            readSessionPayload: { store.payload },
            saveSessionPayload: { store.payload = $0 },
            deleteSessionPayload: { store.payload = nil }
        )
    }

    private func makeAuthConfig() -> AppConfig {
        AppConfig(
            environment: .production,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabasePublishableKey: "sb_publishable_test"
        )
    }

    private func sharedFixtureURL(named name: String) throws -> URL {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["BRASSTUNE_SHARED_FIXTURES_DIR"] {
            let url = URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("fixtures", isDirectory: true).appendingPathComponent(name)
        guard fileManager.fileExists(atPath: url.path) else {
            throw XCTSkip("Shared audio fixture \(name) is not present in this isolated worktree.")
        }
        return url
    }

    private func writtenMIDI(from label: String) throws -> Int {
        let pattern = #"^([A-G])([#b]?)(-?\d+)$"#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(label.startIndex..<label.endIndex, in: label)
        let match = try XCTUnwrap(expression.firstMatch(in: label, range: range))
        let note = String(label[Range(match.range(at: 1), in: label)!])
            + String(label[Range(match.range(at: 2), in: label)!])
        let octave = try XCTUnwrap(Int(label[Range(match.range(at: 3), in: label)!]))
        let pitchClass = try XCTUnwrap([
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
            "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
            "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11,
        ][note])
        return (octave + 1) * 12 + pitchClass
    }

    private func noteAndOctave(from label: String) throws -> (String, Int) {
        let pattern = #"^([A-G](?:#|b)?)(-?\d+)$"#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(label.startIndex..<label.endIndex, in: label)
        let match = try XCTUnwrap(expression.firstMatch(in: label, range: range))
        let note = String(label[Range(match.range(at: 1), in: label)!])
        let octave = try XCTUnwrap(Int(label[Range(match.range(at: 2), in: label)!]))
        return (note, octave)
    }

    private func makePitchFrame(from item: [String: Any]) -> PitchFrame {
        let note = item["written_note_name"] as? String
        let octave = item["written_octave"] as? Int
        let cents = item["cents_deviation"] as? Double
        let status: TuningStatus
        switch item["tuning_status"] as? String {
        case "flat": status = .flat
        case "in_tune": status = .inTune
        case "sharp": status = .sharp
        case "silence": status = .silence
        case "unstable": status = .unstable
        default: status = .noLock
        }
        let defaultValidity = note != nil && octave != nil && cents != nil && [.flat, .inTune, .sharp].contains(status)
        return PitchFrame(
            timestampMs: item["timestamp_ms"] as? Int ?? 0,
            frequencyHz: defaultValidity ? 440 : nil,
            confidence: defaultValidity ? 0.99 : 0,
            rms: defaultValidity ? 0.08 : 0,
            centsDeviation: cents,
            tuningStatus: status,
            writtenNoteName: note,
            writtenOctave: octave,
            isValidForRecording: item["is_valid_for_recording"] as? Bool ?? defaultValidity
        )
    }

    private func makeSession(
        name: String,
        cents: [Double],
        source: PracticeSessionSource = .live
    ) -> PracticeSession {
        let frames = cents.enumerated().map { index, centsValue in
            PitchFrame(
                timestampMs: index * 110,
                frequencyHz: 440,
                confidence: 0.98,
                rms: 0.08,
                centsDeviation: centsValue,
                tuningStatus: BrassTuneCore.tuningStatus(cents: centsValue, confidence: 0.98, rms: 0.08),
                writtenNoteName: "A",
                writtenOctave: 4,
                isValidForRecording: true
            )
        }
        let startedAt = Date(timeIntervalSince1970: 1_000)
        return PracticeSession(
            id: UUID(),
            name: name,
            instrumentId: "trumpet",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(frames.count) * 0.11),
            frames: frames,
            retainedRecordingURL: nil,
            source: source
        )
    }

    private func makeSampleScore() -> ImportedScore {
        let page = ScorePage(
            id: UUID(),
            pageNumber: 1,
            titleSuggestion: nil,
            textSuggestions: [],
            thumbnailPNGData: nil
        )
        return ImportedScore(
            id: UUID(),
            title: "Old test score",
            composer: nil,
            sourceKind: .sample,
            localFileName: nil,
            importedAt: Date(timeIntervalSince1970: 1_000),
            pages: [page],
            selectedPageID: page.id
        )
    }

    private func makePlayAlongFrame(
        note: String?,
        cents: Double?,
        timestampMs: Int,
        confidence: Double = 0.99,
        frequencyHz: Double? = 440,
        writtenOctave: Int = 4,
        isValidForRecording: Bool? = nil,
        tuningStatus: TuningStatus? = nil
    ) -> PitchFrame {
        let rms = note == nil ? 0 : 0.08
        let resolvedTuningStatus = tuningStatus
            ?? BrassTuneCore.tuningStatus(cents: cents, confidence: confidence, rms: rms)
        return PitchFrame(
            timestampMs: timestampMs,
            frequencyHz: frequencyHz,
            confidence: confidence,
            rms: rms,
            centsDeviation: cents,
            tuningStatus: resolvedTuningStatus,
            writtenNoteName: note,
            writtenOctave: note == nil ? nil : writtenOctave,
            isValidForRecording: isValidForRecording
                ?? (
                    note != nil
                    && cents != nil
                    && confidence >= 0.95
                    && [.flat, .inTune, .sharp].contains(resolvedTuningStatus)
                )
        )
    }

    private func makePlayAlongAttempt(
        notes: [String],
        rating: PlayAlongNoteRating
    ) -> PlayAlongAttemptSummary {
        PlayAlongAttemptSummary(
            exercise: .defaultExercise,
            noteGrades: notes.map {
                PlayAlongNoteGrade(
                    writtenNoteName: $0,
                    medianCents: rating == .missed ? nil : 30,
                    sampleCount: rating == .missed ? 0 : 5,
                    rating: rating
                )
            }
        )
    }

    private func makeTinyPNGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            UIColor.white.setStroke()
            context.cgContext.move(to: CGPoint(x: 2, y: 4))
            context.cgContext.addLine(to: CGPoint(x: 14, y: 4))
            context.cgContext.strokePath()
        }
        return try XCTUnwrap(image.pngData())
    }

    private func makePDFData(pageCount: Int) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 144, height: 144)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for pageNumber in 1...pageCount {
                context.beginPage()
                "Page \(pageNumber)".draw(
                    at: CGPoint(x: 16, y: 16),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
                )
            }
        }
    }

    private func testPitchClass(_ note: String) -> Int? {
        let normalized = note
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        return [
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
        ][normalized]
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct TestAPIResponse: Decodable {
    let ok: Bool?
}

private struct CapturedRequest {
    let method: String
    let path: String
    let authorization: String?
    let body: Data?
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        result.append(buffer, count: count)
    }
    return result
}
