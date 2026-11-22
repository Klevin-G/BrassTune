import XCTest
import Foundation
import AVFoundation
@testable import BrassTuneApp

private final class ToneVolumeControlPlaneProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [NativeAudioControlPlaneHooks.Event] = []
    var toneStartDelay: TimeInterval = 0
    var failingEvent: NativeAudioControlPlaneHooks.Event?

    lazy var hooks = NativeAudioControlPlaneHooks { [weak self] event in
        guard let self else { return }
        self.lock.lock()
        self.storedEvents.append(event)
        let delay = event == .toneStart ? self.toneStartDelay : 0
        let shouldFail = event == self.failingEvent
        self.lock.unlock()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        if shouldFail { throw NativeAudioEngineError.outputUnavailable }
    }

    func count(_ event: NativeAudioControlPlaneHooks.Event) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents.filter { $0 == event }.count
    }
}

private final class MetronomeClockProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCallbacks: [(callbackHostTime: UInt64, targetHostTime: UInt64)] = []

    func record(targetHostTime: UInt64) {
        lock.lock()
        storedCallbacks.append((mach_absolute_time(), targetHostTime))
        lock.unlock()
    }

    var callbacks: [(callbackHostTime: UInt64, targetHostTime: UInt64)] {
        lock.lock()
        defer { lock.unlock() }
        return storedCallbacks
    }
}

private final class TimedFrameProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFrame: NativeTimedPitchFrame?

    func record(_ frame: NativeTimedPitchFrame) {
        lock.lock()
        storedFrame = frame
        lock.unlock()
    }

    var frame: NativeTimedPitchFrame? {
        lock.lock()
        defer { lock.unlock() }
        return storedFrame
    }
}

private final class DeferredCaptureStartProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseGate = DispatchSemaphore(value: 0)
    private var captureStartContinuation: CheckedContinuation<Void, Never>?
    private var storedEvents: [NativeAudioControlPlaneHooks.Event] = []
    private var shouldDelayCaptureStart = true

    lazy var hooks = NativeAudioControlPlaneHooks { [weak self] event in
        guard let self else { return }
        self.lock.lock()
        self.storedEvents.append(event)
        let delay = event == .captureStart && self.shouldDelayCaptureStart
        if delay {
            self.captureStartContinuation?.resume()
            self.captureStartContinuation = nil
        }
        self.lock.unlock()
        if delay { self.releaseGate.wait() }
    }

    func waitUntilCaptureStart() async {
        if lock.withLock({ storedEvents.contains(.captureStart) }) { return }
        await withCheckedContinuation { continuation in
            lock.lock()
            if storedEvents.contains(.captureStart) {
                lock.unlock()
                continuation.resume()
            } else {
                captureStartContinuation = continuation
                lock.unlock()
            }
        }
    }

    func resumeCaptureStart() {
        releaseGate.signal()
    }

    func allowImmediateCaptureStart() {
        lock.lock()
        shouldDelayCaptureStart = false
        lock.unlock()
    }

    func count(_ event: NativeAudioControlPlaneHooks.Event) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents.filter { $0 == event }.count
    }
}

private final class RetryableInputFailureProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFailInputInstall = true

    lazy var hooks = NativeAudioControlPlaneHooks { [weak self] event in
        guard let self else { return }
        self.lock.lock()
        let shouldFail = event == .captureInstallTap && self.shouldFailInputInstall
        if shouldFail { self.shouldFailInputInstall = false }
        self.lock.unlock()
        if shouldFail { throw NativeAudioEngineError.inputUnavailable }
    }
}

@MainActor
private final class MutableMicrophoneAuthorization {
    var value: NativeMicrophoneAuthorization

    init(_ value: NativeMicrophoneAuthorization) {
        self.value = value
    }
}

