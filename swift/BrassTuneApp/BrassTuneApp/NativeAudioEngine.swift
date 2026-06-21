import AVFoundation
import BrassTuneCore
import Foundation

@MainActor
final class NativeAudioEngine: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var inputActive = false
    @Published private(set) var playbackActive = false
    @Published private(set) var currentFrame: PitchFrame?
    @Published private(set) var frames: [PitchFrame] = []
    @Published private(set) var lastRecordingURL: URL?

    struct RecordingResult {
        let frames: [PitchFrame]
        let recordingURL: URL?
        let startedAt: Date?
    }

    private let engine = AVAudioEngine()
    private var recordingFile: AVAudioFile?
    private var startedAt: Date?
    private var frameIndex = 0
    private var instrumentId = "trumpet"
    private var referencePitchHz = 440.0
    private var player: AVAudioPlayer?

    func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            permissionDenied = !granted
            return granted
        }
        return false
    }

    func startRecording(instrumentId: String, referencePitchHz: Double, deterministicTestInput: Bool = false) async throws {
        if recording {
            return
        }
        self.instrumentId = instrumentId
        self.referencePitchHz = referencePitchHz
        permissionDenied = false
        frames.removeAll()
        currentFrame = nil
        lastRecordingURL = nil
        startedAt = Date()
        frameIndex = 0

        if deterministicTestInput {
            startDeterministicRecording(referencePitchHz: referencePitchHz)
            return
        }

        guard await requestMicrophonePermission() else {
            permissionDenied = true
            throw UserVisibleError.microphoneDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: [])

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw UserVisibleError.microphoneDenied
        }
        let url = try makeRecordingURL()
        recordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
        lastRecordingURL = url

        inputNode.removeTap(onBus: 0)
        let activeInstrumentId = instrumentId
        let activeReferencePitchHz = referencePitchHz
        let activeRecordingFile = recordingFile
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let sampleRate = buffer.format.sampleRate
            let samples = Self.samples(from: buffer)
            if let activeRecordingFile {
                try? activeRecordingFile.write(from: buffer)
            }
            Task { @MainActor in
                let frame = Self.pitchFrame(
                    samples: samples,
                    sampleRate: sampleRate,
                    index: self.frameIndex,
                    instrumentId: activeInstrumentId,
                    referencePitchHz: activeReferencePitchHz
                )
                self.frameIndex += 1
                self.inputActive = true
                self.currentFrame = frame
                self.frames.append(frame)
            }
        }
        engine.prepare()
        try engine.start()
        recording = true
        inputActive = true
    }

    func stopRecording() -> RecordingResult {
        stopAndResetAudioEngine()
        let result = RecordingResult(frames: frames, recordingURL: lastRecordingURL, startedAt: startedAt)
        recordingFile = nil
        return result
    }

    func play(url: URL) {
        stopPlayback()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        playbackActive = player?.play() ?? false
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playbackActive = false
    }

    func stopAndResetAudioEngine() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        recording = false
        inputActive = false
    }

    private func startDeterministicRecording(referencePitchHz: Double) {
        recording = true
        inputActive = true
        permissionDenied = false
        frames = (0..<32).map { PitchFrame.fixture(index: $0, referencePitchHz: referencePitchHz) }
        currentFrame = frames.last
        lastRecordingURL = makeDeterministicRecordingMarkerURL()
    }

    private func makeRecordingURL() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BrassTuneRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("take-\(UUID().uuidString).caf")
    }

    private func makeDeterministicRecordingMarkerURL() -> URL? {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BrassTuneRecordings", isDirectory: true)
        guard let directory else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ui-test-take-\(UUID().uuidString).txt")
        try? "deterministic test recording marker".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private nonisolated static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private nonisolated static func pitchFrame(
        samples: [Float],
        sampleRate: Double,
        index: Int,
        instrumentId: String,
        referencePitchHz: Double
    ) -> PitchFrame {
        guard samples.count > 8 else {
            return emptyFrame(index: index)
        }
        let rms = sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
        let frequency = estimateFrequency(samples: samples, sampleRate: sampleRate)
        guard let frequency, rms >= BrassTuneCore.silenceRMSThreshold else {
            return PitchFrame(
                timestampMs: index * 46,
                frequencyHz: nil,
                confidence: 0,
                rms: rms,
                centsDeviation: nil,
                tuningStatus: .silence,
                writtenNoteName: nil,
                writtenOctave: nil,
                isValidForRecording: false
            )
        }
        let midi = BrassTuneCore.frequencyToMidi(frequency, referencePitchHz: referencePitchHz)
        let nearestMidi = Int(round(midi))
        let cents = BrassTuneCore.centsDeviation(frequencyHz: frequency, nearestMidi: nearestMidi, referencePitchHz: referencePitchHz)
        let writtenMidi = BrassTuneCore.transposeConcertToWritten(nearestMidi, semitones: transposition(for: instrumentId))
        let confidence = min(0.99, max(0.0, 0.82 + rms * 3.0))
        let status = BrassTuneCore.tuningStatus(cents: cents, confidence: confidence, rms: rms)
        return PitchFrame(
            timestampMs: index * 46,
            frequencyHz: frequency,
            confidence: confidence,
            rms: rms,
            centsDeviation: cents,
            tuningStatus: status,
            writtenNoteName: noteName(for: writtenMidi),
            writtenOctave: writtenMidi / 12 - 1,
            isValidForRecording: status == .inTune || status == .sharp || status == .flat
        )
    }

    private nonisolated static func emptyFrame(index: Int) -> PitchFrame {
        PitchFrame(
            timestampMs: index * 46,
            frequencyHz: nil,
            confidence: 0,
            rms: 0,
            centsDeviation: nil,
            tuningStatus: .silence,
            writtenNoteName: nil,
            writtenOctave: nil,
            isValidForRecording: false
        )
    }

    private nonisolated static func estimateFrequency(samples: [Float], sampleRate: Double) -> Double? {
        let minimumFrequency = 55.0
        let maximumFrequency = 1_200.0
        let minLag = max(1, Int(sampleRate / maximumFrequency))
        let maxLag = min(samples.count / 2, Int(sampleRate / minimumFrequency))
        guard minLag < maxLag else { return nil }
        var bestLag = 0
        var bestScore = 0.0
        for lag in minLag...maxLag {
            var score = 0.0
            var energy = 0.0
            let limit = samples.count - lag
            for index in 0..<limit {
                let current = Double(samples[index])
                let delayed = Double(samples[index + lag])
                score += current * delayed
                energy += current * current
            }
            let normalized = energy > 0 ? score / energy : 0
            if normalized > bestScore {
                bestScore = normalized
                bestLag = lag
            }
        }
        guard bestLag > 0, bestScore > 0.45 else { return nil }
        return sampleRate / Double(bestLag)
    }

    private nonisolated static func transposition(for instrumentId: String) -> Int {
        switch instrumentId {
        case "trumpet": return 2
        case "horn": return 7
        default: return 0
        }
    }

    private nonisolated static func noteName(for midi: Int) -> String {
        let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        return names[((midi % 12) + 12) % 12]
    }
}

