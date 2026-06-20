import XCTest
@testable import BrassTuneApp
import BrassTuneCore

final class BrassTuneAppTests: XCTestCase {
    @MainActor
    func testFixtureRecordingCreatesDeterministicSession() {
        let model = AppModel()
        model.startDemoRecording()
        model.stopDemoRecording()
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions[0].frames.count, 32)
        XCTAssertGreaterThan(model.sessions[0].inTunePercentage, 0)
    }

    @MainActor
    func testAccountDeletionRequiresConfirmation() async {
        let model = AppModel()
        model.sessions = [
            PracticeSession(id: UUID(), name: "Test", instrumentId: "trumpet", startedAt: Date(), endedAt: Date(), frames: [.fixture(index: 0)], retainedRecordingURL: nil)
        ]
        await model.deleteAccount(confirmation: "delete")
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.lastError, .accountDeletionRequiresConfirmation)
        await model.deleteAccount(confirmation: "delete my account")
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(model.authState, .signedOut)
    }

    @MainActor
    func testSessionDeletionRemovesOnlySelectedSession() {
        let model = AppModel()
        let first = makeSession(name: "First", cents: [-2, 1, 6])
        let second = makeSession(name: "Second", cents: [9, 10, 11])
        model.sessions = [first, second]

        model.deleteSession(id: first.id)

        XCTAssertEqual(model.sessions, [second])
    }

    @MainActor
    func testLocalExportIncludesPracticeMetrics() {
        let model = AppModel()
        model.sessions = [makeSession(name: "Exportable take", cents: [-4, 0, 7])]

        let export = model.exportDataText()

        XCTAssertTrue(export.contains("BrassTune local data export"))
        XCTAssertTrue(export.contains("Sessions: 1"))
        XCTAssertTrue(export.contains("Exportable take"))
        XCTAssertTrue(export.contains("Average absolute cents"))
        XCTAssertTrue(export.contains("Cents preview"))
    }

    @MainActor
    func testAnalyticsSnapshotDerivesFromLocalSessions() {
        let model = AppModel()
        model.sessions = [
            makeSession(name: "Accurate", cents: [-2, 0, 3]),
            makeSession(name: "Sharp", cents: [9, 11, 7]),
        ]

        let analytics = model.analyticsSnapshot

        XCTAssertEqual(analytics.sessionCount, 2)
        XCTAssertEqual(analytics.validFrameCount, 6)
        XCTAssertEqual(analytics.bestSessionName, "Accurate")
        XCTAssertGreaterThan(analytics.averageAbsCents, 0)
        XCTAssertLessThan(analytics.averageInTunePercentage, 100)
    }

    @MainActor
    func testAccountFeaturesAreDisabledWithoutSupabaseConfig() {
        let model = AppModel()

        XCTAssertFalse(model.accountFeaturesEnabled)
        XCTAssertNotNil(model.accountUnavailableMessage)
    }

    func testCoreTuningStatusIsAvailableToApp() {
        XCTAssertEqual(BrassTuneCore.tuningStatus(cents: 7, confidence: 0.98, rms: 0.1), .sharp)
    }

    private func makeSession(name: String, cents: [Double]) -> PracticeSession {
        let frames = cents.enumerated().map { index, centsValue in
            PitchFrame(
                timestampMs: index * 110,
                frequencyHz: 440,
                confidence: 0.98,
                rms: 0.08,
                centsDeviation: centsValue,
                tuningStatus: BrassTuneCore.tuningStatus(cents: centsValue, confidence: 0.98, rms: 0.08),
                writtenNoteName: "A",
                writtenOctave: 4,
                isValidForRecording: true
            )
        }
        let startedAt = Date(timeIntervalSince1970: 1_000)
        return PracticeSession(
            id: UUID(),
            name: name,
            instrumentId: "trumpet",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(frames.count) * 0.11),
            frames: frames,
            retainedRecordingURL: nil
        )
    }
}
