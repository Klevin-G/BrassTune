import AVFoundation
import BrassTuneCore
import Darwin
import Foundation
import os
import UIKit

#if PHYSICAL_INSTRUMENTATION
private enum NativeAudioLifecycleTrace {
    static let log = OSLog(
        subsystem: "com.aryasalem.BrassTune",
        // The stock Time Profiler template records only the PointsOfInterest
        // signpost category. This remains compile-gated, so production builds
        // emit no lifecycle instrumentation.
        category: .pointsOfInterest
    )

    static func id() -> OSSignpostID {
        OSSignpostID(log: log)
    }

    static func span<T>(
        _ name: StaticString,
        id: OSSignpostID? = nil,
        operation: () throws -> T
    ) rethrows -> T {
        let signpostID = id ?? self.id()
        var succeeded: Int32 = 0
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        defer {
            os_signpost(
                .end,
                log: log,
                name: name,
                signpostID: signpostID,
                "success=%{public}d",
                succeeded
            )
        }
        let result = try operation()
        succeeded = 1
        return result
    }
}
#endif

/// Test-only physical hooks for the global audio control plane. The closures
/// carry no AVFoundation objects; production leaves this nil so the actor owns
/// and configures `AVAudioSession.sharedInstance()` directly.
struct NativeAudioControlPlaneHooks: Sendable {
    enum Event: Equatable, Sendable {
        case configure(NativeAudioSessionCoordinator.Configuration)
        case activate
        case deactivate
        case captureInstallTap
        case captureRemoveTap
        case captureStart
        case captureStop
        case toneStart
        case tonePlay
        case toneStop
        case rebuildGraphs
    }

    let perform: @Sendable (Event) throws -> Void
}

/// Shared synchronous sequencing primitive for player-node graphs. The
/// scheduling closure must only enqueue a buffer; completion is delivered by
/// its callback later. Keeping this helper non-async prevents a serial audio
/// actor from waiting for buffer consumption before it can execute stop/reset.
enum NativeNonblockingAudioScheduling {
    static func scheduleAndPlay(
        schedule: () throws -> Void,
        play: () throws -> Void
    ) rethrows {
        try schedule()
        try play()
    }
}

/// The only executor allowed to own or operate BrassTune's AVAudioSession and
/// capture/reference-tone AVAudioEngine graphs. AVFoundation objects never
/// leave this actor; MainActor façades exchange only value requests/results.
private actor NativeAudioControlPlane {
    private var owners: Set<NativeAudioSessionCoordinator.Owner> = []
    private var sessionIsActive = false
    private var activeConfiguration: NativeAudioSessionCoordinator.Configuration?
    private var deactivationGeneration: UInt64 = 0
    private var pendingDeactivationTask: Task<Void, Never>?
    private let deactivationDelay: Duration
    private let hooks: NativeAudioControlPlaneHooks?
    private var engine = AVAudioEngine()
    private var tonePlayer = AVAudioPlayerNode()
    private var tonePlayerAttached = false
    private let toneBufferCache = NativeToneBufferCache()
    private var outputGraphRequiresRebuild = false
    private var inputTapInstalled = false
    private var graphGeneration: UInt64 = 0
    private var liveCaptureID: UUID?
    private var liveStartedAt: Date?
    private var liveCapturePipeline: NativeLiveCapturePipeline?

    init(
        hooks: NativeAudioControlPlaneHooks?,
        deactivationDelay: Duration
    ) {
        self.hooks = hooks
        self.deactivationDelay = deactivationDelay
    }

    @discardableResult
    func acquire(
        _ owner: NativeAudioSessionCoordinator.Owner,
        configuration: NativeAudioSessionCoordinator.Configuration?
    ) throws -> Bool {
        guard !owners.contains(owner) else { return false }
        guard owners.allSatisfy({ Self.areCompatible($0, owner) }) else {
            throw NativeAudioEngineError.audioSessionOwnerConflict
        }

        let canReuseConfiguration = sessionIsActive && configuration == activeConfiguration
        if !canReuseConfiguration,
           owner != .metronome || !owners.contains(.capture),
           let configuration {
            try configureSession(for: configuration)
            activeConfiguration = configuration
        }

        deactivationGeneration &+= 1
        pendingDeactivationTask?.cancel()
        pendingDeactivationTask = nil
        owners.insert(owner)
        guard !sessionIsActive else { return true }
        do {
#if PHYSICAL_INSTRUMENTATION
            try NativeAudioLifecycleTrace.span("AudioSessionActivate") {
                try perform(.activate)
            }
#else
            try perform(.activate)
#endif
            sessionIsActive = true
            return true
        } catch {
            owners.remove(owner)
            activeConfiguration = nil
            throw error
        }
    }

    func release(
        _ owner: NativeAudioSessionCoordinator.Owner,
        deactivation: NativeAudioSessionCoordinator.DeactivationPolicy
    ) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        deactivationGeneration &+= 1
        let generation = deactivationGeneration
        if deactivation == .deferred, deactivationDelay != .zero {
            let delay = deactivationDelay
            pendingDeactivationTask?.cancel()
            pendingDeactivationTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await self?.deactivateAfterDelay(generation: generation)
            }
            return
        }
        deactivateIfIdle(generation: generation)
    }

    func deactivateImmediatelyIfIdle() {
        guard owners.isEmpty else { return }
        deactivationGeneration &+= 1
        pendingDeactivationTask?.cancel()
        pendingDeactivationTask = nil
        deactivateIfIdle(generation: deactivationGeneration)
    }

    func invalidateSessionConfiguration() {
        activeConfiguration = nil
    }

    func invalidateAfterMediaServicesReset() {
        deactivationGeneration &+= 1
        pendingDeactivationTask?.cancel()
        pendingDeactivationTask = nil
        owners.removeAll()
        activeConfiguration = nil
        sessionIsActive = false
    }

    func activeOwners() -> Set<NativeAudioSessionCoordinator.Owner> { owners }

    func currentGraphGeneration() -> UInt64 { graphGeneration }

    func startCapture(_ request: NativeCaptureStartRequest) async throws -> NativeCaptureStartResult {
        guard !inputTapInstalled else {
            throw NativeAudioEngineError.inputTapAlreadyInstalled
        }
        let acquired = try acquire(.capture, configuration: .capture)
        guard acquired else { throw NativeAudioEngineError.inputTapAlreadyInstalled }

        do {
            let startedAt = Date()
            if hooks != nil {
                try perform(.captureInstallTap)
                inputTapInstalled = true
                try perform(.captureStart)
                liveCaptureID = request.captureID
                liveStartedAt = startedAt
                outputGraphRequiresRebuild = true
                return NativeCaptureStartResult(
                    generation: request.generation,
                    captureID: request.captureID,
                    startedAt: startedAt,
                    graphGeneration: graphGeneration
                )
            }

            let session = AVAudioSession.sharedInstance()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard session.isInputAvailable,
                  !session.currentRoute.inputs.isEmpty,
                  inputFormat.channelCount > 0,
                  inputFormat.sampleRate.isFinite,
                  inputFormat.sampleRate > 0 else {
                throw NativeAudioEngineError.inputUnavailable
            }
            let fileWriter = try request.recordingURL.map {
                try NativeAudioFileWriter(destinationURL: $0, inputFormat: inputFormat)
            }
            guard let pipeline = NativeLiveCapturePipeline(
                format: inputFormat,
                writer: fileWriter,
                instrumentId: request.instrumentId,
                referencePitchHz: NativeReferencePitch.sanitized(request.referencePitchHz),
                receiveFrame: request.receiveFrame
            ) else {
                throw NativeAudioEngineError.inputUnavailable
            }
            liveCapturePipeline = pipeline
            liveCaptureID = request.captureID
            liveStartedAt = startedAt
            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: inputFormat,
                block: Self.makeRenderTap(pipeline: pipeline)
            )
            inputTapInstalled = true
            outputGraphRequiresRebuild = true
            engine.prepare()
            try engine.start()
            return NativeCaptureStartResult(
                generation: request.generation,
                captureID: request.captureID,
                startedAt: startedAt,
                graphGeneration: graphGeneration
            )
        } catch {
            await rollbackFailedCaptureStart()
            throw error
        }
    }

    func stopCapture(
        generation: UInt64,
        reason: NativeLiveCaptureCompletionReason,
        discard: Bool = false,
        graphIsValid: Bool = true
    ) async -> NativeCaptureStopResult {
        let captureID = liveCaptureID ?? UUID()
        let startedAt = liveStartedAt ?? Date()
        if graphIsValid {
            if hooks != nil {
                try? perform(.captureStop)
                if inputTapInstalled { try? perform(.captureRemoveTap) }
            } else {
                engine.stop()
                if inputTapInstalled { engine.inputNode.removeTap(onBus: 0) }
            }
        }
        inputTapInstalled = false
        let pipelineResult: NativeLiveCapturePipeline.FinishResult?
        let discardedDroppedInputFrameCount: Int
        if discard {
            discardedDroppedInputFrameCount = liveCapturePipeline?.discard().droppedInputFrameCount ?? 0
            pipelineResult = nil
        } else {
            discardedDroppedInputFrameCount = 0
            pipelineResult = liveCapturePipeline?.finish()
        }
        liveCapturePipeline = nil
        liveCaptureID = nil
        liveStartedAt = nil
        release(
            .capture,
            deactivation: reason == .userStopped ? .deferred : .immediate
        )
        return NativeCaptureStopResult(
            generation: generation,
            capture: NativeLiveCapture(
                id: captureID,
                startedAt: startedAt,
                endedAt: Date(),
                frames: pipelineResult?.frames ?? [],
                droppedInputFrameCount: pipelineResult?.droppedInputFrameCount ?? discardedDroppedInputFrameCount,
                recordingURL: pipelineResult?.recording?.recordingURL,
                recordingRetentionFailure: pipelineResult?.recording?.retentionFailure,
                completionReason: reason
            )
        )
    }

    func startTone(_ request: NativeToneStartRequest) async throws -> UInt64 {
        if outputGraphRequiresRebuild { rebuildGraphs() }
        let acquired = try acquire(.tone, configuration: .tone)
        if !acquired {
            await stopTone(deactivation: .immediate)
            _ = try acquire(.tone, configuration: .tone)
        }
        do {
            if hooks != nil {
                try NativeNonblockingAudioScheduling.scheduleAndPlay(
                    schedule: { try perform(.toneStart) },
                    play: { try perform(.tonePlay) }
                )
                return request.generation
            }
            if !tonePlayerAttached {
                engine.attach(tonePlayer)
                tonePlayerAttached = true
            }
            let buffer = try toneBufferCache.buffer(for: request.frequenciesHz)
            tonePlayer.volume = request.volume
            engine.connect(tonePlayer, to: engine.mainMixerNode, format: buffer.format)
            try NativeNonblockingAudioScheduling.scheduleAndPlay(
                schedule: {
                    tonePlayer.scheduleBuffer(
                        buffer,
                        at: nil,
                        options: .loops,
                        completionHandler: nil
                    )
                },
                play: {
                    engine.prepare()
                    try engine.start()
                    tonePlayer.play()
                }
            )
            return request.generation
        } catch {
            if hooks == nil {
                tonePlayer.stop()
                engine.stop()
            }
            release(.tone, deactivation: .immediate)
            throw error
        }
    }

    func stopTone(
        deactivation: NativeAudioSessionCoordinator.DeactivationPolicy
    ) async {
        if hooks != nil {
            try? perform(.toneStop)
        } else {
            tonePlayer.stop()
            engine.stop()
        }
        release(.tone, deactivation: deactivation)
    }

    func mediaServicesReset(
        generation: UInt64,
        captureReason: NativeLiveCaptureCompletionReason
    ) async -> NativeCaptureStopResult? {
        let hadCapture = owners.contains(.capture) || inputTapInstalled || liveCaptureID != nil
        inputTapInstalled = false
        outputGraphRequiresRebuild = true
        invalidateAfterMediaServicesReset()
        let captureResult = hadCapture
            ? await stopCapture(
                generation: generation,
                reason: captureReason,
                graphIsValid: false
            )
            : nil
        owners.removeAll()
        rebuildGraphs()
        return captureResult
    }

    private func rollbackFailedCaptureStart() async {
        if hooks != nil {
            if inputTapInstalled { try? perform(.captureRemoveTap) }
            try? perform(.captureStop)
        } else {
            engine.stop()
            if inputTapInstalled { engine.inputNode.removeTap(onBus: 0) }
        }
        inputTapInstalled = false
        _ = liveCapturePipeline?.discard()
        liveCapturePipeline = nil
        liveCaptureID = nil
        liveStartedAt = nil
        release(.capture, deactivation: .immediate)
    }

    private func rebuildGraphs() {
        if hooks != nil { try? perform(.rebuildGraphs) }
        engine = AVAudioEngine()
        tonePlayer = AVAudioPlayerNode()
        tonePlayerAttached = false
        inputTapInstalled = false
        outputGraphRequiresRebuild = false
        graphGeneration &+= 1
    }

    nonisolated private static func makeRenderTap(
        pipeline: NativeLiveCapturePipeline
    ) -> AVAudioNodeTapBlock {
        { buffer, when in
            let sampleRate = buffer.format.sampleRate
            let timestampMs = Int(max(0, Double(when.sampleTime) / max(sampleRate, 1) * 1_000))
            pipeline.enqueueFromRenderTap(buffer, timestampMs: timestampMs)
        }
    }

    private func configureSession(
        for configuration: NativeAudioSessionCoordinator.Configuration
    ) throws {
        if hooks != nil {
            try perform(.configure(configuration))
            return
        }
        let session = AVAudioSession.sharedInstance()
        switch configuration {
        case .capture:
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetoothHFP, .defaultToSpeaker, .mixWithOthers]
            )
            try session.setPreferredIOBufferDuration(0.03)
        case .tone:
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        case .metronome:
            // A standalone metronome is output-only. Do not retain a capture
            // category or Bluetooth HFP route when no microphone is in use.
            try NativeMetronomeSessionPolicy.configure { category, mode, options in
                try session.setCategory(category, mode: mode, options: options)
            }
        case .recordingPlayback:
            try NativePlaybackSessionPolicy.configure { category, mode, options in
                try session.setCategory(category, mode: mode, options: options)
            }
        }
    }

    private func perform(_ event: NativeAudioControlPlaneHooks.Event) throws {
        if let hooks {
            try hooks.perform(event)
            return
        }
        let session = AVAudioSession.sharedInstance()
        switch event {
        case .activate:
            try session.setActive(true)
        case .deactivate:
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        case .configure:
            break
        case .captureInstallTap, .captureRemoveTap, .captureStart, .captureStop,
             .toneStart, .tonePlay, .toneStop, .rebuildGraphs:
            break
        }
    }

    private func deactivateIfIdle(generation: UInt64) {
        guard owners.isEmpty,
              sessionIsActive,
              generation == deactivationGeneration else { return }
        do {
#if PHYSICAL_INSTRUMENTATION
            try NativeAudioLifecycleTrace.span("AudioSessionDeactivate") {
                try perform(.deactivate)
            }
#else
            try perform(.deactivate)
#endif
            sessionIsActive = false
            activeConfiguration = nil
        } catch {
            // Retain the active marker after a failed deactivation. A media
            // services reset explicitly clears it before the next acquire.
        }
    }

    private func deactivateAfterDelay(generation: UInt64) {
        deactivateIfIdle(generation: generation)
        pendingDeactivationTask = nil
    }

    private static func areCompatible(
        _ lhs: NativeAudioSessionCoordinator.Owner,
        _ rhs: NativeAudioSessionCoordinator.Owner
    ) -> Bool {
        if lhs == rhs { return true }
        if lhs == .metronome || rhs == .metronome {
            return lhs == .capture || rhs == .capture
        }
        return false
    }
}

