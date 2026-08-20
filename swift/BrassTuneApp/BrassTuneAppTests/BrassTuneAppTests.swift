import XCTest
@testable import BrassTuneApp
import AVFoundation
import BrassTuneCore
import CoreText
import CryptoKit
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

private final class MetronomeCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [@Sendable (Result<Void, Error>) -> Void] = []

    func append(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        lock.lock()
        completions.append(completion)
        lock.unlock()
    }

    var first: (@Sendable (Result<Void, Error>) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return completions.first
    }
}

private final class MetronomeGraphProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []
    private var storedTargets: [UInt64] = []
    private var storedCompletions: [@Sendable (Result<Void, Error>) -> Void] = []

    lazy var hooks = NativeMetronomeGraphHooks(
        prepare: { [weak self] in self?.record("prepare") },
        schedule: { [weak self] target, completion in
            guard let self else { return }
            self.lock.lock()
            self.storedEvents.append("schedule")
            self.storedTargets.append(target)
            self.storedCompletions.append(completion)
            self.lock.unlock()
        },
        play: { [weak self] in self?.record("play") },
        stop: { [weak self] in self?.record("stop") },
        reset: { [weak self] in self?.record("reset") }
    )

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    var targets: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return storedTargets
    }

    var completionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCompletions.count
    }

    func completion(at index: Int) -> (@Sendable (Result<Void, Error>) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        guard storedCompletions.indices.contains(index) else { return nil }
        return storedCompletions[index]
    }

    private func record(_ event: String) {
        lock.lock()
        storedEvents.append(event)
        lock.unlock()
    }
}

private final class AudioControlPlaneProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [NativeAudioControlPlaneHooks.Event] = []
    private var storedMainThreadFlags: [Bool] = []
    var failingEvent: NativeAudioControlPlaneHooks.Event?
    var delayedEvent: NativeAudioControlPlaneHooks.Event?
    var delaySeconds: TimeInterval = 0

    lazy var hooks = NativeAudioControlPlaneHooks { [weak self] event in
        guard let self else { return }
        self.lock.lock()
        self.storedEvents.append(event)
        self.storedMainThreadFlags.append(Thread.isMainThread)
        let shouldFail = self.failingEvent == event
        let shouldDelay = self.delayedEvent == event
        let delay = self.delaySeconds
        self.lock.unlock()
        if shouldDelay, delay > 0 { Thread.sleep(forTimeInterval: delay) }
        if shouldFail { throw NativeAudioEngineError.outputUnavailable }
    }

    var events: [NativeAudioControlPlaneHooks.Event] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    var allPhysicalHooksOffMain: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !storedMainThreadFlags.isEmpty && storedMainThreadFlags.allSatisfy { !$0 }
    }

    func count(_ event: NativeAudioControlPlaneHooks.Event) -> Int {
        events.filter { $0 == event }.count
    }
}

private final class InMemoryAuthSessionStore: @unchecked Sendable {
    var payload: String?
}

private final class AuthPersistenceWriteCounter: @unchecked Sendable {
    var payloads: [String] = []
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

private final class FailOncePersistenceWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = true
    private var storedAttemptCount = 0

    func write(_ data: Data, to url: URL) throws {
        lock.lock()
        storedAttemptCount += 1
        let failsThisAttempt = shouldFail
        shouldFail = false
        lock.unlock()
        if failsThisAttempt {
            throw CocoaError(.fileWriteNoPermission)
        }
        try data.write(to: url, options: [.atomic])
    }

