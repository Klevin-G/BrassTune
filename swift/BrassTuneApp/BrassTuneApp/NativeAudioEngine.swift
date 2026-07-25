import AVFoundation
import BrassTuneCore
import Foundation
import UIKit

@MainActor
final class NativeAudioSessionCoordinator {
    enum Owner: Hashable { case capture, tone, metronome, recordingPlayback }

    static let shared = NativeAudioSessionCoordinator()

    private var owners: Set<Owner> = []
    private let activateSession: () throws -> Void
    private let deactivateSession: () throws -> Void

    init(
        activateSession: @escaping () throws -> Void = {
            try AVAudioSession.sharedInstance().setActive(true)
        },
        deactivateSession: @escaping () throws -> Void = {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    ) {
        self.activateSession = activateSession
        self.deactivateSession = deactivateSession
    }

    func acquire(_ owner: Owner, configure: () throws -> Void) throws {
        // Capture owns the stricter `.measurement` session. A late visual
        // metronome timer must never downgrade that mode while the microphone
        // is starting or recording.
        if owner != .metronome || !owners.contains(.capture) {
            try configure()
        }
        guard owners.insert(owner).inserted else { return }
        if owners.count == 1 {
            do { try activateSession() }
            catch {
                owners.remove(owner)
                throw error
            }
        }
    }

    /// Acquires ownership, then runs setup while guaranteeing that a failed
    /// setup cannot strand the owner or leave the shared session active.
    func acquire(
        _ owner: Owner,
        configure: () throws -> Void,
        setup: () throws -> Void
    ) throws {
        try acquire(owner, configure: configure)
        do {
            try setup()
        } catch {
            release(owner)
            throw error
        }
    }

    func release(_ owner: Owner) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        try? deactivateSession()
    }

    var activeOwners: Set<Owner> { owners }

    func isActive(_ owner: Owner) -> Bool { owners.contains(owner) }
}

enum NativeLiveCaptureCompletionReason: Equatable {
    case userStopped
    case interruption
    case routeLoss
}

enum NativeRecordingRetentionFailure: Equatable {
    case durationLimitReached
    case sizeLimitReached
    case writeFailed
}

struct NativeLiveCapture: Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let frames: [PitchFrame]
    let recordingURL: URL?
    let recordingRetentionFailure: NativeRecordingRetentionFailure?
    let completionReason: NativeLiveCaptureCompletionReason
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

final class NativeAudioFileWriter: @unchecked Sendable {
    struct FinishResult {
        let recordingURL: URL?
        let retentionFailure: NativeRecordingRetentionFailure?
    }

    private let lock = NSLock()
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

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
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