private struct NativeCaptureStartRequest: Sendable {
    let generation: UInt64
    let captureID: UUID
    let instrumentId: String
    let referencePitchHz: Double
    let recordingURL: URL?
    let receiveFrame: @Sendable (PitchFrame) -> Void
}

private struct NativeCaptureStartResult: Sendable {
    let generation: UInt64
    let captureID: UUID
    let startedAt: Date
    let graphGeneration: UInt64
}

private struct NativeCaptureStopResult: Sendable {
    let generation: UInt64
    let capture: NativeLiveCapture
}

private struct NativeToneStartRequest: Sendable {
    let generation: UInt64
    let frequenciesHz: [Double]
    let volume: Float
}

private final class NativeAudioHookClosureBox: @unchecked Sendable {
    let activate: () throws -> Void
    let deactivate: () throws -> Void

    init(
        activate: @escaping () throws -> Void,
        deactivate: @escaping () throws -> Void
    ) {
        self.activate = activate
        self.deactivate = deactivate
    }
}

@MainActor
final class NativeAudioSessionCoordinator {
    enum Owner: Hashable, Sendable { case capture, tone, metronome, recordingPlayback }
    enum DeactivationPolicy: Sendable { case deferred, immediate }
    enum Configuration: Equatable, Sendable { case capture, tone, metronome, recordingPlayback }

    static let shared = NativeAudioSessionCoordinator()

    private struct InFlightAcquire {
        let id: UUID
        let task: Task<Bool, Error>
    }

    private var owners: Set<Owner> = []
    private var inFlightAcquires: [Owner: InFlightAcquire] = [:]
    private let controlPlane: NativeAudioControlPlane
    private var commandTail: Task<Void, Never>?

    init(
        hooks: NativeAudioControlPlaneHooks? = nil,
        deactivationDelay: Duration = .milliseconds(200)
    ) {
        controlPlane = NativeAudioControlPlane(
            hooks: hooks,
            deactivationDelay: deactivationDelay
        )
    }

    convenience init(
        activateSession: @escaping () throws -> Void,
        deactivateSession: @escaping () throws -> Void,
        deactivationDelay: Duration = .milliseconds(200)
    ) {
        let box = NativeAudioHookClosureBox(
            activate: activateSession,
            deactivate: deactivateSession
        )
        self.init(
            hooks: NativeAudioControlPlaneHooks { event in
                switch event {
                case .activate: try box.activate()
                case .deactivate: try box.deactivate()
                default: break
                }
            },
            deactivationDelay: deactivationDelay
        )
    }

    @discardableResult
    func acquire(
        _ owner: Owner,
        configuration: Configuration? = nil
    ) async throws -> Bool {
        try await acquireTask(owner, configuration: configuration).value
    }

    func acquireTask(
        _ owner: Owner,
        configuration: Configuration? = nil
    ) throws -> Task<Bool, Error> {
        if let inFlight = inFlightAcquires[owner] { return inFlight.task }
        if owners.contains(owner) { return Task { false } }
        try reserveCompatible(owner)
        let physicalTask = enqueueThrowingTask { plane in
            try await plane.acquire(owner, configuration: configuration)
        }
        let id = UUID()
        let readinessTask = Task { @MainActor [weak self] in
            do {
                let acquired = try await physicalTask.value
                if self?.inFlightAcquires[owner]?.id == id {
                    self?.inFlightAcquires.removeValue(forKey: owner)
                }
                return acquired
            } catch {
                if self?.inFlightAcquires[owner]?.id == id {
                    self?.inFlightAcquires.removeValue(forKey: owner)
                    self?.owners.remove(owner)
                }
                throw error
            }
        }
        inFlightAcquires[owner] = InFlightAcquire(id: id, task: readinessTask)
        return readinessTask
    }

    fileprivate func startCapture(_ request: NativeCaptureStartRequest) throws -> Task<NativeCaptureStartResult, Error> {
        try reserve(.capture)
        return enqueueThrowingTask { plane in
            try await plane.startCapture(request)
        }
    }

    fileprivate func stopCapture(
        generation: UInt64,
        reason: NativeLiveCaptureCompletionReason,
        discard: Bool = false,
        graphIsValid: Bool = true
    ) -> Task<NativeCaptureStopResult, Never> {
        owners.remove(.capture)
        inFlightAcquires.removeValue(forKey: .capture)
        return enqueueTask { plane in
            await plane.stopCapture(
                generation: generation,
                reason: reason,
                discard: discard,
                graphIsValid: graphIsValid
            )
        }
    }

    fileprivate func startTone(_ request: NativeToneStartRequest) throws -> Task<UInt64, Error> {
        try reserve(.tone)
        return enqueueThrowingTask { plane in
            try await plane.startTone(request)
        }
    }

    func rollbackLogicalOwner(_ owner: Owner) {
        owners.remove(owner)
        inFlightAcquires.removeValue(forKey: owner)
    }

    func stopTone(deactivation: DeactivationPolicy = .deferred) {
        guard owners.remove(.tone) != nil else { return }
        inFlightAcquires.removeValue(forKey: .tone)
        enqueueNoWait { plane in
            await plane.stopTone(deactivation: deactivation)
        }
    }

    fileprivate func handleMediaServicesReset(
        generation: UInt64,
        captureReason: NativeLiveCaptureCompletionReason = .interruption
    ) -> Task<NativeCaptureStopResult?, Never> {
        owners.removeAll()
        inFlightAcquires.removeAll()
        return enqueueTask { plane in
            await plane.mediaServicesReset(
                generation: generation,
                captureReason: captureReason
            )
        }
    }

    func release(_ owner: Owner, deactivation: DeactivationPolicy = .deferred) {
        guard owners.remove(owner) != nil else { return }
        inFlightAcquires.removeValue(forKey: owner)
        enqueueNoWait { plane in
            await plane.release(owner, deactivation: deactivation)
        }
    }

    func deactivateImmediatelyIfIdle() {
        guard owners.isEmpty else { return }
        enqueueNoWait { plane in
            await plane.deactivateImmediatelyIfIdle()
        }
    }

    var activeOwners: Set<Owner> { owners }

    func isActive(_ owner: Owner) -> Bool { owners.contains(owner) }

    /// Route loss, interruptions, and media-service resets can change the
    /// system session even if our deferred handoff timer has not fired.
    func invalidateSessionConfiguration() {
        enqueueNoWait { plane in
            await plane.invalidateSessionConfiguration()
        }
    }

    /// Media services reset invalidates AVAudioSession itself, even if a
    /// best-effort deactivation would fail. The next acquire must therefore
    /// configure and activate from scratch rather than trusting a stale flag.
    func invalidateAfterMediaServicesReset() {
        owners.removeAll()
        inFlightAcquires.removeAll()
        enqueueNoWait { plane in
            await plane.invalidateAfterMediaServicesReset()
        }
    }

    func flush() async {
        await commandTail?.value
    }

    func physicalActiveOwners() async -> Set<Owner> {
        await flush()
        return await controlPlane.activeOwners()
    }

    func graphGeneration() async -> UInt64 {
        await flush()
        return await controlPlane.currentGraphGeneration()
    }

    private func reserve(_ owner: Owner) throws {
        guard !owners.contains(owner) else {
            throw NativeAudioEngineError.inputTapAlreadyInstalled
        }
        guard owners.allSatisfy({ Self.areCompatible($0, owner) }) else {
            throw NativeAudioEngineError.audioSessionOwnerConflict
        }
        owners.insert(owner)
    }

    private func reserveCompatible(_ owner: Owner) throws {
        guard owners.allSatisfy({ Self.areCompatible($0, owner) }) else {
            throw NativeAudioEngineError.audioSessionOwnerConflict
        }
        owners.insert(owner)
    }

    private func enqueue<Result: Sendable>(
        _ operation: @escaping @Sendable (NativeAudioControlPlane) async throws -> Result
    ) async throws -> Result {
        let previous = commandTail
        let plane = controlPlane
        let task = Task<Result, Error> {
            await previous?.value
            return try await operation(plane)
        }
        commandTail = Task { _ = try? await task.value }
        return try await task.value
    }

    private func enqueueTask<Result: Sendable>(
        _ operation: @escaping @Sendable (NativeAudioControlPlane) async -> Result
    ) -> Task<Result, Never> {
        let previous = commandTail
        let plane = controlPlane
        let task = Task<Result, Never> {
            await previous?.value
            return await operation(plane)
        }
        commandTail = Task { _ = await task.value }
        return task
    }

    private func enqueueThrowingTask<Result: Sendable>(
        _ operation: @escaping @Sendable (NativeAudioControlPlane) async throws -> Result
    ) -> Task<Result, Error> {
        let previous = commandTail
        let plane = controlPlane
        let task = Task<Result, Error> {
            await previous?.value
            return try await operation(plane)
        }
        commandTail = Task { _ = try? await task.value }
        return task
    }

