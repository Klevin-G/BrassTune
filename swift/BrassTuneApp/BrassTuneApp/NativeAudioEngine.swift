import AVFoundation
import BrassTuneCore
import Foundation
import UIKit

@MainActor
final class NativeAudioEngine: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var currentFrame: PitchFrame?
    @Published private(set) var frames: [PitchFrame] = []
    @Published private(set) var activeSource: PracticeSessionSource = .sample
    @Published private(set) var audioNotice: String?
    @Published private(set) var routeChanged = false

    private let engine = AVAudioEngine()
    private var fixtureStartedAt: Date?
    private var fixtureInstrumentId = "trumpet"
    private var fixtureReferencePitchHz = 440.0
    private var liveStartedAt: Date?
    private let maxLiveFrames = 18_000
    private let pitchProcessingQueue = DispatchQueue(label: "com.brasstune.native.pitch-processing", qos: .userInitiated)
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    static var defaultRecordingSource: PracticeSessionSource {
        #if targetEnvironment(simulator)
        .sample
        #else
        .live
        #endif
    }

    init() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.routeChanged = true
                self?.audioNotice = "Audio route changed. Confirm headphones or speaker output before continuing."
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                guard let self else { return }
                if typeValue == AVAudioSession.InterruptionType.began.rawValue {
                    self.stopAndResetAudioEngine()
                    self.audioNotice = "Recording stopped because the audio session was interrupted."
                }
            }
        }
    }

    func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            permissionDenied = !granted
            if granted {
                audioNotice = nil
            } else {
                audioNotice = "Microphone access is denied. Sample mode remains available."
            }
            return granted
        }
        return false
    }

    func startFixtureRecording(instrumentId: String, referencePitchHz: Double) {
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
        let elapsed = max(3.5, Date().timeIntervalSince(fixtureStartedAt ?? Date()))
        let frameCount = min(240, max(12, Int((elapsed / 0.11).rounded())))
        frames = (0..<frameCount).map { PitchFrame.fixture(index: $0, instrumentId: fixtureInstrumentId, referencePitchHz: fixtureReferencePitchHz) }
        currentFrame = frames.last
        recording = false
        fixtureStartedAt = nil
        return frames
    }

    func startLiveRecording(instrumentId: String, referencePitchHz: Double) async throws -> Bool {
        guard await requestMicrophonePermission() else {
            recording = false
            activeSource = .live
            frames.removeAll()
            currentFrame = nil
            return false
        }
        try configureAndStartLiveEngine(instrumentId: instrumentId, referencePitchHz: referencePitchHz)
        return true
    }

    func stopLiveRecording() -> [PitchFrame] {
        let captured = frames
        stopAndResetAudioEngine()
        frames = captured
        currentFrame = captured.last
        return captured
    }

    func stopAndResetAudioEngine() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        recording = false
        fixtureStartedAt = nil
        liveStartedAt = nil
    }

    private func configureAndStartLiveEngine(instrumentId: String, referencePitchHz: Double) throws {
        stopAndResetAudioEngine()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.allowBluetoothHFP, .defaultToSpeaker, .mixWithOthers]
        )
        try session.setPreferredIOBufferDuration(0.03)
        try session.setActive(true)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            audioNotice = "No usable microphone input route is available."
            throw NativeAudioEngineError.inputUnavailable
        }

        let startedAt = Date()
        frames.removeAll()
        currentFrame = nil
        activeSource = .live
        liveStartedAt = startedAt
        audioNotice = nil
        routeChanged = false

        let processingQueue = pitchProcessingQueue
        do {
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
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
                        self?.appendLiveFrame(frame)
                    }
                }
            }
            try engine.start()
        } catch {
            stopAndResetAudioEngine()
            audioNotice = "Live microphone could not start. Check the current audio route and try again."
            throw error
        }

        recording = true
    }

    private func appendLiveFrame(_ frame: PitchFrame) {
        guard recording, activeSource == .live else { return }
        frames.append(frame)
        if frames.count > maxLiveFrames {
            frames.removeFirst(frames.count - maxLiveFrames)
        }
        currentFrame = frame
    }
}

enum NativeAudioEngineError: Error {
    case inputUnavailable
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
        let profileRange = frequencyRange(for: instrumentId)
        let minFrequency = max(45.0, profileRange.min * 0.75)
        let maxFrequency = min(1_500.0, profileRange.max * 1.12)
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

    private static func frequencyRange(for instrumentId: String) -> (min: Double, max: Double) {
        switch instrumentId {
        case "trumpet": return (130, 1_500)
        case "horn": return (80, 1_200)
        case "trombone": return (50, 700)
        case "euphonium": return (55, 700)
        case "tuba": return (32, 500)
        default: return (55, 1_300)
        }
    }
}

@MainActor
final class NativeMetronomeOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isPrepared = false

    func playTick(settings: MetronomeSettings, accent: Bool) {
        if settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: accent ? .medium : .light)
                .impactOccurred(intensity: accent ? 0.85 : 0.55)
        }

        guard !settings.visualOnly, !settings.muted, settings.volume > 0 else { return }
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
    }

    private func prepareIfNeeded() throws {
        if !isPrepared {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            isPrepared = true
        }
        if !engine.isRunning {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord || session.mode != .measurement {
                try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
            }
            try session.setActive(true)
            try engine.start()
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
