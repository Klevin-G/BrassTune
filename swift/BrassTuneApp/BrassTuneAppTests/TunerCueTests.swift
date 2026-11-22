import XCTest
@testable import BrassTuneApp

final class TunerCueTests: XCTestCase {
    func testCueBeatUsesLastBeatWhenTickWrapsAfterMeasure() {
        XCTAssertEqual(
            tunerMetronomeCueBeat(
                tick: 0,
                beatsPerMeasure: 4,
                ticksPerBeat: 2,
                pulseSequence: 8
            ),
            4
        )
    }

    func testCueBeatStaysOnWrittenBeatForEachSubdivision() {
        XCTAssertEqual(
            tunerMetronomeCueBeat(
                tick: 1,
                beatsPerMeasure: 4,
                ticksPerBeat: 2,
                pulseSequence: 1
            ),
            1
        )
        XCTAssertEqual(
            tunerMetronomeCueBeat(
                tick: 2,
                beatsPerMeasure: 4,
                ticksPerBeat: 2,
                pulseSequence: 2
            ),
            1
        )
        XCTAssertEqual(
            tunerMetronomeCueBeat(
                tick: 3,
                beatsPerMeasure: 4,
                ticksPerBeat: 2,
                pulseSequence: 3
            ),
            2
        )
    }

    func testCueBeatUsesFirstBeatBeforeAnyPulse() {
        XCTAssertEqual(
            tunerMetronomeCueBeat(
                tick: 0,
                beatsPerMeasure: 4,
                ticksPerBeat: 2,
                pulseSequence: 0
            ),
            1
        )
    }
}