    private func enqueueNoWait(
        _ operation: @escaping @Sendable (NativeAudioControlPlane) async -> Void
    ) {
        let task: Task<Void, Never> = enqueueTask(operation)
        commandTail = task
    }

    private static func areCompatible(_ lhs: Owner, _ rhs: Owner) -> Bool {
        if lhs == rhs { return true }
        // The metronome may coexist with capture only as a visual clock; its
        // output implementation detects capture and releases itself. All
        // other audible capture/playback/tone handoffs must be explicit.
        if lhs == .metronome || rhs == .metronome {
            return lhs == .capture || rhs == .capture
        }
        return false
    }
}

/// A single source of truth for persisted and live A4 values. Rejecting NaN
/// and infinity avoids propagating invalid values into logarithmic pitch math.
enum NativeReferencePitch {
    static let defaultHz = 440.0
    static let allowedRange = 430.0...450.0

    static func sanitized(_ value: Double) -> Double {
        guard value.isFinite, allowedRange.contains(value) else { return defaultHz }
        return value
    }
}

enum NativeLiveCaptureCompletionReason: Equatable, Sendable {
    case userStopped
    case interruption
    case routeLoss
}

enum NativeRecordingRetentionFailure: Equatable, Sendable {
    case durationLimitReached
    case sizeLimitReached
    case writeFailed
}

struct NativeLiveCapture: Equatable, Identifiable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let frames: [PitchFrame]
    let droppedInputFrameCount: Int
    let recordingURL: URL?
    let recordingRetentionFailure: NativeRecordingRetentionFailure?
    let completionReason: NativeLiveCaptureCompletionReason

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        frames: [PitchFrame],
        droppedInputFrameCount: Int = 0,
        recordingURL: URL?,
        recordingRetentionFailure: NativeRecordingRetentionFailure?,
        completionReason: NativeLiveCaptureCompletionReason
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.frames = frames
        self.droppedInputFrameCount = droppedInputFrameCount
        self.recordingURL = recordingURL
        self.recordingRetentionFailure = recordingRetentionFailure
        self.completionReason = completionReason
    }
}

struct NativeRecordingRetentionQuota: Equatable {
    /// A five-minute cap keeps local, uncompressed CAF takes bounded while
    /// still covering a focused practice pass.
    static let shipping = NativeRecordingRetentionQuota(
        maximumDuration: 5 * 60,
        maximumBytes: 64 * 1024 * 1024
    )

    let maximumDuration: TimeInterval
    let maximumBytes: Int64

    func failure(
        frameCount: Int64,
        sampleRate: Double,
        estimatedBytes: Int64
    ) -> NativeRecordingRetentionFailure? {
        if sampleRate > 0, Double(frameCount) / sampleRate > maximumDuration {
            return .durationLimitReached
        }
        if estimatedBytes > maximumBytes {
            return .sizeLimitReached
        }
        return nil
    }
}

struct NativePlaybackSessionPolicy {
    static func configure(
        _ apply: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions) throws -> Void
    ) rethrows {
        // `.playback` deliberately ignores the Ring/Silent switch. A saved
        // practice take should behave like media, not like a notification.
        try apply(.playback, .default, [])
    }
}

struct NativeMetronomeSessionPolicy {
    static func configure(
        _ apply: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions) throws -> Void
    ) rethrows {
        try apply(.playback, .default, [.mixWithOthers])
    }
}

/// A preallocated, bounded PCM pool shared by the render callback and the
/// serial file consumer. Its lock protects only slot ownership and is never
/// held during copying, file I/O, or pitch analysis.
private final class NativeCaptureBufferPool: @unchecked Sendable {
    final class Slot: @unchecked Sendable {
        let index: Int
        let buffer: AVAudioPCMBuffer

        init(index: Int, buffer: AVAudioPCMBuffer) {
            self.index = index
            self.buffer = buffer
        }
    }

    private let lock = NSLock()
    private let slots: [Slot]
    private var availableIndices: [Int]
    private var failedClosed = false

    init?(format: AVAudioFormat, frameCapacity: AVAudioFrameCount, slotCount: Int = 2) {
        guard frameCapacity > 0, slotCount > 0 else { return nil }
        var preparedSlots: [Slot] = []
        preparedSlots.reserveCapacity(slotCount)
        for index in 0..<slotCount {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
                return nil
            }
            preparedSlots.append(Slot(index: index, buffer: buffer))
        }
        slots = preparedSlots
        var indices = Array(preparedSlots.indices)
        indices.reserveCapacity(slotCount)
        availableIndices = indices
    }

    func acquire() -> Slot? {
        lock.lock()
        defer { lock.unlock() }
        guard !failedClosed, let index = availableIndices.popLast() else {
            failedClosed = true
            return nil
        }
        return slots[index]
    }

    func release(_ slot: Slot) {
        lock.lock()
        availableIndices.append(slot.index)
        lock.unlock()
    }

    func failClosed() {
        lock.lock()
        failedClosed = true
        lock.unlock()
    }

    func hasFailure() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return failedClosed
    }
}

final class NativeAudioFileWriter: @unchecked Sendable {
    struct FinishResult {
        let recordingURL: URL?
        let retentionFailure: NativeRecordingRetentionFailure?
    }

    /// File writes intentionally live off the render thread. The callback only
    /// claims a preallocated PCM slot; when the writer cannot keep up, the take
    /// is marked unusable instead of growing memory or callback latency.
    private let bufferPool: NativeCaptureBufferPool
    private let writerQueue = DispatchQueue(
        label: "com.brasstune.native.recording-writer",
        qos: .utility
    )
    private var audioFile: AVAudioFile?
    private var retentionFailure: NativeRecordingRetentionFailure?
    private var writtenFrames: Int64 = 0
    private var estimatedBytes: Int64 = 0
    private let sampleRate: Double
    private let bytesPerFrame: Int64
    private let quota: NativeRecordingRetentionQuota

    let destinationURL: URL

    init(
        destinationURL: URL,
        inputFormat: AVAudioFormat,
        recordingBufferFrameCapacity: AVAudioFrameCount = 4096,
        quota: NativeRecordingRetentionQuota = .shipping
    ) throws {
        self.destinationURL = destinationURL
        self.quota = quota
        self.sampleRate = inputFormat.sampleRate
        let declaredBytesPerFrame = Int64(inputFormat.streamDescription.pointee.mBytesPerFrame)
        let bytesPerBufferFrame = max(
            1,
            declaredBytesPerFrame == 0
                ? Int64(MemoryLayout<Float>.size)
                : declaredBytesPerFrame
        )
        // In non-interleaved PCM, the ASBD byte count is per channel buffer.
        // Account for all channel buffers before deciding a take can grow.
        let bufferCount = inputFormat.isInterleaved ? 1 : max(1, Int64(inputFormat.channelCount))
        self.bytesPerFrame = bytesPerBufferFrame * bufferCount
        guard let bufferPool = NativeCaptureBufferPool(
            format: inputFormat,
            frameCapacity: recordingBufferFrameCapacity
        ) else {
            throw NativeAudioEngineError.inputUnavailable
        }
        self.bufferPool = bufferPool
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        audioFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: inputFormat.settings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destinationURL.path
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = destinationURL
        try? mutableURL.setResourceValues(resourceValues)
    }

    /// Called from AVAudioEngine's tap. It never performs file I/O or creates
    /// PCM buffers: audio is copied into an already allocated bounded slot.
    func enqueueCopy(from buffer: AVAudioPCMBuffer) {
        guard let slot = bufferPool.acquire() else { return }
        guard Self.copy(buffer, into: slot.buffer) else {
            bufferPool.failClosed()
            bufferPool.release(slot)
            return
        }
        writerQueue.async { [self] in
            defer { self.bufferPool.release(slot) }
            self.write(slot.buffer)
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile, retentionFailure == nil else { return }
        let nextFrameCount = writtenFrames + Int64(buffer.frameLength)
        let nextEstimatedBytes = estimatedBytes + Int64(buffer.frameLength) * bytesPerFrame
        if let quotaFailure = quota.failure(
            frameCount: nextFrameCount,
            sampleRate: sampleRate,
            estimatedBytes: nextEstimatedBytes
        ) {
            retentionFailure = quotaFailure
            return
        }
        do {
            try audioFile.write(from: buffer)
            writtenFrames = nextFrameCount
            estimatedBytes = nextEstimatedBytes
        } catch {
            retentionFailure = .writeFailed
        }
    }

    /// Used by the pre-created live-capture consumer, never by the render tap.
    func writeFromConsumer(_ buffer: AVAudioPCMBuffer) {
        writerQueue.sync { write(buffer) }
    }

    /// The producer detected an overflow. Record the failure off the render
    /// callback so a partial CAF can never be surfaced as a complete take.
    func failClosedFromConsumer() {
        writerQueue.sync {
            if retentionFailure == nil {
                retentionFailure = .writeFailed
            }
        }
    }

    func finish() -> FinishResult {
        let failure = writerQueue.sync { () -> NativeRecordingRetentionFailure? in
            // A dropped writer buffer means the file cannot honestly be
            // presented as a complete listen-back recording.
            if bufferPool.hasFailure(), retentionFailure == nil {
                retentionFailure = .writeFailed
            }
            let failure = retentionFailure
            audioFile = nil
            return failure
        }

        let preservesCappedAudio = failure == .durationLimitReached || failure == .sizeLimitReached
        guard (failure == nil || preservesCappedAudio),
              FileManager.default.fileExists(atPath: destinationURL.path),
              ((try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 else {
            try? FileManager.default.removeItem(at: destinationURL)
            return FinishResult(recordingURL: nil, retentionFailure: failure)
        }
        return FinishResult(recordingURL: destinationURL, retentionFailure: failure)
    }

    func discard() {
        writerQueue.sync {
            audioFile = nil
        }
        try? FileManager.default.removeItem(at: destinationURL)
    }

    private static func copy(_ buffer: AVAudioPCMBuffer, into copiedBuffer: AVAudioPCMBuffer) -> Bool {
        guard buffer.frameLength <= copiedBuffer.frameCapacity else { return false }
        copiedBuffer.frameLength = buffer.frameLength
        let sourceList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinationList = UnsafeMutableAudioBufferListPointer(copiedBuffer.mutableAudioBufferList)
        guard sourceList.count == destinationList.count else { return false }
        for index in sourceList.indices {
            guard let source = sourceList[index].mData,
                  let destination = destinationList[index].mData else { return false }
            let byteCount = min(sourceList[index].mDataByteSize, destinationList[index].mDataByteSize)
            memcpy(destination, source, Int(byteCount))
        }
        return true
    }
}

/// Lower-target lock-free Int32 wrapper. `OSAtomic` remains available to the
/// project's deployment target (deprecated, but intentionally used here until
/// the target can ship a C11-atomic shim). No render-tap operation waits on an
/// app lock or allocates memory.
private final class NativeLegacyAtomicInt32: @unchecked Sendable {
    private var storage: Int32

    init(_ initialValue: Int32) {
        storage = initialValue
    }

    func load() -> Int32 {
        OSAtomicAdd32Barrier(0, &storage)
    }

    func store(_ value: Int32) {
        while true {
            let current = load()
            if OSAtomicCompareAndSwap32Barrier(current, value, &storage) { return }
        }
    }

    @discardableResult
    func increment() -> Int32 {
        OSAtomicIncrement32Barrier(&storage)
    }
}

/// Lock-free single-producer/single-consumer handoff for AVAudioEngine's
/// render tap. All PCM slots and the polling consumer are created before the
/// tap starts. Release/acquire atomics publish a fully copied slot; the tap
/// only copies into a free preallocated slot and advances one atomic index.
final class NativeLiveCapturePipeline: @unchecked Sendable {
    struct FinishResult {
        let recording: NativeAudioFileWriter.FinishResult?
        let frames: [PitchFrame]
        let droppedInputFrameCount: Int
    }

    private final class Slot: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        let timestampMs = NativeLegacyAtomicInt32(0)

        init?(format: AVAudioFormat, frameCapacity: AVAudioFrameCount) {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
                return nil
            }
            self.buffer = buffer
        }
    }

    private let slots: [Slot]
    private let producerIndex = NativeLegacyAtomicInt32(0)
    private let consumerIndex = NativeLegacyAtomicInt32(0)
    private let acceptingInput = NativeLegacyAtomicInt32(1)
    private let droppedInputFrameCount = NativeLegacyAtomicInt32(0)
    private let queue = DispatchQueue(label: "com.brasstune.native.live-capture-consumer", qos: .userInitiated)
    private let timer: DispatchSourceTimer
    private let writer: NativeAudioFileWriter?
    private let instrumentId: String
    private let referencePitchHz: Double
    private let receiveFrame: @Sendable (PitchFrame) -> Void
    private var drainedFrames: [PitchFrame] = []

    init?(
        format: AVAudioFormat,
        // AVAudioEngine can deliver an oversized first slice after a route or
        // input/output graph handoff even when the requested tap size is 4096.
        // Preallocating 8192-frame slots keeps that physical-device callback
        // on the bounded copy path instead of falsely reporting an overflow.
        frameCapacity: AVAudioFrameCount = 8192,
        slotCount: Int = 4,
        writer: NativeAudioFileWriter?,
        instrumentId: String,
        referencePitchHz: Double,
        automaticallyDrain: Bool = true,
        receiveFrame: @escaping @Sendable (PitchFrame) -> Void
    ) {
        guard slotCount >= 2 else { return nil }
        var preparedSlots: [Slot] = []
        preparedSlots.reserveCapacity(slotCount)
        for _ in 0..<slotCount {
            guard let slot = Slot(format: format, frameCapacity: frameCapacity) else { return nil }
            preparedSlots.append(slot)
        }
        slots = preparedSlots
        self.writer = writer
        self.instrumentId = instrumentId
        self.referencePitchHz = referencePitchHz
        self.receiveFrame = receiveFrame
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.drain() }
        timer.schedule(
            deadline: automaticallyDrain ? .now() : .distantFuture,
            repeating: .milliseconds(5),
            leeway: .milliseconds(2)
        )
        timer.resume()
    }

