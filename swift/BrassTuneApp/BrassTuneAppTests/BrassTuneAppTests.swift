import XCTest
@testable import BrassTuneApp
import BrassTuneCore
import UIKit

final class BrassTuneAppTests: XCTestCase {
    @MainActor
    func testFixtureRecordingCreatesDeterministicSession() {
        let model = makeModel()
        model.startDemoRecording()
        model.stopDemoRecording()
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertGreaterThanOrEqual(model.sessions[0].frames.count, 12)
        XCTAssertGreaterThan(model.sessions[0].inTunePercentage, 0)
    }

    @MainActor
    func testAccountDeletionRequiresConfirmation() async {
        let model = makeModel()
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
        let model = makeModel()
        let first = makeSession(name: "First", cents: [-2, 1, 6])
        let second = makeSession(name: "Second", cents: [9, 10, 11])
        model.sessions = [first, second]

        model.deleteSession(id: first.id)

        XCTAssertEqual(model.sessions, [second])
    }

    @MainActor
    func testLocalExportIncludesPracticeMetrics() {
        let model = makeModel()
        model.sessions = [makeSession(name: "Exportable take", cents: [-4, 0, 7])]
        model.importSampleScore()

        let export = model.exportDataText()

        XCTAssertTrue(export.contains("BrassTune local data export"))
        XCTAssertTrue(export.contains("Sessions: 1"))
        XCTAssertTrue(export.contains("Exportable take"))
        XCTAssertTrue(export.contains("Average absolute cents"))
        XCTAssertTrue(export.contains("Cents preview"))
        XCTAssertTrue(export.contains("Scores: 1"))
        XCTAssertTrue(export.contains("Long-tone study"))
    }

    @MainActor
    func testAnalyticsSnapshotDerivesFromLocalSessions() {
        let model = makeModel()
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
        let model = makeModel()

        XCTAssertFalse(model.accountFeaturesEnabled)
        XCTAssertNotNil(model.accountUnavailableMessage)
    }

    @MainActor
    func testMetronomeStateSurvivesRecordingFlow() {
        let model = makeModel()

        model.startMetronome()
        model.adjustTempo(by: 8)
        model.startDemoRecording()
        model.toggleMetronomeMute()
        model.stopDemoRecording()

        XCTAssertTrue(model.metronomeRunning)
        XCTAssertEqual(model.metronome.bpm, 100)
        XCTAssertFalse(model.metronome.muted)
        XCTAssertEqual(model.sessions.count, 1)
        model.stopMetronome()
    }

    @MainActor
    func testTapTempoClampsAndUpdatesBPM() {
        let model = makeModel()
        let start = Date(timeIntervalSince1970: 10)

        model.tapTempo(now: start)
        model.tapTempo(now: start.addingTimeInterval(0.5))
        model.tapTempo(now: start.addingTimeInterval(1.0))

        XCTAssertEqual(model.metronome.bpm, 120)
        model.setTempo(10)
        XCTAssertEqual(model.metronome.bpm, 30)
        model.setTempo(260)
        XCTAssertEqual(model.metronome.bpm, 240)
    }

    @MainActor
    func testScoreSampleAnnotationAttachAndDelete() throws {
        let model = makeModel()
        model.importSampleScore()
        let score = try XCTUnwrap(model.scores.first)

        model.updateScoreAnnotation(scoreID: score.id, focusMeasures: "9-16", notes: "Tune releases", tempoTarget: 104, problemPassage: "second phrase")
        model.startDemoRecording()
        model.stopDemoRecording()
        model.attachScoreToLatestSession(scoreID: score.id)

        XCTAssertEqual(model.activeScoreID, score.id)
        XCTAssertEqual(model.scores[0].annotation.focusMeasures, "9-16")
        XCTAssertEqual(model.sessions[0].attachedScoreID, score.id)

        model.deleteScore(id: score.id)

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertNil(model.sessions[0].attachedScoreID)
        XCTAssertFalse(model.sessions[0].practiceNotes.contains("Long-tone study"))
        XCTAssertFalse(model.sessions[0].practiceNotes.contains("9-16"))
    }

    @MainActor
    func testClearingLocalPracticeDataRemovesImportedScoreFiles() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)

        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Local score")
        let fileName = try XCTUnwrap(model.scores.first?.localFileName)
        let storedURL = scoreDirectory.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        model.clearLocalPracticeData()

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scoreDirectory.path))
    }

    @MainActor
    func testAccountDeletionRemovesImportedScoreFiles() async throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)

        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Disposable score")
        let fileName = try XCTUnwrap(model.scores.first?.localFileName)
        let storedURL = scoreDirectory.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        await model.deleteAccount(confirmation: "delete my account")

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scoreDirectory.path))
    }

    @MainActor
    func testLocalPersistenceRestoresSessionsSettingsScoresAndMetronome() {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)

        model.selectedInstrumentId = "horn"
        model.referencePitchHz = 442.0
        model.setTempo(108)
        model.importSampleScore()
        model.startDemoRecording()
        model.stopDemoRecording()

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)

        XCTAssertEqual(restored.selectedInstrumentId, "horn")
        XCTAssertEqual(restored.referencePitchHz, 442.0)
        XCTAssertEqual(restored.metronome.bpm, 108)
        XCTAssertEqual(restored.sessions.count, 1)
        XCTAssertEqual(restored.scores.count, 1)
        XCTAssertEqual(restored.activeScoreID, restored.scores.first?.id)
    }

    func testFixtureFramesReflectInstrumentTransposition() {
        let trumpet = PitchFrame.fixture(index: 0, instrumentId: "trumpet")
        let horn = PitchFrame.fixture(index: 0, instrumentId: "horn")

        XCTAssertEqual(trumpet.writtenNoteName, "D")
        XCTAssertEqual(trumpet.writtenOctave, 5)
        XCTAssertEqual(horn.writtenNoteName, "D")
        XCTAssertEqual(horn.writtenOctave, 4)
    }

    func testCoreTuningStatusIsAvailableToApp() {
        XCTAssertEqual(BrassTuneCore.tuningStatus(cents: 7, confidence: 0.98, rms: 0.1), .sharp)
    }

    @MainActor
    private func makeModel() -> AppModel {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        return AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)
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

    private func makeTinyPNGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            UIColor.white.setStroke()
            context.cgContext.move(to: CGPoint(x: 2, y: 4))
            context.cgContext.addLine(to: CGPoint(x: 14, y: 4))
            context.cgContext.strokePath()
        }
        return try XCTUnwrap(image.pngData())
    }
}
