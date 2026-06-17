import Foundation
import Testing
@testable import BrassTuneCore

private struct PitchMathCase: Decodable {
    let frequency_hz: Double
    let reference_pitch_hz: Double
    let expected_nearest_midi: Int
    let expected_cents: Double
}

private struct TranspositionCase: Decodable {
    let instrument_id: String
    let concert_midi: Int
    let expected_written_midi: Int
}

private let transpositions = [
    "trumpet": 2,
    "horn": 7,
    "trombone": 0,
    "euphonium": 0,
    "tuba": 0
]

private func fixtureURL(_ name: String) throws -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures")
        .appendingPathComponent(name)
}

private func loadFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    let data = try Data(contentsOf: fixtureURL(name))
    return try JSONDecoder().decode(T.self, from: data)
}

@Test func pitchMathFixturesMatchWebCore() throws {
    let cases = try loadFixture("pitch_math_cases.json", as: [PitchMathCase].self)
    for item in cases {
        let midi = BrassTuneCore.frequencyToMidi(item.frequency_hz, referencePitchHz: item.reference_pitch_hz)
        #expect(Int(midi.rounded()) == item.expected_nearest_midi)
        let cents = BrassTuneCore.centsDeviation(frequencyHz: item.frequency_hz, nearestMidi: item.expected_nearest_midi, referencePitchHz: item.reference_pitch_hz)
        #expect(abs(cents - item.expected_cents) < 0.05)
    }
}

@Test func transpositionFixturesMatchWebCore() throws {
    let cases = try loadFixture("transposition_cases.json", as: [TranspositionCase].self)
    for item in cases {
        #expect(BrassTuneCore.transposeConcertToWritten(item.concert_midi, semitones: transpositions[item.instrument_id] ?? 0) == item.expected_written_midi)
    }
}

@Test func confidenceSemanticsMatchBrassTune() {
    #expect(BrassTuneCore.tuningStatus(cents: 0, confidence: 0.94, rms: 0.1) == .unstable)
    #expect(BrassTuneCore.tuningStatus(cents: 0, confidence: 0.95, rms: 0.1) == .inTune)
    #expect(BrassTuneCore.tuningStatus(cents: nil, confidence: 0.99, rms: 0.0) == .silence)
}