    var attemptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedAttemptCount
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
            preservePendingTunerStartWhileInactive: { false },
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
            preservePendingTunerStartWhileInactive: { false },
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
            preservePendingTunerStartWhileInactive: { false },
            cancelTunerStart: { cleanupCount += 1 },
            isTunerRecording: { true },
            stopTunerRecording: { cleanupCount += 1 },
            releasePracticeAudio: { cleanupCount += 1 }
        )

        XCTAssertEqual(cleanupCount, 0)
    }

    @MainActor
    func testSystemPermissionSheetInactiveTransitionPreservesPendingTunerStart() {
        var events: [String] = []

        AppSceneAudioLifecycle.handleTransition(
            from: .active,
            to: .inactive,
            preservePendingTunerStartWhileInactive: { true },
            cancelTunerStart: { events.append("cancel tuner start") },
            isTunerRecording: { false },
            stopTunerRecording: { events.append("stop tuner recording") },
            releasePracticeAudio: { events.append("release practice audio") }
        )

        XCTAssertEqual(events, ["release practice audio"])
    }

    @MainActor
    func testBackgroundTransitionStillCancelsPendingPermissionRequest() {
        var events: [String] = []

        AppSceneAudioLifecycle.handleTransition(
            from: .active,
            to: .background,
            preservePendingTunerStartWhileInactive: { true },
            cancelTunerStart: { events.append("cancel tuner start") },
            isTunerRecording: { false },
            stopTunerRecording: { events.append("stop tuner recording") },
            releasePracticeAudio: { events.append("release practice audio") }
        )

        XCTAssertEqual(events, ["cancel tuner start", "release practice audio"])
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

    func testPracticeHomeShortcutsHideDisabledPacksAndDeduplicateFavoritesAndRecents() {
        let shared = PracticeShortcut(
            kind: .playAlongExercise,
            referenceID: "shared-exercise",
            title: "Shared exercise"
        )
        let pack = PracticeShortcut(
            kind: .practicePack,
            referenceID: "disabled-pack",
            title: "Disabled pack"
        )

        let visible = uniqueReleaseVisibleShortcuts([shared, pack, shared])

        XCTAssertEqual(visible, [shared])
        XCTAssertFalse(NativeReleaseFeatureFlags.offlinePacks)
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
    func testLocalExportUsesVersionedDeterministicJSONAndIncludesImportedScore() throws {
        let model = makeModel()
        model.sessions = [makeSession(name: "Exportable recording", cents: [-4, 0, 7])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Warm-up score")

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let export = model.exportDataText(exportedAt: date)
        let repeated = model.exportDataText(exportedAt: date)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(NativePracticeHistoryExport.self, from: try XCTUnwrap(export.data(using: .utf8)))

        XCTAssertEqual(export, repeated)
        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.exportedAt, date)
        XCTAssertEqual(payload.sessions.map(\.name), ["Exportable recording"])
        XCTAssertEqual(payload.scores.map(\.title), ["Warm-up score"])
    }

    @MainActor
    func testClearPracticeHistoryPreservesImportedScoreMetadata() {
        let model = makeModel()
        let score = makeSampleScore()
        model.sessions = [makeSession(name: "History", cents: Array(repeating: 0, count: 12))]
        model.scores = [score]
        model.activeScoreID = score.id

        model.clearLocalPracticeData()

        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(model.scores, [score])
        XCTAssertEqual(model.activeScoreID, score.id)
    }

    func testPracticeSessionMigratesActivityIdentityFromLegacyPayload() throws {
        let id = UUID()
        let legacy = """
        {"id":"\(id.uuidString)","name":"Legacy","instrumentId":"trumpet","startedAt":"2024-01-01T00:00:00Z","frames":[],"source":"live"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(PracticeSession.self, from: Data(legacy.utf8))

        XCTAssertEqual(session.activityInstanceID, id)
        XCTAssertEqual(session.activity, .tuning)
        XCTAssertEqual(session.completion, .completed)
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
        model.config = .local

        XCTAssertFalse(model.accountFeaturesEnabled)
        XCTAssertEqual(
            model.accountUnavailableMessage,
            "Practice as a guest today. Account sign-in will be available when secure account access is ready."
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
        let englishGoogleCTA = try value("Sign in with Google", "en")
        XCTAssertEqual(englishGoogleCTA, "Sign in with Google")
        for locale in expectedLocales.subtracting(["en"]) {
            let localizedGoogleCTA = try value("Sign in with Google", locale)
            XCTAssertFalse(localizedGoogleCTA.isEmpty, "Google CTA is empty for \(locale)")
            XCTAssertNotEqual(localizedGoogleCTA, englishGoogleCTA, "Google CTA is not localized for \(locale)")
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
        XCTAssertEqual(try value("Class", "ar"), "الصف")
        let arabicClassKeys = [
            "Active class",
            "Class code",
            "Return to Settings and sign in before joining a class.",
            "Sign in before using classes.",
            "That class action conflicts with your current membership.",
            "That class could not be found.",
        ]
        for key in arabicClassKeys {
            let arabic = try value(key, "ar")
            XCTAssertFalse(arabic.contains("فئة"), "\(key) used the category translation for Class")
            XCTAssertFalse(arabic.contains("دعوى"), "\(key) used lawsuit wording")
        }
        let firstRecording = try value(
            "Use the Tuner or finish a Play-Along exercise to save your first recording.",
            "ar"
        )
        XCTAssertFalse(firstRecording.contains("Tuner"))
        XCTAssertFalse(firstRecording.contains("Play-Along"))

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

    func testGoogleSignInBrandFontIsBundledLicensedAndCoversEveryLocalizedCTA() throws {
        let appDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fontURL = appDirectory.appendingPathComponent(
            "BrassTuneApp/Resources/Fonts/GoogleSans-Medium.ttf"
        )
        let fontData = try Data(contentsOf: fontURL)
        let digest = SHA256.hash(data: fontData)
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(
            digest,
            "e9156f50951740b525f8e6d110e0be344214cb6d5fce1e76cd3e828a604997e9"
        )

        let license = try String(
            contentsOf: appDirectory.appendingPathComponent(
                "BrassTuneApp/Resources/Fonts/GoogleSans-OFL.txt"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(license.contains("Copyright 2025 The Google Sans Project Authors"))
        XCTAssertTrue(license.contains("SIL OPEN FONT LICENSE Version 1.1"))

        XCTAssertNotNil(Bundle.main.url(forResource: "GoogleSans-Medium", withExtension: "ttf"))
        XCTAssertNotNil(Bundle.main.url(forResource: "GoogleSans-OFL", withExtension: "txt"))
        let font = try XCTUnwrap(
            UIFont(
                name: NativeGoogleSignInBranding.fontName,
                size: NativeGoogleSignInBranding.fontSize
            )
        )
        XCTAssertEqual(font.fontName, "GoogleSans-Medium")
        XCTAssertEqual(font.pointSize, 14, accuracy: 0.001)
        XCTAssertEqual(
            font.lineHeight + NativeGoogleSignInBranding.lineSpacing,
            NativeGoogleSignInBranding.lineHeight,
            accuracy: 0.001
        )
        XCTAssertEqual(NativeGoogleSignInBranding.logoSize, 18)
        XCTAssertEqual(NativeGoogleSignInBranding.leadingPadding, 16)
        XCTAssertEqual(NativeGoogleSignInBranding.logoTextSpacing, 12)
        XCTAssertEqual(NativeGoogleSignInBranding.trailingPadding, 16)

        let coreTextFont = CTFontCreateWithName(
            NativeGoogleSignInBranding.fontName as CFString,
            NativeGoogleSignInBranding.fontSize,
            nil
        )
        let englishCharacters = Array(AppLanguage.english.localized("Sign in with Google").utf16)
        var englishGlyphs = [CGGlyph](repeating: 0, count: englishCharacters.count)
        let googleSansCoversEnglishCTA = englishCharacters.withUnsafeBufferPointer { characterBuffer in
            englishGlyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                CTFontGetGlyphsForCharacters(
                    coreTextFont,
                    characterBuffer.baseAddress!,
                    glyphBuffer.baseAddress!,
                    englishCharacters.count
                )
            }
        }
        XCTAssertTrue(googleSansCoversEnglishCTA)

        for language in AppLanguage.allCases.dropFirst() {
            let callToAction = language.localized("Sign in with Google")
            let attributedCTA = NSAttributedString(
                string: callToAction,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): coreTextFont,
                ]
            )
            let line = CTLineCreateWithAttributedString(attributedCTA)
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            XCTAssertFalse(runs.isEmpty, "No text run for \(language.rawValue)")
            for run in runs {
                let glyphCount = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                    CTRunGetGlyphs(
                        run,
                        CFRange(location: 0, length: 0),
                        glyphBuffer.baseAddress!
                    )
                }
                XCTAssertFalse(
                    glyphs.contains(0),
                    "Google Sans cascading could not render the CTA for \(language.rawValue)"
                )
            }
        }
    }

    func testTuningMeterGeometryClampsSymmetricallyAndDoesNotMirrorInArabic() {
        let previous = NativeLocalization.language
        defer { NativeLocalization.language = previous }

        NativeLocalization.language = .english
        XCTAssertEqual(tuningMeterIndicatorOffset(cents: -50, width: 200), -95, accuracy: 0.001)
        XCTAssertEqual(tuningMeterIndicatorOffset(cents: 0, width: 200), 0, accuracy: 0.001)
        XCTAssertEqual(tuningMeterIndicatorOffset(cents: 50, width: 200), 95, accuracy: 0.001)
        XCTAssertEqual(tuningMeterIndicatorOffset(cents: -500, width: 200), -95, accuracy: 0.001)
        XCTAssertEqual(tuningMeterIndicatorOffset(cents: 500, width: 200), 95, accuracy: 0.001)

        NativeLocalization.language = .arabic
        XCTAssertEqual(tuningMeterIndicatorOffset(cents: -25, width: 200), -47.5, accuracy: 0.001)
        XCTAssertEqual(tuningMeterIndicatorOffset(cents: 25, width: 200), 47.5, accuracy: 0.001)
        XCTAssertEqual(tuningMeterIndicatorOffset(cents: nil, width: 200), 0, accuracy: 0.001)
    }

    func testKeychainSessionUsesThisDeviceOnlyAccessibility() {
        XCTAssertEqual(KeychainStore.sessionAccessibility, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    func testKeychainErrorMappingKeepsOperationSpecificUserRecovery() {
        XCTAssertEqual(
            KeychainStore.userVisibleError(for: KeychainStoreError(operation: .read, status: errSecParam)),
            .secureStorageReadFailed
        )
        XCTAssertEqual(
            KeychainStore.userVisibleError(for: KeychainStoreError(operation: .save, status: errSecMissingEntitlement)),
            .secureStorageUnavailable
        )
        XCTAssertEqual(
            KeychainStore.userVisibleError(for: KeychainStoreError(operation: .read, status: nil, isCorrupt: true)),
            .secureStorageCorrupt
        )
        XCTAssertEqual(
            KeychainStore.userVisibleError(for: KeychainStoreError(operation: .save, status: errSecParam)),
            .secureStorageSaveFailed
        )
        XCTAssertEqual(
            KeychainStore.userVisibleError(for: KeychainStoreError(operation: .delete, status: errSecParam)),
            .secureStorageDeletionFailed
        )
    }

    @MainActor
    func testGoogleOAuthTransactionUsesPKCEStateAndExactNativeCallback() throws {
        let verifier = String(repeating: "v", count: 64)
        let expectedScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let transaction = try AuthService.googleOAuthTransaction(
            config: makeAuthConfig(),
            state: "state-123",
            codeVerifier: verifier
        )
        let components = try XCTUnwrap(
            URLComponents(url: transaction.authorizationURL, resolvingAgainstBaseURL: false)
        )
        let values = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "project.supabase.co")
        XCTAssertEqual(components.path, "/auth/v1/authorize")
        XCTAssertEqual(values["provider"], "google")
        XCTAssertEqual(values["scopes"], "openid email profile")
        XCTAssertEqual(values["code_challenge_method"], "s256")
        XCTAssertNotEqual(values["code_challenge"], verifier)
        XCTAssertEqual(
            values["redirect_to"],
            "\(expectedScheme)://oauth/google?state=state-123"
        )
        XCTAssertNil(values["apikey"], "The publishable key belongs in API headers, not browser history.")
        XCTAssertEqual(transaction.callbackURL.scheme, expectedScheme)
        XCTAssertEqual(
            expectedScheme,
            AuthService.resolvedOAuthCallbackScheme(
                rawValue: expectedScheme,
                bundleIdentifier: Bundle.main.bundleIdentifier
            )
        )
    }

    @MainActor
    func testOAuthCallbackSchemeResolverBindsExactBundleIdentityAndFailsClosed() throws {
        XCTAssertEqual(
            AuthService.resolvedOAuthCallbackScheme(
                rawValue: AuthService.productionOAuthCallbackScheme,
                bundleIdentifier: AuthService.productionBundleIdentifier
            ),
            AuthService.productionOAuthCallbackScheme
        )
        XCTAssertEqual(
            AuthService.resolvedOAuthCallbackScheme(
                rawValue: "  COM.BRASSTUNE.AUTH.DEV  ",
                bundleIdentifier: "com.aryasalem.BrassTune.dev"
            ),
            AuthService.developmentOAuthCallbackScheme
        )
        for fixtureIdentifier in [
            "com.brasstune.BrassTuneAppTests.dev",
            "com.brasstune.BrassTuneAppUITests.dev",
        ] {
            XCTAssertEqual(
                AuthService.resolvedOAuthCallbackScheme(
                    rawValue: AuthService.developmentOAuthCallbackScheme,
                    bundleIdentifier: fixtureIdentifier
                ),
                AuthService.developmentOAuthCallbackScheme
            )
        }

        for (rawValue, bundleIdentifier) in [
            (AuthService.developmentOAuthCallbackScheme, AuthService.productionBundleIdentifier),
            (AuthService.productionOAuthCallbackScheme, "com.aryasalem.BrassTune.dev"),
            (nil, AuthService.productionBundleIdentifier),
            ("$(BRASSTUNE_AUTH_CALLBACK_SCHEME)", AuthService.productionBundleIdentifier),
            ("another.app.callback", AuthService.productionBundleIdentifier),
            (AuthService.productionOAuthCallbackScheme, "another.app"),
        ] as [(String?, String?)] {
            XCTAssertNil(
                AuthService.resolvedOAuthCallbackScheme(
                    rawValue: rawValue,
                    bundleIdentifier: bundleIdentifier
                )
            )
        }

        let currentScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let mismatchedScheme = currentScheme == AuthService.productionOAuthCallbackScheme
            ? AuthService.developmentOAuthCallbackScheme
            : AuthService.productionOAuthCallbackScheme

        let mismatchedCallback = try XCTUnwrap(
            URL(string: "\(mismatchedScheme)://oauth/google?state=expected-state&code=code")
        )
        XCTAssertThrowsError(
            try AuthService.validatedGoogleOAuthCode(
                mismatchedCallback,
                expectedState: "expected-state",
                callbackScheme: currentScheme
            )
        ) { error in
            XCTAssertEqual(error as? UserVisibleError, .oauthCallbackInvalid)
        }
        XCTAssertThrowsError(
            try AuthService.googleOAuthTransaction(
                config: makeAuthConfig(),
                state: "untrusted-state",
                codeVerifier: String(repeating: "u", count: 64),
                callbackScheme: mismatchedScheme
            )
        ) { error in
            XCTAssertEqual(error as? UserVisibleError, .oauthCallbackInvalid)
        }
    }

    @MainActor
    func testUITestAuthPersistenceBypassIsDevelopmentOnly() {
        let arguments = ["UITEST_AUTH_NO_PERSIST"]
        for bundleIdentifier in AuthService.developmentBundleIdentifiers {
            XCTAssertTrue(
                AuthService.shouldDisableAuthPersistence(
                    arguments: arguments,
                    bundleIdentifier: bundleIdentifier
                )
            )
            XCTAssertTrue(
                AuthService.shouldReturnEmptyAuthState(
                    arguments: arguments,
                    bundleIdentifier: bundleIdentifier
                ),
                "No-persist probes must never read or refresh a stored session."
            )
        }
        for bundleIdentifier in [
            AuthService.productionBundleIdentifier,
            "another.app",
        ] {
            XCTAssertFalse(
                AuthService.shouldDisableAuthPersistence(
                    arguments: arguments,
                    bundleIdentifier: bundleIdentifier
                )
            )
            XCTAssertFalse(
                AuthService.shouldReturnEmptyAuthState(
                    arguments: arguments,
                    bundleIdentifier: bundleIdentifier
                )
            )
        }
        XCTAssertFalse(
            AuthService.shouldDisableAuthPersistence(
                arguments: [],
                bundleIdentifier: "com.aryasalem.BrassTune.dev"
            )
        )
        XCTAssertFalse(
            AuthService.shouldDisableAuthPersistence(
                arguments: arguments,
                bundleIdentifier: nil
            )
        )
        XCTAssertTrue(
            AuthService.shouldReturnEmptyAuthState(
                arguments: ["UITEST_AUTH_EMPTY"],
                bundleIdentifier: "com.aryasalem.BrassTune.dev"
            )
        )
        XCTAssertFalse(
            AuthService.shouldReturnEmptyAuthState(
                arguments: ["UITEST_AUTH_EMPTY"],
                bundleIdentifier: AuthService.productionBundleIdentifier
            )
        )
    }

    @MainActor
    func testGoogleOAuthCallbackRejectsStateMismatchTokensAndUnexpectedFields() throws {
        let callbackScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let valid = try XCTUnwrap(
            URL(string: "\(callbackScheme)://oauth/google?state=expected&code=single-use-code")
        )
        XCTAssertEqual(
            try AuthService.validatedGoogleOAuthCode(
                valid,
                expectedState: "expected",
                callbackScheme: callbackScheme
            ),
            "single-use-code"
        )

        for invalid in [
            "\(callbackScheme)://oauth/google?state=wrong&code=single-use-code",
            "\(callbackScheme)://oauth/google?state=expected&access_token=must-not-be-accepted",
            "\(callbackScheme)://oauth/google?state=expected&code=ok&extra=unexpected",
            "\(callbackScheme)://oauth/google?state=expected&code=ok#access_token=secret",
            "other.app://oauth/google?state=expected&code=ok",
        ] {
            let url = try XCTUnwrap(URL(string: invalid))
            XCTAssertThrowsError(
                try AuthService.validatedGoogleOAuthCode(
                    url,
                    expectedState: "expected",
                    callbackScheme: callbackScheme
                ),
                invalid
            ) { error in
                XCTAssertEqual(error as? UserVisibleError, .oauthCallbackInvalid)
            }
        }
    }

    @MainActor
    func testAppleServiceSendsExactNonceAndIdentityTokenAndPersistsSession() async throws {
        let credentialStore = InMemoryAuthSessionStore()
        let networkSession = makeStubSession()
        let authService = AuthService(
            session: networkSession,
            readSessionPayload: { credentialStore.payload },
            saveSessionPayload: { credentialStore.payload = $0 },
            deleteSessionPayload: { credentialStore.payload = nil }
        )
        nonisolated(unsafe) var capturedRequest: URLRequest?
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            capturedRequest = request
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"apple-access","refresh_token":"apple-refresh","expires_in":3600,"user":{"id":"apple-user","email":"apple@example.com"}}"#.utf8)
            )
        }

        let result = try await authService.signInWithApple(
            identityToken: Data("signed-apple-identity-token".utf8),
            rawNonce: "exact-raw-nonce",
            config: makeAuthConfig()
        )

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/auth/v1/token")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "grant_type" })?.value,
            "id_token"
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(requestBodyData(request))) as? [String: String]
        )
        XCTAssertEqual(
            body,
            [
                "provider": "apple",
                "id_token": "signed-apple-identity-token",
                "nonce": "exact-raw-nonce",
            ]
        )
        XCTAssertEqual(result.session.userID, "apple-user")
        XCTAssertEqual(result.session.accessToken, "apple-access")
        XCTAssertEqual(try authService.restoreSessionOrThrow(), result.session)
        XCTAssertNotNil(credentialStore.payload)
    }

    @MainActor
    func testGoogleServiceUsesBrowserPKCEVerifierForTokenExchangeAndPersistsSession() async throws {
        let credentialStore = InMemoryAuthSessionStore()
        let networkSession = makeStubSession()
        nonisolated(unsafe) var capturedAuthorizationURL: URL?
        nonisolated(unsafe) var capturedCallbackScheme: String?
        nonisolated(unsafe) var capturedTokenRequest: URLRequest?
        let authService = AuthService(
            session: networkSession,
            readSessionPayload: { credentialStore.payload },
            saveSessionPayload: { credentialStore.payload = $0 },
            deleteSessionPayload: { credentialStore.payload = nil },
            webAuthentication: { authorizationURL, callbackScheme in
                capturedAuthorizationURL = authorizationURL
                capturedCallbackScheme = callbackScheme
                let authorizationQuery = URLComponents(
                    url: authorizationURL,
                    resolvingAgainstBaseURL: false
                )?.queryItems ?? []
                let redirect = try XCTUnwrap(
                    authorizationQuery.first(where: { $0.name == "redirect_to" })?.value
                )
                var callback = try XCTUnwrap(URLComponents(string: redirect))
                let state = try XCTUnwrap(
                    callback.queryItems?.first(where: { $0.name == "state" })?.value
                )
                callback.queryItems = [
                    URLQueryItem(name: "state", value: state),
                    URLQueryItem(name: "code", value: "single-use-google-code"),
                ]
                return try XCTUnwrap(callback.url)
            }
        )
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            capturedTokenRequest = request
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"google-access","refresh_token":"google-refresh","expires_in":3600,"user":{"id":"google-user","email":"google@example.com"}}"#.utf8)
            )
        }

        let session = try await authService.signInWithGoogle(config: makeAuthConfig())

        let authorizationURL = try XCTUnwrap(capturedAuthorizationURL)
        XCTAssertEqual(authorizationURL.path, "/auth/v1/authorize")
        XCTAssertEqual(capturedCallbackScheme, AuthService.oauthCallbackScheme)
        let authorizationQuery = URLComponents(
            url: authorizationURL,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        XCTAssertEqual(authorizationQuery.first(where: { $0.name == "provider" })?.value, "google")
        XCTAssertEqual(authorizationQuery.first(where: { $0.name == "code_challenge_method" })?.value, "s256")

        let tokenRequest = try XCTUnwrap(capturedTokenRequest)
        XCTAssertEqual(tokenRequest.url?.path, "/auth/v1/token")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(tokenRequest.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "grant_type" })?.value,
            "pkce"
        )
        let tokenBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(requestBodyData(tokenRequest))) as? [String: String]
        )
        XCTAssertEqual(tokenBody["auth_code"], "single-use-google-code")
        let verifier = try XCTUnwrap(tokenBody["code_verifier"])
        XCTAssertTrue((43...128).contains(verifier.count))
        let verifierDigest = Data(SHA256.hash(data: Data(verifier.utf8)))
        let expectedChallenge = verifierDigest.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(
            authorizationQuery.first(where: { $0.name == "code_challenge" })?.value,
            expectedChallenge
        )
        XCTAssertEqual(session.userID, "google-user")
        XCTAssertEqual(session.accessToken, "google-access")
        XCTAssertEqual(try authService.restoreSessionOrThrow(), session)
        XCTAssertNotNil(credentialStore.payload)
    }

    @MainActor
    func testGoogleServiceStateMismatchMakesZeroTokenRequestsAndWritesNoCredential() async throws {
        let credentialStore = InMemoryAuthSessionStore()
        nonisolated(unsafe) var tokenRequestCount = 0
        let authService = AuthService(
            session: makeStubSession(),
            readSessionPayload: { credentialStore.payload },
            saveSessionPayload: { credentialStore.payload = $0 },
            deleteSessionPayload: { credentialStore.payload = nil },
            webAuthentication: { _, callbackScheme in
                try XCTUnwrap(URL(string: "\(callbackScheme)://oauth/google?state=mismatched-state&code=must-not-exchange"))
            }
        )
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            tokenRequestCount += 1
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                data: Data()
            )
        }

        do {
            _ = try await authService.signInWithGoogle(config: makeAuthConfig())
            XCTFail("Expected mismatched OAuth state to fail closed")
        } catch let error as UserVisibleError {
            XCTAssertEqual(error, .oauthCallbackInvalid)
        }
        XCTAssertEqual(tokenRequestCount, 0)
        XCTAssertNil(credentialStore.payload)
        XCTAssertNil(try authService.restoreSessionOrThrow())
    }

    @MainActor
    func testPasswordResetRequestUsesTrustedHTTPSWebDestination() async throws {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        nonisolated(unsafe) var capturedRequest: URLRequest?
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            capturedRequest = request
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data()
            )
        }

        try await authService.requestPasswordReset(
            email: "player@example.com",
            config: makeAuthConfig()
        )

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/auth/v1/recover")
        let query = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        ).queryItems ?? []
        XCTAssertEqual(
            query.first(where: { $0.name == "redirect_to" })?.value,
            "https://brasstune.vercel.app/auth/reset-password"
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(requestBodyData(request))) as? [String: String]
        )
        XCTAssertEqual(body["email"], "player@example.com")
        XCTAssertNil(body["code_challenge_method"])
        XCTAssertNil(body["code_challenge"])
        XCTAssertNil(body["code_verifier"])
    }

    @MainActor
    func testRemoteOAuthProviderCapabilityEnablesOnlyConfiguredProvider() async throws {
        let networkSession = makeStubSession()
        nonisolated(unsafe) var providerRequestCount = 0
        let authService = AuthService(
            session: networkSession
        )
        let model = AppModel(
            persistenceStore: .ephemeral(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            ),
            authService: authService
        )
        model.config = makeAuthConfig()
        defer { StubURLProtocol.handler = nil }

        StubURLProtocol.handler = { request in
            if request.url?.path == "/auth/v1/settings" {
                providerRequestCount += 1
                return .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data: Data(#"{"external":{"email":true,"apple":false,"google":true}}"#.utf8)
                )
            }
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                data: Data()
            )
        }

        await model.loadAuthProviderConfiguration()
        XCTAssertFalse(model.appleSignInAvailable)
        XCTAssertTrue(model.googleSignInAvailable)
        XCTAssertEqual(model.authProviderConfiguration, AuthProviderConfiguration(apple: false, google: true))
        XCTAssertEqual(providerRequestCount, 1)
    }

    @MainActor
    func testProviderAndAppleFailuresRemainAtRecoverableGatewayWithoutWritingSession() async {
        let stored = InMemoryAuthSessionStore()
        let authService = AuthService(
            session: makeStubSession(),
            readSessionPayload: { stored.payload },
            saveSessionPayload: { stored.payload = $0 },
            deleteSessionPayload: { stored.payload = nil }
        )
        let model = AppModel(
            persistenceStore: .ephemeral(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            ),
            authService: authService
        )

        await model.loadAuthProviderConfiguration()
        XCTAssertFalse(model.appleSignInAvailable)
        XCTAssertFalse(model.googleSignInAvailable)
        XCTAssertEqual(
            model.authProviderRecoveryMessage,
            "BrassTune couldn't check Apple and Google sign-in. Retry or use email and password."
        )

        model.reportAuthFailure(.appleSignInCancelled)
        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertEqual(model.persistenceAccessState, .restoringIdentity)
        XCTAssertTrue(model.authNoticeIsError)
        XCTAssertEqual(model.authNotice, UserVisibleError.appleSignInCancelled.localizedDescription)
        XCTAssertNil(stored.payload)
    }

    @MainActor
    func testInfoPlistRegistersOnlyTheNativeOAuthCallbackScheme() throws {
        let appDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = appDirectory.appendingPathComponent("BrassTuneApp/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { type in
            type["CFBundleURLSchemes"] as? [String] ?? []
        }
        XCTAssertEqual(plist[AuthService.oauthCallbackSchemeInfoKey] as? String, "$(BRASSTUNE_AUTH_CALLBACK_SCHEME)")
        XCTAssertEqual(urlTypes.first?["CFBundleURLName"] as? String, "$(BRASSTUNE_AUTH_CALLBACK_SCHEME)")
        XCTAssertEqual(schemes, ["$(BRASSTUNE_AUTH_CALLBACK_SCHEME)"])
        XCTAssertEqual(plist["UIAppFonts"] as? [String], ["GoogleSans-Medium.ttf"])
        XCTAssertNil(String(data: data, encoding: .utf8)?.range(of: "secret", options: .caseInsensitive))

        let repositoryRoot = appDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let supabaseConfig = try String(
            contentsOf: repositoryRoot.appendingPathComponent("supabase/config.toml"),
            encoding: .utf8
        )
        XCTAssertTrue(
            supabaseConfig.contains(#""com.brasstune.auth://oauth/google\\?state=*""#),
            "The bounded native callback must escape the literal question mark before a dashboard config push."
        )
        XCTAssertFalse(
            supabaseConfig.contains(#""com.brasstune.auth://oauth/google?state=*""#),
            "An unescaped question mark is a one-character Supabase glob wildcard."
        )
    }

    @MainActor
    func testBuiltAppAndTestHostRegisterOnlyResolvedOAuthCallbackScheme() throws {
        let builtPlist = try XCTUnwrap(Bundle.main.infoDictionary)
        let configuredScheme = try XCTUnwrap(
            builtPlist[AuthService.oauthCallbackSchemeInfoKey] as? String
        )
        let expectedScheme = try XCTUnwrap(
            AuthService.resolvedOAuthCallbackScheme(
                rawValue: configuredScheme,
                bundleIdentifier: Bundle.main.bundleIdentifier
            )
        )
        XCTAssertEqual(builtPlist[AuthService.oauthCallbackSchemeInfoKey] as? String, expectedScheme)
        let urlTypes = try XCTUnwrap(builtPlist["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(urlTypes.count, 1)
        XCTAssertEqual(urlTypes.first?["CFBundleURLName"] as? String, expectedScheme)
        XCTAssertEqual(
            urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] },
            [expectedScheme]
        )
        XCTAssertEqual(AuthService.oauthCallbackScheme, expectedScheme)
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
            XCTAssertEqual(error as? UserVisibleError, .secureStorageCorrupt)
        }
        XCTAssertNotNil(store.payload, "An unreadable Keychain item must not be erased as though it were absent.")
    }

    @MainActor
    func testKeychainSaveUpdatesExistingAddsMissingAndPreservesExistingCredentialOnFailure() throws {
        var stored = "old"
        var addCalls = 0
        try KeychainStore.save(
            "new",
            service: "test",
            account: "account",
            update: { _, attributes in
                let values = attributes as NSDictionary
                stored = String(data: values[kSecValueData] as! Data, encoding: .utf8)!
                return errSecSuccess
            },
            add: { _ in addCalls += 1; return errSecSuccess }
        )
        XCTAssertEqual(stored, "new")
        XCTAssertEqual(addCalls, 0)

        stored = ""
        try KeychainStore.save(
            "added",
            service: "test",
            account: "account",
            update: { _, _ in errSecItemNotFound },
            add: { query in
                let values = query as NSDictionary
                stored = String(data: values[kSecValueData] as! Data, encoding: .utf8)!
                return errSecSuccess
            }
        )
        XCTAssertEqual(stored, "added")

        stored = "survives"
        XCTAssertThrowsError(
            try KeychainStore.save(
                "replacement",
                service: "test",
                account: "account",
                update: { _, _ in errSecNotAvailable },
                add: { _ in XCTFail("Add must not run when update failed"); return errSecSuccess }
            )
        ) { error in
            XCTAssertEqual(error as? KeychainStoreError, KeychainStoreError(operation: .save, status: errSecNotAvailable))
        }
        XCTAssertEqual(stored, "survives")
    }

    @MainActor
    func testGuestSignInRequiresExplicitMergeOrSeparateDecisionAndDeduplicatesSessions() async throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-guest-upgrade-\(UUID().uuidString).json")
        let credentials = InMemoryAuthSessionStore()
        let auth = AuthService(
            session: makeStubSession(),
            readSessionPayload: { credentials.payload },
            saveSessionPayload: { credentials.payload = $0 },
            deleteSessionPayload: { credentials.payload = nil }
        )
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: auth)
        model.config = makeAuthConfig()
        let duplicate = makeSession(name: "Existing account", cents: [1])
        let guestOnly = makeSession(name: "Guest only", cents: [2])
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            .init(response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data: Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"guest-upgrade","email":"player@example.com"}}"#.utf8))
        }

        await model.signIn(email: "player@example.com", password: "password")
        model.sessions = [duplicate]
        await model.signOut()
        model.enterGuestDemo(presentTutorial: false)
        model.sessions = [duplicate, guestOnly]
        let guestExercise: SavedPlayAlongExercise
        switch model.saveCustomExercise(title: "Guest pattern", notes: ["C", "D", "E"]) {
        case .success(let exercise): guestExercise = exercise
        case .failure(let error):
            XCTFail("Expected valid guest exercise: \(error)")
            return
        }
        model.updateWeeklyGoal(minutes: 145, sessions: 6)
        model.updateDroneSettings(
            DroneSettings(writtenMIDINote: 55, interval: .perfectFifth, volume: 0.18),
            restartIfPlaying: false
        )

        await model.signIn(email: "player@example.com", password: "password")
        XCTAssertEqual(model.authState, .guest)
        XCTAssertEqual(model.guestAccountUpgradePrompt?.canMerge, true)
        XCTAssertNil(credentials.payload, "A pending guest-upgrade choice must not create a restorable account session.")
        model.flushPendingPersistence()

        let relaunchedBeforeChoice = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            authService: auth
        )
        relaunchedBeforeChoice.config = makeAuthConfig()
        await relaunchedBeforeChoice.restoreSession()
        XCTAssertEqual(relaunchedBeforeChoice.authState, .guest)
        XCTAssertEqual(
            relaunchedBeforeChoice.sessions.map(\.id),
            [duplicate.id, guestOnly.id],
            "Relaunch before a choice must restore the guest namespace, not the pending account."
        )
        model.resolveGuestAccountUpgrade(.merge)

        XCTAssertEqual(model.authState, .signedIn(email: "player@example.com"))
        XCTAssertEqual(Set(model.sessions.map(\.id)), Set([duplicate.id, guestOnly.id]))
        XCTAssertEqual(model.sessions.count, 2)
        XCTAssertTrue(
            model.playAlongExercises.contains(where: { $0.id == guestExercise.exercise.id }),
            "Merge must preserve guest custom exercises as well as sessions."
        )
        XCTAssertEqual(model.practiceFeatures.weeklyGoal, WeeklyPracticeGoal(targetMinutes: 145, targetSessions: 6))
        XCTAssertEqual(
            model.practiceFeatures.droneSettings,
            DroneSettings(writtenMIDINote: 55, interval: .perfectFifth, volume: 0.18)
        )

        let relaunchedAfterMerge = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            authService: auth
        )
        relaunchedAfterMerge.config = makeAuthConfig()
        await relaunchedAfterMerge.restoreSession()
        XCTAssertEqual(relaunchedAfterMerge.authState, .signedIn(email: "player@example.com"))
        XCTAssertEqual(Set(relaunchedAfterMerge.sessions.map(\.id)), Set([duplicate.id, guestOnly.id]))
        XCTAssertTrue(relaunchedAfterMerge.playAlongExercises.contains(where: { $0.id == guestExercise.exercise.id }))
    }

    @MainActor
    func testGuestUpgradeKeepSeparateAndCancelPreserveGuestData() async throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-guest-choices-\(UUID().uuidString).json")
        let credentials = InMemoryAuthSessionStore()
        let auth = AuthService(session: makeStubSession(), readSessionPayload: { credentials.payload }, saveSessionPayload: { credentials.payload = $0 }, deleteSessionPayload: { credentials.payload = nil })
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: auth)
        model.config = makeAuthConfig()
        let guest = makeSession(name: "Guest survives", cents: [0])
        model.enterGuestDemo(presentTutorial: false)
        model.sessions = [guest]
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            .init(response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data: Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"guest-choice","email":"player@example.com"}}"#.utf8))
        }

        await model.signIn(email: "player@example.com", password: "password")
        model.resolveGuestAccountUpgrade(.cancel)
        XCTAssertEqual(model.authState, .guest)
        XCTAssertEqual(model.sessions.map(\.id), [guest.id])
        XCTAssertNil(credentials.payload)

        await model.signIn(email: "player@example.com", password: "password")
        model.resolveGuestAccountUpgrade(.keepSeparate)
        XCTAssertEqual(model.authState, .signedIn(email: "player@example.com"))
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNotNil(credentials.payload, "Keep separate is an explicit choice to persist the account session.")
        model.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(model.sessions.map(\.id), [guest.id])
    }

    @MainActor
    func testGuestUpgradeCorruptAccountNamespacePreservesGuestAndDefersCredentials() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-guest-upgrade-corrupt-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-guest-upgrade-corrupt-scores-\(UUID().uuidString)", isDirectory: true)
        let targetStateURL = NativeStorageNamespace.account(userID: "corrupt-target")
            .stateFile(basedAt: stateURL)
        let credentials = InMemoryAuthSessionStore()
        let auth = AuthService(
            session: makeStubSession(),
            readSessionPayload: { credentials.payload },
            saveSessionPayload: { credentials.payload = $0 },
            deleteSessionPayload: { credentials.payload = nil }
        )
        defer {
            StubURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: targetStateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        try FileManager.default.createDirectory(
            at: targetStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a BrassTune snapshot".utf8).write(to: targetStateURL)
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!,
                data: Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"corrupt-target","email":"player@example.com"}}"#.utf8)
            )
        }

        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            authService: auth
        )
        model.config = makeAuthConfig()
        model.enterGuestDemo(presentTutorial: false)
        let guestSession = makeSession(name: "Guest survives failed upgrade", cents: [0])
        model.sessions = [guestSession]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Guest score")
        model.flushPendingPersistence()

        await model.signIn(email: "player@example.com", password: "password")
        XCTAssertNotNil(model.guestAccountUpgradePrompt)
        XCTAssertNil(credentials.payload)

        model.resolveGuestAccountUpgrade(.keepSeparate)

        XCTAssertEqual(model.authState, .guest)
        XCTAssertEqual(model.persistenceAccessState, .guest)
        XCTAssertEqual(model.sessions.map(\.id), [guestSession.id])
        XCTAssertEqual(model.scores.map(\.title), ["Guest score"])
        XCTAssertNotNil(model.guestAccountUpgradePrompt, "The user must be able to cancel or retry after a target failure.")
        XCTAssertNotNil(model.lastError)
        XCTAssertNil(credentials.payload, "Failed target preparation must not write a restorable account credential.")

        let relaunched = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            authService: auth
        )
        relaunched.config = makeAuthConfig()
        await relaunched.restoreSession()
        XCTAssertEqual(relaunched.authState, .guest)
        XCTAssertEqual(relaunched.sessions.map(\.id), [guestSession.id])
        XCTAssertEqual(relaunched.scores.map(\.title), ["Guest score"])
    }

    @MainActor
    func testGuestUpgradeCredentialPersistenceFailureRestoresGuestBeforeCommit() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-guest-upgrade-keychain-\(UUID().uuidString).json")
        var storedCredential: String?
        let auth = AuthService(
            session: makeStubSession(),
            readSessionPayload: { storedCredential },
            saveSessionPayload: { _ in throw UserVisibleError.secureStorageSaveFailed },
            deleteSessionPayload: { storedCredential = nil }
        )
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!,
                data: Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"keychain-target","email":"player@example.com"}}"#.utf8)
            )
        }
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: auth)
        model.config = makeAuthConfig()
        model.enterGuestDemo(presentTutorial: false)
        let guestSession = makeSession(name: "Guest survives credential failure", cents: [0])
        model.sessions = [guestSession]

        await model.signIn(email: "player@example.com", password: "password")
        XCTAssertNotNil(model.guestAccountUpgradePrompt)
        XCTAssertNil(storedCredential)

        model.resolveGuestAccountUpgrade(.keepSeparate)

        XCTAssertEqual(model.authState, .guest)
        XCTAssertEqual(model.persistenceAccessState, .guest)
        XCTAssertEqual(model.sessions.map(\.id), [guestSession.id])
        XCTAssertNotNil(model.guestAccountUpgradePrompt)
        XCTAssertEqual(model.lastError, .secureStorageSaveFailed)
        XCTAssertNil(storedCredential)
    }

    @MainActor
    func testGuestMergeSnapshotWriteFailurePreservesGuestAndDoesNotPersistCredential() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-guest-merge-write-\(UUID().uuidString).json")
        let targetStateURL = NativeStorageNamespace.account(userID: "merge-write-target")
            .stateFile(basedAt: stateURL)
        let credentials = InMemoryAuthSessionStore()
        let store = NativePersistenceStore.ephemeral(
            fileURL: stateURL,
            writeData: { data, url in
                guard url.standardizedFileURL != targetStateURL.standardizedFileURL else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        let auth = AuthService(
            session: makeStubSession(),
            readSessionPayload: { credentials.payload },
            saveSessionPayload: { credentials.payload = $0 },
            deleteSessionPayload: { credentials.payload = nil }
        )
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!,
                data: Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"merge-write-target","email":"player@example.com"}}"#.utf8)
            )
        }
        let model = AppModel(persistenceStore: store, authService: auth)
        model.config = makeAuthConfig()
        model.enterGuestDemo(presentTutorial: false)
        let guestSession = makeSession(name: "Guest survives merged write failure", cents: [0])
        model.sessions = [guestSession]
        model.flushPendingPersistence()

        await model.signIn(email: "player@example.com", password: "password")
        XCTAssertEqual(model.guestAccountUpgradePrompt?.canMerge, true)
        XCTAssertNil(credentials.payload)

        model.resolveGuestAccountUpgrade(.merge)

        XCTAssertEqual(model.authState, .guest)
        XCTAssertEqual(model.persistenceAccessState, .guest)
        XCTAssertEqual(model.sessions.map(\.id), [guestSession.id])
        XCTAssertNotNil(model.guestAccountUpgradePrompt)
        XCTAssertNotNil(model.lastError)
        XCTAssertNil(credentials.payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetStateURL.path))

        let relaunched = AppModel(persistenceStore: store, authService: auth)
        relaunched.config = makeAuthConfig()
        await relaunched.restoreSession()
        XCTAssertEqual(relaunched.authState, .guest)
        XCTAssertEqual(relaunched.sessions.map(\.id), [guestSession.id])
    }

    @MainActor
    func testExpiredCredentialDeletionFailureLeavesRemovalMarkerForRelaunchRecovery() async throws {
        let credentials = InMemoryAuthSessionStore()
        credentials.payload = #"{"userID":"expired-user","accessToken":"old","refreshToken":"refresh","email":"expired@example.com","expiresAt":0}"#
        var pendingDigests: [String] = []
        let pendingStore = PendingDigestStore(load: { pendingDigests }, save: { pendingDigests = $0 })
        let auth = AuthService(
            session: makeStubSession(),
            readSessionPayload: { credentials.payload },
            saveSessionPayload: { credentials.payload = $0 },
            deleteSessionPayload: { throw UserVisibleError.secureStorageDeletionFailed }
        )
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-expired-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), pendingCredentialRemovalStore: pendingStore, authService: auth)
        model.config = makeAuthConfig()
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            .init(response: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, data: Data())
        }

        await model.restoreSession()
        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertEqual(model.lastError, .secureStorageDeletionFailed)
        XCTAssertFalse(pendingDigests.isEmpty)

        let relaunched = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), pendingCredentialRemovalStore: pendingStore, authService: auth)
        relaunched.config = makeAuthConfig()
        await relaunched.restoreSession()
        XCTAssertEqual(relaunched.authState, .signedOut)
        XCTAssertEqual(relaunched.lastError, .secureStorageDeletionFailed)
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
        let authService = makeIsolatedAuthService(session: session)
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
        XCTAssertEqual(
            model.authNotice,
            "Password reset email sent. Open the secure web reset page from the email, then return to BrassTune and sign in."
        )
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
                data: Data(#"{"id":"confirmation-id","email":"new@example.com","created_at":"2026-08-15T12:00:00Z"}"#.utf8)
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

    func testSupabaseAuthResponseDecodesNestedSessionUser() throws {
        let response = try JSONDecoder().decode(
            SupabaseAuthResponse.self,
            from: Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"nested-id","email":"nested@example.com","created_at":"2026-08-15T12:00:00Z"}}"#.utf8)
        )

        XCTAssertEqual(response.accessToken, "access")
        XCTAssertEqual(response.refreshToken, "refresh")
        XCTAssertEqual(response.expiresIn, 3600)
        XCTAssertEqual(response.user?.id, "nested-id")
        XCTAssertEqual(response.user?.email, "nested@example.com")
    }

    func testSupabaseAuthResponseIgnoresTopLevelUserOutsideSignup() throws {
        let response = try JSONDecoder().decode(
            SupabaseAuthResponse.self,
            from: Data(#"{"id":"top-level-id","email":"confirm@example.com","created_at":"2026-08-15T12:00:00Z","last_sign_in_at":"2026-08-15T12:00:00Z"}"#.utf8)
        )

        XCTAssertNil(response.accessToken)
        XCTAssertNil(response.refreshToken)
        XCTAssertNil(response.expiresIn)
        XCTAssertNil(response.user)
    }

    func testSupabaseAuthResponseEmptyAndMalformedPayloadsFailClosed() throws {
        let empty = try JSONDecoder().decode(SupabaseAuthResponse.self, from: Data("{}".utf8))
        XCTAssertNil(empty.user)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                SupabaseAuthResponse.self,
                from: Data(#"{"access_token":7}"#.utf8)
            )
        )
    }

    @MainActor
    func testNestedSignupConfirmationResponseRemainsRecoverable() async throws {
        let session = makeStubSession()
        let authService = makeIsolatedAuthService(session: session)
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"user":{"id":"nested-confirmation-id","email":"nested@example.com"}}"#.utf8)
            )
        }

        do {
            _ = try await authService.signUp(
                email: "nested@example.com",
                password: "long-enough-password",
                config: makeAuthConfig(),
                persist: false
            )
            XCTFail("A signup response without a session must require email confirmation.")
        } catch let error as UserVisibleError {
            XCTAssertEqual(error, .emailConfirmationRequired)
        }
    }

    @MainActor
    func testFailedSignupAndGenericTopLevelTokenResponsesNeverPersistCredentials() async throws {
        let cases: [(name: String, payload: String, signsUp: Bool, expectedError: UserVisibleError)] = [
            ("top-level confirmation", #"{"id":"confirmation-id","email":"new@example.com"}"#, true, .emailConfirmationRequired),
            ("nested confirmation", #"{"user":{"id":"nested-confirmation-id"}}"#, true, .emailConfirmationRequired),
            ("password token with top-level user", #"{"access_token":"password-token","id":"top-level-id","email":"token@example.com"}"#, false, .authenticationFailed),
            ("hybrid signup", #"{"access_token":"hybrid-token","id":"hybrid-id","email":"hybrid@example.com"}"#, true, .malformedResponse),
            ("empty signup", "{}", true, .authenticationFailed),
            ("malformed signup", #"{"access_token":7}"#, true, .malformedResponse),
            ("token without nested user", #"{"access_token":"orphan-token"}"#, true, .authenticationFailed),
        ]
        defer { StubURLProtocol.handler = nil }

        for fixture in cases {
            let counter = AuthPersistenceWriteCounter()
            let authService = AuthService(
                session: makeStubSession(),
                service: "com.brasstune.tests.\(UUID().uuidString)",
                account: "current-session",
                readSessionPayload: { nil },
                saveSessionPayload: { counter.payloads.append($0) },
                deleteSessionPayload: {}
            )
            StubURLProtocol.handler = { request in
                .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data: Data(fixture.payload.utf8)
                )
            }

            do {
                if fixture.signsUp {
                    _ = try await authService.signUp(
                        email: "new@example.com",
                        password: "long-enough-password",
                        config: makeAuthConfig()
                    )
                } else {
                    _ = try await authService.signIn(
                        email: "token@example.com",
                        password: "long-enough-password",
                        config: makeAuthConfig()
                    )
                }
                XCTFail("\(fixture.name) must fail closed.")
            } catch let error as UserVisibleError {
                XCTAssertEqual(error, fixture.expectedError, fixture.name)
            }
            XCTAssertEqual(counter.payloads.count, 0, fixture.name)
        }
    }

    @MainActor
    func testAutoConfirmedNestedSignupPersistsSessionExactlyOnce() async throws {
        let counter = AuthPersistenceWriteCounter()
        let authService = AuthService(
            session: makeStubSession(),
            service: "com.brasstune.tests.\(UUID().uuidString)",
            account: "current-session",
            readSessionPayload: { nil },
            saveSessionPayload: { counter.payloads.append($0) },
            deleteSessionPayload: {}
        )
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"confirmed-token","refresh_token":"confirmed-refresh","expires_in":3600,"user":{"id":"confirmed-id","email":"confirmed@example.com"}}"#.utf8)
            )
        }

        let session = try await authService.signUp(
            email: "confirmed@example.com",
            password: "long-enough-password",
            config: makeAuthConfig()
        )

        XCTAssertEqual(session.userID, "confirmed-id")
        XCTAssertEqual(counter.payloads.count, 1)
    }

    func testPhotosPickerDoesNotRequestFullLibraryPermission() throws {
        let infoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BrassTuneApp/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertNil(plist["NSPhotoLibraryUsageDescription"])
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
        model.resolveGuestAccountUpgrade(.keepSeparate)
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
        model.resolveGuestAccountUpgrade(.keepSeparate)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty, "Account B must not inherit account A or guest scores.")
        model.sessions = [makeSession(name: "Account B only", cents: [2])]

        await model.signOut()
        XCTAssertTrue(model.sessions.isEmpty)
        await model.signIn(email: "a@example.com", password: "password")
        XCTAssertEqual(model.sessions.map(\.id), [accountASession.id])
        XCTAssertEqual(model.scores.map(\.title), ["Account A score"])
        // A process relaunch cannot leave its old snapshot writer running.
        // Flush this still-live test model before constructing its replacement
        // so the test models that lifecycle instead of two app processes.
        model.flushPendingPersistence()

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
        afterDeletionRelaunch.resolveGuestAccountUpgrade(.keepSeparate)
        XCTAssertTrue(afterDeletionRelaunch.sessions.isEmpty, "A deleted account namespace must stay deleted after relaunch.")
        XCTAssertTrue(afterDeletionRelaunch.scores.isEmpty)
    }

    @MainActor
    func testMicrophoneRationaleStatePersistsPerGuestAndAccountNamespace() async throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BrassTune-microphone-rationale-\(UUID().uuidString).json"
        )
        let authService = makeIsolatedAuthService(session: makeStubSession())
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            authService: authService
        )
        model.config = makeAuthConfig()
        defer {
            StubURLProtocol.handler = nil
            try? authService.signOut()
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(
                at: NativeStorageNamespace.account(userID: "rationale-user").stateFile(basedAt: stateURL)
            )
        }
        StubURLProtocol.handler = { request in
            if request.url?.path == "/auth/v1/logout" {
                return .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    data: Data()
                )
            }
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"rationale-user","email":"player@example.com"}}"#.utf8)
            )
        }

        model.enterGuestDemo(presentTutorial: false)
        XCTAssertFalse(model.microphoneRationaleSeen)
        model.markMicrophoneRationaleSeen()
        model.flushPendingPersistence()
        XCTAssertTrue(model.microphoneRationaleSeen)

        await model.signIn(email: "player@example.com", password: "password")
        XCTAssertFalse(
            model.microphoneRationaleSeen,
            "A new account namespace must not inherit the guest rationale state."
        )
        model.markMicrophoneRationaleSeen()
        model.flushPendingPersistence()

        await model.signOut()
        model.enterGuestDemo(presentTutorial: false)
        XCTAssertTrue(
            model.microphoneRationaleSeen,
            "Returning to the guest namespace must restore its one-time rationale state."
        )
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
    func testAppleSignInFailsClosedUntilRemoteCapabilityIsLoaded() async {
        let model = AppModel(
            persistenceStore: .ephemeral(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            )
        )
        model.config = makeAuthConfig()

        await model.completeAppleSignIn(identityToken: Data("apple-id-token".utf8), rawNonce: "nonce")

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertEqual(model.lastError, .oauthProviderUnavailable)
        XCTAssertTrue(model.authNoticeIsError)
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
    func testScoreRenameTrimsPersistsAndRejectsInvalidTitles() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        model.enterGuestDemo(presentTutorial: false)
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Original title")
        let scoreID = try XCTUnwrap(model.scores.first?.id)

        XCTAssertTrue(model.renameScore(id: scoreID, title: "  Concert étude  "))
        XCTAssertEqual(model.scores.first?.title, "Concert étude")
        XCTAssertFalse(model.renameScore(id: scoreID, title: "   \n"))
        XCTAssertFalse(model.renameScore(id: scoreID, title: String(repeating: "A", count: 121)))
        XCTAssertEqual(model.scores.first?.title, "Concert étude")
        model.flushPendingPersistence()

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        restored.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(restored.scores.first?.title, "Concert étude")
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
    func testClearingPracticeHistoryPreservesImportedScoreFiles() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)
        model.enterGuestDemo(presentTutorial: false)
        model.sessions = [makeSession(name: "History to clear", cents: [-2, 0, 3])]

        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Local score")
        let fileName = try XCTUnwrap(model.scores.first?.localFileName)
        let storedURL = scoreDirectory.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        model.clearLocalPracticeData()

        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(model.scores.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scoreDirectory.path))
    }

    @MainActor
    func testLocalStateAndImportedScoresReceiveDataProtectionAndBackupExclusion() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-privacy-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-privacy-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)
        model.enterGuestDemo(presentTutorial: false)
        model.sessions = [makeSession(name: "Private state", cents: [0, 1, -1])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Private score")
        model.flushPendingPersistence()

        let scoreURL = try XCTUnwrap(model.scores.first.flatMap { model.storedScoreFileURL(for: $0) })
        for url in [stateURL, scoreDirectory, scoreURL] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            // The simulator does not report a protection attribute back from
            // attributesOfItem, but it does execute the same iOS API. This
            // keeps the test behavioral without treating simulator metadata as
            // physical-device proof.
            XCTAssertNoThrow(try NativeLocalStorageProtection.apply(to: url))
        }

        // Existing installs are migrated when their namespace is activated.
        for url in [stateURL, scoreDirectory, scoreURL] {
            var values = URLResourceValues()
            values.isExcludedFromBackup = false
            var mutableURL = url
            try mutableURL.setResourceValues(values)
        }
        let relaunched = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)
        relaunched.enterGuestDemo(presentTutorial: false)
        for url in [stateURL, scoreDirectory, scoreURL] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
    }

    func testStoredScoreFileRejectsTraversalAndAbsolutePersistedNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-safe-name-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = NativeScoreImportService(storageDirectory: directory)

        for unsafeName in ["../outside.png", "/tmp/outside.png", "nested/score.png", "..", "C:\\outside.png"] {
            XCTAssertNil(service.storedFileURL(named: unsafeName))
            XCTAssertThrowsError(try service.deleteStoredFile(named: unsafeName)) { error in
                XCTAssertEqual(error as? NativeScoreImportService.ImportError, .unsafeStoredFile)
            }
        }
    }

    func testStoredScoreFileRejectsSymlinkEscapeWithoutDeletingTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-symlink-\(UUID().uuidString)", isDirectory: true)
        let outsideURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-outside-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outsideURL)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("outside score".utf8).write(to: outsideURL)
        let linkURL = directory.appendingPathComponent("linked-score.png")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideURL)
        let service = NativeScoreImportService(storageDirectory: directory)

        XCTAssertNil(service.storedFileURL(named: "linked-score.png"))
        XCTAssertThrowsError(try service.deleteStoredFile(named: "linked-score.png")) { error in
            XCTAssertEqual(error as? NativeScoreImportService.ImportError, .unsafeStoredFile)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkURL.path))
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

    func testScoreImportCancellationIsNotPresentedAsAnError() {
        XCTAssertNil(scoreImportFailureMessage(for: CocoaError(.userCancelled)))
        XCTAssertNil(scoreImportFailureMessage(for: CancellationError()))
        XCTAssertNotNil(scoreImportFailureMessage(for: CocoaError(.fileReadCorruptFile)))
    }

    func testPhotoImportStoresTheDetectedImageTypeInsteadOfForcingPNG() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTuneScores-types-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = NativeScoreImportService(storageDirectory: directory)

        let png = try service.importImageData(
            makeTinyPNGData(),
            preferredName: "PNG score",
            sourceKind: .photos
        )
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(png.localFileName)).pathExtension, "png")

        let image = try XCTUnwrap(UIImage(data: makeTinyPNGData()))
        let jpegData = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let jpeg = try service.importImageData(
            jpegData,
            preferredName: "JPEG score",
            sourceKind: .photos
        )
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(jpeg.localFileName)).pathExtension, "jpg")
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
    func testClearingPracticeHistoryDoesNotDeleteScoresWhenScoreRemoverFails() throws {
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
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertNil(model.lastError)
        model.flushPendingPersistence()

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        restored.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(restored.scores.count, 1)
        XCTAssertTrue(restored.sessions.isEmpty)
    }

    @MainActor
    func testClearingPracticeHistoryDoesNotRequirePersistenceStoreClear() throws {
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
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertNil(model.lastError)
        model.flushPendingPersistence()

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        restored.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(restored.scores.first?.id, score.id)
        XCTAssertTrue(restored.sessions.isEmpty)
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
    func testLegacySilentMetronomeDefaultsMigrateToAudibleDefaultsAndWriteBack() throws {
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

        // The repaired snapshot must reach disk after the namespace becomes
        // writable, not be lost behind the restoring-identity write gate.
        restored.flushPendingPersistence()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migratedOnDisk = try decoder.decode(
            NativeLocalSnapshot.self,
            from: Data(contentsOf: stateURL)
        )
        XCTAssertEqual(migratedOnDisk.metronomeDefaultsVersion, 2)
        XCTAssertEqual(migratedOnDisk.snapshotVersion, 5)
        XCTAssertFalse(migratedOnDisk.metronome.muted)
        XCTAssertFalse(migratedOnDisk.metronome.visualOnly)
        XCTAssertEqual(migratedOnDisk.metronome.volume, 0.6, accuracy: 0.001)

        let secondRelaunch = AppModel(persistenceStore: store)
        secondRelaunch.enterGuestDemo(presentTutorial: false)
        XCTAssertFalse(secondRelaunch.metronome.muted)
        XCTAssertFalse(secondRelaunch.metronome.visualOnly)
        XCTAssertEqual(secondRelaunch.metronome.volume, 0.6, accuracy: 0.001)
    }

    @MainActor
    func testFailedRestoredSnapshotMigrationRearmsUntilNextPersistenceTrigger() async throws {
        let guestStateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-migration-retry-\(UUID().uuidString).json")
        let userID = "migration-retry-user"
        let accountStateURL = NativeStorageNamespace.account(userID: userID)
            .stateFile(basedAt: guestStateURL)
        defer {
            try? FileManager.default.removeItem(at: guestStateURL)
            try? FileManager.default.removeItem(at: accountStateURL)
        }
        var legacyMetronome = MetronomeSettings()
        legacyMetronome.muted = true
        legacyMetronome.visualOnly = true
        legacyMetronome.volume = 0
        NativePersistenceStore.ephemeral(fileURL: accountStateURL).save(
            NativeLocalSnapshot(
                selectedInstrumentId: "trumpet",
                referencePitchHz: 440,
                sessions: [],
                scores: [],
                activeScoreID: nil,
                metronome: legacyMetronome,
                metronomeDefaultsVersion: 1,
                gatewayCompleted: true
            )
        )
        let storedSession = AuthSession(
            userID: userID,
            accessToken: "unexpired-access",
            refreshToken: "refresh",
            email: "migration@example.com",
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let encodedSession = String(data: try JSONEncoder().encode(storedSession), encoding: .utf8)
        let writer = FailOncePersistenceWriter()
        let retryingStore = NativePersistenceStore.ephemeral(
            fileURL: guestStateURL,
            writeData: writer.write
        )
        let authService = AuthService(
            session: makeStubSession(),
            readSessionPayload: { encodedSession },
            saveSessionPayload: { _ in },
            deleteSessionPayload: { }
        )
        let restored = AppModel(persistenceStore: retryingStore, authService: authService)
        restored.config = makeAuthConfig()
        await restored.restoreSession()
        restored.flushPendingPersistence()
        for _ in 0..<50 where writer.attemptCount < 1 {
            await Task.yield()
        }
        XCTAssertEqual(writer.attemptCount, 1)

        // A failed asynchronous migration write stays armed without creating
        // an unbounded automatic retry loop.
        for _ in 0..<20 { await Task.yield() }
        restored.flushPendingPersistence()
        XCTAssertEqual(writer.attemptCount, 1)

        // The next real state change consumes the re-armed token and writes the
        // already-repaired snapshot exactly once.
        restored.referencePitchHz = 442
        restored.flushPendingPersistence()
        for _ in 0..<50 where writer.attemptCount < 2 {
            await Task.yield()
        }
        XCTAssertEqual(writer.attemptCount, 2)

        let secondRelaunch = AppModel(persistenceStore: retryingStore, authService: authService)
        secondRelaunch.config = makeAuthConfig()
        await secondRelaunch.restoreSession()
        XCTAssertEqual(secondRelaunch.authState, .signedIn(email: "migration@example.com"))
        XCTAssertEqual(secondRelaunch.referencePitchHz, 442)
        XCTAssertFalse(secondRelaunch.metronome.muted)
        XCTAssertFalse(secondRelaunch.metronome.visualOnly)
        XCTAssertEqual(secondRelaunch.metronome.volume, 0.6, accuracy: 0.001)
    }

    @MainActor
    func testShippingRestoreQuarantinesLegacyFixtureSessionsAndScoresAndWritesBack() throws {
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

        restored.flushPendingPersistence()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let quarantinedOnDisk = try decoder.decode(
            NativeLocalSnapshot.self,
            from: Data(contentsOf: stateURL)
        )
        XCTAssertTrue(quarantinedOnDisk.sessions.isEmpty)
        XCTAssertTrue(quarantinedOnDisk.scores.isEmpty)
        XCTAssertNil(quarantinedOnDisk.activeScoreID)
        XCTAssertEqual(quarantinedOnDisk.snapshotVersion, 5)

        let secondRelaunch = AppModel(persistenceStore: store)
        secondRelaunch.enterGuestDemo(presentTutorial: false)
        XCTAssertTrue(secondRelaunch.sessions.isEmpty)
        XCTAssertTrue(secondRelaunch.scores.isEmpty)
        XCTAssertNil(secondRelaunch.activeScoreID)
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
            XCTAssertEqual(range.minimumHz, try XCTUnwrap(item["expected_detector_min_frequency_hz"] as? Double))
            XCTAssertEqual(range.maximumHz, try XCTUnwrap(item["expected_detector_max_frequency_hz"] as? Double))
            let profile = try XCTUnwrap(InstrumentProfiles.profile(for: instrumentID))
            XCTAssertEqual(
                BrassTuneCore.midiToFrequency(Double(profile.practicalSoundingRange.minimum)),
                try XCTUnwrap(item["expected_practical_min_frequency_hz"] as? Double),
                accuracy: 0.000_000_1
            )
            XCTAssertEqual(
                BrassTuneCore.midiToFrequency(Double(profile.practicalSoundingRange.maximum)),
                try XCTUnwrap(item["expected_practical_max_frequency_hz"] as? Double),
                accuracy: 0.000_000_1
            )
        }
    }

    func testAllSelectedInstrumentDetectorWindowsGatePitchAtExactBoundaries() {
        let expectedRanges: [String: InstrumentAcousticRange] = [
            "trumpet": .init(minimumHz: 130, maximumHz: 1_500),
            "cornet": .init(minimumHz: 130, maximumHz: 1_500),
            "flugelhorn": .init(minimumHz: 130, maximumHz: 1_500),
            "c-trumpet": .init(minimumHz: 130, maximumHz: 1_500),
            "horn": .init(minimumHz: 80, maximumHz: 1_200),
            "trombone": .init(minimumHz: 50, maximumHz: 700),
            "euphonium": .init(minimumHz: 55, maximumHz: 800),
            "baritone-concert": .init(minimumHz: 55, maximumHz: 800),
            "baritone": .init(minimumHz: 55, maximumHz: 800),
            "euphonium-treble": .init(minimumHz: 55, maximumHz: 800),
            "tuba": .init(minimumHz: 30, maximumHz: 500),
        ]
        XCTAssertEqual(Set(InstrumentProfiles.all.map(\.id)), Set(expectedRanges.keys))
        for (instrument, range) in expectedRanges {
            XCTAssertEqual(InstrumentAcousticRange.forInstrument(instrument), range, instrument)
            XCTAssertEqual(NativePitchDetector.acousticRange(for: instrument), range, instrument)
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

    func testPracticalRangeBoundariesRemainAcceptedAcrossReferencePitchExtremes() {
        for profile in InstrumentProfiles.all {
            for referencePitchHz in [430.0, 440.0, 450.0] {
                for (midi, cents) in [
                    (profile.practicalSoundingRange.minimum, -10.0),
                    (profile.practicalSoundingRange.maximum, 10.0),
                ] {
                    let frequency = BrassTuneCore.midiToFrequency(
                        Double(midi),
                        referencePitchHz: referencePitchHz
                    ) * pow(2, cents / 1_200)
                    let frame = PitchFrame.detected(
                        timestampMs: 0,
                        frequencyHz: frequency,
                        confidence: 0.99,
                        rms: 0.1,
                        instrumentId: profile.id,
                        referencePitchHz: referencePitchHz
                    )
                    XCTAssertNotNil(frame.writtenNoteName, "\(profile.id), A4=\(referencePitchHz), \(cents) cents")
                    XCTAssertNotNil(frame.writtenOctave)
                    XCTAssertEqual(frame.centsDeviation ?? .nan, cents, accuracy: 0.000_001)
                    XCTAssertTrue(frame.isValidForRecording)
                }
            }
        }
    }

    func testBroadDetectorAcceptsOutsidePracticalRangeForMajorNinthTrebleLowBrass() throws {
        let profile = try XCTUnwrap(InstrumentProfiles.profile(for: "euphonium-treble"))
        XCTAssertEqual(profile.transpositionSemitones, 14)
        let outsidePracticalConcertMIDI = profile.practicalSoundingRange.minimum - 1
        let frequency = BrassTuneCore.midiToFrequency(Double(outsidePracticalConcertMIDI))
        XCTAssertTrue(InstrumentAcousticRange.forInstrument(profile.id).contains(frequency))

        let frame = PitchFrame.detected(
            timestampMs: 0,
            frequencyHz: frequency,
            confidence: 0.99,
            rms: 0.1,
            instrumentId: profile.id,
            referencePitchHz: 440
        )
        let expectedWrittenMIDI = BrassTuneCore.transposeConcertToWritten(
            outsidePracticalConcertMIDI,
            semitones: profile.transpositionSemitones
        )
        XCTAssertEqual(expectedWrittenMIDI, outsidePracticalConcertMIDI + 14)
        XCTAssertEqual(frame.writtenOctave, (expectedWrittenMIDI / 12) - 1)
        XCTAssertEqual(frame.centsDeviation ?? .nan, 0, accuracy: 0.000_001)
        XCTAssertTrue(frame.isValidForRecording)
    }

    func testUnknownInstrumentDetectorRangeFailsClosed() {
        let unknown = PitchFrame.detected(timestampMs: 0, frequencyHz: 440, confidence: 0.99, rms: 0.1, instrumentId: "unknown", referencePitchHz: 440)
        XCTAssertEqual(InstrumentAcousticRange.forInstrument("unknown").minimumHz, .infinity)
        XCTAssertNil(unknown.writtenNoteName)
        XCTAssertNil(unknown.centsDeviation)
        XCTAssertFalse(unknown.isValidForRecording)
        XCTAssertEqual(instrumentDisplayName("unknown"), "Unsupported instrument")
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

    func testNativeNoteStatisticsDurationWeightMedianAndDeviationMatchCloudAndWeb() throws {
        func event(id: Int, durationMs: Int, cents: Double) -> NativeNoteEvent {
            NativeNoteEvent(
                writtenNote: "D",
                writtenOctave: 4,
                startedAtMs: id * 10_000,
                endedAtMs: id * 10_000 + max(0, durationMs),
                durationMs: durationMs,
                sampleCount: 10,
                averageSignedCents: cents,
                averageAbsoluteCents: abs(cents),
                medianCents: cents,
                standardDeviationCents: 2,
                minimumCents: cents,
                maximumCents: cents,
                inTunePercentage: 70,
                stabilityScore: 90
            )
        }

        let weighted = try XCTUnwrap(
            NativePitchAnalytics.calculateNoteStatistics(
                events: [
                    event(id: 1, durationMs: 1_000, cents: 0),
                    event(id: 2, durationMs: 3_000, cents: 12),
                    event(id: 3, durationMs: 0, cents: -100)
                ]
            ).first
        )
        XCTAssertEqual(weighted.averageSignedCents, 9, accuracy: 0.000_001)
        XCTAssertEqual(weighted.medianCents, 12, accuracy: 0.000_001)
        XCTAssertEqual(weighted.standardDeviationCents, sqrt(27), accuracy: 0.000_001)

        let legacy = try XCTUnwrap(
            NativePitchAnalytics.calculateNoteStatistics(
                events: [
                    event(id: 4, durationMs: 0, cents: 4),
                    event(id: 5, durationMs: -1_000, cents: 10)
                ]
            ).first
        )
        XCTAssertEqual(legacy.averageSignedCents, 7, accuracy: 0.000_001)
        XCTAssertEqual(legacy.medianCents, 7, accuracy: 0.000_001)
        XCTAssertEqual(legacy.standardDeviationCents, 3, accuracy: 0.000_001)
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

    func testPlayAlongExerciseCatalogIncludesAllCoreGeneratedScaleFamilies() throws {
        let scaleCategories: [PlayAlongExerciseCategory] = [.major, .naturalMinor, .harmonicMinor, .melodicMinor, .chromatic]
        XCTAssertEqual(PlayAlongExercise.defaultExercise.id, "cmaj")
        XCTAssertEqual(PlayAlongExercise.library.filter { $0.category == .practicePattern }.count, 2)
        XCTAssertEqual(PlayAlongExercise.library.count, 62)
        XCTAssertEqual(Set(PlayAlongExercise.library.map(\.id)).count, PlayAlongExercise.library.count)
        XCTAssertTrue(["cmaj", "cmin", "csmin", "chromatic", "arpeggio", "longtones"].allSatisfy { id in
            PlayAlongExercise.library.contains { $0.id == id }
        })
        for category in scaleCategories {
            let exercises = PlayAlongExercise.library.filter { $0.category == category }
            XCTAssertEqual(exercises.count, 12, "\(category)")
            XCTAssertEqual(Set(exercises.compactMap { testPitchClass($0.writtenNotes.first ?? "") }).count, 12, "\(category)")
            XCTAssertFalse(exercises.contains { $0.writtenNotes.isEmpty }, "\(category)")
        }
    }

    func testPlayAlongScaleSpellingsAndPitchClassesMatchCore() throws {
        let coreTypes: [PlayAlongExerciseCategory: ScaleType] = [
            .major: .major,
            .naturalMinor: .naturalMinor,
            .harmonicMinor: .harmonicMinor,
            .melodicMinor: .melodicMinor,
            .chromatic: .chromatic,
        ]
        for (category, type) in coreTypes {
            let exercises = PlayAlongExercise.library.filter { $0.category == category }
            for (exercise, root) in zip(exercises, ScaleRoot.allCases) {
                let generated = try XCTUnwrap(ScaleGenerator.generate(root: root, type: type, octaves: .one, direction: .ascending))
                XCTAssertEqual(exercise.writtenNotes, generated.notes.map(\.writtenName), exercise.id)
                XCTAssertEqual(testPitchClass(exercise.writtenNotes.first ?? ""), root.pitchClass, exercise.id)
                XCTAssertEqual(exercise.writtenNotes.first, exercise.writtenNotes.last, exercise.id)
            }
        }
    }

    @MainActor
    func testTransientCoreScaleStartsWithoutPersistingACustomExercise() async throws {
        let model = makeModel(playAlongFixturesEnabled: true)
        let exercise = try XCTUnwrap(
            PlayAlongExercise.scaleExercise(
                root: .f,
                type: .melodicMinor,
                direction: .both,
                octaves: .two,
                id: "generated:f:melodic-minor:two:both"
            )
        )
        let customBefore = model.practiceFeatures.customExercises

        await model.startPlayAlong(exercise: exercise)

        XCTAssertEqual(model.playAlongSession?.exercise, exercise)
        XCTAssertEqual(model.playAlongSession?.exercise.writtenNotes.count, 29)
        XCTAssertEqual(model.practiceFeatures.customExercises, customBefore)
        XCTAssertFalse(model.playAlongExercises.contains { $0.id == exercise.id })
        model.stopPlayAlong()
    }

    func testThreeOctaveScaleAvailabilityFailsClosedForUnknownOrNarrowProfiles() {
        XCTAssertFalse(PlayAlongExercise.isScaleAvailable(
            root: .c, type: .major, octaves: .three, direction: .ascending, instrumentID: "unknown"
        ))
        XCTAssertFalse(PlayAlongExercise.isScaleAvailable(
            root: .c, type: .major, octaves: .three, direction: .ascending, instrumentID: "trumpet"
        ))
        XCTAssertTrue(PlayAlongExercise.isScaleAvailable(
            root: .d, type: .major, octaves: .three, direction: .ascending, instrumentID: "tuba"
        ))
        XCTAssertNil(PlayAlongExercise.scaleExercise(
            root: .c, type: .major, octaves: .three, id: "unsafe-unknown-profile"
        ))
    }

    @MainActor
    func testVisualScaleCompletionPersistsPracticeTimeWithoutPitchOrRecordingClaims() throws {
        let model = makeModel()
        let activityID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let configuration = VisualScalePracticeConfiguration(
            exerciseID: "scale:tuba:B:major:1:ascending",
            instrumentID: "tuba",
            root: .b,
            type: .major,
            octaves: .one,
            direction: .ascending,
            tempoBPM: 84,
            loopCount: 1
        )
        model.selectedInstrumentId = "tuba"
        let completion = VisualScalePracticeCompletion(
            activityInstanceID: activityID,
            configuration: configuration,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(18)
        )

        XCTAssertTrue(model.saveVisualScaleCompletion(completion))
        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(session.id, activityID)
        XCTAssertEqual(session.activityInstanceID, activityID)
        XCTAssertEqual(session.source, .manual)
        XCTAssertEqual(session.activity, .visualScalePractice)
        XCTAssertEqual(session.completion, .completed)
        XCTAssertEqual(session.visualScaleConfiguration, configuration)
        XCTAssertEqual(session.durationSeconds, 18, accuracy: 0.001)
        XCTAssertTrue(session.frames.isEmpty)
        XCTAssertNil(session.retainedRecordingURL)
        XCTAssertEqual(session.validFrameCount, 0)
        XCTAssertFalse(session.activity.contributesPitchMetrics)
        XCTAssertTrue(session.contributesPracticeTime)
        XCTAssertFalse(model.saveVisualScaleCompletion(completion), "Activity identity must prevent double logging.")

        let roundTrip = try JSONDecoder().decode(
            PracticeSession.self,
            from: JSONEncoder().encode(session)
        )
        XCTAssertEqual(roundTrip, session)
    }

    @MainActor
    func testScoreGuidedPracticePersistsOneManualAttachedCompletionWithoutAudioClaims() throws {
        let model = makeModel()
        var score = makeSampleScore()
        score.annotation.focusMeasures = "Measures 9–16"
        score.annotation.problemPassage = "Middle entrance"
        score.annotation.notes = "Keep the air moving through every note."
        model.scores = [score]
        model.selectedInstrumentId = "trumpet"
        model.setTempo(96)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let run = try XCTUnwrap(model.startScoreGuidedPractice(scoreID: score.id, startedAt: startedAt))
        XCTAssertEqual(run.configuration.tempoBPM, score.annotation.tempoTarget)
        XCTAssertEqual(run.configuration.focusMeasures, score.annotation.focusMeasures)
        XCTAssertEqual(run.configuration.pageNumber, score.selectedPage?.pageNumber)
        XCTAssertEqual(run.configuration.practiceNotes, score.annotation.notes)
        XCTAssertEqual(model.activeScoreID, score.id)
        XCTAssertEqual(model.metronome.bpm, 96, "Score tempo is run-local and must not overwrite the global metronome.")

        var discardedTimer = ScoreGuidedPracticeTimerState()
        discardedTimer.start(at: startedAt)
        discardedTimer.pause(at: startedAt.addingTimeInterval(3))
        XCTAssertTrue(model.sessions.isEmpty, "Discarding a guided timer must not persist a completion.")
        XCTAssertEqual(model.metronome.bpm, 96, "Cancelling a guided run must preserve global metronome tempo.")

        let completion = ScoreGuidedPracticeCompletion(
            activityInstanceID: run.activityInstanceID,
            configuration: run.configuration,
            startedAt: run.startedAt,
            completedAt: startedAt.addingTimeInterval(12)
        )
        XCTAssertTrue(model.saveScoreGuidedPracticeCompletion(completion))
        XCTAssertFalse(model.saveScoreGuidedPracticeCompletion(completion))
        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(session.attachedScoreID, score.id)
        XCTAssertEqual(session.scoreGuidedPracticeConfiguration, run.configuration)
        XCTAssertEqual(session.activity, .practicePlan)
        XCTAssertEqual(session.source, .manual)
        XCTAssertTrue(session.frames.isEmpty)
        XCTAssertNil(session.retainedRecordingURL)
        XCTAssertTrue(session.contributesPracticeTime)
        XCTAssertTrue(session.practiceNotes.contains("page \(run.configuration.pageNumber)"))
        XCTAssertTrue(session.practiceNotes.contains(run.configuration.practiceNotes))
        XCTAssertEqual(model.metronome.bpm, 96)
    }

    func testScoreGuidedPracticeTimerAccumulatesOnlyActiveFractionalSegments() {
        let origin = Date(timeIntervalSince1970: 1_800_000_000)
        var timer = ScoreGuidedPracticeTimerState()
        timer.start(at: origin)
        timer.pause(at: origin.addingTimeInterval(1.25))
        timer.pause(at: origin.addingTimeInterval(9)) // A paused timer must not double count.
        timer.resume(at: origin.addingTimeInterval(12))
        XCTAssertEqual(timer.activeDuration(at: origin.addingTimeInterval(12.4)), 1.65, accuracy: 0.000_001)
        timer.pause(at: origin.addingTimeInterval(13.75)) // background-style pause
        timer.resume(at: origin.addingTimeInterval(30))
        XCTAssertEqual(timer.finish(at: origin.addingTimeInterval(30.5)), 3.5, accuracy: 0.000_001)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.finish(at: origin.addingTimeInterval(40)), 3.5, accuracy: 0.000_001)
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
    func testClassDirectorAndInvitationFlowsUseExistingAPIContracts() async throws {
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
        defer {
            StubURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: stateURL)
        }

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
            let method = request.httpMethod ?? "GET"
            let path = request.url?.path ?? ""
            let data: Data
            switch (method, path) {
            case ("POST", "/api/ensemble/groups"):
                data = Data(#"{"id":7,"name":"Wind Ensemble","director_user_id":42,"join_code":"OLD7"}"#.utf8)
            case ("GET", "/api/ensemble/groups"):
                data = Data(#"[{"id":7,"name":"Wind Ensemble","director_user_id":42,"join_code":"OLD7","viewer_role":"owner","viewer_can_leave":false,"viewer_can_manage":true}]"#.utf8)
            case ("GET", "/api/ensemble/invitations"):
                data = Data(#"{"invitations":[{"member_id":901,"group_id":8,"group_name":"Studio One","instrument_id":"unassigned","role_in_group":"student","director_name":"Rivera"},{"member_id":902,"group_id":9,"group_name":"Studio Two","instrument_id":"unassigned","role_in_group":"student","director_name":"Chen"}]}"#.utf8)
            case ("GET", "/api/ensemble/groups/7"):
                data = Data(#"{"id":7,"name":"Wind Ensemble","director_user_id":42,"join_code":"OLD7","viewer_role":"owner","viewer_can_leave":false,"viewer_can_manage":true,"roster_scope":"full","members":[{"id":101,"group_id":7,"user_id":501,"username":"student_one","display_name":"Student One","instrument_id":"trumpet","role_in_group":"student","status":"active"}]}"#.utf8)
            case ("GET", "/api/ensemble/groups/7/roster"):
                data = Data(#"{"group_id":7,"practice_aggregate_scope":"membership_interval","students":[{"member_id":101,"user_id":501,"username":"student_one","display_name":"Student One","instrument_id":"trumpet","status":"active","role_in_group":"student","sessions_count":3,"practice_minutes":24.0,"average_abs_cents":6.5,"in_tune_percentage":82.0}]}"#.utf8)
            case ("GET", "/api/ensemble/groups/7/summary"):
                data = Data(#"{"group_id":7,"session_count":3,"sections":[{"instrument_id":"trumpet","session_count":3,"practice_minutes":24.0,"average_abs_cents":6.5,"top_problem_notes":[]}],"overall":{"instrument_id":"all","session_count":3,"practice_minutes":24.0,"average_abs_cents":6.5,"top_problem_notes":[]},"practice_aggregate_scope":"membership_interval"}"#.utf8)
            case ("POST", "/api/ensemble/groups/7/members/by-username"):
                data = Data(#"{"id":102,"group_id":7,"user_id":502,"username":"new_student","display_name":"New Student","instrument_id":"horn","role_in_group":"student","status":"invited"}"#.utf8)
            case ("POST", "/api/ensemble/groups/7/join-code/rotate"):
                data = Data(#"{"group_id":7,"join_code":"NEW7"}"#.utf8)
            case ("DELETE", "/api/ensemble/groups/7/members/101"):
                data = Data(#"{"removed":true}"#.utf8)
            case ("POST", "/api/ensemble/invitations/901/decline"):
                data = Data(#"{"declined":true}"#.utf8)
            case ("POST", "/api/ensemble/invitations/902/accept"):
                data = Data(#"{"accepted":true,"group_id":9}"#.utf8)
            default:
                XCTFail("Unexpected class request: \(method) \(path)")
                data = Data()
            }
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: data
            )
        }

        let created = await model.createEnsemble(name: " Wind Ensemble ")
        XCTAssertTrue(created)
        XCTAssertEqual(model.selectedEnsembleRoster.map(\.memberID), [101])
        XCTAssertEqual(model.selectedEnsembleAggregate?.sessionCount, 3)

        let invited = await model.inviteEnsembleMember(
            groupID: 7,
            username: " NEW_STUDENT ",
            instrumentID: "horn"
        )
        XCTAssertTrue(invited)
        let rotated = await model.rotateEnsembleJoinCode(id: 7)
        XCTAssertTrue(rotated)
        XCTAssertEqual(model.ensembles.first?.joinCode, "NEW7")
        let removed = await model.removeEnsembleMember(groupID: 7, memberID: 101)
        XCTAssertTrue(removed)

        let declined = await model.respondToEnsembleInvitation(memberID: 901, accept: false)
        XCTAssertTrue(declined)
        let accepted = await model.respondToEnsembleInvitation(
            memberID: 902,
            accept: true,
            instrumentID: "trombone"
        )
        XCTAssertTrue(accepted)

        XCTAssertTrue(capturedRequests.allSatisfy { $0.authorization == "Bearer fresh-token" })
        let invite = try XCTUnwrap(capturedRequests.first {
            $0.method == "POST" && $0.path == "/api/ensemble/groups/7/members/by-username"
        })
        let invitePayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(invite.body)) as? [String: String]
        )
        XCTAssertEqual(invitePayload["username"], "new_student")
        XCTAssertEqual(invitePayload["role_in_group"], "student")
        XCTAssertEqual(invitePayload["instrument_id"], "horn")
        let accept = try XCTUnwrap(capturedRequests.first {
            $0.method == "POST" && $0.path == "/api/ensemble/invitations/902/accept"
        })
        let acceptPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(accept.body)) as? [String: String]
        )
        XCTAssertEqual(acceptPayload["instrument_id"], "trombone")
    }

    func testClassAggregateDTOsIgnoreRecordingAndReflectionFields() throws {
        let decoder = JSONDecoder()
        let roster = try decoder.decode(
            EnsembleRoster.self,
            from: Data(#"{"group_id":7,"students":[{"member_id":101,"username":"student_one","display_name":"Student One","instrument_id":"trumpet","status":"active","role_in_group":"student","sessions_count":3,"practice_minutes":24.0,"average_abs_cents":6.5,"in_tune_percentage":82.0,"recording_url":"https://private.invalid/audio.wav","reflection":"private"}]}"#.utf8)
        )
        XCTAssertEqual(roster.students.first?.sessionsCount, 3)
        XCTAssertEqual(roster.students.first?.practiceMinutes, 24)

        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(roster)) as? [String: Any]
        )
        let students = try XCTUnwrap(encoded["students"] as? [[String: Any]])
        let student = try XCTUnwrap(students.first)
        XCTAssertNil(student["recording_url"])
        XCTAssertNil(student["reflection"])
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
        model.resolveGuestAccountUpgrade(.keepSeparate)
        model.sessions = [makeSession(name: "Private account session", cents: [2])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Private account score")

        await model.loadEnsembles()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertEqual(model.persistenceAccessState, .lockedSignedOut)
        XCTAssertFalse(model.gatewayCompleted)
        XCTAssertEqual(
            model.authNotice,
            NativeLocalization.string("Your sign-in expired. Sign in again, then retry.")
        )
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
        XCTAssertTrue(announcement.contains("concert-pitch transposition"))
        XCTAssertTrue(announcement.contains("change it later"))
        XCTAssertFalse(announcement.contains("Step"))
    }

    @MainActor
    func testProgressMilestonesAreEarnedOnlyFromRecordedLocalEvidence() {
        let model = makeModel()
        model.completeTutorial()

        var milestones = progressOnboardingMilestones(for: model)
        XCTAssertEqual(milestones.map(\.earned), [true, false, false, false])
        XCTAssertFalse(progressShouldShowWarmupResume(nil))

        var silentSession = makeSession(name: "Silence", cents: [0])
        silentSession.frames = [
            PitchFrame.detected(
                timestampMs: 0,
                frequencyHz: nil,
                confidence: 0,
                rms: 0,
                instrumentId: "trumpet",
                referencePitchHz: 440
            )
        ]
        model.sessions = [silentSession]
        milestones = progressOnboardingMilestones(for: model)
        XCTAssertEqual(
            milestones.map(\.earned),
            [true, false, false, false],
            "A silent or invalid detector frame is not a recorded note."
        )

        model.sessions = [makeSession(name: "First note", cents: [0])]
        milestones = progressOnboardingMilestones(for: model)
        XCTAssertEqual(milestones.map(\.earned), [true, true, false, false])

        let warmupStart = Date(timeIntervalSince1970: 1_000)
        model.startOrResumeWarmup(now: warmupStart)
        XCTAssertTrue(progressShouldShowWarmupResume(model.currentWarmupCheckpoint))
        model.advanceWarmup(now: warmupStart.addingTimeInterval(301))
        XCTAssertFalse(progressShouldShowWarmupResume(model.currentWarmupCheckpoint))

        model.practiceFeatures.playAlongAttempts = [
            makePlayAlongAttempt(notes: ["C", "D"], rating: .excellent)
        ]
        milestones = progressOnboardingMilestones(for: model)
        XCTAssertEqual(milestones.map(\.earned), [true, true, true, true])
    }

    func testProgressWeeklySessionsExcludesOlderPractice() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_770_206_400) // 2026-02-04 12:00:00 UTC
        var currentWeek = makeSession(name: "This week", cents: [0])
        currentWeek.startedAt = now.addingTimeInterval(-86_400)
        var previousWeek = makeSession(name: "Previous week", cents: [0])
        previousWeek.startedAt = now.addingTimeInterval(-8 * 86_400)

        let sessions = progressWeeklySessions(
            [previousWeek, currentWeek],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(sessions.map(\.id), [currentWeek.id])
    }

    func testTunerVoiceOverStateCombinesNoteAndQuantizedCentsWithoutFrameFlooding() {
        let previous = NativeLocalization.language
        defer { NativeLocalization.language = previous }
        NativeLocalization.language = .english

        XCTAssertEqual(
            tunerVoiceOverState(frame: nil, isListening: false),
            "Play a note, Ready"
        )
        let sharpA = makePlayAlongFrame(note: "A", cents: 11.1, timestampMs: 0)
        let sharpB = makePlayAlongFrame(note: "A", cents: 12.2, timestampMs: 100)
        let flat = makePlayAlongFrame(note: "A", cents: -17.4, timestampMs: 200)
        let centered = makePlayAlongFrame(note: "A", cents: 0, timestampMs: 300)
        let centeredSharp = makePlayAlongFrame(note: "A", cents: 5, timestampMs: 400)
        XCTAssertEqual(
            tunerVoiceOverState(frame: sharpA, isListening: true),
            tunerVoiceOverState(frame: sharpB, isListening: true),
            "Small frame-to-frame jitter in one five-cent bucket must not churn the accessibility value."
        )
        XCTAssertTrue(tunerVoiceOverState(frame: sharpA, isListening: true).contains("10 cents sharp"))
        XCTAssertTrue(tunerVoiceOverState(frame: flat, isListening: true).contains("15 cents flat"))
        XCTAssertTrue(tunerVoiceOverState(frame: sharpA, isListening: true).contains("A4"))
        XCTAssertTrue(tunerVoiceOverState(frame: centered, isListening: true).contains("0 cents, In tune"))
        XCTAssertTrue(tunerVoiceOverState(frame: centeredSharp, isListening: true).contains("+5 cents, In tune"))
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

    func testGeneratedScaleGraderRejectsCorrectPitchClassInWrongOctave() {
        var grader = PlayAlongGrader(
            writtenNotes: ["Bb"],
            writtenMIDIs: [58],
            holdDurationMs: 300,
            minimumSamples: 3,
            attackTrimMs: 0
        )

        for timestamp in stride(from: 0, through: 300, by: 100) {
            grader.feed(makePlayAlongFrame(note: "A#", cents: 2, timestampMs: timestamp, writtenOctave: 6))
        }
        XCTAssertFalse(grader.isComplete)
        XCTAssertTrue(grader.noteGrades.isEmpty)

        for timestamp in stride(from: 1_000, through: 1_300, by: 100) {
            grader.feed(makePlayAlongFrame(note: "A#", cents: 2, timestampMs: timestamp, writtenOctave: 3))
        }
        XCTAssertTrue(grader.isComplete)
        XCTAssertEqual(grader.noteGrades.first?.writtenNoteName, "Bb")
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

    func testFixtureFramesReflectInstrumentTransposition() throws {
        for profile in [InstrumentProfiles.profile(for: "trumpet"), InstrumentProfiles.profile(for: "horn")].compactMap({ $0 }) {
            let fixture = PitchFrame.fixture(index: 0, instrumentId: profile.id)
            let concertMIDI = Int(BrassTuneCore.frequencyToMidi(try XCTUnwrap(fixture.frequencyHz)).rounded())
            let writtenMIDI = BrassTuneCore.transposeConcertToWritten(concertMIDI, semitones: profile.transpositionSemitones)
            XCTAssertEqual(testPitchClass(fixture.writtenNoteName ?? ""), writtenMIDI % 12)
            XCTAssertEqual(fixture.writtenOctave, (writtenMIDI / 12) - 1)
        }
    }

    func testCoreProfilesDrivePitchFramesAndDroneMathIncludingLegacyIDs() throws {
        let expected: [(id: String, notation: String, semitones: Int)] = [
            ("trumpet", "B♭", 2), ("horn", "F", 7), ("trombone", "C", 0),
            ("french-horn", "F", 7), ("c_trumpet", "C", 0), ("euphonium-tc", "B♭", 14),
        ]
        for item in expected {
            let profile = try XCTUnwrap(InstrumentProfiles.profile(for: item.id))
            XCTAssertEqual(profile.displayNotation, item.notation)
            XCTAssertEqual(profile.transpositionSemitones, item.semitones)
            XCTAssertEqual(PracticePitchMath.concertMIDI(forWrittenMIDI: 60, instrumentID: item.id), 60 - item.semitones)
            let frame = PitchFrame.detected(
                timestampMs: 0,
                frequencyHz: BrassTuneCore.midiToFrequency(60 - Double(item.semitones)),
                confidence: 0.99,
                rms: 0.1,
                instrumentId: item.id,
                referencePitchHz: 440
            )
            XCTAssertEqual(frame.writtenNoteName, "C", item.id)
            XCTAssertEqual(frame.writtenOctave, 4, item.id)
        }
        XCTAssertEqual(instrumentDisplayName("trumpet"), "Trumpet in B♭")
        let drone = try XCTUnwrap(PracticePitchMath.frequency(writtenMIDI: 60, instrumentID: "horn", referencePitchHz: 440))
        XCTAssertEqual(drone, BrassTuneCore.midiToFrequency(53), accuracy: 0.000_001)
        XCTAssertNil(PracticePitchMath.frequency(writtenMIDI: 60, instrumentID: "unrecognized", referencePitchHz: 440))
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
    func testAudioControlPlaneRunsPhysicalToneHooksOffMainAndPreservesFIFOAcrossRestart() async throws {
        let probe = AudioControlPlaneProbe()
        probe.delayedEvent = .toneStop
        probe.delaySeconds = 0.05
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: { true }
        )

        try engine.startTone(frequencyHz: 440, volume: 0.3)
        await coordinator.flush()
        engine.stopTone(deactivation: .immediate)
        try engine.startTone(frequencyHz: 442, volume: 0.3)
        await coordinator.flush()
        for _ in 0..<10 { await Task.yield() }

        let events = probe.events
        let toneStarts = events.indices.filter { events[$0] == .toneStart }
        let tonePlays = events.indices.filter { events[$0] == .tonePlay }
        let toneStops = events.indices.filter { events[$0] == .toneStop }
        XCTAssertEqual(toneStarts.count, 2)
        XCTAssertEqual(tonePlays.count, 2)
        XCTAssertEqual(toneStops.count, 1)
        XCTAssertLessThan(try XCTUnwrap(toneStarts.first), try XCTUnwrap(tonePlays.first))
        XCTAssertLessThan(try XCTUnwrap(tonePlays.first), try XCTUnwrap(toneStops.first))
        XCTAssertLessThan(try XCTUnwrap(toneStarts.first), try XCTUnwrap(toneStops.first))
        XCTAssertLessThan(try XCTUnwrap(toneStops.first), try XCTUnwrap(toneStarts.last))
        XCTAssertTrue(probe.allPhysicalHooksOffMain)
        XCTAssertTrue(engine.tonePlaying, "A stale completion from the first start must not stop the restarted tone.")
        XCTAssertEqual(coordinator.activeOwners, [.tone])

        engine.stopTone(deactivation: .immediate)
        await coordinator.flush()
    }

    @MainActor
    func testConcurrentSameOwnerAcquiresAwaitOnePhysicalActivation() async throws {
        let probe = AudioControlPlaneProbe()
        probe.delayedEvent = .activate
        probe.delaySeconds = 0.05
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )

        let first = try coordinator.acquireTask(
            .recordingPlayback,
            configuration: .recordingPlayback
        )
        let second = try coordinator.acquireTask(
            .recordingPlayback,
            configuration: .recordingPlayback
        )
        let firstResult = try await first.value
        let secondResult = try await second.value

        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult, "A duplicate logical owner must await the in-flight physical readiness result.")
        XCTAssertEqual(probe.count(.configure(.recordingPlayback)), 1)
        XCTAssertEqual(probe.count(.activate), 1)
        XCTAssertEqual(coordinator.activeOwners, [.recordingPlayback])

        coordinator.release(.recordingPlayback, deactivation: .immediate)
        await coordinator.flush()
    }

    @MainActor
    func testConcurrentSameOwnerAcquiresShareFailureAndRollbackOwner() async throws {
        let probe = AudioControlPlaneProbe()
        probe.delayedEvent = .activate
        probe.delaySeconds = 0.05
        probe.failingEvent = .activate
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )

        let first = try coordinator.acquireTask(.metronome, configuration: .metronome)
        let second = try coordinator.acquireTask(.metronome, configuration: .metronome)
        for task in [first, second] {
            do {
                _ = try await task.value
                XCTFail("Every waiter must observe the shared physical activation failure.")
            } catch {
                XCTAssertEqual(error as? NativeAudioEngineError, .outputUnavailable)
            }
        }

        XCTAssertEqual(probe.count(.configure(.metronome)), 1)
        XCTAssertEqual(probe.count(.activate), 1)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        let physicalOwners = await coordinator.physicalActiveOwners()
        XCTAssertTrue(physicalOwners.isEmpty)
    }

    @MainActor
    func testProductionMetronomeGraphSchedulesThenPlaysWithoutWaitingForConsumption() async throws {
        let graphProbe = MetronomeGraphProbe()
        let sessionProbe = AudioControlPlaneProbe()
        let completionHandled = expectation(description: "stale production graph completion handled")
        var submittedCount = 0
        let coordinator = NativeAudioSessionCoordinator(
            hooks: sessionProbe.hooks,
            deactivationDelay: .zero
        )
        let output = NativeMetronomeOutput(
            audioSessionCoordinator: coordinator,
            onScheduleResult: { _ in completionHandled.fulfill() },
            onScheduleSubmitted: { submittedCount += 1 },
            graphHooks: graphProbe.hooks
        )

        output.playTick(
            settings: MetronomeSettings(),
            accent: false,
            hostTime: 123_456,
            pulseIndex: 1
        )
        for _ in 0..<100 where submittedCount < 1 {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(submittedCount, 1)
        XCTAssertEqual(graphProbe.events, ["prepare", "schedule", "play"])
        XCTAssertEqual(graphProbe.targets, [123_456])
        XCTAssertEqual(graphProbe.completionCount, 1)
        XCTAssertEqual(coordinator.activeOwners, [.metronome])

        let staleCompletion = try XCTUnwrap(graphProbe.completion(at: 0))
        output.stop()
        output.playTick(
            settings: MetronomeSettings(),
            accent: true,
            hostTime: 223_456,
            pulseIndex: 2
        )
        for _ in 0..<100 where submittedCount < 2 {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(submittedCount, 2)
        XCTAssertEqual(graphProbe.events, ["prepare", "schedule", "play", "stop", "prepare", "schedule", "play"])
        XCTAssertEqual(graphProbe.targets, [123_456, 223_456])

        staleCompletion(.failure(NativeAudioEngineError.outputUnavailable))
        await fulfillment(of: [completionHandled], timeout: 1)
        XCTAssertNil(output.lastFailure)
        XCTAssertEqual(coordinator.activeOwners, [.metronome])

        output.stop()
        await coordinator.flush()
    }

    @MainActor
    func testLiveCaptureLogicalStopIsSynchronousAndPhysicalRestartWaitsForFIFOTeardown() async throws {
        let probe = AudioControlPlaneProbe()
        probe.delayedEvent = .captureStop
        probe.delaySeconds = 0.08
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: { true }
        )

        let firstStartSucceeded = try await engine.startLiveRecording(
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        XCTAssertTrue(firstStartSucceeded)
        let clock = ContinuousClock()
        let stopStarted = clock.now
        let firstStop = engine.stopLiveRecording()
        let logicalStopDuration = stopStarted.duration(to: clock.now)
        XCTAssertLessThan(logicalStopDuration, .milliseconds(40))
        XCTAssertFalse(engine.recording)
        XCTAssertFalse(coordinator.isActive(.capture))

        let restarted = Task { @MainActor in
            try await engine.startLiveRecording(instrumentId: "trumpet", referencePitchHz: 440)
        }
        _ = await firstStop.value
        let restartSucceeded = try await restarted.value
        XCTAssertTrue(restartSucceeded)
        await coordinator.flush()

        let events = probe.events
        let installs = events.indices.filter { events[$0] == .captureInstallTap }
        let removals = events.indices.filter { events[$0] == .captureRemoveTap }
        XCTAssertEqual(installs.count, 2)
        XCTAssertEqual(removals.count, 1)
        XCTAssertLessThan(try XCTUnwrap(removals.first), try XCTUnwrap(installs.last))
        XCTAssertTrue(engine.recording)
        XCTAssertEqual(coordinator.activeOwners, [.capture])

        _ = await engine.stopLiveRecording().value
        await coordinator.flush()
    }

    @MainActor
    func testConcurrentLiveStartsInstallOnlyOneInputTap() async throws {
        let probe = AudioControlPlaneProbe()
        probe.delayedEvent = .captureStart
        probe.delaySeconds = 0.08
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: { true }
        )

        let firstStart = Task { @MainActor in
            try await engine.startLiveRecording(instrumentId: "trumpet", referencePitchHz: 440)
        }
        for _ in 0..<100 where probe.count(.captureInstallTap) == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(probe.count(.captureInstallTap), 1)

        let duplicateStart = try await engine.startLiveRecording(
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        XCTAssertFalse(duplicateStart, "A concurrent start must not reserve or install a second input tap.")
        let firstStartSucceeded = try await firstStart.value
        XCTAssertTrue(firstStartSucceeded)
        XCTAssertEqual(probe.count(.captureInstallTap), 1)

        _ = await engine.stopLiveRecording().value
        await coordinator.flush()
    }

    @MainActor
    func testFailedCaptureStartRollsBackTapSessionAndLogicalOwner() async throws {
        let probe = AudioControlPlaneProbe()
        probe.failingEvent = .captureStart
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: { true }
        )

        do {
            _ = try await engine.startLiveRecording(instrumentId: "trumpet", referencePitchHz: 440)
            XCTFail("The injected physical start failure must propagate.")
        } catch {
            XCTAssertEqual(error as? NativeAudioEngineError, .outputUnavailable)
        }
        await coordinator.flush()

        XCTAssertFalse(engine.recording)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        let physicalOwners = await coordinator.physicalActiveOwners()
        XCTAssertTrue(physicalOwners.isEmpty)
        XCTAssertEqual(probe.count(.captureInstallTap), 1)
        XCTAssertEqual(probe.count(.captureRemoveTap), 1)
        XCTAssertEqual(probe.count(.captureStop), 1)
        XCTAssertEqual(probe.count(.deactivate), 1)
    }

    @MainActor
    func testMediaResetRebuildsControlPlaneBeforeFreshToneStart() async throws {
        let probe = AudioControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: { true }
        )

        try engine.startTone(frequencyHz: 440, volume: 0.3)
        await coordinator.flush()
        let beforeReset = await coordinator.graphGeneration()
        engine.handleMediaServicesReset()
        await coordinator.flush()
        let afterReset = await coordinator.graphGeneration()
        XCTAssertGreaterThan(afterReset, beforeReset)
        XCTAssertEqual(probe.count(.rebuildGraphs), 1)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)

        try engine.startTone(frequencyHz: 442, volume: 0.3)
        await coordinator.flush()
        XCTAssertEqual(probe.count(.toneStart), 2)
        XCTAssertEqual(probe.count(.configure(.tone)), 2)
        XCTAssertEqual(probe.count(.activate), 2)
        XCTAssertEqual(coordinator.activeOwners, [.tone])

        engine.stopTone(deactivation: .immediate)
        await coordinator.flush()
    }

    @MainActor
    func testAudioSessionCoordinatorDeactivatesOnlyAfterFinalOwner() async throws {
        var activationCount = 0
        var deactivationCount = 0
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { activationCount += 1 },
            deactivateSession: { deactivationCount += 1 },
            deactivationDelay: .zero
        )

        try await coordinator.acquire(.capture)
        try await coordinator.acquire(.metronome)
        XCTAssertEqual(activationCount, 1)
        coordinator.release(.capture)
        XCTAssertEqual(deactivationCount, 0)
        coordinator.release(.metronome)
        await coordinator.flush()
        XCTAssertEqual(deactivationCount, 1)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)

        let metronomeOutput = NativeMetronomeOutput(audioSessionCoordinator: coordinator)
        try await coordinator.acquire(.capture)
        metronomeOutput.playTick(settings: MetronomeSettings(), accent: false)
        XCTAssertEqual(coordinator.activeOwners, [.capture], "A metronome timer must not acquire or reconfigure the session while capture owns measurement mode.")
        coordinator.release(.capture)
        await coordinator.flush()
        XCTAssertEqual(deactivationCount, 2)

        let engine = NativeAudioEngine(audioSessionCoordinator: coordinator)
        try await coordinator.acquire(.capture)
        engine.stopAndResetAudioEngine()
        await coordinator.flush()
        XCTAssertEqual(deactivationCount, 3, "Stopping capture must release and deactivate its final session owner.")

        try await coordinator.acquire(.metronome)
        metronomeOutput.stop()
        await coordinator.flush()
        XCTAssertEqual(deactivationCount, 4, "Stopping the metronome must release and deactivate its final session owner.")

        try await coordinator.acquire(.metronome)
        var mutedSettings = MetronomeSettings()
        mutedSettings.muted = true
        metronomeOutput.playTick(settings: mutedSettings, accent: false)
        await coordinator.flush()
        XCTAssertTrue(coordinator.activeOwners.isEmpty, "Switching to muted output must release metronome ownership immediately.")
        XCTAssertEqual(deactivationCount, 5)

        try await coordinator.acquire(.metronome)
        var visualSettings = MetronomeSettings()
        visualSettings.visualOnly = true
        metronomeOutput.playTick(settings: visualSettings, accent: false)
        await coordinator.flush()
        XCTAssertTrue(coordinator.activeOwners.isEmpty, "Switching to visual-only output must release metronome ownership immediately.")
        XCTAssertEqual(deactivationCount, 6)
    }

    @MainActor
    func testAudioSessionCoordinatorDefersAndCancelsDeactivationAcrossRapidHandoffs() async throws {
        var activationCount = 0
        var deactivationCount = 0
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { activationCount += 1 },
            deactivateSession: { deactivationCount += 1 },
            deactivationDelay: .milliseconds(40)
        )

        try await coordinator.acquire(.capture)
        coordinator.release(.capture)
        XCTAssertEqual(deactivationCount, 0)

        try await coordinator.acquire(.tone)
        XCTAssertEqual(activationCount, 1, "A rapid handoff must reuse the still-active shared session.")
        coordinator.release(.tone)
        XCTAssertEqual(deactivationCount, 0)

        try await Task.sleep(for: .milliseconds(80))
        await coordinator.flush()
        XCTAssertEqual(deactivationCount, 1, "Only the final quiescent release should deactivate the session.")

        try await coordinator.acquire(.capture)
        coordinator.release(.capture, deactivation: .immediate)
        await coordinator.flush()
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(deactivationCount, 2, "Lifecycle-loss paths must retain immediate deactivation.")
    }

    @MainActor
    func testAudioSessionCoordinatorCachesOnlyActiveDeferredOwnerConfiguration() async throws {
        let probe = AudioControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .seconds(5)
        )

        try await coordinator.acquire(.tone, configuration: .tone)
        coordinator.release(.tone)
        try await coordinator.acquire(.tone, configuration: .tone)
        XCTAssertEqual(probe.count(.configure(.tone)), 1, "A same-owner handoff during deferred deactivation should reuse AVAudioSession configuration.")
        XCTAssertEqual(probe.count(.activate), 1)

        coordinator.release(.tone, deactivation: .immediate)
        await coordinator.flush()
        try await coordinator.acquire(.tone, configuration: .tone)
        XCTAssertEqual(probe.count(.configure(.tone)), 2, "A real deactivation must require a fresh session configuration.")

        coordinator.invalidateSessionConfiguration()
        coordinator.release(.tone)
        try await coordinator.acquire(.tone, configuration: .tone)
        XCTAssertEqual(probe.count(.configure(.tone)), 3, "Lifecycle invalidation must never reuse a stale session configuration.")
    }

    @MainActor
    func testAudioSessionSetupRunsOnlyForNewOwnerAcquisition() async throws {
        let probe = AudioControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )

        let firstAcquire = try await coordinator.acquire(.tone, configuration: .tone)
        let repeatedAcquire = try await coordinator.acquire(.tone, configuration: .tone)
        XCTAssertTrue(firstAcquire)
        XCTAssertFalse(repeatedAcquire)
        XCTAssertEqual(probe.count(.configure(.tone)), 1)
        coordinator.release(.tone, deactivation: .immediate)
        await coordinator.flush()
    }

    @MainActor
    func testLifecycleTeardownForcesImmediateReleaseDespiteLongHandoffDelay() async throws {
        let probe = AudioControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .seconds(30)
        )

        try await coordinator.acquire(.tone)
        coordinator.release(.tone)
        coordinator.deactivateImmediatelyIfIdle()
        await coordinator.flush()
        XCTAssertEqual(probe.count(.deactivate), 1)
    }

    @MainActor
    func testMediaServicesResetForcesFreshConfigurationAndActivationAfterFailedDeactivation() async throws {
        let probe = AudioControlPlaneProbe()
        probe.failingEvent = .deactivate
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )

        try await coordinator.acquire(.tone, configuration: .tone)
        coordinator.release(.tone, deactivation: .immediate)
        await coordinator.flush()
        XCTAssertEqual(probe.count(.deactivate), 1)

        coordinator.invalidateAfterMediaServicesReset()
        try await coordinator.acquire(.tone, configuration: .tone)
        XCTAssertEqual(probe.count(.configure(.tone)), 2)
        XCTAssertEqual(probe.count(.activate), 2)
    }

    @MainActor
    func testRecordingPlaybackConfigurationParticipatesInDeferredReuse() async throws {
        let probe = AudioControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .seconds(5)
        )

        try await coordinator.acquire(.recordingPlayback, configuration: .recordingPlayback)
        coordinator.release(.recordingPlayback)
        try await coordinator.acquire(.recordingPlayback, configuration: .recordingPlayback)
        XCTAssertEqual(probe.count(.configure(.recordingPlayback)), 1)
    }

    @MainActor
    func testStaleMetronomeFailureCannotReleaseRestartedRun() async throws {
        let completionBox = MetronomeCompletionBox()
        let staleHandlerRan = expectation(description: "stale metronome result handled")
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { },
            deactivateSession: { },
            deactivationDelay: .zero
        )
        let output = NativeMetronomeOutput(
            audioSessionCoordinator: coordinator,
            scheduleOverride: { _, _, _, completion in
                completionBox.append(completion)
            },
            onScheduleResult: { _ in
                staleHandlerRan.fulfill()
            }
        )
        let settings = MetronomeSettings()

        output.playTick(settings: settings, accent: false)
        for _ in 0..<50 where completionBox.first == nil { await Task.yield() }
        let staleCompletion = try XCTUnwrap(completionBox.first)
        output.stop()
        output.playTick(settings: settings, accent: true)
        XCTAssertEqual(coordinator.activeOwners, [.metronome])

        staleCompletion(.failure(NativeAudioEngineError.outputUnavailable))
        await fulfillment(of: [staleHandlerRan], timeout: 1)

        XCTAssertEqual(coordinator.activeOwners, [.metronome])
        XCTAssertNil(output.lastFailure)
    }

    @MainActor
    func testMetronomeMediaResetForcesFreshActivationAfterFailedDeactivation() async throws {
        enum ExpectedFailure: Error { case deactivation }
        var activationCount = 0
        var deactivationCount = 0
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { activationCount += 1 },
            deactivateSession: {
                deactivationCount += 1
                throw ExpectedFailure.deactivation
            },
            deactivationDelay: .zero
        )
        let output = NativeMetronomeOutput(
            audioSessionCoordinator: coordinator,
            scheduleOverride: { _, _, _, completion in completion(.success(())) }
        )

        output.playTick(settings: MetronomeSettings(), accent: false)
        for _ in 0..<50 where !coordinator.isActive(.metronome) { await Task.yield() }
        coordinator.release(.metronome, deactivation: .immediate)
        await coordinator.flush()
        XCTAssertEqual(deactivationCount, 1, "The pre-reset immediate release must exercise a failing AVAudioSession deactivation.")
        XCTAssertTrue(coordinator.activeOwners.isEmpty)

        output.playTick(settings: MetronomeSettings(), accent: true)
        for _ in 0..<50 where !coordinator.isActive(.metronome) { await Task.yield() }
        await coordinator.flush()
        XCTAssertEqual(activationCount, 1, "A failed deactivation leaves the coordinator's active marker intact before reset.")
        XCTAssertEqual(coordinator.activeOwners, [.metronome])

        output.handleMediaServicesReset()
        await coordinator.flush()
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        XCTAssertEqual(deactivationCount, 1, "Reset must clear the stale marker before releasing ownership, not retry the invalid session.")

        output.playTick(settings: MetronomeSettings(), accent: true)
        for _ in 0..<50 where !coordinator.isActive(.metronome) { await Task.yield() }
        await coordinator.flush()
        XCTAssertEqual(activationCount, 2, "The post-reset metronome run must activate a fresh session.")
    }

    @MainActor
    func testRecordingPlaybackMediaResetStopsOwnershipAndForcesFreshConfiguration() async {
        let probe = AudioControlPlaneProbe()
        var playing = false
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .seconds(5)
        )
        let driver = NativeRecordingPlaybackDriver(
            duration: { 4 },
            currentTime: { 0 },
            setCurrentTime: { _ in },
            isPlaying: { playing },
            prepareToPlay: { true },
            play: { playing = true; return true },
            pause: { playing = false },
            stop: { playing = false }
        )
        let player = NativeRecordingPlayer(
            audioSessionCoordinator: coordinator,
            makeDriver: { _ in driver }
        )
        let url = URL(fileURLWithPath: "/app-owned/reset-test.caf")

        player.play(url: url)
        for _ in 0..<20 where player.state != .playing { await Task.yield() }
        XCTAssertEqual(coordinator.activeOwners, [.recordingPlayback])
        player.handleMediaServicesReset()
        XCTAssertEqual(player.state, .stopped)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        XCTAssertTrue(player.notice?.localizedCaseInsensitiveContains("services restarted") == true)

        player.play(url: url)
        for _ in 0..<20 where player.state != .playing { await Task.yield() }
        XCTAssertEqual(probe.count(.activate), 2)
        XCTAssertEqual(probe.count(.configure(.recordingPlayback)), 2)
        XCTAssertEqual(coordinator.activeOwners, [.recordingPlayback])
    }

    @MainActor
    func testRecordingPlaybackMediaResetUnloadsInvalidDriverForSameURLReplay() async {
        let probe = AudioControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        var makeDriverCount = 0
        var firstDriverIsInvalid = false
        var playedDriverIDs: [Int] = []
        let player = NativeRecordingPlayer(
            audioSessionCoordinator: coordinator,
            makeDriver: { _ in
                makeDriverCount += 1
                let driverID = makeDriverCount
                var isPlaying = false
                return NativeRecordingPlaybackDriver(
                    duration: { 3 },
                    currentTime: { 0 },
                    setCurrentTime: { _ in },
                    isPlaying: { isPlaying },
                    prepareToPlay: { !(driverID == 1 && firstDriverIsInvalid) },
                    play: {
                        guard !(driverID == 1 && firstDriverIsInvalid) else { return false }
                        playedDriverIDs.append(driverID)
                        isPlaying = true
                        return true
                    },
                    pause: { isPlaying = false },
                    stop: { isPlaying = false }
                )
            }
        )
        let url = URL(fileURLWithPath: "/app-owned/media-reset-reload.caf")

        player.play(url: url)
        for _ in 0..<50 where player.state != .playing { await Task.yield() }
        XCTAssertEqual(makeDriverCount, 1)
        XCTAssertEqual(playedDriverIDs, [1])

        firstDriverIsInvalid = true
        player.handleMediaServicesReset()
        await coordinator.flush()
        XCTAssertNil(player.loadedURL)
        XCTAssertEqual(player.duration, 0)

        player.play(url: url)
        for _ in 0..<50 where player.state != .playing { await Task.yield() }
        XCTAssertEqual(makeDriverCount, 2)
        XCTAssertEqual(playedDriverIDs, [1, 2])
        XCTAssertEqual(player.state, .playing)

        player.stopAndUnload()
        await coordinator.flush()
    }

    @MainActor
    func testRapidRecordingReplayDoesNotLetStaleWaiterReleaseSharedReadiness() async throws {
        let probe = AudioControlPlaneProbe()
        probe.delayedEvent = .activate
        probe.delaySeconds = 0.05
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        var playCount = 0
        var isPlaying = false
        let driver = NativeRecordingPlaybackDriver(
            duration: { 3 },
            currentTime: { 0 },
            setCurrentTime: { _ in },
            isPlaying: { isPlaying },
            prepareToPlay: { true },
            play: {
                playCount += 1
                isPlaying = true
                return true
            },
            pause: { isPlaying = false },
            stop: { isPlaying = false }
        )
        let player = NativeRecordingPlayer(
            audioSessionCoordinator: coordinator,
            makeDriver: { _ in driver }
        )
        let url = URL(fileURLWithPath: "/app-owned/rapid-replay.caf")

        player.play(url: url)
        player.play(url: url)
        for _ in 0..<100 where player.state != .playing {
            try await Task.sleep(for: .milliseconds(2))
        }
        await coordinator.flush()

        XCTAssertEqual(probe.count(.activate), 1)
        XCTAssertEqual(playCount, 1)
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(coordinator.activeOwners, [.recordingPlayback])
        let physicalOwners = await coordinator.physicalActiveOwners()
        XCTAssertEqual(physicalOwners, [.recordingPlayback])

        player.stopAndUnload()
        await coordinator.flush()
    }

    @MainActor
    func testToneBufferCacheReusesNormalizedBuffersWithinBoundedCapacity() throws {
        let cache = NativeToneBufferCache(capacity: 2)
        let first = try cache.buffer(for: [440])
        let repeated = try cache.buffer(for: [440])
        XCTAssertTrue(first === repeated)
        XCTAssertEqual(first.frameLength, 44_100)
        XCTAssertEqual(first.format.sampleRate, 44_100)
        XCTAssertEqual(try XCTUnwrap(first.floatChannelData?[0])[0], 0, accuracy: 0.000_001)

        let chord = try cache.buffer(for: [440, 550])
        let samples = chord.floatChannelData?[0]
        XCTAssertNotNil(samples)
        let peak = (0..<Int(chord.frameLength)).reduce(Float.zero) { current, index in
            max(current, abs(samples![index]))
        }
        XCTAssertLessThanOrEqual(peak, 1.000_001, "Normalized chord buffers must not encode user volume or clip.")

        _ = try cache.buffer(for: [660])
        XCTAssertEqual(cache.count, 2, "The cache must evict rather than retaining arbitrary tone combinations.")
    }

    @MainActor
    func testMetronomeStopWithoutSessionOwnerIsNoOp() {
        var deactivationCount = 0
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { },
            deactivateSession: { deactivationCount += 1 },
            deactivationDelay: .zero
        )
        let output = NativeMetronomeOutput(audioSessionCoordinator: coordinator)

        output.stop()

        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        XCTAssertEqual(deactivationCount, 0)
    }

    @MainActor
    func testToneRouteLossAndInterruptionDeactivateWithoutWaitingForIdleDelay() async throws {
        var activationCount = 0
        var deactivationCount = 0
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { activationCount += 1 },
            deactivateSession: { deactivationCount += 1 },
            deactivationDelay: .seconds(5)
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            simulateTonePlayback: true
        )

        try engine.startTone(frequencyHz: 440, volume: 0.5)
        try await coordinator.acquire(.tone)
        engine.handleRouteChange(rawReason: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
        await coordinator.flush()
        XCTAssertEqual(deactivationCount, 1, "Route loss must not leave a deferred audio-session deactivation pending.")
        XCTAssertTrue(coordinator.activeOwners.isEmpty)

        try engine.startTone(frequencyHz: 440, volume: 0.5)
        try await coordinator.acquire(.tone)
        engine.handleInterruption(rawType: AVAudioSession.InterruptionType.began.rawValue)
        await coordinator.flush()
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(deactivationCount, 2, "An interruption must deactivate immediately even when normal handoffs are delayed.")
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
    }

    @MainActor
    func testAudioSessionCoordinatorRejectsIncompatibleOwnersAndMakesRepeatedHandoffsIdempotent() async throws {
        var activationCount = 0
        var deactivationCount = 0
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { activationCount += 1 },
            deactivateSession: { deactivationCount += 1 },
            deactivationDelay: .zero
        )

        let firstCaptureAcquire = try await coordinator.acquire(.capture)
        let repeatedCaptureAcquire = try await coordinator.acquire(.capture)
        XCTAssertTrue(firstCaptureAcquire)
        XCTAssertFalse(repeatedCaptureAcquire)
        XCTAssertEqual(activationCount, 1)
        do {
            _ = try await coordinator.acquire(.tone)
            XCTFail("Capture and tone must conflict.")
        } catch {
            XCTAssertEqual(error as? NativeAudioEngineError, .audioSessionOwnerConflict)
        }
        XCTAssertEqual(coordinator.activeOwners, [.capture])
        coordinator.release(.tone)
        coordinator.release(.capture)
        coordinator.release(.capture)
        await coordinator.flush()
        XCTAssertEqual(deactivationCount, 1)

        try await coordinator.acquire(.recordingPlayback)
        do { _ = try await coordinator.acquire(.capture); XCTFail("Playback and capture must conflict.") }
        catch { XCTAssertEqual(error as? NativeAudioEngineError, .audioSessionOwnerConflict) }
        do { _ = try await coordinator.acquire(.metronome); XCTFail("Playback and metronome must conflict.") }
        catch { XCTAssertEqual(error as? NativeAudioEngineError, .audioSessionOwnerConflict) }
        coordinator.release(.recordingPlayback)
        await coordinator.flush()
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(deactivationCount, 2)
    }

    func testAudioReferencePitchAndStableTunerStateRejectInvalidInputs() throws {
        XCTAssertEqual(NativeReferencePitch.sanitized(.nan), 440)
        XCTAssertEqual(NativeReferencePitch.sanitized(.infinity), 440)
        XCTAssertEqual(NativeReferencePitch.sanitized(429.9), 440)
        XCTAssertEqual(NativeReferencePitch.sanitized(450.1), 440)
        XCTAssertEqual(NativeReferencePitch.sanitized(442), 442)

        let stable = PitchFrame(
            timestampMs: 1, frequencyHz: 440, confidence: 0.98, rms: 0.08,
            centsDeviation: 0, tuningStatus: .inTune, writtenNoteName: "A",
            writtenOctave: 4, isValidForRecording: true
        )
        let lowConfidence = PitchFrame(
            timestampMs: 2, frequencyHz: 440, confidence: 0.4, rms: 0.08,
            centsDeviation: 0, tuningStatus: .unstable, writtenNoteName: "A",
            writtenOctave: 4, isValidForRecording: false
        )
        let outOfRange = PitchFrame(
            timestampMs: 3, frequencyHz: 440, confidence: 0.99, rms: 0.08,
            centsDeviation: nil, tuningStatus: .noLock, writtenNoteName: nil,
            writtenOctave: nil, isValidForRecording: false
        )
        XCTAssertTrue(NativeAudioEngine.isStableTunerFrame(stable))
        XCTAssertFalse(NativeAudioEngine.isStableTunerFrame(lowConfidence))
        XCTAssertFalse(NativeAudioEngine.isStableTunerFrame(outOfRange))
    }

    @MainActor
    func testAppModelSanitizesRestoredOrUserEnteredReferencePitch() {
        let model = makeModel()
        model.referencePitchHz = .nan
        XCTAssertEqual(model.referencePitchHz, 440)
        model.referencePitchHz = 451
        XCTAssertEqual(model.referencePitchHz, 440)
        model.referencePitchHz = 443
        XCTAssertEqual(model.referencePitchHz, 443)
    }

    func testMetronomeClickBuffersFollowNegotiatedFormatAndUseHostClockSeam() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffers = try NativeMetronomeClickBuffers(outputFormat: format)
        XCTAssertEqual(buffers.regular.format.sampleRate, 48_000, accuracy: 0.001)
        XCTAssertEqual(buffers.regular.format.channelCount, 2)
        XCTAssertEqual(buffers.accent.format.channelCount, 2)
        XCTAssertGreaterThan(buffers.regular.frameLength, 0)
        XCTAssertTrue(buffers.matches(format))

        let scheduled = NativeMetronomeScheduling.hostTime(now: 123_456)
        XCTAssertEqual(scheduled.hostTime, 123_456)

        let timeline = NativeMetronomeTimeline(anchorHostTime: 10_000, intervalSeconds: 0.125)
        XCTAssertEqual(
            timeline.hostTime(forPulseIndex: 10_000),
            10_000 &+ (AVAudioTime.hostTime(forSeconds: 0.125) &* 10_000),
            "Every pulse must stay anchored instead of accumulating rounded deadlines."
        )
        let targets = (1...360).map { timeline.hostTime(forPulseIndex: UInt64($0)) }
        XCTAssertEqual(targets.count, Set(targets).count)
        XCTAssertTrue(
            zip(targets, targets.dropFirst()).allSatisfy {
                $1 &- $0 == timeline.intervalHostTicks
            },
            "A six-minute-equivalent 360-pulse run must preserve one exact anchored host-time interval."
        )
        XCTAssertEqual(
            targets.last,
            timeline.anchorHostTime &+ (timeline.intervalHostTicks &* 360)
        )
    }

    func testStandaloneMetronomeSessionPolicyIsPlaybackOriented() throws {
        var captured: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
        NativeMetronomeSessionPolicy.configure { category, mode, options in
            captured = (category, mode, options)
        }
        XCTAssertEqual(captured?.0, .playback)
        XCTAssertEqual(captured?.1, .default)
        XCTAssertEqual(captured?.2, [.mixWithOthers])
    }

    @MainActor
    func testMetronomeHapticsRemainAvailableForVisualOnlyAndMutedTicks() {
        let coordinator = NativeAudioSessionCoordinator(activateSession: {}, deactivateSession: {})
        var accents: [Bool] = []
        let output = NativeMetronomeOutput(
            audioSessionCoordinator: coordinator,
            playHaptic: { accents.append($0) }
        )
        var visualOnly = MetronomeSettings()
        visualOnly.visualOnly = true
        visualOnly.hapticsEnabled = true
        output.playTick(settings: visualOnly, accent: true)
        var muted = MetronomeSettings()
        muted.muted = true
        muted.hapticsEnabled = true
        output.playTick(settings: muted, accent: false)
        XCTAssertEqual(accents, [true, false])
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
    }

    @MainActor
    func testMetronomeHandoffStopsReferenceToneBeforeStarting() throws {
        var stopped = false
        AppAudioOwnershipHandoff.prepareForMetronomePlayback { stopped = true }
        XCTAssertTrue(stopped)

        let coordinator = NativeAudioSessionCoordinator(activateSession: {}, deactivateSession: {})
        let engine = NativeAudioEngine(audioSessionCoordinator: coordinator, simulateTonePlayback: true)
        let model = makeModel(audioEngine: engine, audioSessionCoordinator: coordinator)
        try engine.startTone(frequencyHz: 440, volume: 0.3)
        XCTAssertTrue(engine.tonePlaying)
        model.startMetronome()
        XCTAssertFalse(engine.tonePlaying)
    }

    @MainActor
    func testMetronomeAcquireAndScheduleFailuresNotifyLifecycleHandler() async {
        let coordinator = NativeAudioSessionCoordinator(activateSession: {}, deactivateSession: {})
        _ = try? await coordinator.acquire(.tone, configuration: .tone)
        var events: [NativeMetronomeOutput.LifecycleEvent] = []
        let output = NativeMetronomeOutput(audioSessionCoordinator: coordinator)
        output.setLifecycleHandler { events.append($0) }
        output.playTick(settings: MetronomeSettings(), accent: false)
        XCTAssertEqual(events, [.outputFailure])

        let scheduleCoordinator = NativeAudioSessionCoordinator(activateSession: {}, deactivateSession: {})
        let scheduleOutput = NativeMetronomeOutput(
            audioSessionCoordinator: scheduleCoordinator,
            scheduleOverride: { _, _, _, completion in completion(.failure(NativeAudioEngineError.outputUnavailable)) }
        )
        scheduleOutput.setLifecycleHandler { events.append($0) }
        scheduleOutput.playTick(settings: MetronomeSettings(), accent: false)
        for _ in 0..<50 where events.count < 2 { await Task.yield() }
        XCTAssertEqual(events, [.outputFailure, .outputFailure])
        XCTAssertTrue(scheduleCoordinator.activeOwners.isEmpty)
    }

    @MainActor
    func testMetronomeActivationFailureStopsAppModelAndPresentsRecoverableNotice() async {
        let probe = AudioControlPlaneProbe()
        probe.failingEvent = .activate
        let coordinator = NativeAudioSessionCoordinator(hooks: probe.hooks, deactivationDelay: .zero)
        let model = makeModel(audioSessionCoordinator: coordinator)
        model.startMetronome()
        for _ in 0..<100 where model.metronomeRunning { await Task.yield() }
        XCTAssertFalse(model.metronomeRunning)
        XCTAssertEqual(
            model.lastError?.localizedDescription,
            NativeLocalization.string("Your audio output changed. Check your headphones or speaker before continuing.")
        )
    }

    @MainActor
    func testMetronomeColdStartWaitsForReadinessAndAnchorsFirstClickInTheFuture() async throws {
        var targets: [UInt64] = []
        let submitted = expectation(description: "initial metronome click submitted")
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: {},
            deactivateSession: {},
            deactivationDelay: .zero
        )
        let output = NativeMetronomeOutput(
            audioSessionCoordinator: coordinator,
            scheduleOverride: { _, _, hostTime, completion in
                targets.append(hostTime)
                completion(.success(()))
            },
            onScheduleSubmitted: { submitted.fulfill() }
        )
        let requestedHostTime = mach_absolute_time()
        output.playTick(
            settings: MetronomeSettings(),
            accent: true,
            hostTime: requestedHostTime,
            onInitialPulseScheduled: { anchorHostTime in
                XCTAssertEqual(anchorHostTime, targets.first)
            }
        )

        await fulfillment(of: [submitted], timeout: 1)
        let target = try XCTUnwrap(targets.first)
        XCTAssertGreaterThanOrEqual(
            target,
            requestedHostTime &+ AVAudioTime.hostTime(
                forSeconds: NativeMetronomeOutput.initialSchedulingMarginSeconds
            )
        )
    }

    @MainActor
    func testMetronomeRouteAndInterruptionResetGraphReleaseOwnershipAndNotifyAppModel() async throws {
        let graphProbe = MetronomeGraphProbe()
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: {},
            deactivateSession: {},
            deactivationDelay: .zero
        )
        var events: [NativeMetronomeOutput.LifecycleEvent] = []
        let output = NativeMetronomeOutput(
            audioSessionCoordinator: coordinator,
            scheduleOverride: { _, _, _, completion in completion(.success(())) },
            graphHooks: graphProbe.hooks
        )
        output.setLifecycleHandler { events.append($0) }
        output.playTick(settings: MetronomeSettings(), accent: false)
        for _ in 0..<50 where !coordinator.isActive(.metronome) { await Task.yield() }

        output.handleRouteChange(rawReason: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
        await coordinator.flush()
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        XCTAssertEqual(events, [.routeChanged])
        XCTAssertTrue(graphProbe.events.contains("reset"))

        output.playTick(settings: MetronomeSettings(), accent: false)
        for _ in 0..<50 where !coordinator.isActive(.metronome) { await Task.yield() }
        output.handleInterruption(rawType: AVAudioSession.InterruptionType.began.rawValue)
        await coordinator.flush()
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        XCTAssertEqual(events, [.routeChanged, .interruption])

        let model = makeModel(audioSessionCoordinator: coordinator)
        model.startMetronome()
        for _ in 0..<50 where !model.metronomeRunning { await Task.yield() }
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        for _ in 0..<50 where model.metronomeRunning { await Task.yield() }
        XCTAssertFalse(model.metronomeRunning)
        XCTAssertEqual(model.lastError?.localizedDescription, NativeLocalization.string("Microphone interrupted"))
    }

    func testAudioFrameDeliveryHopsToMainActorBeforeInvokingReceiver() async {
        let delivered = expectation(description: "Frame delivered on MainActor")
        let frame = PitchFrame(
            timestampMs: 7,
            frequencyHz: 440,
            confidence: 0.99,
            rms: 0.08,
            centsDeviation: 0,
            tuningStatus: .inTune,
            writtenNoteName: "A",
            writtenOctave: 4,
            isValidForRecording: true
        )
        let receiver = NativeAudioFrameDelivery.toMainActor { received in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(received, frame)
            delivered.fulfill()
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                receiver(frame)
                continuation.resume()
            }
        }
        await fulfillment(of: [delivered], timeout: 2)
    }

    func testLiveCaptureFinishDrainsTailFrameBeforeReturning() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
        buffer.frameLength = 256
        let pipeline = try XCTUnwrap(NativeLiveCapturePipeline(
            format: format,
            frameCapacity: 256,
            writer: nil,
            instrumentId: "trumpet",
            referencePitchHz: 440,
            receiveFrame: { _ in }
        ))

        pipeline.enqueueFromRenderTap(buffer, timestampMs: 321)
        let result = pipeline.finish()

        XCTAssertEqual(result.frames.count, 1)
        XCTAssertEqual(result.frames.first?.timestampMs, 321)
    }

    func testLiveCapturePipelineCountsOverflowAndMarksResultIncomplete() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
        buffer.frameLength = 256
        let pipeline = try XCTUnwrap(NativeLiveCapturePipeline(
            format: format,
            frameCapacity: 256,
            slotCount: 2,
            writer: nil,
            instrumentId: "trumpet",
            referencePitchHz: 440,
            automaticallyDrain: false,
            receiveFrame: { _ in }
        ))

        pipeline.enqueueFromRenderTap(buffer, timestampMs: 100)
        pipeline.enqueueFromRenderTap(buffer, timestampMs: 200)
        pipeline.enqueueFromRenderTap(buffer, timestampMs: 300)
        let result = pipeline.finish()

        XCTAssertEqual(result.frames.count, 1)
        XCTAssertEqual(result.droppedInputFrameCount, 2)
    }

    func testLiveCapturePipelineDiscardPreservesOverflowDiagnostics() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
        buffer.frameLength = 256
        let pipeline = try XCTUnwrap(NativeLiveCapturePipeline(
            format: format,
            frameCapacity: 256,
            slotCount: 2,
            writer: nil,
            instrumentId: "trumpet",
            referencePitchHz: 440,
            automaticallyDrain: false,
            receiveFrame: { _ in }
        ))

        pipeline.enqueueFromRenderTap(buffer, timestampMs: 100)
        pipeline.enqueueFromRenderTap(buffer, timestampMs: 200)
        pipeline.enqueueFromRenderTap(buffer, timestampMs: 300)
        let result = pipeline.discard()

        XCTAssertEqual(result.droppedInputFrameCount, 2)
    }

    @MainActor
    func testDiscardedLiveCapturePreservesDiagnosticsWithoutRepublishingAcceptedFrames() async throws {
        let probe = AudioControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: { true }
        )
        let model = makeModel(
            audioEngine: engine,
            audioSessionCoordinator: coordinator,
            playAlongFixturesEnabled: false
        )

        await model.startPlayAlong()
        XCTAssertEqual(model.playAlongPhase, .running)
        let acceptedFrame = PitchFrame.fixture(index: 0)
        engine.seedAcceptedLiveFrameForTesting(acceptedFrame)
        XCTAssertEqual(engine.frames, [acceptedFrame])
        XCTAssertEqual(engine.currentFrame, acceptedFrame)
        XCTAssertEqual(engine.acceptedLiveFrameCount, 1)
        let completion = try XCTUnwrap(model.stopPlayAlong())
        let capture = await completion.value

        XCTAssertEqual(capture.completionReason, .userStopped)
        XCTAssertEqual(capture.droppedInputFrameCount, 0)
        XCTAssertTrue(capture.frames.isEmpty)
        XCTAssertTrue(engine.frames.isEmpty)
        XCTAssertNil(engine.currentFrame)
        XCTAssertEqual(engine.acceptedLiveFrameCount, 1)
        XCTAssertFalse(engine.recording)
        XCTAssertFalse(coordinator.isActive(.capture))
        await coordinator.flush()
    }

    @MainActor
    func testTonePlaybackDoesNotManufactureMicrophonePermission() async throws {
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { },
            deactivateSession: { }
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: { false },
            simulateTonePlayback: true
        )
        let permissionGranted = await engine.requestMicrophonePermission()
        XCTAssertFalse(permissionGranted)
        XCTAssertEqual(engine.audioState, .permissionDenied)

        try engine.startTone(frequencyHz: 440, volume: 0.5)
        XCTAssertTrue(engine.tonePlaying)
        XCTAssertEqual(engine.audioState, .permissionDenied)
        engine.stopTone()
        XCTAssertEqual(engine.audioState, .permissionDenied)
    }

    @MainActor
    func testMediaServicesResetRebuildsGraphsAndReleasesMetronomeOwnership() async throws {
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { },
            deactivateSession: { }
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            simulateTonePlayback: true
        )
        XCTAssertEqual(engine.audioGraphGeneration, 0)
        engine.handleMediaServicesReset()
        await coordinator.flush()
        for _ in 0..<10 where engine.audioGraphGeneration == 0 { await Task.yield() }
        XCTAssertEqual(engine.audioGraphGeneration, 1)

        let output = NativeMetronomeOutput(audioSessionCoordinator: coordinator)
        try await coordinator.acquire(.metronome)
        output.handleMediaServicesReset()
        await coordinator.flush()
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        XCTAssertEqual(output.lastFailure, .outputUnavailable)
    }

    func testRecordingFileStoreOnlyReturnsAndDeletesOwnedPlayableFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTuneRecordings-\(UUID().uuidString)", isDirectory: true)
        let externalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).caf")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: externalURL)
        }
        let store = NativeRecordingFileStore(
            storageDirectory: directory,
            isPlayableAudio: { url in
                (try? Data(contentsOf: url)) == Data("valid".utf8)
            }
        )
        let ownedURL = store.destinationURL(id: UUID(uuidString: "10000000-0000-0000-0000-000000000099")!)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("valid".utf8).write(to: ownedURL)
        try Data("valid".utf8).write(to: externalURL)

        XCTAssertEqual(store.availableURL(ownedURL), ownedURL.standardizedFileURL)
        XCTAssertNil(store.availableURL(externalURL), "A retained URL outside BrassTune's namespaced directory must never be played or deleted.")
        XCTAssertNil(store.availableURL(directory.appendingPathComponent("missing.caf")))
        XCTAssertNil(store.availableURL(directory.appendingPathComponent("wrong.m4a")))

        try store.deleteRecording(at: externalURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalURL.path), "Cleanup must not touch a URL BrassTune does not own.")
        try store.deleteRecording(at: ownedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownedURL.path))
    }

    @MainActor
    func testListenBackUsesPlaybackCategoryAndReleasesOwnershipForPauseStopRouteAndInterruption() async throws {
        let probe = AudioControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        var playing = false
        var currentTime: TimeInterval = 0
        let driver = NativeRecordingPlaybackDriver(
            duration: { 12 },
            currentTime: { currentTime },
            setCurrentTime: { currentTime = $0 },
            isPlaying: { playing },
            prepareToPlay: { true },
            play: {
                playing = true
                return true
            },
            pause: { playing = false },
            stop: { playing = false }
        )
        let player = NativeRecordingPlayer(
            audioSessionCoordinator: coordinator,
            makeDriver: { _ in driver }
        )
        let url = URL(fileURLWithPath: "/app-owned/test.caf")

        player.play(url: url)
        for _ in 0..<20 where player.state != .playing { await Task.yield() }

        XCTAssertEqual(probe.count(.configure(.recordingPlayback)), 1)
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(coordinator.activeOwners, [.recordingPlayback])
        XCTAssertEqual(probe.count(.activate), 1)

        player.handleRouteChange(rawReason: AVAudioSession.RouteChangeReason.categoryChange.rawValue)
        XCTAssertEqual(player.state, .playing, "Self-induced category changes are not output loss.")

        player.pause()
        await coordinator.flush()
        XCTAssertEqual(player.state, .paused)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        XCTAssertEqual(probe.count(.deactivate), 1)

        player.play(url: url)
        for _ in 0..<20 where player.state != .playing { await Task.yield() }
        XCTAssertEqual(player.state, .playing)
        player.handleInterruption(rawType: AVAudioSession.InterruptionType.began.rawValue)
        XCTAssertEqual(player.state, .paused)
        XCTAssertTrue(player.notice?.contains("ready") == true)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)

        player.play(url: url)
        for _ in 0..<20 where player.state != .playing { await Task.yield() }
        player.handleRouteChange(rawReason: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
        XCTAssertEqual(player.state, .stopped)
        XCTAssertTrue(player.notice?.contains("output changed") == true)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        await coordinator.flush()
        XCTAssertEqual(probe.count(.activate), 3)
        XCTAssertEqual(probe.count(.deactivate), 3)
    }

    @MainActor
    func testListenBackFailureCopyNamesRecordingForCategoryAndDriverFailures() async {
        let categoryProbe = AudioControlPlaneProbe()
        categoryProbe.failingEvent = .configure(.recordingPlayback)
        let coordinator = NativeAudioSessionCoordinator(hooks: categoryProbe.hooks)
        let url = URL(fileURLWithPath: "/app-owned/test.caf")
        let driver = NativeRecordingPlaybackDriver(
            duration: { 1 },
            currentTime: { 0 },
            setCurrentTime: { _ in },
            isPlaying: { false },
            prepareToPlay: { true },
            play: { false },
            pause: {},
            stop: {}
        )
        let categoryFailurePlayer = NativeRecordingPlayer(
            audioSessionCoordinator: coordinator,
            makeDriver: { _ in driver }
        )

        categoryFailurePlayer.play(url: url)
        for _ in 0..<100 where categoryFailurePlayer.notice == nil {
            try? await Task.sleep(for: .milliseconds(2))
        }

        XCTAssertEqual(
            categoryFailurePlayer.notice,
            "BrassTune couldn't play this recording. Check your audio output and try again."
        )
        XCTAssertFalse(categoryFailurePlayer.notice?.localizedCaseInsensitiveContains("reference tone") == true)

        let driverProbe = AudioControlPlaneProbe()
        let driverCoordinator = NativeAudioSessionCoordinator(hooks: driverProbe.hooks)
        let driverFailurePlayer = NativeRecordingPlayer(
            audioSessionCoordinator: driverCoordinator,
            makeDriver: { _ in driver }
        )
        driverFailurePlayer.play(url: url)
        for _ in 0..<100 where driverFailurePlayer.notice == nil {
            try? await Task.sleep(for: .milliseconds(2))
        }

        XCTAssertEqual(
            driverFailurePlayer.notice,
            "BrassTune couldn't play this recording. Check your audio output and try again."
        )
        XCTAssertTrue(driverCoordinator.activeOwners.isEmpty)
    }

    @MainActor
    func testAudioEngineIgnoresCategoryChangeButStopsToneForLostOutputRoute() throws {
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: {},
            deactivateSession: {}
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            simulateTonePlayback: true
        )
        try engine.startTone(frequencyHz: 440, volume: 0.2)

        engine.handleRouteChange(rawReason: AVAudioSession.RouteChangeReason.categoryChange.rawValue)
        XCTAssertTrue(engine.tonePlaying)
        XCTAssertFalse(engine.routeChanged)

        engine.handleRouteChange(rawReason: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
        XCTAssertFalse(engine.tonePlaying)
        XCTAssertTrue(engine.routeChanged)
        XCTAssertTrue(engine.audioNotice?.contains("output changed") == true)
    }

    @MainActor
    func testAudioOperationalStateReflectsMicrophonePermissionResult() async {
        let deniedEngine = NativeAudioEngine(
            audioSessionCoordinator: NativeAudioSessionCoordinator(
                activateSession: {},
                deactivateSession: {}
            ),
            microphonePermissionRequester: { false }
        )
        XCTAssertEqual(deniedEngine.audioState, .permissionNotDetermined)
        let denied = await deniedEngine.requestMicrophonePermission()
        XCTAssertFalse(denied)
        XCTAssertEqual(deniedEngine.audioState, .permissionDenied)
        XCTAssertTrue(deniedEngine.permissionDenied)

        let grantedEngine = NativeAudioEngine(
            audioSessionCoordinator: NativeAudioSessionCoordinator(
                activateSession: {},
                deactivateSession: {}
            ),
            microphonePermissionRequester: { true }
        )
        let granted = await grantedEngine.requestMicrophonePermission()
        XCTAssertTrue(granted)
        XCTAssertEqual(grantedEngine.audioState, .permissionGranted(.idle))
        XCTAssertFalse(grantedEngine.permissionDenied)
    }

    @MainActor
    func testInterruptedCaptureRetainsOneSessionSnapshotAndDeletesItsFileWithSession() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let recordingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTuneRecordings-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: recordingDirectory)
        }
        let recordingURL = recordingDirectory.appendingPathComponent("interrupted.caf")
        try makeSilentCAF(at: recordingURL)
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(
            persistenceStore: store,
            recordingStorageDirectory: recordingDirectory
        )
        model.enterGuestDemo(presentTutorial: false)
        let captureID = UUID()
        let capture = NativeLiveCapture(
            id: captureID,
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_003),
            frames: (0..<8).map { PitchFrame.fixture(index: $0) },
            recordingURL: recordingURL,
            recordingRetentionFailure: nil,
            completionReason: .interruption
        )

        XCTAssertTrue(model.retainUnexpectedLiveCapture(capture))
        XCTAssertFalse(model.retainUnexpectedLiveCapture(capture), "The same interruption completion must be retained exactly once.")
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions.first?.retainedRecordingURL, recordingURL.standardizedFileURL)
        XCTAssertTrue(model.audioEngine.audioNotice?.contains("Saved") == true)
        model.flushPendingPersistence()

        let restored = AppModel(
            persistenceStore: store,
            recordingStorageDirectory: recordingDirectory
        )
        restored.enterGuestDemo(presentTutorial: false)
        let restoredSession = try XCTUnwrap(restored.sessions.first)
        XCTAssertEqual(restored.availableRecordingURL(for: restoredSession), recordingURL.standardizedFileURL)

        restored.deleteSession(id: restoredSession.id)
        XCTAssertTrue(restored.sessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordingURL.path))
    }

    @MainActor
    func testUserStoppedNoSignalCaptureReturnsTunerToIdleWithoutMicrophoneError() {
        let model = AppModel(
            persistenceStore: .ephemeral(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            )
        )
        model.enterGuestDemo(presentTutorial: false)
        let capture = NativeLiveCapture(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_000.2),
            frames: [],
            recordingURL: nil,
            recordingRetentionFailure: nil,
            completionReason: .userStopped
        )

        XCTAssertFalse(model.handleUserStoppedLiveCapture(capture))
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNil(model.lastError)
        XCTAssertNil(model.audioEngine.audioNotice)
    }

    @MainActor
    func testUserStoppedCaptureDoesNotHideDroppedFrameFailure() {
        let model = AppModel(
            persistenceStore: .ephemeral(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            )
        )
        model.enterGuestDemo(presentTutorial: false)
        let capture = NativeLiveCapture(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_003),
            frames: (0..<8).map { PitchFrame.fixture(index: $0) },
            droppedInputFrameCount: 1,
            recordingURL: nil,
            recordingRetentionFailure: nil,
            completionReason: .userStopped
        )

        XCTAssertFalse(model.handleUserStoppedLiveCapture(capture))
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNotNil(model.lastError)
        XCTAssertTrue(model.audioEngine.audioNotice?.contains("couldn't save") == true)
    }

    @MainActor
    func testRestoreMigratesMissingRetainedRecordingToUnavailable() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let recordingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTuneRecordings-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: recordingDirectory)
        }
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let seed = AppModel(persistenceStore: store, recordingStorageDirectory: recordingDirectory)
        seed.enterGuestDemo(presentTutorial: false)
        var session = makeSession(name: "Older take", cents: [0])
        session.retainedRecordingURL = recordingDirectory.appendingPathComponent("missing.caf")
        seed.sessions = [session]
        seed.flushPendingPersistence()

        let restored = AppModel(persistenceStore: store, recordingStorageDirectory: recordingDirectory)
        restored.enterGuestDemo(presentTutorial: false)

        XCTAssertNil(restored.sessions.first?.retainedRecordingURL)
        XCTAssertNil(restored.sessions.first.flatMap(restored.availableRecordingURL(for:)))

        restored.flushPendingPersistence()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let repairedOnDisk = try decoder.decode(
            NativeLocalSnapshot.self,
            from: Data(contentsOf: stateURL)
        )
        XCTAssertNil(repairedOnDisk.sessions.first?.retainedRecordingURL)
        XCTAssertEqual(repairedOnDisk.snapshotVersion, 5)

        let secondRelaunch = AppModel(persistenceStore: store, recordingStorageDirectory: recordingDirectory)
        secondRelaunch.enterGuestDemo(presentTutorial: false)
        XCTAssertNil(secondRelaunch.sessions.first?.retainedRecordingURL)
        XCTAssertNil(secondRelaunch.sessions.first.flatMap(secondRelaunch.availableRecordingURL(for:)))
    }

    @MainActor
    func testClearLocalPracticeDataDeletesRecordingDirectory() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let recordingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTuneRecordings-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: recordingDirectory)
        }
        let recordingURL = recordingDirectory.appendingPathComponent("clear-me.caf")
        try makeSilentCAF(at: recordingURL)
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            recordingStorageDirectory: recordingDirectory
        )
        model.enterGuestDemo(presentTutorial: false)
        var session = makeSession(name: "Clear me", cents: [0])
        session.retainedRecordingURL = recordingURL
        model.sessions = [session]

        model.clearLocalPracticeData()

        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordingDirectory.path))
    }

    @MainActor
    func testClearLocalPracticeDataRestoresPersistedSnapshotWhenRecordingCleanupFails() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let recordingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTuneRecordings-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: recordingDirectory)
        }
        let recordingURL = recordingDirectory.appendingPathComponent("keep-me.caf")
        try makeSilentCAF(at: recordingURL)
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            recordingStorageDirectory: recordingDirectory,
            recordingFileRemover: { _ in throw CocoaError(.fileWriteNoPermission) }
        )
        model.enterGuestDemo(presentTutorial: false)
        var session = makeSession(name: "Keep me", cents: [0])
        session.retainedRecordingURL = recordingURL
        model.sessions = [session]
        model.flushPendingPersistence()

        model.clearLocalPracticeData()

        XCTAssertEqual(model.sessions, [session])
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't clear its saved local data, so your practice data was kept. Try again."
            )
        )
        let relaunched = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            recordingStorageDirectory: recordingDirectory
        )
        relaunched.enterGuestDemo(presentTutorial: false)
        XCTAssertEqual(relaunched.sessions.count, 1)
        XCTAssertEqual(relaunched.sessions.first?.id, session.id)
        XCTAssertEqual(relaunched.sessions.first?.name, session.name)
        XCTAssertEqual(relaunched.sessions.first?.retainedRecordingURL, recordingURL.standardizedFileURL)
    }

    func testRecordingRetentionQuotaRejectsDurationAndSizeWithoutAllowingUnboundedCAF() {
        let quota = NativeRecordingRetentionQuota(maximumDuration: 5, maximumBytes: 100)

        XCTAssertNil(quota.failure(frameCount: 4_410, sampleRate: 44_100, estimatedBytes: 100))
        XCTAssertEqual(
            quota.failure(frameCount: 220_501, sampleRate: 44_100, estimatedBytes: 100),
            .durationLimitReached
        )
        XCTAssertEqual(
            quota.failure(frameCount: 4_410, sampleRate: 44_100, estimatedBytes: 101),
            .sizeLimitReached
        )
    }

    func testQuotaLimitedWriterRetainsThePlayableCappedPortion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTuneRecordings-\(UUID().uuidString)", isDirectory: true)
        let recordingURL = directory.appendingPathComponent("capped.caf")
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 512
        buffer.floatChannelData?.pointee.initialize(repeating: 0.1, count: 512)
        let writer = try NativeAudioFileWriter(
            destinationURL: recordingURL,
            inputFormat: format,
            quota: NativeRecordingRetentionQuota(maximumDuration: 60, maximumBytes: 3_000)
        )

        writer.enqueueCopy(from: buffer)
        writer.enqueueCopy(from: buffer)
        let result = writer.finish()

        XCTAssertEqual(result.retentionFailure, .sizeLimitReached)
        XCTAssertEqual(result.recordingURL, recordingURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingURL.path))
        XCTAssertGreaterThan(
            try XCTUnwrap(recordingURL.resourceValues(forKeys: [.fileSizeKey]).fileSize),
            0
        )
        XCTAssertNoThrow(try NativeRecordingPlaybackDriver.live(url: recordingURL))
    }

    @MainActor
    func testWriteFailureSavesPitchResultWithoutAdvertisingListenBack() {
        let model = AppModel(
            persistenceStore: .ephemeral(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            )
        )
        model.enterGuestDemo(presentTutorial: false)
        let capture = NativeLiveCapture(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_003),
            frames: (0..<8).map { PitchFrame.fixture(index: $0) },
            recordingURL: nil,
            recordingRetentionFailure: .writeFailed,
            completionReason: .interruption
        )

        XCTAssertTrue(model.retainUnexpectedLiveCapture(capture))
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertNil(model.sessions.first?.retainedRecordingURL)
        XCTAssertNotNil(model.lastError)
        XCTAssertTrue(model.audioEngine.audioNotice?.contains("couldn't save") == true)
    }

    @MainActor
    func testDroppedInputFramesFailClosedWithoutSavingPartialAnalytics() {
        let model = AppModel(
            persistenceStore: .ephemeral(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            )
        )
        model.enterGuestDemo(presentTutorial: false)
        let capture = NativeLiveCapture(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_003),
            frames: (0..<8).map { PitchFrame.fixture(index: $0) },
            droppedInputFrameCount: 2,
            recordingURL: nil,
            recordingRetentionFailure: .writeFailed,
            completionReason: .interruption
        )

        XCTAssertFalse(model.retainUnexpectedLiveCapture(capture))
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNotNil(model.lastError)
        XCTAssertTrue(model.audioEngine.audioNotice?.contains("couldn't save") == true)
    }

    @MainActor
    func testQuotaLimitedCaptureKeepsPlayablePartialAudioAndFullTuningResult() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let recordingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTuneRecordings-\(UUID().uuidString)", isDirectory: true)
        let recordingURL = recordingDirectory.appendingPathComponent("partial.caf")
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: recordingDirectory)
        }
        try makeSilentCAF(at: recordingURL)
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            recordingStorageDirectory: recordingDirectory
        )
        model.enterGuestDemo(presentTutorial: false)
        let capture = NativeLiveCapture(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_010),
            frames: (0..<8).map { PitchFrame.fixture(index: $0) },
            recordingURL: recordingURL,
            recordingRetentionFailure: .durationLimitReached,
            completionReason: .interruption
        )

        XCTAssertTrue(model.retainUnexpectedLiveCapture(capture))
        let savedSession = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(savedSession.retainedRecordingURL, recordingURL.standardizedFileURL)
        XCTAssertEqual(model.availableRecordingURL(for: savedSession), recordingURL.standardizedFileURL)
        XCTAssertNil(model.lastError)
        XCTAssertTrue(model.audioEngine.audioNotice?.localizedCaseInsensitiveContains("partial") == true)
        XCTAssertEqual(savedSession.frames, capture.frames)
    }

    @MainActor
    func testQuotaCaptureWithCorruptAudioFileDoesNotClaimPartialListenBack() throws {
        let recordingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrassTuneRecordings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: recordingDirectory) }
        let corruptRecordingURL = recordingDirectory.appendingPathComponent("corrupt.caf")
        try FileManager.default.createDirectory(at: recordingDirectory, withIntermediateDirectories: true)
        try Data([0x00, 0x01, 0x02]).write(to: corruptRecordingURL)
        let model = AppModel(
            persistenceStore: .ephemeral(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            ),
            recordingStorageDirectory: recordingDirectory
        )
        model.enterGuestDemo(presentTutorial: false)
        let capture = NativeLiveCapture(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_003),
            frames: (0..<8).map { PitchFrame.fixture(index: $0) },
            recordingURL: corruptRecordingURL,
            recordingRetentionFailure: .sizeLimitReached,
            completionReason: .interruption
        )

        XCTAssertTrue(model.retainUnexpectedLiveCapture(capture))
        XCTAssertNil(model.sessions.first?.retainedRecordingURL)
        XCTAssertNotNil(model.lastError)
        XCTAssertFalse(model.audioEngine.audioNotice?.localizedCaseInsensitiveContains("partial") == true)
        XCTAssertTrue(model.audioEngine.audioNotice?.contains("couldn't save") == true)
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
            // Detector ranges intentionally reject unknown instruments. Pick
            // a known profile that contains each synthetic fixture frequency.
            let fixtureInstrument = expectedMIDI <= 65 ? "tuba" : "c-trumpet"
            let frame = NativePitchDetector.frame(
                samples: harmonicTone(frequency: target, multiplier: 1),
                sampleRate: sampleRate,
                timestampMs: 0,
                instrumentId: fixtureInstrument,
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
                    instrumentId: fixtureInstrument,
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
        audioSessionCoordinator: NativeAudioSessionCoordinator = .shared,
        playAlongFixturesEnabled: Bool = NativeAudioEngine.testFixturesEnabled
    ) -> AppModel {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            authService: AuthService(session: makeStubSession(), readSessionPayload: { nil }),
            audioSessionCoordinator: audioSessionCoordinator,
            audioEngine: audioEngine,
            playAlongFixturesEnabled: playAlongFixturesEnabled
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

    private func makeSilentCAF(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)
        )
        buffer.frameLength = 512
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) {
                samples[index] = 0
            }
        }
        try file.write(from: buffer)
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