    func finish() -> FinishResult {
        lock.lock()
        let failure = retentionFailure
        audioFile = nil
        lock.unlock()

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
        lock.lock()
        audioFile = nil
        lock.unlock()
        try? FileManager.default.removeItem(at: destinationURL)
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
    private let configurePlaybackSession: () throws -> Void
    private var driver: NativeRecordingPlaybackDriver?
    private var progressTimer: Timer?
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    private var prepareForPlayback: (() -> Void)?

    init(
        audioSessionCoordinator: NativeAudioSessionCoordinator = .shared,
        makeDriver: @escaping (URL) throws -> NativeRecordingPlaybackDriver = NativeRecordingPlaybackDriver.live,
        configurePlaybackSession: (() throws -> Void)? = nil
    ) {
        self.audioSessionCoordinator = audioSessionCoordinator
        self.makeDriver = makeDriver
        self.configurePlaybackSession = configurePlaybackSession ?? {
            let session = AVAudioSession.sharedInstance()
            try NativePlaybackSessionPolicy.configure { category, mode, options in
                try session.setCategory(category, mode: mode, options: options)
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
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
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

        do {
            try audioSessionCoordinator.acquire(.recordingPlayback) {
                try configurePlaybackSession()
            }
        } catch {
            notice = Self.recordingPlaybackFailureNotice()
            return
        }

        guard let driver else {
            audioSessionCoordinator.release(.recordingPlayback)
            return
        }
        _ = driver.prepareToPlay()
        guard driver.play() else {
            audioSessionCoordinator.release(.recordingPlayback)
            notice = Self.recordingPlaybackFailureNotice()
            return
        }
        state = .playing
        currentTime = driver.currentTime()
        scheduleProgressTimer()
    }

    private static func recordingPlaybackFailureNotice() -> String {
        NativeLocalization.string(
            "BrassTune couldn't play this recording. Check your audio output and try again."
        )
    }

    func pause() {
        guard state == .playing, let driver else { return }
        driver.pause()
        currentTime = driver.currentTime()
        state = .paused
        invalidateProgressTimer()
        audioSessionCoordinator.release(.recordingPlayback)
    }

    func stop() {
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
        notice = NativeLocalization.string("Your audio output changed. Check your headphones or speaker before continuing.")
    }

    func handleInterruption(rawType: UInt?) {
        guard rawType == AVAudioSession.InterruptionType.began.rawValue,
              state == .playing else { return }
        pause()
        notice = NativeLocalization.string("Try again when you're ready.")
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

@MainActor
final class NativeAudioEngine: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var currentFrame: PitchFrame?
    @Published private(set) var frames: [PitchFrame] = []
    @Published private(set) var activeSource: PracticeSessionSource = .live
    @Published private(set) var audioNotice: String?
    @Published private(set) var routeChanged = false
    @Published private(set) var tonePlaying = false
    @Published private(set) var toneFrequencyHz: Double?
    @Published private(set) var toneFrequenciesHz: [Double] = []

    private let engine = AVAudioEngine()
    private let tonePlayer = AVAudioPlayerNode()
    private var tonePlayerAttached = false
    private var fixtureStartedAt: Date?
    private var fixtureInstrumentId = "trumpet"
    private var fixtureReferencePitchHz = 440.0
    private var liveStartedAt: Date?
    private var liveCaptureID: UUID?
    private var liveFileWriter: NativeAudioFileWriter?
    private var liveStartRequestID: UUID?
    private let maxLiveFrames = 18_000
    private let pitchProcessingQueue = DispatchQueue(label: "com.brasstune.native.pitch-processing", qos: .userInitiated)
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
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
        if ProcessInfo.processInfo.arguments.contains("UITEST_MIC_DENIED") {
            permissionDenied = true
            audioNotice = NativeLocalization.string("Microphone access is off. Allow it in Settings, then try again.")
        }
    }

    func requestMicrophonePermission() async -> Bool {
        let granted = await microphonePermissionRequester()
        permissionDenied = !granted
        audioNotice = granted ? nil : NativeLocalization.string("Microphone access is off. Allow it in Settings, then try again.")
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
        permissionDenied = false
        activeSource = .sample
        audioNotice = nil
        routeChanged = false
        fixtureStartedAt = Date()
        fixtureInstrumentId = instrumentId
        fixtureReferencePitchHz = referencePitchHz
        frames = (0..<12).map { PitchFrame.fixture(index: $0, instrumentId: instrumentId, referencePitchHz: referencePitchHz) }
        currentFrame = frames.last
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
        return frames
    }

    func startLiveRecording(
        instrumentId: String,
        referencePitchHz: Double,
        recordingURL: URL? = nil
    ) async throws -> Bool {
        if Self.testFixturesEnabled {
            // Simulate a live capture so the tuner's recording UI is drivable in
            // UI tests without a physical microphone. activeSource stays .live so
            // it behaves like a real live take (no sample-mode surface).
            stopAndResetAudioEngine()
            recording = true
            permissionDenied = false
            activeSource = .live
            audioNotice = nil
            routeChanged = false
            frames = (0..<12).map { PitchFrame.fixture(index: $0, instrumentId: instrumentId, referencePitchHz: referencePitchHz) }
            currentFrame = frames.last
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
        try configureAndStartLiveEngine(
            instrumentId: instrumentId,
            referencePitchHz: referencePitchHz,
            recordingURL: recordingURL
        )
        return true
    }

    func cancelPendingLiveStart() {
        liveStartRequestID = nil
    }

    func setTonePlaybackPreparation(_ preparation: @escaping () -> Void) {
        prepareForTonePlayback = preparation
    }

    func setUnexpectedCaptureCompletion(_ completion: @escaping (NativeLiveCapture) -> Void) {
        unexpectedCaptureCompletion = completion
    }

    func stopLiveRecording() -> NativeLiveCapture {
        finishLiveCapture(reason: .userStopped)
    }

    func discardLiveRecording() {
        resetAudioEngine(discardCaptureFile: true)
        frames.removeAll()
        currentFrame = nil
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
        audioNotice = nil
        routeChanged = false
        let safeVolume = Float(min(0.5, max(0.05, volume)))

        if Self.testFixturesEnabled || simulateTonePlayback {
            tonePlaying = true
            toneFrequencyHz = frequencyHz
            toneFrequenciesHz = frequenciesHz
            return
        }

        let session = AVAudioSession.sharedInstance()
        try audioSessionCoordinator.acquire(.tone) {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }

        if !tonePlayerAttached {
            engine.attach(tonePlayer)
            tonePlayerAttached = true
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100),
              let samples = buffer.floatChannelData?[0] else {
            audioSessionCoordinator.release(.tone)
            throw NativeAudioEngineError.outputUnavailable
        }
        buffer.frameLength = 44_100
        let fadeFrames = 441
        let perToneVolume = safeVolume / Float(frequenciesHz.count)
        for frame in 0..<Int(buffer.frameLength) {
            let sample = frequenciesHz.reduce(0.0) { partial, frequency in
                let phase = 2 * Double.pi * frequency * Double(frame) / format.sampleRate
                return partial + sin(phase)
            }
            let fadeIn = min(1, Double(frame) / Double(fadeFrames))
            let fadeOut = min(1, Double(Int(buffer.frameLength) - frame) / Double(fadeFrames))
            samples[frame] = Float(sample) * perToneVolume * Float(min(fadeIn, fadeOut))
        }
        engine.connect(tonePlayer, to: engine.mainMixerNode, format: format)
        tonePlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        engine.prepare()
        do { try engine.start() }
        catch {
            audioSessionCoordinator.release(.tone)
            throw error
        }
        tonePlayer.play()
        tonePlaying = true
        toneFrequencyHz = frequencyHz
        toneFrequenciesHz = frequenciesHz
    }

    func stopTone() {
        guard tonePlaying || tonePlayer.isPlaying else { return }
        tonePlayer.stop()
        engine.stop()
        tonePlaying = false
        toneFrequencyHz = nil
        toneFrequenciesHz = []
        audioSessionCoordinator.release(.tone)
    }

    func setExternalAudioNotice(_ message: String?) {
        audioNotice = message
    }

    func stopAndResetAudioEngine() {
        resetAudioEngine(discardCaptureFile: true)
    }

    func handleRouteChange(rawReason: UInt?) {
        guard NativeRecordingPlayer.isOutputLossRouteChange(rawReason: rawReason) else {
            // `.categoryChange` is emitted for BrassTune's own session
            // reconfiguration. Treating it as output loss stops tones that just
            // started and makes listen-back appear broken.
            return
        }

        let wasPlayingTone = tonePlaying
        let wasCapturingLive = recording && activeSource == .live
        if wasCapturingLive {
            let capture = finishLiveCapture(reason: .routeLoss)
            routeChanged = true
            audioNotice = NativeLocalization.string("Your audio output changed. Check your headphones or speaker before continuing.")
            unexpectedCaptureCompletion?(capture)
            return
        } else if wasPlayingTone {
            stopTone()
        }
        routeChanged = true
        if wasPlayingTone {
            audioNotice = NativeLocalization.string("The reference tone stopped because your audio output changed. Check your headphones or speaker before restarting.")
        } else {
            audioNotice = NativeLocalization.string("Your audio output changed. Check your headphones or speaker before continuing.")
        }
    }

    func handleInterruption(rawType: UInt?) {
        guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
        if recording, activeSource == .live {
            let capture = finishLiveCapture(reason: .interruption)
            audioNotice = NativeLocalization.string("Recording stopped because the audio session was interrupted.")
            unexpectedCaptureCompletion?(capture)
        } else if tonePlaying {
            stopTone()
            audioNotice = NativeLocalization.string("The reference tone stopped because your audio output changed. Check your headphones or speaker before restarting.")
        }
    }

    private func resetAudioEngine(discardCaptureFile: Bool) {
        tonePlayer.stop()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        if discardCaptureFile {
            liveFileWriter?.discard()
        } else {
            _ = liveFileWriter?.finish()
        }
        liveFileWriter = nil
        recording = false
        tonePlaying = false
        toneFrequencyHz = nil
        toneFrequenciesHz = []
        fixtureStartedAt = nil
        liveStartedAt = nil
        liveCaptureID = nil
        liveStartRequestID = nil
        audioSessionCoordinator.release(.capture)
        audioSessionCoordinator.release(.tone)
    }

    private func configureAndStartLiveEngine(
        instrumentId: String,
        referencePitchHz: Double,
        recordingURL: URL?
    ) throws {
        stopAndResetAudioEngine()
        let session = AVAudioSession.sharedInstance()
        let startedAt = Date()
        let captureID = UUID()
        let processingQueue = pitchProcessingQueue
        do {
            try audioSessionCoordinator.acquire(.capture, configure: {
                try session.setCategory(
                    .playAndRecord,
                    mode: .measurement,
                    options: [.allowBluetoothHFP, .defaultToSpeaker, .mixWithOthers]
                )
                try session.setPreferredIOBufferDuration(0.03)
            }, setup: {
                let inputNode = engine.inputNode
                let inputFormat = inputNode.outputFormat(forBus: 0)
                guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
                    throw NativeAudioEngineError.inputUnavailable
                }
                let fileWriter = try recordingURL.map {
                    try NativeAudioFileWriter(destinationURL: $0, inputFormat: inputFormat)
                }

                frames.removeAll()
                currentFrame = nil
                activeSource = .live
                liveStartedAt = startedAt
                liveCaptureID = captureID
                liveFileWriter = fileWriter
                audioNotice = nil
                routeChanged = false

                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self, fileWriter] buffer, _ in
                    fileWriter?.write(buffer)
                    let timestampMs = Int(max(0, Date().timeIntervalSince(startedAt) * 1000))
                    let sampleRate = buffer.format.sampleRate
                    guard let samples = NativePitchDetector.samples(from: buffer), let self else { return }
                    processingQueue.async { [weak self] in
                        let frame = NativePitchDetector.frame(
                            samples: samples,
                            sampleRate: sampleRate,
                            timestampMs: timestampMs,
                            instrumentId: instrumentId,
                            referencePitchHz: referencePitchHz
                        )
                        Task { @MainActor in
                            self?.appendLiveFrame(frame, captureID: captureID)
                        }
                    }
                }
                try engine.start()
            })
        } catch {
            stopAndResetAudioEngine()
            if case NativeAudioEngineError.inputUnavailable = error {
                audioNotice = NativeLocalization.string("BrassTune can't hear a microphone.")
            } else {
                audioNotice = NativeLocalization.string("BrassTune couldn't start the microphone. Check your audio input and try again.")
            }
            throw error
        }

        recording = true
    }

    private func finishLiveCapture(reason: NativeLiveCaptureCompletionReason) -> NativeLiveCapture {
        let captureID = liveCaptureID ?? UUID()
        let startedAt = liveStartedAt ?? Date()
        let endedAt = Date()
        let capturedFrames = frames
        tonePlayer.stop()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        let recordingResult = liveFileWriter?.finish()
        liveFileWriter = nil
        recording = false
        tonePlaying = false
        toneFrequencyHz = nil
        toneFrequenciesHz = []
        fixtureStartedAt = nil
        liveStartedAt = nil
        liveCaptureID = nil
        liveStartRequestID = nil
        audioSessionCoordinator.release(.capture)
        audioSessionCoordinator.release(.tone)
        frames = capturedFrames
        currentFrame = capturedFrames.last
        return NativeLiveCapture(
            id: captureID,
            startedAt: startedAt,
            endedAt: endedAt,
            frames: capturedFrames,
            recordingURL: recordingResult?.recordingURL,
            recordingRetentionFailure: recordingResult?.retentionFailure,
            completionReason: reason
        )
    }

    private func appendLiveFrame(_ frame: PitchFrame, captureID: UUID) {
        guard recording,
              activeSource == .live,
              liveCaptureID == captureID else { return }
        frames.append(frame)
        if frames.count > maxLiveFrames {
            frames.removeFirst(frames.count - maxLiveFrames)
        }
        currentFrame = frame
    }
}

enum NativeAudioEngineError: Error {
    case captureActive
    case inputUnavailable
    case outputUnavailable
    case invalidToneFrequency
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

@MainActor
final class NativeMetronomeOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isPrepared = false
    private let audioSessionCoordinator: NativeAudioSessionCoordinator