    /// The only live-tap entrypoint. It contains no app lock, allocation,
    /// asynchronous closure creation, file work, clock call, or UI publish.
    func enqueueFromRenderTap(_ buffer: AVAudioPCMBuffer, timestampMs: Int) {
        guard acceptingInput.load() == 1 else { return }
        let producer = Int(producerIndex.load())
        let next = (producer + 1) % slots.count
        guard next != Int(consumerIndex.load()) else {
            droppedInputFrameCount.increment()
            return
        }
        let slot = slots[producer]
        guard Self.copy(buffer, into: slot.buffer) else {
            droppedInputFrameCount.increment()
            return
        }
        slot.timestampMs.store(Int32(clamping: timestampMs))
        producerIndex.store(Int32(next))
    }

    func finish() -> FinishResult {
        acceptingInput.store(0)
        let frames = queue.sync { () -> [PitchFrame] in
            drain()
            return drainedFrames
        }
        timer.cancel()
        let droppedFrames = Int(droppedInputFrameCount.load())
        if droppedFrames > 0 {
            writer?.failClosedFromConsumer()
        }
        return FinishResult(
            recording: writer?.finish(),
            frames: frames,
            droppedInputFrameCount: droppedFrames
        )
    }

    struct DiscardResult: Equatable {
        let droppedInputFrameCount: Int
    }

    func discard() -> DiscardResult {
        acceptingInput.store(0)
        queue.sync {
            drain()
            drainedFrames.removeAll(keepingCapacity: false)
        }
        timer.cancel()
        writer?.discard()
        return DiscardResult(
            droppedInputFrameCount: Int(droppedInputFrameCount.load())
        )
    }

    private func drain() {
        while true {
            let consumer = Int(consumerIndex.load())
            guard consumer != Int(producerIndex.load()) else { return }
            let slot = slots[consumer]
            writer?.writeFromConsumer(slot.buffer)
            let frame = NativePitchDetector.frame(
                from: slot.buffer,
                timestampMs: Int(slot.timestampMs.load()),
                instrumentId: instrumentId,
                referencePitchHz: referencePitchHz
            )
            drainedFrames.append(frame)
            receiveFrame(frame)
            consumerIndex.store(Int32((consumer + 1) % slots.count))
        }
    }

    private static func copy(_ source: AVAudioPCMBuffer, into destination: AVAudioPCMBuffer) -> Bool {
        guard source.frameLength <= destination.frameCapacity else { return false }
        destination.frameLength = source.frameLength
        let sourceList = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationList = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        guard sourceList.count == destinationList.count else { return false }
        for index in sourceList.indices {
            guard let sourceData = sourceList[index].mData,
                  let destinationData = destinationList[index].mData else { return false }
            memcpy(destinationData, sourceData, Int(min(sourceList[index].mDataByteSize, destinationList[index].mDataByteSize)))
        }
        return true
    }
}

/// Converts a MainActor frame consumer into a genuinely nonisolated Sendable
/// callback. The audio consumer queue invokes only the outer closure; the
/// receiver itself is entered after Swift has hopped to MainActor.
enum NativeAudioFrameDelivery {
    nonisolated static func toMainActor(
        _ receiver: @escaping @MainActor @Sendable (PitchFrame) -> Void
    ) -> @Sendable (PitchFrame) -> Void {
        { frame in
            Task { @MainActor in
                receiver(frame)
            }
        }
    }
}

struct NativeRecordingPlaybackDriver {
    let duration: () -> TimeInterval
    let currentTime: () -> TimeInterval
    let setCurrentTime: (TimeInterval) -> Void
    let isPlaying: () -> Bool
    let prepareToPlay: () -> Bool
    let play: () -> Bool
    let pause: () -> Void
    let stop: () -> Void

    static func live(url: URL) throws -> NativeRecordingPlaybackDriver {
        let player = try AVAudioPlayer(contentsOf: url)
        return NativeRecordingPlaybackDriver(
            duration: { player.duration },
            currentTime: { player.currentTime },
            setCurrentTime: { player.currentTime = $0 },
            isPlaying: { player.isPlaying },
            prepareToPlay: { player.prepareToPlay() },
            play: { player.play() },
            pause: { player.pause() },
            stop: { player.stop() }
        )
    }
}

@MainActor
final class NativeRecordingPlayer: ObservableObject {
    enum State: Equatable {
        case stopped
        case playing
        case paused
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var loadedURL: URL?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var notice: String?

    private let audioSessionCoordinator: NativeAudioSessionCoordinator
    private let makeDriver: (URL) throws -> NativeRecordingPlaybackDriver
    private var driver: NativeRecordingPlaybackDriver?
    private var progressTimer: Timer?
    private var playbackGeneration: UInt64 = 0
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    nonisolated(unsafe) private var mediaServicesResetObserver: NSObjectProtocol?
    private var prepareForPlayback: (() -> Void)?

    init(
        audioSessionCoordinator: NativeAudioSessionCoordinator = .shared,
        makeDriver: @escaping (URL) throws -> NativeRecordingPlaybackDriver = NativeRecordingPlaybackDriver.live
    ) {
        self.audioSessionCoordinator = audioSessionCoordinator
        self.makeDriver = makeDriver
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                self?.handleRouteChange(rawReason: rawReason)
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(rawType: rawType)
            }
        }
        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMediaServicesReset()
            }
        }
    }

    deinit {
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
        }
    }

    func setPlaybackPreparation(_ preparation: @escaping () -> Void) {
        prepareForPlayback = preparation
    }

    func togglePlayback(url: URL) {
        if loadedURL == url, state == .playing {
            pause()
        } else {
            play(url: url)
        }
    }

    func play(url: URL) {
        notice = nil
        if loadedURL != url {
            stopAndUnload()
            do {
                driver = try makeDriver(url)
                loadedURL = url
                duration = max(0, driver?.duration() ?? 0)
            } catch {
                notice = NativeLocalization.string("This recording is no longer on this device.")
                return
            }
        }

        prepareForPlayback?()
        guard !audioSessionCoordinator.isActive(.capture) else {
            notice = NativeLocalization.string("Stop and save recording")
            return
        }

        playbackGeneration &+= 1
        let generation = playbackGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.audioSessionCoordinator.acquire(
                    .recordingPlayback,
                    configuration: .recordingPlayback
                )
            } catch {
                guard generation == self.playbackGeneration else { return }
                self.notice = Self.recordingPlaybackFailureNotice()
                return
            }
            // A newer play request may be awaiting the same coalesced physical
            // session readiness. The stale waiter must not release that newer
            // request's shared owner after activation completes.
            guard generation == self.playbackGeneration else { return }
            guard let driver = self.driver else {
                self.audioSessionCoordinator.release(.recordingPlayback, deactivation: .immediate)
                return
            }
            _ = driver.prepareToPlay()
            guard driver.play() else {
                self.audioSessionCoordinator.release(.recordingPlayback, deactivation: .immediate)
                self.notice = Self.recordingPlaybackFailureNotice()
                return
            }
            self.state = .playing
            self.currentTime = driver.currentTime()
            self.scheduleProgressTimer()
        }
    }

    private static func recordingPlaybackFailureNotice() -> String {
        NativeLocalization.string(
            "BrassTune couldn't play this recording. Check your audio output and try again."
        )
    }

    func pause() {
        guard state == .playing, let driver else { return }
        playbackGeneration &+= 1
        driver.pause()
        currentTime = driver.currentTime()
        state = .paused
        invalidateProgressTimer()
        audioSessionCoordinator.release(.recordingPlayback)
    }

    func stop() {
        playbackGeneration &+= 1
        driver?.stop()
        driver?.setCurrentTime(0)
        currentTime = 0
        state = .stopped
        invalidateProgressTimer()
        audioSessionCoordinator.release(.recordingPlayback)
    }

    func stopAndUnload() {
        stop()
        driver = nil
        loadedURL = nil
        duration = 0
        notice = nil
    }

    func handleRouteChange(rawReason: UInt?) {
        guard Self.isOutputLossRouteChange(rawReason: rawReason),
              state == .playing || state == .paused else { return }
        stop()
        audioSessionCoordinator.deactivateImmediatelyIfIdle()
        notice = NativeLocalization.string("Your audio output changed. Check your headphones or speaker before continuing.")
    }

    func handleInterruption(rawType: UInt?) {
        guard rawType == AVAudioSession.InterruptionType.began.rawValue,
              state == .playing else { return }
        pause()
        audioSessionCoordinator.deactivateImmediatelyIfIdle()
        notice = NativeLocalization.string("Try again when you're ready.")
    }

    func handleMediaServicesReset() {
        playbackGeneration &+= 1
        let hadActivePlayback = state != .stopped || audioSessionCoordinator.isActive(.recordingPlayback)
        driver?.stop()
        driver?.setCurrentTime(0)
        driver = nil
        loadedURL = nil
        currentTime = 0
        duration = 0
        state = .stopped
        invalidateProgressTimer()
        // This must happen before release: media services may already have
        // discarded the underlying session, even if a prior deactivation
        // attempt failed. A later explicit play must configure and activate.
        audioSessionCoordinator.invalidateAfterMediaServicesReset()
        audioSessionCoordinator.release(.recordingPlayback, deactivation: .immediate)
        if hadActivePlayback {
            notice = NativeLocalization.string("Audio services restarted. Try the audio action again.")
        }
    }

    static func isOutputLossRouteChange(rawReason: UInt?) -> Bool {
        rawReason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            || rawReason == AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue
    }

    private func scheduleProgressTimer() {
        invalidateProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let driver = self.driver else { return }
                self.currentTime = driver.currentTime()
                if !driver.isPlaying(), self.currentTime >= max(0, self.duration - 0.05) {
                    self.stop()
                }
            }
        }
    }

    private func invalidateProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

enum NativeAudioActivityState: Equatable {
    case idle
    case starting
    case listeningNoSignal
    case estimating
    case stable
    case interrupted
    case routeChanged
    case recoverableError
    case fatalError
}

/// The single externally observable microphone contract. `permissionGranted`
/// carries the live operational phase so callers cannot mistake a grant for an
/// active, healthy audio capture.
enum NativeAudioOperationalState: Equatable {
    case permissionNotDetermined
    case permissionRequesting
    case permissionGranted(NativeAudioActivityState)
    case permissionDenied
    case permissionRestrictedOrUnavailable
}

