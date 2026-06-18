import XCTest
@testable import BrassTuneApp
import BrassTuneCore

@MainActor
final class BrassTuneAppTests: XCTestCase {
    func testFixtureRecordingCreatesDeterministicSession() {
        let model = AppModel()
        model.startDemoRecording()
        model.stopDemoRecording()
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions[0].frames.count, 32)
        XCTAssertGreaterThan(model.sessions[0].inTunePercentage, 0)
    }

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
    }

    func testCoreTuningStatusIsAvailableToApp() {
        XCTAssertEqual(BrassTuneCore.tuningStatus(cents: 7, confidence: 0.98, rms: 0.1), .sharp)
    }
}
