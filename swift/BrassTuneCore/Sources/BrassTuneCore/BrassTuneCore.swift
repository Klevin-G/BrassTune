import Foundation

public enum TuningStatus: String, Codable {
    case flat
    case inTune = "in_tune"
    case sharp
    case unstable
    case silence
}

public struct InstrumentProfile: Codable, Equatable {
    public let id: String
    public let transpositionSemitones: Int

    public init(id: String, transpositionSemitones: Int) {
        self.id = id
        self.transpositionSemitones = transpositionSemitones
    }
}

public enum BrassTuneCore {
    public static let minimumRecordingConfidence = 0.95
    public static let silenceRMSThreshold = 0.01

    public static func frequencyToMidi(_ frequencyHz: Double, referencePitchHz: Double = 440.0) -> Double {
        69.0 + 12.0 * log2(frequencyHz / referencePitchHz)
    }

    public static func midiToFrequency(_ midi: Double, referencePitchHz: Double = 440.0) -> Double {
        referencePitchHz * pow(2.0, (midi - 69.0) / 12.0)
    }

    public static func centsDeviation(frequencyHz: Double, nearestMidi: Int, referencePitchHz: Double = 440.0) -> Double {
        1200.0 * log2(frequencyHz / midiToFrequency(Double(nearestMidi), referencePitchHz: referencePitchHz))
    }

    public static func transposeConcertToWritten(_ concertMidi: Int, semitones: Int) -> Int {
        concertMidi + semitones
    }

    public static func tuningStatus(cents: Double?, confidence: Double, rms: Double) -> TuningStatus {
        guard rms >= silenceRMSThreshold else { return .silence }
        guard confidence >= minimumRecordingConfidence, let cents else { return .unstable }
        if cents < -5 { return .flat }
        if cents > 5 { return .sharp }
        return .inTune
    }
}
