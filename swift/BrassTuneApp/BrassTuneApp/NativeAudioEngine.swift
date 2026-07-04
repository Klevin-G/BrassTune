import AVFoundation
import Foundation
import UIKit

@MainActor
final class NativeAudioEngine: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var currentFrame: PitchFrame?
    @Published private(set) var frames: [PitchFrame] = []

    private let engine = AVAudioEngine()
    private var fixtureStartedAt: Date?
    private var fixtureInstrumentId = "trumpet"
    private var fixtureReferencePitchHz = 440.0

    func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            permissionDenied = !granted
            return granted
        }
        return false
    }

    func startFixtureRecording(instrumentId: String, referencePitchHz: Double) {
        recording = true
        permissionDenied = false
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

    func stopAndResetAudioEngine() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        recording = false
        fixtureStartedAt = nil
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
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)
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