/// A normalized, faded tone buffer can be reused across starts. Volume stays
/// on the player node so changing a slider never requires rebuilding 44,100
/// samples. The small LRU bound prevents an unbounded cache from retaining
/// arbitrary user-selected chord combinations.
struct NativeToneBufferCacheKey: Hashable {
    let frequencyBitPatterns: [UInt64]

    init(frequenciesHz: [Double]) {
        frequencyBitPatterns = frequenciesHz.map(\.bitPattern)
    }
}

final class NativeToneBufferCache {
    private let capacity: Int
    private var buffers: [NativeToneBufferCacheKey: AVAudioPCMBuffer] = [:]
    private var recency: [NativeToneBufferCacheKey] = []

    init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    func buffer(for frequenciesHz: [Double]) throws -> AVAudioPCMBuffer {
        let key = NativeToneBufferCacheKey(frequenciesHz: frequenciesHz)
        if let cached = buffers[key] {
            touch(key)
            return cached
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100),
              let samples = buffer.floatChannelData?[0] else {
            throw NativeAudioEngineError.outputUnavailable
        }
        buffer.frameLength = 44_100
        let fadeFrames = 441
        let normalization = 1 / Float(frequenciesHz.count)
        for frame in 0..<Int(buffer.frameLength) {
            let sample = frequenciesHz.reduce(0.0) { partial, frequency in
                let phase = 2 * Double.pi * frequency * Double(frame) / format.sampleRate
                return partial + sin(phase)
            }
            let fadeIn = min(1, Double(frame) / Double(fadeFrames))
            let fadeOut = min(1, Double(Int(buffer.frameLength) - frame) / Double(fadeFrames))
            samples[frame] = Float(sample) * normalization * Float(min(fadeIn, fadeOut))
        }

        buffers[key] = buffer
        touch(key)
        while recency.count > capacity {
            buffers.removeValue(forKey: recency.removeFirst())
        }
        return buffer
    }

    var count: Int { buffers.count }