    init(audioSessionCoordinator: NativeAudioSessionCoordinator = .shared) {
        self.audioSessionCoordinator = audioSessionCoordinator
    }

    func playTick(settings: MetronomeSettings, accent: Bool) {
        if settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: accent ? .medium : .light)
                .impactOccurred(intensity: accent ? 0.85 : 0.55)
        }

        guard !audioSessionCoordinator.isActive(.capture) else {
            stop()
            return
        }

        guard !settings.visualOnly, !settings.muted, settings.volume > 0 else {
            stop()
            return
        }
        do {
            try prepareIfNeeded()
            player.volume = Float(min(1, max(0, settings.volume)))
            player.scheduleBuffer(clickBuffer(accent: accent), at: nil, options: .interrupts)
            if !player.isPlaying {
                player.play()
            }
        } catch {
            // A failed audio session should not stop the visual metronome.
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        audioSessionCoordinator.release(.metronome)
    }

    private func prepareIfNeeded() throws {
        if !isPrepared {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            isPrepared = true
        }
        if !engine.isRunning {
            let session = AVAudioSession.sharedInstance()
            try audioSessionCoordinator.acquire(.metronome) {
                if session.category != .playAndRecord || session.mode != .measurement {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
                }
            }
            do { try engine.start() }
            catch {
                audioSessionCoordinator.release(.metronome)
                throw error
            }
        }
    }

    private func clickBuffer(accent: Bool) -> AVAudioPCMBuffer {
        let sampleRate = 44_100.0
        let duration = accent ? 0.048 : 0.036
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let frequency = accent ? 1_760.0 : 1_320.0
        let amplitude = accent ? 0.55 : 0.38
        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let envelope = exp(-time * 90)
            channel[frame] = Float(sin(2 * Double.pi * frequency * time) * amplitude * envelope)
        }
        return buffer
    }
}