@MainActor
final class NativeMetronomeEngine: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var currentBeat = 0
    @Published private(set) var scheduledTickCount = 0
    @Published private(set) var bleedPolicy = "Use headphones or mute clicks while recording."

    private var settings = MetronomeSettings()
    private var timer: Timer?
    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var audioGraphReady = false

    func configure(_ settings: MetronomeSettings) {
        var cleaned = settings
        cleaned.clamp()
        self.settings = cleaned
        if running {
            restartTimer()
        }
    }

    func start(settings: MetronomeSettings, recordingActive: Bool) {
        configure(settings)
        bleedPolicy = recordingActive && !settings.muted
            ? "Clicks are audible during recording. Headphones reduce click bleed."
            : "Metronome timing is scheduled from the native audio clock."
        running = true
        currentBeat = 0
        scheduledTickCount = 0
        startAudioEngineIfNeeded()
        restartTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
        running = false
        currentBeat = 0
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = 60.0 / Double(settings.bpm * settings.subdivision)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard running else { return }
        scheduledTickCount += 1
        currentBeat = (currentBeat % settings.beatsPerMeasure) + 1
        guard !settings.muted else { return }
        playClick(accent: settings.accentFirstBeat && currentBeat == 1)
    }

    private func startAudioEngineIfNeeded() {
        guard !audioEngine.isRunning else { return }
        if !audioGraphReady {
            audioEngine.attach(player)
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
            audioGraphReady = true
        }
        try? audioEngine.start()
        if !player.isPlaying {
            player.play()
        }
    }

    private func playClick(accent: Bool) {
        guard let buffer = makeClickBuffer(accent: accent) else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func makeClickBuffer(accent: Bool) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(sampleRate * 0.035)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let frequency = accent ? 1_400.0 : 920.0
        let amplitude = Float(settings.volume * (accent ? 0.45 : 0.28))
        guard let channel = buffer.floatChannelData?[0] else { return buffer }
        for index in 0..<Int(frameCount) {
            let envelope = Float(1.0 - Double(index) / Double(frameCount))
            channel[index] = sin(Float(2.0 * Double.pi * frequency * Double(index) / sampleRate)) * amplitude * envelope
        }
        return buffer
    }
}
