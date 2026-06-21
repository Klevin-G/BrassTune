import AVFoundation
import Foundation

@MainActor
final class NativeAudioEngine: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var currentFrame: PitchFrame?
    @Published private(set) var frames: [PitchFrame] = []

    private let engine = AVAudioEngine()

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
        frames = (0..<32).map { PitchFrame.fixture(index: $0, referencePitchHz: referencePitchHz) }
        currentFrame = frames.last
    }

    func stopFixtureRecording() -> [PitchFrame] {
        recording = false
        return frames
    }

    func stopAndResetAudioEngine() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        recording = false
    }
}