@MainActor
private final class DeferredPlayAlongMicrophonePermission {
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

@MainActor
final class AudioReliabilityTests: XCTestCase {
    func testMicrophoneAuthorizationColdStartReflectsNonpromptingSnapshot() {
        for (authorization, expected) in [
            (NativeMicrophoneAuthorization.granted, NativeAudioOperationalState.permissionGranted(.idle)),
            (.denied, .permissionDenied),
            (.undetermined, .permissionNotDetermined),
        ] {
            let engine = NativeAudioEngine(
                microphoneAuthorizationReader: { authorization },
                simulateTonePlayback: true
            )
            XCTAssertEqual(engine.audioState, expected)
        }
    }

    func testForegroundAuthorizationRefreshUpdatesIdleStateWithoutPrompting() {
        let authorization = MutableMicrophoneAuthorization(.undetermined)
        let engine = NativeAudioEngine(
            microphonePermissionRequester: { XCTFail("Foreground refresh must not prompt for microphone access."); return false },
            microphoneAuthorizationReader: { authorization.value },
            simulateTonePlayback: true
        )

        authorization.value = .granted
        engine.refreshMicrophoneAuthorization()
        XCTAssertEqual(engine.audioState, .permissionGranted(.idle))

        authorization.value = .denied
        engine.refreshMicrophoneAuthorization()
        XCTAssertEqual(engine.audioState, .permissionDenied)

        authorization.value = .granted
        engine.refreshMicrophoneAuthorization()
        XCTAssertEqual(engine.audioState, .permissionGranted(.idle))
    }

    func testAuthorizationRefreshPreservesPendingRequestAndActiveCapture() async throws {
        let permission = DeferredPlayAlongMicrophonePermission()
        let authorization = MutableMicrophoneAuthorization(.undetermined)
        let coordinator = NativeAudioSessionCoordinator(
            hooks: NativeAudioControlPlaneHooks { _ in },
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: permission.request,
            microphoneAuthorizationReader: { authorization.value }
        )

        let permissionRequest = Task { @MainActor in await engine.requestMicrophonePermission() }
        await permission.waitUntilRequested()
        authorization.value = .granted
        engine.refreshMicrophoneAuthorization()
        XCTAssertEqual(engine.audioState, .permissionRequesting)
        permission.resolve(granted: true)
        let permissionGranted = await permissionRequest.value
        XCTAssertTrue(permissionGranted)

        let started = try await engine.startLiveRecording(instrumentId: "trumpet", referencePitchHz: 440)
        XCTAssertTrue(started)
        XCTAssertTrue(engine.listening)
        authorization.value = .denied
        engine.refreshMicrophoneAuthorization()
        XCTAssertTrue(engine.listening)
        XCTAssertEqual(engine.audioState, .permissionGranted(.starting))
        _ = engine.stopLiveRecording()
        await coordinator.flush()
    }

    func testInputFailureAfterGrantedAuthorizationIsNotPermissionDenied() async {
        let probe = RetryableInputFailureProbe()
        let authorization = MutableMicrophoneAuthorization(.granted)
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: { XCTFail("Granted authorization must not request again."); return false },
            microphoneAuthorizationReader: { authorization.value }
        )

        do {
            _ = try await engine.startLiveRecording(instrumentId: "trumpet", referencePitchHz: 440)
            XCTFail("Unavailable input should fail capture startup.")
        } catch NativeAudioEngineError.inputUnavailable {
            XCTAssertEqual(engine.audioState, .permissionGranted(.inputUnavailable))
            XCTAssertFalse(engine.permissionDenied)
            XCTAssertEqual(
                engine.audioNotice,
                NativeLocalization.string("MIC-INPUT: BrassTune can't hear a microphone. Check your audio input and retry.")
            )
        } catch {
            XCTFail("Unexpected capture failure: \(error)")
        }
        await coordinator.flush()

        // A granted snapshot must preserve the genuine input diagnosis. A
        // later Settings revocation is a real authorization transition and
        // must supersede that stale hardware state.
        engine.refreshMicrophoneAuthorization()
        XCTAssertEqual(engine.audioState, .permissionGranted(.inputUnavailable))
        authorization.value = .denied
        engine.refreshMicrophoneAuthorization()
        XCTAssertEqual(engine.audioState, .permissionDenied)
        authorization.value = .granted
        engine.refreshMicrophoneAuthorization()
        XCTAssertEqual(engine.audioState, .permissionGranted(.idle))