    private func touch(_ key: NativeToneBufferCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

@MainActor
final class NativeAudioEngine: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var currentFrame: PitchFrame?
    @Published private(set) var frames: [PitchFrame] = []
    /// Number of live microphone frames accepted by the UI-side receiver for
    /// the active capture. Unlike `frames`, this diagnostic survives a
    /// deliberate discard so physical instrumentation can prove the capture
    /// had an input-delivery denominator without retaining pitch data.
    @Published private(set) var acceptedLiveFrameCount = 0
    @Published private(set) var activeSource: PracticeSessionSource = .live
    @Published private(set) var audioNotice: String?
    @Published private(set) var routeChanged = false
    @Published private(set) var audioState: NativeAudioOperationalState = .permissionNotDetermined
    @Published private(set) var tonePlaying = false
    @Published private(set) var toneFrequencyHz: Double?
    @Published private(set) var toneFrequenciesHz: [Double] = []

    private(set) var audioGraphGeneration: UInt64 = 0
    private var fixtureStartedAt: Date?
    private var fixtureInstrumentId = "trumpet"
    private var fixtureReferencePitchHz = 440.0
    private var liveStartRequestID: UUID?
    private var activeCaptureID: UUID?
    private var requestGeneration: UInt64 = 0
    private let maxLiveFrames = 18_000
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    nonisolated(unsafe) private var mediaServicesResetObserver: NSObjectProtocol?
    private let audioSessionCoordinator: NativeAudioSessionCoordinator
    private let microphonePermissionRequester: @MainActor () async -> Bool
    private let simulateTonePlayback: Bool
    private var prepareForTonePlayback: (() -> Void)?
    private var unexpectedCaptureCompletion: ((NativeLiveCapture) -> Void)?

    static var defaultRecordingSource: PracticeSessionSource {
        NativeTestFixtures.areEnabled ? .sample : .live
    }

    static var testFixturesEnabled: Bool { NativeTestFixtures.areEnabled }

    init(
        audioSessionCoordinator: NativeAudioSessionCoordinator = .shared,
        microphonePermissionRequester: (@MainActor () async -> Bool)? = nil,
        simulateTonePlayback: Bool = false
    ) {
        self.audioSessionCoordinator = audioSessionCoordinator
        self.microphonePermissionRequester = microphonePermissionRequester ?? {
            await AVAudioApplication.requestRecordPermission()
        }
        self.simulateTonePlayback = simulateTonePlayback
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                self?.handleRouteChange(rawReason: rawReason)
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(rawType: typeValue)
            }
        }
        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMediaServicesReset()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("UITEST_MIC_DENIED") {
            setAudioState(.permissionDenied)
        }
    }

    deinit {
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
        }
    }

    func requestMicrophonePermission() async -> Bool {
        setAudioState(.permissionRequesting)
        let granted = await microphonePermissionRequester()
        guard audioState == .permissionRequesting else { return granted }
        setAudioState(granted ? .permissionGranted(.idle) : .permissionDenied)
        return granted
    }

    func startFixtureRecording(instrumentId: String, referencePitchHz: Double) {
        guard Self.testFixturesEnabled else {
            stopAndResetAudioEngine()
            activeSource = .live
            frames.removeAll()
            currentFrame = nil
            return
        }
        stopAndResetAudioEngine()
        recording = true
        activeSource = .sample
        fixtureStartedAt = Date()
        fixtureInstrumentId = instrumentId
        fixtureReferencePitchHz = NativeReferencePitch.sanitized(referencePitchHz)
        frames = (0..<12).map { PitchFrame.fixture(index: $0, instrumentId: instrumentId, referencePitchHz: fixtureReferencePitchHz) }
        currentFrame = frames.last
        setAudioState(.permissionGranted(
            currentFrame.map(Self.isStableTunerFrame) == true ? .stable : .estimating
        ))
    }

    func stopFixtureRecording() -> [PitchFrame] {
        guard Self.testFixturesEnabled, activeSource == .sample else {
            stopAndResetAudioEngine()
            frames.removeAll()
            currentFrame = nil
            return []
        }
        let elapsed = max(3.5, Date().timeIntervalSince(fixtureStartedAt ?? Date()))
        let frameCount = min(240, max(12, Int((elapsed / 0.11).rounded())))
        frames = (0..<frameCount).map { PitchFrame.fixture(index: $0, instrumentId: fixtureInstrumentId, referencePitchHz: fixtureReferencePitchHz) }
        currentFrame = frames.last
        recording = false
        fixtureStartedAt = nil
        setAudioState(.permissionGranted(.idle))
        return frames
    }

    func startLiveRecording(
        instrumentId: String,
        referencePitchHz: Double,
        recordingURL: URL? = nil
    ) async throws -> Bool {
        // Multiple UI actions can arrive while permission is being resolved.
        // Never install a second tap or race the first request's cleanup.
        if recording, activeSource == .live { return true }
        guard liveStartRequestID == nil else { return false }
        guard !audioSessionCoordinator.isActive(.capture) else { return false }
        if Self.testFixturesEnabled {
            // Simulate a live capture so the tuner's recording UI is drivable in
            // UI tests without a physical microphone. activeSource stays .live so
            // it behaves like a real live take (no sample-mode surface).
            stopAndResetAudioEngine()
            recording = true
            activeSource = .live
            let safeReferencePitch = NativeReferencePitch.sanitized(referencePitchHz)
            frames = (0..<12).map { PitchFrame.fixture(index: $0, instrumentId: instrumentId, referencePitchHz: safeReferencePitch) }
            currentFrame = frames.last
            setAudioState(.permissionGranted(
                currentFrame.map(Self.isStableTunerFrame) == true ? .stable : .estimating
            ))
            return true
        }
        let requestID = UUID()
        liveStartRequestID = requestID
        let permissionGranted = await requestMicrophonePermission()
        guard liveStartRequestID == requestID else { return false }
        liveStartRequestID = nil
        guard permissionGranted else {
            recording = false
            activeSource = .live
            frames.removeAll()
            currentFrame = nil
            return false
        }
        requestGeneration &+= 1
        let generation = requestGeneration
        let captureID = UUID()
        activeCaptureID = captureID
        frames.removeAll()
        currentFrame = nil
        acceptedLiveFrameCount = 0
        activeSource = .live
        setAudioState(.permissionGranted(.starting))
        let request = NativeCaptureStartRequest(
            generation: generation,
            captureID: captureID,
            instrumentId: instrumentId,
            referencePitchHz: NativeReferencePitch.sanitized(referencePitchHz),
            recordingURL: recordingURL,
            receiveFrame: Self.makeFrameReceiver(engine: self, captureID: captureID)
        )
        let physicalStart: Task<NativeCaptureStartResult, Error>
        do {
            physicalStart = try audioSessionCoordinator.startCapture(request)
        } catch {
            setAudioState(.permissionGranted(.recoverableError))
            throw error
        }
        do {
            let result = try await physicalStart.value
            guard result.generation == requestGeneration,
                  liveStartRequestID == nil else {
                return false
            }
            audioGraphGeneration = result.graphGeneration
            recording = true
            return true
        } catch {
            guard generation == requestGeneration else { return false }
            audioSessionCoordinator.rollbackLogicalOwner(.capture)
            recording = false
            if case NativeAudioEngineError.inputUnavailable = error {
                setAudioState(.permissionRestrictedOrUnavailable)
            } else {
                setAudioState(.permissionGranted(.recoverableError))
            }
            throw error
        }
    }

    func cancelPendingLiveStart() {
        requestGeneration &+= 1
        if !recording, audioSessionCoordinator.isActive(.capture) {
            let generation = requestGeneration
            activeCaptureID = nil
            _ = audioSessionCoordinator.stopCapture(
                generation: generation,
                reason: .userStopped,
                discard: true
            )
        }
        if audioState == .permissionRequesting {
            setAudioState(.permissionNotDetermined)
        }
        liveStartRequestID = nil
    }

    func setTonePlaybackPreparation(_ preparation: @escaping () -> Void) {
        prepareForTonePlayback = preparation
    }

    func setUnexpectedCaptureCompletion(_ completion: @escaping (NativeLiveCapture) -> Void) {
        unexpectedCaptureCompletion = completion
    }

    func stopLiveRecording() -> Task<NativeLiveCapture, Never> {
        stopLiveCapture(reason: .userStopped, discard: false)
    }

    @discardableResult
    func discardLiveRecording() -> Task<NativeLiveCapture, Never> {
        let completion = stopLiveCapture(reason: .userStopped, discard: true)
        frames.removeAll()
        currentFrame = nil
        return completion
    }

    func startTone(frequencyHz: Double, volume: Double) throws {
        try startTone(frequenciesHz: [frequencyHz], volume: volume)
    }

    func startTone(frequenciesHz: [Double], volume: Double) throws {
        guard (1...4).contains(frequenciesHz.count),
              frequenciesHz.allSatisfy({ $0.isFinite && (20...5_000).contains($0) }) else {
            throw NativeAudioEngineError.invalidToneFrequency
        }
        prepareForTonePlayback?()
        if recording {
            guard !recording else {
                throw NativeAudioEngineError.captureActive
            }
        }
        let frequencyHz = frequenciesHz[0]
        stopAndResetAudioEngine()
        activeSource = .live
        let safeVolume = Float(min(0.5, max(0.05, volume)))

        if Self.testFixturesEnabled || simulateTonePlayback {
            tonePlaying = true
            toneFrequencyHz = frequencyHz
            toneFrequenciesHz = frequenciesHz
            return
        }
        requestGeneration &+= 1
        let generation = requestGeneration
        let physicalStart = try audioSessionCoordinator.startTone(NativeToneStartRequest(
            generation: generation,
            frequenciesHz: frequenciesHz,
            volume: safeVolume
        ))
        tonePlaying = true
        toneFrequencyHz = frequencyHz
        toneFrequenciesHz = frequenciesHz
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let completedGeneration = try await physicalStart.value
                guard completedGeneration == self.requestGeneration,
                      self.tonePlaying else {
                    return
                }
                self.audioGraphGeneration = await self.audioSessionCoordinator.graphGeneration()
            } catch {
                guard generation == self.requestGeneration else { return }
                self.audioSessionCoordinator.rollbackLogicalOwner(.tone)
                self.tonePlaying = false
                self.toneFrequencyHz = nil
                self.toneFrequenciesHz = []
                self.setAudioState(.permissionGranted(.recoverableError))
            }
        }
    }

    func stopTone(
        deactivation: NativeAudioSessionCoordinator.DeactivationPolicy = .deferred
    ) {
        guard tonePlaying || audioSessionCoordinator.isActive(.tone) else { return }
        requestGeneration &+= 1
        tonePlaying = false
        toneFrequencyHz = nil
        toneFrequenciesHz = []
        audioSessionCoordinator.stopTone(deactivation: deactivation)
    }

    func setExternalAudioNotice(_ message: String?) {
        audioNotice = message
    }

    func stopAndResetAudioEngine() {
        resetAudioEngine(discardCaptureFile: true)
    }

    /// Call after feature teardown when the app leaves the active scene. This
    /// cancels any short handoff delay without disturbing an active owner.
    func deactivateSessionImmediatelyIfIdle() {
        audioSessionCoordinator.deactivateImmediatelyIfIdle()
    }

    func handleRouteChange(rawReason: UInt?) {
        guard NativeRecordingPlayer.isOutputLossRouteChange(rawReason: rawReason) else {
            // `.categoryChange` is emitted for BrassTune's own session
            // reconfiguration. Treating it as output loss stops tones that just
            // started and makes listen-back appear broken.
            return
        }
        audioSessionCoordinator.invalidateSessionConfiguration()

        let wasPlayingTone = tonePlaying
        let wasCapturingLive = recording && activeSource == .live
        if wasCapturingLive {
            let generation = requestGeneration &+ 1
            let completion = stopLiveCapture(reason: .routeLoss, discard: false)
            setAudioState(.permissionGranted(.routeChanged))
            Task { @MainActor [weak self] in
                let capture = await completion.value
                guard let self, generation == self.requestGeneration else { return }
                self.unexpectedCaptureCompletion?(capture)
            }
            return
        } else if wasPlayingTone {
            stopTone(deactivation: .immediate)
            routeChanged = true
            audioNotice = NativeLocalization.string("The reference tone stopped because your audio output changed. Check your headphones or speaker before restarting.")
            return
        }
        if case .permissionGranted = audioState {
            setAudioState(.permissionGranted(.routeChanged))
        } else {
            audioNotice = NativeLocalization.string("Your audio output changed. Check your headphones or speaker before continuing.")
        }
    }

    func handleInterruption(rawType: UInt?) {
        if rawType == AVAudioSession.InterruptionType.began.rawValue {
            audioSessionCoordinator.invalidateSessionConfiguration()
        }
        if rawType == AVAudioSession.InterruptionType.began.rawValue,
           recording, activeSource == .live {
            let generation = requestGeneration &+ 1
            let completion = stopLiveCapture(reason: .interruption, discard: false)
            setAudioState(.permissionGranted(.interrupted))
            Task { @MainActor [weak self] in
                let capture = await completion.value
                guard let self, generation == self.requestGeneration else { return }
                self.unexpectedCaptureCompletion?(capture)
            }
        } else if rawType == AVAudioSession.InterruptionType.began.rawValue, tonePlaying {
            stopTone(deactivation: .immediate)
            if case .permissionGranted = audioState {
                setAudioState(.permissionGranted(.interrupted))
            } else {
                audioNotice = NativeLocalization.string("The reference tone stopped because audio was interrupted. Try again when the interruption ends.")
            }
        } else if rawType == AVAudioSession.InterruptionType.ended.rawValue,
                  audioState == .permissionGranted(.interrupted) {
            // Do not silently resume a microphone after a phone call. The
            // next explicit start receives a newly validated route instead.
            setAudioState(.permissionGranted(.idle))
        }
    }

    func handleMediaServicesReset() {
        requestGeneration &+= 1
        let generation = requestGeneration
        let wasCapturing = recording && activeSource == .live
        recording = false
        tonePlaying = false
        toneFrequencyHz = nil
        toneFrequenciesHz = []
        liveStartRequestID = nil
        let completion = audioSessionCoordinator.handleMediaServicesReset(
            generation: generation
        )
        Task { @MainActor [weak self] in
            let captureResult = await completion.value
            guard let self, generation == self.requestGeneration else { return }
            self.audioGraphGeneration = await self.audioSessionCoordinator.graphGeneration()
            if wasCapturing, let captureResult,
               captureResult.generation == generation {
                self.frames = captureResult.capture.frames
                self.currentFrame = captureResult.capture.frames.last
                self.unexpectedCaptureCompletion?(captureResult.capture)
            }
        }
        // AVAudioEngine nodes/taps are invalid after this notification. State
        // is recoverable, but no automatic restart can safely assume a route.
        if case .permissionGranted = audioState {
            setAudioState(.permissionGranted(.recoverableError))
        } else {
            audioNotice = NativeLocalization.string("Audio services restarted. Try the audio action again.")
        }
    }

    private func resetAudioEngine(discardCaptureFile: Bool, graphIsValid: Bool = true) {
        requestGeneration &+= 1
        let generation = requestGeneration
        if audioSessionCoordinator.isActive(.capture) {
            _ = audioSessionCoordinator.stopCapture(
                generation: generation,
                reason: .userStopped,
                discard: discardCaptureFile,
                graphIsValid: graphIsValid
            )
        }
        audioSessionCoordinator.stopTone()
        recording = false
        tonePlaying = false
        toneFrequencyHz = nil
        toneFrequenciesHz = []
        fixtureStartedAt = nil
        liveStartRequestID = nil
        if case .permissionGranted = audioState {
            setAudioState(.permissionGranted(.idle))
        }
    }

    private func stopLiveCapture(
        reason: NativeLiveCaptureCompletionReason,
        discard: Bool
    ) -> Task<NativeLiveCapture, Never> {
        requestGeneration &+= 1
        let generation = requestGeneration
        let fallbackID = activeCaptureID ?? UUID()
        // A deliberate discard must report lifecycle diagnostics (including
        // dropped input frames) without returning or republishing either the
        // render-pipeline frames or the UI's last accepted frame cache.
        let fallbackFrames = discard ? [] : frames
        activeCaptureID = nil
        recording = false
        tonePlaying = false
        toneFrequencyHz = nil
        toneFrequenciesHz = []
        fixtureStartedAt = nil
        liveStartRequestID = nil
        if reason == .userStopped {
            setAudioState(.permissionGranted(.idle))
        }
        guard audioSessionCoordinator.isActive(.capture) else {
            return Task {
                NativeLiveCapture(
                    id: fallbackID,
                    startedAt: Date(),
                    endedAt: Date(),
                    frames: fallbackFrames,
                    recordingURL: nil,
                    recordingRetentionFailure: nil,
                    completionReason: reason
                )
            }
        }
        let physicalStop = audioSessionCoordinator.stopCapture(
            generation: generation,
            reason: reason,
            discard: discard
        )
        return Task { @MainActor [weak self] in
            let result = await physicalStop.value
            let capture = !discard && result.capture.frames.isEmpty && !fallbackFrames.isEmpty
                ? NativeLiveCapture(
                    id: result.capture.id,
                    startedAt: result.capture.startedAt,
                    endedAt: result.capture.endedAt,
                    frames: fallbackFrames,
                    droppedInputFrameCount: result.capture.droppedInputFrameCount,
                    recordingURL: result.capture.recordingURL,
                    recordingRetentionFailure: result.capture.recordingRetentionFailure,
                    completionReason: result.capture.completionReason
                )
                : result.capture
            if let self, result.generation == self.requestGeneration {
                if discard {
                    self.frames.removeAll()
                    self.currentFrame = nil
                } else {
                    self.frames = capture.frames
                    self.currentFrame = capture.frames.last
                }
            }
            return capture
        }
    }

    private func appendLiveFrame(_ frame: PitchFrame, captureID: UUID) {
        guard recording,
              activeSource == .live,
              activeCaptureID == captureID else { return }
        frames.append(frame)
        acceptedLiveFrameCount &+= 1
        if frames.count > maxLiveFrames {
            frames.removeFirst(frames.count - maxLiveFrames)
        }
        currentFrame = frame
        if frame.rms < BrassTuneCore.silenceRMSThreshold {
            setAudioState(.permissionGranted(.listeningNoSignal))
        } else if !Self.isStableTunerFrame(frame) {
            setAudioState(.permissionGranted(.estimating))
        } else {
            setAudioState(.permissionGranted(.stable))
        }
    }

    /// Test-only hook for regression coverage of teardown behavior after an
    /// accepted microphone frame. It has internal visibility only and is not
    /// reachable from the app's release UI surface.
    func seedAcceptedLiveFrameForTesting(_ frame: PitchFrame) {
        guard let activeCaptureID else { return }
        appendLiveFrame(frame, captureID: activeCaptureID)
    }

    private func setAudioState(_ state: NativeAudioOperationalState) {
        audioState = state
        permissionDenied = state == .permissionDenied || state == .permissionRestrictedOrUnavailable
        routeChanged = state == .permissionGranted(.routeChanged)
        switch state {
        case .permissionDenied:
            audioNotice = NativeLocalization.string("Microphone access is off. Allow it in Settings, then try again.")
        case .permissionRestrictedOrUnavailable:
            audioNotice = NativeLocalization.string("BrassTune can't hear a microphone.")
        case .permissionGranted(.interrupted):
            audioNotice = NativeLocalization.string("Recording stopped because the audio session was interrupted.")
        case .permissionGranted(.routeChanged):
            audioNotice = NativeLocalization.string("Your audio output changed. Check your headphones or speaker before continuing.")
        case .permissionGranted(.recoverableError):
            audioNotice = NativeLocalization.string("BrassTune couldn't start the microphone. Check your audio input and try again.")
        case .permissionGranted(.fatalError):
            audioNotice = NativeLocalization.string("BrassTune couldn't continue the microphone session.")
        default:
            audioNotice = nil
        }
    }

    /// The consumer queue calls this nonisolated Sendable closure. Actor entry
    /// happens only inside the task, so Swift never invokes a MainActor-inferred
    /// closure on the audio consumer queue before it can hop actors.
    nonisolated private static func makeFrameReceiver(
        engine: NativeAudioEngine,
        captureID: UUID
    ) -> @Sendable (PitchFrame) -> Void {
        NativeAudioFrameDelivery.toMainActor { [weak engine] frame in
            engine?.appendLiveFrame(frame, captureID: captureID)
        }
    }

    nonisolated static func isStableTunerFrame(_ frame: PitchFrame) -> Bool {
        frame.frequencyHz?.isFinite == true
            && frame.centsDeviation?.isFinite == true
            && frame.confidence.isFinite
            && frame.confidence >= BrassTuneCore.minimumRecordingConfidence
            && frame.rms.isFinite
            && frame.rms >= BrassTuneCore.silenceRMSThreshold
            && [.flat, .inTune, .sharp].contains(frame.tuningStatus)
    }

}

enum NativeAudioEngineError: Error, Equatable {
    case captureActive
    case inputUnavailable
    case outputUnavailable
    case invalidToneFrequency
    case audioSessionOwnerConflict
    case inputTapAlreadyInstalled
}

enum NativePitchDetector {
    static func frame(
        from buffer: AVAudioPCMBuffer,
        timestampMs: Int,
        instrumentId: String,
        referencePitchHz: Double
    ) -> PitchFrame {
        guard let samples = samples(from: buffer) else {
            return PitchFrame.detected(
                timestampMs: timestampMs,
                frequencyHz: nil,
                confidence: 0,
                rms: 0,
                instrumentId: instrumentId,
                referencePitchHz: referencePitchHz
            )
        }
        return frame(
            samples: samples,
            sampleRate: buffer.format.sampleRate,
            timestampMs: timestampMs,
            instrumentId: instrumentId,
            referencePitchHz: referencePitchHz
        )
    }