        do {
            let retried = try await engine.startLiveRecording(instrumentId: "trumpet", referencePitchHz: 440)
            XCTAssertTrue(retried)
            XCTAssertTrue(engine.listening)
        } catch {
            XCTFail("Capture should retry after the input becomes available: \(error)")
        }
        _ = engine.stopLiveRecording()
        await coordinator.flush()
    }

    func testCancelDuringDelayedCaptureStartCleansUpAndAllowsFreshRetry() async throws {
        let probe = DeferredCaptureStartProbe()
        let coordinator = NativeAudioSessionCoordinator(hooks: probe.hooks, deactivationDelay: .zero)
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: { XCTFail("Granted authorization must not request again."); return false },
            microphoneAuthorizationReader: { .granted }
        )

        let pendingStart = Task { @MainActor in
            try await engine.startLiveRecording(instrumentId: "trumpet", referencePitchHz: 440)
        }
        await probe.waitUntilCaptureStart()
        engine.cancelPendingLiveStart()
        probe.resumeCaptureStart()

        let started = try await pendingStart.value
        XCTAssertFalse(started)
        await coordinator.flush()
        XCTAssertFalse(engine.listening)
        XCTAssertFalse(engine.recording)
        XCTAssertFalse(coordinator.isActive(.capture))
        let physicalOwners = await coordinator.physicalActiveOwners()
        XCTAssertFalse(physicalOwners.contains(.capture))
        XCTAssertEqual(probe.count(.captureInstallTap), 1)
        XCTAssertEqual(probe.count(.captureRemoveTap), 1)

        probe.allowImmediateCaptureStart()
        let retried = try await engine.startLiveRecording(instrumentId: "trumpet", referencePitchHz: 440)
        XCTAssertTrue(retried)
        XCTAssertTrue(engine.listening)
        _ = engine.stopLiveRecording()
        await coordinator.flush()
    }

    func testCanceledPlayAlongPermissionStartCannotResumeIntoHiddenCapture() async {
        let permission = DeferredPlayAlongMicrophonePermission()
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { XCTFail("A canceled play-along request must not acquire capture ownership.") },
            deactivateSession: {},
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: permission.request
        )
        let persistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canceled-play-along-\(UUID().uuidString).json")
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: persistenceURL),
            audioSessionCoordinator: coordinator,
            audioEngine: engine,
            playAlongFixturesEnabled: false
        )

        let pendingStart = Task { @MainActor in
            await model.startPlayAlong()
        }
        await permission.waitUntilRequested()
        XCTAssertTrue(model.playAlongStartInProgress)
        XCTAssertFalse(engine.recording)

        _ = model.stopPlayAlong()
        permission.resolve(granted: true)
        await pendingStart.value
        await coordinator.flush()
        XCTAssertFalse(model.playAlongStartInProgress)

        XCTAssertFalse(engine.recording)
        XCTAssertFalse(engine.listening)
        XCTAssertNil(model.playAlongSession)
        XCTAssertEqual(model.playAlongPhase, .idle)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertFalse(coordinator.isActive(.capture))
    }

    func testCombinedTunerWarnsOnlyWhenAudibleClickGridLeavesNoCleanCapture() {
        var dense = MetronomeSettings(bpm: 300, subdivision: .eighth)
        XCTAssertTrue(
            MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(for: dense),
            "A 100 ms audible grid cannot fit a 4096-frame capture outside the click-protection interval."
        )

        dense.visualOnly = true
        dense.muted = true
        XCTAssertFalse(MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(for: dense))

        dense.visualOnly = false
        dense.muted = false
        dense.volume = 0
        XCTAssertFalse(MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(for: dense))

        let sparse = MetronomeSettings(bpm: 92, subdivision: .quarter)
        XCTAssertFalse(MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(for: sparse))
    }

    func testCombinedTunerWarnsAtTheCaptureBoundary() {
        // 20 ms before a click, 120 ms after it, and a 4096-frame capture at
        // 48 kHz require 225.3 ms between audible grid pulses.
        let boundary = MetronomeTunerAudibleCaptureCompatibility.captureDuration
            + MetronomeTunerAudibleCaptureCompatibility.clickProtectedDuration
        // Integer BPM settings straddle the computed boundary at 267/266 BPM.
        var atBoundary = MetronomeSettings(bpm: 267, subdivision: .quarter)
        XCTAssertTrue(MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(for: atBoundary))

        XCTAssertGreaterThanOrEqual(boundary, atBoundary.intervalSeconds)
        atBoundary.bpm = 266
        XCTAssertFalse(MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(for: atBoundary))
    }

    func testCombinedTunerUsesObservedCaptureDurationForRouteSpecificRisk() {
        let settings = MetronomeSettings(bpm: 260, subdivision: .quarter)
        XCTAssertFalse(
            MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(
                for: settings,
                captureDuration: 4096.0 / 48_000.0
            )
        )
        XCTAssertTrue(
            MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(
                for: settings,
                captureDuration: 4096.0 / 44_100.0
            ),
            "The same 231 ms grid is unsafe when the active route extends the captured frame."
        )
        XCTAssertTrue(
            MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(
                for: settings,
                captureDuration: 4096.0 / 16_000.0
            )
        )
    }

    func testCombinedTunerRequiresStableFramesAndRejectsClickWindows() {
        var gate = MetronomeTunerReadoutGate()
        let note = PitchFrame(timestampMs: 0, frequencyHz: 440, confidence: 0.99, rms: 0.2,
            centsDeviation: 0, tuningStatus: .inTune, writtenNoteName: "A", writtenOctave: 4, isValidForRecording: true)
        let click = PitchFrame(timestampMs: 0, frequencyHz: 1320, confidence: 0.99, rms: 0.2,
            centsDeviation: 0, tuningStatus: .inTune, writtenNoteName: "E", writtenOctave: 6, isValidForRecording: true)
        XCTAssertNil(gate.consume(note, at: 0))
        XCTAssertEqual(gate.consume(note, at: 0.1), note)
        gate.recordClick(at: 0.2, settlingDuration: 0.2)
        XCTAssertEqual(gate.consume(click, at: 0.25), note)
        XCTAssertEqual(gate.consume(click, at: 0.35), note)
        XCTAssertNil(gate.consume(click, at: 0.8), "A stale held note must expire; one new frame cannot establish a pitch.")
    }

    func testCombinedTunerEnablesPassiveCaptureAndStopsOnExit() async {
        let coordinator = NativeAudioSessionCoordinator(activateSession: {}, deactivateSession: {}, deactivationDelay: .zero)
        let engine = NativeAudioEngine(audioSessionCoordinator: coordinator, microphonePermissionRequester: { false }, simulateTonePlayback: true)
        let model = AppModel(audioSessionCoordinator: coordinator, audioEngine: engine)
        // Denial must fail closed without opening a system permission sheet.
        await model.setMetronomeTunerEnabled(true)
        if engine.listening {
            XCTAssertTrue(model.metronomeTunerEnabled)
            XCTAssertFalse(engine.takeRecording)
            XCTAssertFalse(model.metronomeTemporarilyMutedForRecording)
        } else {
            XCTAssertFalse(model.metronomeTunerEnabled, "Denied/unavailable capture must not claim combined mode.")
        }
        model.stopMetronomeTuner()
        XCTAssertFalse(model.metronomeTunerEnabled)
        XCTAssertFalse(engine.listening)
        XCTAssertFalse(model.metronomeRunning)
    }

    func testDroneVolumeUpdateKeepsTheRunningToneAndSession() async throws {
        let probe = ToneVolumeControlPlaneProbe()
        probe.toneStartDelay = 0.05
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(
            audioSessionCoordinator: coordinator,
            microphonePermissionRequester: { true }
        )

        try engine.startTone(frequencyHz: 440, volume: 0.15)
        try engine.startTone(frequencyHz: 440, volume: 0.45)
        await coordinator.flush()

        XCTAssertTrue(engine.tonePlaying)
        XCTAssertEqual(engine.toneFrequencyHz, 440)
        XCTAssertEqual(coordinator.activeOwners, [.tone])
        XCTAssertEqual(probe.count(.toneStart), 1)
        XCTAssertEqual(probe.count(.tonePlay), 1)
        XCTAssertEqual(probe.count(.toneStop), 0)
        XCTAssertEqual(probe.count(.activate), 1)

        engine.stopTone(deactivation: .immediate)
        await coordinator.flush()
    }

    func testMetronomeClockWaitsForFutureAnchorBeforeDenseGridSubmission() async throws {
        let clock = NativeMetronomeClock()
        let probe = MetronomeClockProbe()
        let submitted = expectation(description: "first dense-grid pulse submitted")
        let interval = 0.05
        let anchorHostTime = mach_absolute_time() &+ AVAudioTime.hostTime(forSeconds: 0.1)
        let expectedFirstTarget = anchorHostTime &+ AVAudioTime.hostTime(forSeconds: interval)
        defer { clock.stop() }

        clock.start(intervalSeconds: interval, anchorHostTime: anchorHostTime) { _, targetHostTime in
            probe.record(targetHostTime: targetHostTime)
            submitted.fulfill()
        }

        try await Task.sleep(for: .milliseconds(75))
        XCTAssertTrue(
            probe.callbacks.isEmpty,
            "The clock must not schedule pulse 1 before its future pulse-0 anchor is due."
        )
        await fulfillment(of: [submitted], timeout: 1)

        let callback = try XCTUnwrap(probe.callbacks.first)
        XCTAssertGreaterThanOrEqual(callback.callbackHostTime, anchorHostTime)
        XCTAssertEqual(callback.targetHostTime, expectedFirstTarget)
    }

    func testNewerPulseSupersedesAStaleAwaitingSessionAcquire() async throws {
        var scheduledTargets: [UInt64] = []
        let submitted = expectation(description: "only newest pulse submitted")
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: { Thread.sleep(forTimeInterval: 0.05) },
            deactivateSession: {},
            deactivationDelay: .zero
        )
        let output = NativeMetronomeOutput(
            audioSessionCoordinator: coordinator,
            scheduleOverride: { _, _, targetHostTime, completion in
                scheduledTargets.append(targetHostTime)
                completion(.success(()))
                submitted.fulfill()
            }
        )
        let firstTarget = mach_absolute_time() &+ AVAudioTime.hostTime(forSeconds: 0.2)
        let secondTarget = firstTarget &+ AVAudioTime.hostTime(forSeconds: 0.05)
        defer { output.stop() }

        output.playTick(settings: MetronomeSettings(), accent: false, hostTime: firstTarget)
        output.playTick(settings: MetronomeSettings(), accent: false, hostTime: secondTarget)

        await fulfillment(of: [submitted], timeout: 1)
        await coordinator.flush()
        XCTAssertEqual(scheduledTargets, [secondTarget])
    }

    func testDenseMetronomePCMHasHeadroomAndZeroEndedEnvelope() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
        )
        // 300 BPM, compound triplets, and quarter subdivisions produces the
        // shortest supported 16.7 ms grid. Clicks must finish well before
        // the next edge rather than summing into a distorted transient.
        let shortestGrid = 60.0 / (300.0 * 3.0 * 4.0)
        let buffers = try NativeMetronomeClickBuffers(
            outputFormat: format,
            intervalSeconds: shortestGrid
        )

        for buffer in [buffers.regular, buffers.accent] {
            XCTAssertLessThanOrEqual(
                Double(buffer.frameLength) / buffer.format.sampleRate,
                shortestGrid * 0.5 + 0.000_1
            )
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            let values = (0..<Int(buffer.frameLength)).map { samples[$0] }
            let peak = values.map { abs($0) }.max() ?? 0
            let mean = values.reduce(0, +) / Float(max(1, values.count))
            XCTAssertLessThanOrEqual(peak, 0.35)
            XCTAssertLessThan(abs(mean), 0.02)
            XCTAssertEqual(values.first ?? .nan, 0, accuracy: 0.000_001)
            XCTAssertLessThan(abs(values.last ?? .infinity), 0.000_5)
        }
    }

    func testDenseCompoundPatternRendersSampleAlignedGridAndLoopsWithoutClipping() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        var settings = MetronomeSettings()
        settings.bpm = 300
        settings.beatsPerMeasure = 12
        settings.beatUnit = 8
        settings.subdivision = .sixteenth
        let ticks = settings.beatsPerMeasure * settings.subdivision.ticksPerBeat
        let framesPerTick = settings.intervalSeconds * format.sampleRate
        let pattern = try NativeMetronomePatternBuffers(
            outputFormat: format,
            settings: settings,
            countInGridTicks: 7,
            startingGridTick: 0
        )
        let countIn = try XCTUnwrap(pattern.countIn)
        XCTAssertEqual(pattern.measureGridTicks, ticks)
        XCTAssertEqual(Int(countIn.frameLength), Int((7 * framesPerTick).rounded()))
        XCTAssertEqual(Int(pattern.measure.frameLength), Int((Double(ticks) * framesPerTick).rounded()))

        func peak(_ buffer: AVAudioPCMBuffer, tick: Int) throws -> Float {
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            let first = Int((Double(tick) * framesPerTick).rounded())
            let last = min(Int(buffer.frameLength), first + Int(framesPerTick.rounded()))
            return (first..<last).map { abs(samples[$0]) }.max() ?? 0
        }
        let regularPeak = try peak(countIn, tick: 0)
        XCTAssertGreaterThan(regularPeak, 0.05)
        XCTAssertGreaterThan(try peak(pattern.measure, tick: 0), regularPeak)
        for index in [12, 24, 36] {
            XCTAssertGreaterThan(try peak(pattern.measure, tick: index), regularPeak)
        }
        for index in 0..<ticks {
            XCTAssertLessThanOrEqual(try peak(pattern.measure, tick: index), 0.35)
        }
        let samples = try XCTUnwrap(pattern.measure.floatChannelData?[0])
        XCTAssertEqual(samples[0], 0, accuracy: 0.000_001)
        XCTAssertEqual(samples[Int(pattern.measure.frameLength) - 1], 0, accuracy: 0.000_001)
        let retirementLeadFrames = Int((0.004 * format.sampleRate).rounded())
        for frame in (Int(pattern.measure.frameLength) - retirementLeadFrames)..<Int(pattern.measure.frameLength) {
            XCTAssertEqual(samples[frame], 0, accuracy: 0.000_001,
                "The outgoing loop's last 4 ms must already be silent before a replacement begins.")
        }
    }

    func testPatternRetunePreservesMeasurePhaseWithoutCountIn() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        var settings = MetronomeSettings()
        settings.subdivision = .triplet
        let pattern = try NativeMetronomePatternBuffers(
            outputFormat: format,
            settings: settings,
            countInGridTicks: 0,
            startingGridTick: 2
        )
        let samples = try XCTUnwrap(pattern.measure.floatChannelData?[0])
        let framesPerTick = settings.intervalSeconds * format.sampleRate
        func peak(_ tick: Int) -> Float {
            let first = Int((Double(tick) * framesPerTick).rounded())
            return (first..<min(first + Int(framesPerTick.rounded()), Int(pattern.measure.frameLength)))
                .map { abs(samples[$0]) }.max() ?? 0
        }
        XCTAssertGreaterThan(peak(10), peak(0), "A resumed pattern should accent the next downbeat at the correct phase.")
    }

    func testPatternSetupRetargetsLateStartToWholeGridBoundary() {
        let interval = 60.0 / (300 * 3 * 4)
        let anchor: UInt64 = 1_000_000_000
        let now = anchor &+ AVAudioTime.hostTime(forSeconds: 0.2)
        let chosen = NativeMetronomeScheduling.safeTarget(
            anchor,
            now: now,
            intervalSeconds: interval
        )
        let gridTicks = AVAudioTime.hostTime(forSeconds: interval)
        XCTAssertGreaterThanOrEqual(chosen, now &+ AVAudioTime.hostTime(forSeconds: 0.04))
        XCTAssertEqual((chosen - anchor) % gridTicks, 0)
        XCTAssertEqual(
            chosen - NativeMetronomeScheduling.retirementTarget(forNewStart: chosen),
            AVAudioTime.hostTime(forSeconds: 0.004)
        )
    }

    func testRapidEditsRestoreTheStillAudibleLoopBeforeThePendingStart() {
        let now: UInt64 = 1_000_000
        let futureStart = now + 100_000
        XCTAssertEqual(
            NativeMetronomeHandoffDecision.choose(
                now: now,
                currentStart: futureStart,
                hasRetiringLoop: true
            ),
            .restoreAudibleLoop
        )
        XCTAssertEqual(
            NativeMetronomeHandoffDecision.choose(
                now: now,
                currentStart: futureStart,
                hasRetiringLoop: false
            ),
            .discardUnheardLoop
        )
        XCTAssertEqual(
            NativeMetronomeHandoffDecision.choose(
                now: futureStart,
                currentStart: futureStart,
                hasRetiringLoop: true
            ),
            .retirePriorLoop
        )
        XCTAssertEqual(
            NativeMetronomeHandoffDecision.choose(
                now: futureStart,
                currentStart: futureStart,
                hasRetiringLoop: false
            ),
            .keepCurrentLoop
        )
    }

    func testCombinedCaptureUsesAudibleDuplexModeWhileSoloTunerKeepsMeasurement() throws {
        var modes: [AVAudioSession.Mode] = []
        for audible in [false, true] {
            NativeCaptureSessionPolicy.configure(audibleMetronome: audible) { category, mode, options in
                XCTAssertEqual(category, .playAndRecord)
                XCTAssertTrue(options.contains(.defaultToSpeaker))
                modes.append(mode)
            }
        }
        XCTAssertEqual(modes, [.measurement, .default])
    }

    func testDronePitchUpdateTransitionsWithoutStoppingTheAudioSession() async throws {
        let probe = ToneVolumeControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(audioSessionCoordinator: coordinator)

        try engine.startTone(frequencyHz: 440, volume: 0.3)
        await coordinator.flush()
        try engine.startTone(frequencyHz: 466.163_761_5, volume: 0.3)
        await coordinator.flush()

        XCTAssertTrue(engine.tonePlaying)
        XCTAssertEqual(try XCTUnwrap(engine.toneFrequencyHz), 466.163_761_5, accuracy: 0.000_001)
        XCTAssertEqual(coordinator.activeOwners, [.tone])
        XCTAssertEqual(probe.count(.toneStart), 1)
        XCTAssertEqual(probe.count(.toneTransition), 1)
        XCTAssertEqual(probe.count(.toneStop), 0)

        engine.stopTone(deactivation: .immediate)
        await coordinator.flush()
    }

    func testDroneCrossfadePreservesGainHeadroomAtEveryTransitionStep() {
        for step in 0...NativeToneCrossfade.stepCount {
            let gains = NativeToneCrossfade.gains(forStep: step)
            XCTAssertGreaterThanOrEqual(gains.outgoing, 0)
            XCTAssertGreaterThanOrEqual(gains.incoming, 0)
            XCTAssertLessThanOrEqual(gains.outgoing, 1)
            XCTAssertLessThanOrEqual(gains.incoming, 1)
            XCTAssertEqual(gains.outgoing + gains.incoming, 1, accuracy: 0.000_001)
        }
        XCTAssertEqual(NativeToneCrossfade.gains(forStep: 0).outgoing, 1)
        XCTAssertEqual(NativeToneCrossfade.gains(forStep: 0).incoming, 0)
        XCTAssertEqual(NativeToneCrossfade.gains(forStep: NativeToneCrossfade.stepCount).outgoing, 0)
        XCTAssertEqual(NativeToneCrossfade.gains(forStep: NativeToneCrossfade.stepCount).incoming, 1)
    }

    func testFailedDroneRetuneKeepsThePriorPitchPublished() async throws {
        let probe = ToneVolumeControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(audioSessionCoordinator: coordinator)

        try engine.startTone(frequencyHz: 440, volume: 0.3)
        await coordinator.flush()
        probe.failingEvent = .toneTransition
        try engine.startTone(frequencyHz: 466.163_761_5, volume: 0.3)
        await coordinator.flush()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(engine.tonePlaying)
        XCTAssertEqual(engine.toneFrequencyHz, 440)
        XCTAssertEqual(engine.toneFrequenciesHz, [440])
        XCTAssertEqual(engine.audioNotice, NativeLocalization.string("BrassTune couldn't start the reference tone. Check your audio output and try again."))

        engine.stopTone(deactivation: .immediate)
        await coordinator.flush()
    }

    func testRapidDroneABARetuneQueuesTheCorrectiveFinalPitch() async throws {
        let probe = ToneVolumeControlPlaneProbe()
        let coordinator = NativeAudioSessionCoordinator(
            hooks: probe.hooks,
            deactivationDelay: .zero
        )
        let engine = NativeAudioEngine(audioSessionCoordinator: coordinator)
        let a = 440.0
        let b = 466.163_761_5

        try engine.startTone(frequencyHz: a, volume: 0.3)
        await coordinator.flush()
        try engine.startTone(frequencyHz: b, volume: 0.3)
        try engine.startTone(frequencyHz: a, volume: 0.3)
        await coordinator.flush()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(probe.count(.toneStart), 1)
        XCTAssertEqual(probe.count(.toneTransition), 2)
        XCTAssertEqual(probe.count(.toneStop), 0)
        XCTAssertTrue(engine.tonePlaying)
        XCTAssertEqual(engine.toneFrequencyHz, a)
        XCTAssertEqual(engine.toneFrequenciesHz, [a])

        engine.stopTone(deactivation: .immediate)
        await coordinator.flush()
    }

    func testTimedCaptureFramePreservesRenderTapHostInterval() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
        buffer.frameLength = 256
        let probe = TimedFrameProbe()
        let pipeline = try XCTUnwrap(NativeLiveCapturePipeline(
            format: format,
            frameCapacity: 256,
            writer: nil,
            instrumentId: "trumpet",
            referencePitchHz: 440,
            automaticallyDrain: false,
            receiveFrame: { _ in },
            receiveTimedFrame: { probe.record($0) }
        ))

        pipeline.enqueueFromRenderTap(
            buffer,
            timestampMs: 100,
            captureStartHostTime: 12_000,
            captureEndHostTime: 15_000
        )
        _ = pipeline.finish()

        let timedFrame = try XCTUnwrap(probe.frame)
        XCTAssertEqual(timedFrame.captureStartHostTime, 12_000)
        XCTAssertEqual(timedFrame.captureEndHostTime, 15_000)
        XCTAssertEqual(timedFrame.frame.timestampMs, 100)
    }

    func testExplicitDuplexOptionSchedulesAnAudiblePulseDuringPassiveCapture() async throws {
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: {},
            deactivateSession: {},
            deactivationDelay: .zero
        )
        let audiblePulse = expectation(description: "audible passive-capture pulse accepted")
        var targets: [UInt64] = []
        let output = NativeMetronomeOutput(
            audioSessionCoordinator: coordinator,
            scheduleOverride: { _, _, targetHostTime, completion in
                targets.append(targetHostTime)
                completion(.success(()))
            }
        )
        defer {
            output.stop()
            coordinator.release(.capture, deactivation: .immediate)
        }

        try await coordinator.acquire(.capture, configuration: .capture)
        let target = mach_absolute_time() &+ AVAudioTime.hostTime(forSeconds: 0.15)
        output.playTick(
            settings: MetronomeSettings(),
            accent: true,
            hostTime: target,
            allowAudibleDuringCapture: true,
            onAudiblePulseScheduled: { acceptedHostTime in
                XCTAssertEqual(acceptedHostTime, target)
                audiblePulse.fulfill()
            }
        )

        await fulfillment(of: [audiblePulse], timeout: 1)
        XCTAssertEqual(targets, [target])
        XCTAssertEqual(coordinator.activeOwners, [.capture, .metronome])
    }
}