    static func frame(
        samples: [Float],
        sampleRate: Double,
        timestampMs: Int,
        instrumentId: String,
        referencePitchHz: Double
    ) -> PitchFrame {
        guard !samples.isEmpty, sampleRate > 0 else {
            return PitchFrame.detected(
                timestampMs: timestampMs,
                frequencyHz: nil,
                confidence: 0,
                rms: 0,
                instrumentId: instrumentId,
                referencePitchHz: referencePitchHz
            )
        }

        let rms = rootMeanSquare(samples)
        guard rms >= BrassTuneCore.silenceRMSThreshold else {
            return PitchFrame.detected(
                timestampMs: timestampMs,
                frequencyHz: nil,
                confidence: 0,
                rms: rms,
                instrumentId: instrumentId,
                referencePitchHz: referencePitchHz
            )
        }

        let mean = samples.reduce(0.0) { $0 + Double($1) } / Double(samples.count)
        let centered = samples.map { Double($0) - mean }
        let detection = autocorrelationPitch(samples: centered, sampleRate: sampleRate, instrumentId: instrumentId)
        let lockedFrequency = detection.confidence >= 0.55 ? detection.frequencyHz : nil

        return PitchFrame.detected(
            timestampMs: timestampMs,
            frequencyHz: lockedFrequency,
            confidence: detection.confidence,
            rms: rms,
            instrumentId: instrumentId,
            referencePitchHz: referencePitchHz
        )
    }

    static func samples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        if let floatData = buffer.floatChannelData {
            let channelCount = max(1, Int(buffer.format.channelCount))
            var samples = Array(repeating: Float(0), count: frameLength)
            for channelIndex in 0..<channelCount {
                let channel = floatData[channelIndex]
                for frameIndex in 0..<frameLength {
                    samples[frameIndex] += channel[frameIndex] / Float(channelCount)
                }
            }
            return samples
        }

        return nil
    }

    private static func rootMeanSquare(_ samples: [Float]) -> Double {
        let squareSum = samples.reduce(0.0) { partial, sample in
            let value = Double(sample)
            return partial + value * value
        }
        return sqrt(squareSum / Double(samples.count))
    }

    private static func autocorrelationPitch(samples: [Double], sampleRate: Double, instrumentId: String) -> (frequencyHz: Double?, confidence: Double) {
        guard samples.count >= 64 else { return (nil, 0) }
        let profileRange = acousticRange(for: instrumentId)
        let minFrequency = profileRange.minimumHz
        let maxFrequency = profileRange.maximumHz
        let minLag = max(1, Int(sampleRate / maxFrequency))
        let maxLag = min(samples.count / 2, Int(sampleRate / minFrequency))
        guard minLag < maxLag else { return (nil, 0) }

        var correlations: [Int: Double] = [:]
        correlations.reserveCapacity(maxLag - minLag + 1)

        for lag in minLag...maxLag {
            correlations[lag] = correlation(samples: samples, lag: lag)
        }

        let bestCorrelation = correlations.values.max() ?? 0
        guard bestCorrelation > 0 else { return (nil, 0) }

        let lockThreshold = max(0.82, bestCorrelation * 0.92)
        var selectedLag = 0
        var selectedCorrelation = 0.0

        for lag in minLag...maxLag {
            let current = correlations[lag] ?? 0
            let previous = correlations[lag - 1] ?? current
            let next = correlations[lag + 1] ?? current
            if current >= lockThreshold, current >= previous, current >= next {
                selectedLag = lag
                selectedCorrelation = current
                break
            }
        }

        guard selectedLag > 0 else { return (nil, min(0.94, max(0, bestCorrelation))) }

        let previous = correlations[selectedLag - 1] ?? selectedCorrelation
        let next = correlations[selectedLag + 1] ?? selectedCorrelation
        let divisor = previous - 2 * selectedCorrelation + next
        let offset = divisor == 0 ? 0 : min(0.5, max(-0.5, (previous - next) / (2 * divisor)))
        let refinedLag = Double(selectedLag) + offset
        guard refinedLag > 0 else { return (nil, min(0.94, max(0, selectedCorrelation))) }
        return (sampleRate / refinedLag, min(0.999, max(0, selectedCorrelation)))
    }

    static func acousticRange(for instrumentId: String) -> InstrumentAcousticRange {
        InstrumentAcousticRange.forInstrument(instrumentId)
    }

    private static func correlation(samples: [Double], lag: Int) -> Double {
        var numerator = 0.0
        var energyA = 0.0
        var energyB = 0.0
        let count = samples.count - lag
        guard count > 0 else { return 0 }
        for index in 0..<count {
            let a = samples[index]
            let b = samples[index + lag]
            numerator += a * b
            energyA += a * a
            energyB += b * b
        }
        guard energyA > 0, energyB > 0 else { return 0 }
        return numerator / sqrt(energyA * energyB)
    }

}

/// Click PCM is constructed once for the negotiated hardware rate and channel
/// count. This avoids scheduling a fixed 44.1 kHz mono buffer onto a graph
/// negotiated for a Bluetooth or multichannel route.
struct NativeMetronomeClickBuffers {
    let regular: AVAudioPCMBuffer
    let accent: AVAudioPCMBuffer
    let sampleRate: Double
    let channelCount: AVAudioChannelCount

    init(outputFormat: AVAudioFormat) throws {
        guard outputFormat.sampleRate.isFinite,
              outputFormat.sampleRate > 0,
              outputFormat.channelCount > 0,
              let clickFormat = AVAudioFormat(
                standardFormatWithSampleRate: outputFormat.sampleRate,
                channels: outputFormat.channelCount
              ) else {
            throw NativeAudioEngineError.outputUnavailable
        }
        sampleRate = clickFormat.sampleRate
        channelCount = clickFormat.channelCount
        regular = try Self.makeBuffer(format: clickFormat, accent: false)
        accent = try Self.makeBuffer(format: clickFormat, accent: true)
    }

    func matches(_ format: AVAudioFormat) -> Bool {
        abs(sampleRate - format.sampleRate) < 0.5 && channelCount == format.channelCount
    }

    func buffer(accent: Bool) -> AVAudioPCMBuffer { accent ? self.accent : regular }

    private static func makeBuffer(format: AVAudioFormat, accent: Bool) throws -> AVAudioPCMBuffer {
        let duration = accent ? 0.048 : 0.036
        let frameCount = AVAudioFrameCount((format.sampleRate * duration).rounded(.up))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            throw NativeAudioEngineError.outputUnavailable
        }
        buffer.frameLength = frameCount
        let frequency = accent ? 1_760.0 : 1_320.0
        let amplitude = accent ? 0.55 : 0.38
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let sample = Float(sin(2 * Double.pi * frequency * time) * amplitude * exp(-time * 90))
            for channel in 0..<Int(format.channelCount) {
                channels[channel][frame] = sample
            }
        }
        return buffer
    }
}

/// The audible edge uses a host-time timestamp and a serial audio queue. UI
/// beat state remains on MainActor, but scroll/run-loop pressure cannot cause
/// AVAudioPlayerNode scheduling to execute on the main run loop.
enum NativeMetronomeScheduling {
    static func hostTime(now: UInt64 = mach_absolute_time()) -> AVAudioTime {
        AVAudioTime(hostTime: now)
    }
}

#if PHYSICAL_INSTRUMENTATION
/// Stable physical-jitter evidence schema. `phase` is 0 for schedule-call
/// return and 1 for completion; `status` is 0 pending, 1 success, 2 failure;
/// `error` is 0 none, 1 output unavailable, 2 owner conflict, 99 other.
private enum NativeMetronomePulseTrace {
    struct Snapshot: Sendable {
        let runGeneration: UInt64
        let pulseIndex: UInt64
        let targetHostTime: UInt64
        let scheduleCallStartHostTime: UInt64
        let scheduleCallEndHostTime: UInt64
    }

    static let log = OSLog(
        subsystem: "com.aryasalem.BrassTune",
        category: .pointsOfInterest
    )

    static func emitSchedule(_ snapshot: Snapshot) {
        emit(snapshot, phase: 0, status: 0, error: 0, stale: false)
    }

    static func emitCompletion(
        _ snapshot: Snapshot,
        result: Result<Void, Error>,
        stale: Bool
    ) {
        switch result {
        case .success:
            emit(snapshot, phase: 1, status: 1, error: 0, stale: stale)
        case .failure(let failure):
            let errorCode: UInt32
            switch failure as? NativeAudioEngineError {
            case .outputUnavailable: errorCode = 1
            case .audioSessionOwnerConflict: errorCode = 2
            default: errorCode = 99
            }
            emit(snapshot, phase: 1, status: 2, error: errorCode, stale: stale)
        }
    }

    private static func emit(
        _ snapshot: Snapshot,
        phase: UInt32,
        status: UInt32,
        error: UInt32,
        stale: Bool
    ) {
        os_signpost(
            .event,
            log: log,
            name: "MetronomePulse",
            "schema=1 phase=%{public}u run_generation=%{public}llu pulse_index=%{public}llu target_host_time=%{public}llu schedule_call_start_host_time=%{public}llu schedule_call_end_host_time=%{public}llu status=%{public}u error=%{public}u stale=%{public}u",
            phase,
            snapshot.runGeneration,
            snapshot.pulseIndex,
            snapshot.targetHostTime,
            snapshot.scheduleCallStartHostTime,
            snapshot.scheduleCallEndHostTime,
            status,
            error,
            stale ? 1 : 0
        )
    }
}

private final class NativeMetronomePulseTraceContext: @unchecked Sendable {
    private let lock = NSLock()
    private let runGeneration: UInt64
    private let pulseIndex: UInt64
    private let targetHostTime: UInt64
    private let scheduleCallStartHostTime: UInt64
    private var scheduleCallEndHostTime: UInt64 = 0
    private var scheduleEventEmitted = false

    init(runGeneration: UInt64, pulseIndex: UInt64, targetHostTime: UInt64) {
        self.runGeneration = runGeneration
        self.pulseIndex = pulseIndex
        self.targetHostTime = targetHostTime
        scheduleCallStartHostTime = mach_absolute_time()
    }

    func markScheduleCallEnded() -> (NativeMetronomePulseTrace.Snapshot, Bool) {
        lock.lock()
        defer { lock.unlock() }
        if scheduleCallEndHostTime == 0 {
            scheduleCallEndHostTime = mach_absolute_time()
        }
        let snapshot = NativeMetronomePulseTrace.Snapshot(
            runGeneration: runGeneration,
            pulseIndex: pulseIndex,
            targetHostTime: targetHostTime,
            scheduleCallStartHostTime: scheduleCallStartHostTime,
            scheduleCallEndHostTime: scheduleCallEndHostTime
        )
        let shouldEmitSchedule = !scheduleEventEmitted
        scheduleEventEmitted = true
        return (snapshot, shouldEmitSchedule)
    }
}
#endif

/// An anchored monotonic timeline calculates every pulse from the same host
/// time. Multiplication avoids cumulative floating-point drift over a long run.
struct NativeMetronomeTimeline: Equatable {
    let anchorHostTime: UInt64
    let intervalHostTicks: UInt64

    init(anchorHostTime: UInt64 = mach_absolute_time(), intervalSeconds: TimeInterval) {
        self.anchorHostTime = anchorHostTime
        intervalHostTicks = max(1, AVAudioTime.hostTime(forSeconds: intervalSeconds))
    }

    func hostTime(forPulseIndex pulseIndex: UInt64) -> UInt64 {
        anchorHostTime &+ (intervalHostTicks &* pulseIndex)
    }
}

/// A dedicated timer wakes slightly before each anchored pulse so the serial
/// player queue can submit the click at the exact future host time.
final class NativeMetronomeClock: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.brasstune.native.metronome-clock", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var timeline: NativeMetronomeTimeline?
    private var nextPulseIndex: UInt64 = 1

    func start(
        intervalSeconds: TimeInterval,
        anchorHostTime: UInt64,
        onPulse: @escaping @Sendable (_ pulseIndex: UInt64, _ targetHostTime: UInt64) -> Void
    ) {
        let boundedInterval = max(0.01, intervalSeconds)
        let leadSeconds = min(0.04, boundedInterval * 0.2)
        let intervalNanoseconds = max(1_000_000, Int((boundedInterval * 1_000_000_000).rounded()))
        let firstDeadlineNanoseconds = max(
            1_000_000,
            Int(((boundedInterval - leadSeconds) * 1_000_000_000).rounded())
        )
        queue.sync {
            cancelLocked()
            timeline = NativeMetronomeTimeline(
                anchorHostTime: anchorHostTime,
                intervalSeconds: boundedInterval
            )
            nextPulseIndex = 1
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(
                deadline: .now() + .nanoseconds(firstDeadlineNanoseconds),
                repeating: .nanoseconds(intervalNanoseconds),
                leeway: .milliseconds(1)
            )
            source.setEventHandler { [weak self] in
                guard let self, let timeline = self.timeline else { return }
                let pulseIndex = self.nextPulseIndex
                let targetHostTime = timeline.hostTime(forPulseIndex: pulseIndex)
                self.nextPulseIndex &+= 1
                onPulse(pulseIndex, targetHostTime)
            }
            timer = source
            source.resume()
        }
    }

    func stop() {
        queue.sync { cancelLocked() }
    }

    private func cancelLocked() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        timeline = nil
    }
}

struct NativeMetronomeGraphHooks: Sendable {
    let prepare: @Sendable () throws -> Void
    let schedule: @Sendable (
        _ targetHostTime: UInt64,
        _ completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) -> Void
    let play: @Sendable () -> Void
    let stop: @Sendable () -> Void
    let reset: @Sendable () -> Void
}

private actor NativeMetronomeAudioGraph {
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var isAttached = false
    private var buffers: NativeMetronomeClickBuffers?
    private let hooks: NativeMetronomeGraphHooks?

    init(hooks: NativeMetronomeGraphHooks? = nil) {
        self.hooks = hooks
    }

    func schedule(
        volume: Float,
        accent: Bool,
        hostTime: UInt64,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) throws {
        if let hooks {
            try hooks.prepare()
            NativeNonblockingAudioScheduling.scheduleAndPlay(
                schedule: { hooks.schedule(hostTime, completion) },
                play: hooks.play
            )
            return
        }
        try prepareIfNeeded()
        guard let buffers else { throw NativeAudioEngineError.outputUnavailable }
        player.volume = volume
        NativeNonblockingAudioScheduling.scheduleAndPlay(
            schedule: {
                player.scheduleBuffer(
                    buffers.buffer(accent: accent),
                    at: NativeMetronomeScheduling.hostTime(now: hostTime),
                    options: .interrupts,
                    completionHandler: { completion(.success(())) }
                )
            },
            play: {
                if !player.isPlaying { player.play() }
            }
        )
    }

    func stop() {
        if let hooks {
            hooks.stop()
            return
        }
        player.stop()
        engine.stop()
    }

    func reset() {
        if let hooks {
            hooks.reset()
            return
        }
        // A media-services reset invalidates the old AVFoundation graph. Do
        // not message those objects again; replace them on this actor.
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        isAttached = false
        buffers = nil
    }

    private func prepareIfNeeded() throws {
        if !isAttached {
            engine.attach(player)
            isAttached = true
        }
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        if buffers?.matches(outputFormat) != true {
            engine.stop()
            engine.disconnectNodeOutput(player)
            let newBuffers = try NativeMetronomeClickBuffers(outputFormat: outputFormat)
            engine.connect(player, to: engine.mainMixerNode, format: AVAudioFormat(
                standardFormatWithSampleRate: newBuffers.sampleRate,
                channels: newBuffers.channelCount
            ))
            buffers = newBuffers
        }
        if !engine.isRunning { try engine.start() }
    }
}

typealias NativeMetronomeSchedule = (
    _ volume: Float,
    _ accent: Bool,
    _ hostTime: UInt64,
    _ completion: @escaping @Sendable (Result<Void, Error>) -> Void
) -> Void

@MainActor
final class NativeMetronomeOutput {
    enum LifecycleEvent: Equatable {
        case routeChanged
        case interruption
        case mediaServicesReset
        case outputFailure
    }

    static let initialSchedulingMarginSeconds: TimeInterval = 0.1

    private let graph: NativeMetronomeAudioGraph
    private let audioSessionCoordinator: NativeAudioSessionCoordinator
    private let scheduleOverride: NativeMetronomeSchedule?
    private let onScheduleResult: ((UInt64) -> Void)?
    private let onScheduleSubmitted: (() -> Void)?
    private let playHaptic: (Bool) -> Void
    private var lifecycleHandler: ((LifecycleEvent) -> Void)?
    private var runGeneration: UInt64 = 0
    private var graphCommandTail: Task<Void, Never>?
    @Published private(set) var lastFailure: NativeAudioEngineError?
    nonisolated(unsafe) private var mediaServicesResetObserver: NSObjectProtocol?
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?

    init(
        audioSessionCoordinator: NativeAudioSessionCoordinator = .shared,
        scheduleOverride: NativeMetronomeSchedule? = nil,
        onScheduleResult: ((UInt64) -> Void)? = nil,
        onScheduleSubmitted: (() -> Void)? = nil,
        graphHooks: NativeMetronomeGraphHooks? = nil,
        playHaptic: @escaping (Bool) -> Void = { accent in
            UIImpactFeedbackGenerator(style: accent ? .medium : .light)
                .impactOccurred(intensity: accent ? 0.85 : 0.55)
        }
    ) {
        graph = NativeMetronomeAudioGraph(hooks: graphHooks)
        self.audioSessionCoordinator = audioSessionCoordinator
        self.scheduleOverride = scheduleOverride
        self.onScheduleResult = onScheduleResult
        self.onScheduleSubmitted = onScheduleSubmitted
        self.playHaptic = playHaptic
        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMediaServicesReset()
            }
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                self?.handleRouteChange(rawReason: rawReason)
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(rawType: rawType)
            }
        }
    }

    deinit {
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func setLifecycleHandler(_ handler: @escaping (LifecycleEvent) -> Void) {
        lifecycleHandler = handler
    }

    func playTick(
        settings: MetronomeSettings,
        accent: Bool,
        hostTime: UInt64 = mach_absolute_time(),
        pulseIndex: UInt64 = 0,
        onInitialPulseScheduled: ((UInt64) -> Void)? = nil
    ) {
        // Haptics are part of the visual metronome experience, so they must
        // not depend on an audible route or audio-session acquisition.
        if settings.hapticsEnabled { playHaptic(accent) }
        guard !audioSessionCoordinator.isActive(.capture) else {
            stop()
            onInitialPulseScheduled?(hostTime)
            return
        }

        guard !settings.visualOnly, !settings.muted, settings.volume > 0 else {
            stop()
            onInitialPulseScheduled?(hostTime)
            return
        }
        do {
            let wasAlreadyActive = audioSessionCoordinator.isActive(.metronome)
            let acquireTask = try audioSessionCoordinator.acquireTask(
                .metronome,
                configuration: .metronome
            )
            if !wasAlreadyActive {
                runGeneration &+= 1
            }
            let scheduleGeneration = runGeneration
            lastFailure = nil
            let safeVolume = Float(min(1, max(0, settings.volume)))
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    _ = try await acquireTask.value
                } catch {
                    guard scheduleGeneration == self.runGeneration else { return }
                    self.audioSessionCoordinator.rollbackLogicalOwner(.metronome)
                    self.reportFailure(error)
                    return
                }
                guard scheduleGeneration == self.runGeneration,
                      self.audioSessionCoordinator.isActive(.metronome) else {
                    self.audioSessionCoordinator.release(.metronome, deactivation: .immediate)
                    return
                }
                // The first click cannot be scheduled until the asynchronous
                // session and graph setup are ready. Re-anchor it far enough
                // ahead of the host clock for AVAudioPlayerNode to accept it.
                let scheduledHostTime: UInt64
                if onInitialPulseScheduled != nil {
                    scheduledHostTime = max(
                        hostTime,
                        mach_absolute_time() &+ AVAudioTime.hostTime(
                            forSeconds: Self.initialSchedulingMarginSeconds
                        )
                    )
                } else {
                    scheduledHostTime = hostTime
                }
#if PHYSICAL_INSTRUMENTATION
                let traceContext = NativeMetronomePulseTraceContext(
                    runGeneration: scheduleGeneration,
                    pulseIndex: pulseIndex,
                    targetHostTime: hostTime
                )
                let completion: @Sendable (Result<Void, Error>) -> Void = { [weak self] result in
                    let (snapshot, shouldEmitSchedule) = traceContext.markScheduleCallEnded()
                    if shouldEmitSchedule { NativeMetronomePulseTrace.emitSchedule(snapshot) }
                    Task { @MainActor in
                        self?.handleScheduleResult(
                            result,
                            generation: scheduleGeneration,
                            trace: snapshot
                        )
                    }
                }
#else
                let completion: @Sendable (Result<Void, Error>) -> Void = { [weak self] result in
                    Task { @MainActor in
                        self?.handleScheduleResult(result, generation: scheduleGeneration)
                    }
                }
#endif
                if let scheduleOverride = self.scheduleOverride {
                    scheduleOverride(safeVolume, accent, scheduledHostTime, completion)
                } else {
                    do {
                        try await self.enqueueGraphSchedule(
                            volume: safeVolume,
                            accent: accent,
                            hostTime: scheduledHostTime,
                            completion: completion
                        )
                    } catch {
                        completion(.failure(error))
                    }
                }
                self.onScheduleSubmitted?()
                onInitialPulseScheduled?(scheduledHostTime)
#if PHYSICAL_INSTRUMENTATION
                let (snapshot, shouldEmitSchedule) = traceContext.markScheduleCallEnded()
                if shouldEmitSchedule { NativeMetronomePulseTrace.emitSchedule(snapshot) }
#endif
            }
        } catch {
            reportFailure(error)
        }
    }

    func stop() {
        // Visual-only timers and late callbacks call this frequently. Do not
        // synchronously touch the AVAudioEngine unless this instance still
        // owns an audible metronome session.
        runGeneration &+= 1
        guard audioSessionCoordinator.isActive(.metronome) else { return }
        audioSessionCoordinator.release(.metronome)
        enqueueGraphCommand { graph in await graph.stop() }
    }

    func handleMediaServicesReset() {
        stopAndReset(for: .mediaServicesReset, invalidatingMediaServices: true)
    }

    func handleRouteChange(rawReason: UInt?) {
        guard rawReason != AVAudioSession.RouteChangeReason.categoryChange.rawValue else { return }
        stopAndReset(for: .routeChanged)
    }

    func handleInterruption(rawType: UInt?) {
        guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
        stopAndReset(for: .interruption)
    }

    private func stopAndReset(
        for event: LifecycleEvent,
        invalidatingMediaServices: Bool = false
    ) {
        runGeneration &+= 1
        if invalidatingMediaServices {
            audioSessionCoordinator.invalidateAfterMediaServicesReset()
        } else {
            audioSessionCoordinator.invalidateSessionConfiguration()
        }
        audioSessionCoordinator.release(.metronome, deactivation: .immediate)
        enqueueGraphCommand { graph in await graph.reset() }
        lastFailure = .outputUnavailable
        lifecycleHandler?(event)
    }

    private func handleScheduleResult(_ result: Result<Void, Error>, generation: UInt64) {
        onScheduleResult?(generation)
        guard generation == runGeneration,
              audioSessionCoordinator.isActive(.metronome) else { return }
        if case .failure(let error) = result {
            reportFailure(error)
        }
    }

    private func reportFailure(_ error: Error) {
        lastFailure = (error as? NativeAudioEngineError) ?? .outputUnavailable
        stopAndReset(for: .outputFailure)
    }

    private func enqueueGraphSchedule(
        volume: Float,
        accent: Bool,
        hostTime: UInt64,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) async throws {
        let previous = graphCommandTail
        let graph = graph
        let task = Task<Void, Error> {
            await previous?.value
            try await graph.schedule(
                volume: volume,
                accent: accent,
                hostTime: hostTime,
                completion: completion
            )
        }
        graphCommandTail = Task { _ = try? await task.value }
        try await task.value
    }

    private func enqueueGraphCommand(
        _ operation: @escaping @Sendable (NativeMetronomeAudioGraph) async -> Void
    ) {
        let previous = graphCommandTail
        let graph = graph
        let task = Task<Void, Never> {
            await previous?.value
            await operation(graph)
        }
        graphCommandTail = task
    }

#if PHYSICAL_INSTRUMENTATION
    private func handleScheduleResult(
        _ result: Result<Void, Error>,
        generation: UInt64,
        trace: NativeMetronomePulseTrace.Snapshot
    ) {
        NativeMetronomePulseTrace.emitCompletion(
            trace,
            result: result,
            stale: generation != runGeneration || !audioSessionCoordinator.isActive(.metronome)
        )
        handleScheduleResult(result, generation: generation)
    }
#endif
}
