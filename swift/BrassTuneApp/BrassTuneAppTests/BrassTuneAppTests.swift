import XCTest
@testable import BrassTuneApp
import BrassTuneCore
import UIKit

final class BrassTuneAppTests: XCTestCase {
    // MARK: - Shipping defaults and local model behavior

    @MainActor
    func testShippingDefaultsUseLiveMicrophoneAndAudibleMetronome() {
        XCTAssertFalse(NativeTestFixtures.areEnabled)
        XCTAssertEqual(NativeAudioEngine.defaultRecordingSource, .live)
        XCTAssertEqual(PracticeSessionSource.allCases, [.live])
        XCTAssertFalse(ScoreSourceKind.allCases.contains(.sample))

        let settings = MetronomeSettings()
        XCTAssertFalse(settings.muted)
        XCTAssertFalse(settings.visualOnly)
        XCTAssertEqual(settings.volume, 0.6, accuracy: 0.001)
    }

    @MainActor
    func testFixtureEntryPointsDoNothingWithoutUITestLaunchFlag() {
        let model = makeModel()

        model.startDemoRecording()
        model.stopDemoRecording()
        model.importSampleScore()

        XCTAssertEqual(model.recordingSource, .live)
        XCTAssertFalse(model.audioEngine.recording)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty)
    }

    @MainActor
    func testNoArgumentAccountDeletionClearsLocalState() async {
        let model = makeModel()
        model.sessions = [makeSession(name: "Test recording", cents: [-2, 0, 3])]

        await model.deleteAccount()

        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertNil(model.lastError)
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
    func testLocalExportIncludesPracticeMetricsAndImportedScore() throws {
        let model = makeModel()
        model.sessions = [makeSession(name: "Exportable recording", cents: [-4, 0, 7])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Warm-up score")

        let export = model.exportDataText()

        XCTAssertTrue(export.contains("BrassTune local data export"))
        XCTAssertTrue(export.contains("Sessions: 1"))
        XCTAssertTrue(export.contains("Exportable recording"))
        XCTAssertTrue(export.contains("Average absolute cents"))
        XCTAssertTrue(export.contains("Cents preview"))
        XCTAssertTrue(export.contains("Scores: 1"))
        XCTAssertTrue(export.contains("Warm-up score"))
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
    func testMetronomeUserSettingsRemainAudibleAndPersistable() {
        let model = makeModel()

        XCTAssertFalse(model.metronomeTemporarilyMutedForRecording)
        model.setTempo(100)
        model.setMetronomeVolume(0.72)

        XCTAssertEqual(model.metronome.bpm, 100)
        XCTAssertFalse(model.metronome.muted)
        XCTAssertFalse(model.metronome.visualOnly)
        XCTAssertEqual(model.metronome.volume, 0.72, accuracy: 0.001)
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
    func testScoreAnnotationAttachAndDelete() throws {
        let model = makeModel()
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Local score")
        let score = try XCTUnwrap(model.scores.first)
        model.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]

        model.updateScoreAnnotation(
            scoreID: score.id,
            focusMeasures: "9-16",
            notes: "Tune releases",
            tempoTarget: 104,
            problemPassage: "second phrase"
        )
        model.attachScoreToLatestSession(scoreID: score.id)

        XCTAssertEqual(model.activeScoreID, score.id)
        XCTAssertEqual(model.scores[0].annotation.focusMeasures, "9-16")
        XCTAssertEqual(model.sessions[0].attachedScoreID, score.id)

        model.deleteScore(id: score.id)

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertNil(model.sessions[0].attachedScoreID)
        XCTAssertFalse(model.sessions[0].practiceNotes.contains("Local score"))
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
    func testFailedPhotoImportRemovesCopiedScoreFile() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)

        XCTAssertThrowsError(try model.importPhotoScore(data: Data("not an image".utf8), preferredName: "Broken score"))

        XCTAssertTrue(model.scores.isEmpty)
        let storedFiles = (try? FileManager.default.contentsOfDirectory(at: scoreDirectory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(storedFiles.isEmpty)
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

        await model.deleteAccount()

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scoreDirectory.path))
    }

    @MainActor
    func testLocalPersistenceRestoresLiveSessionsSettingsScoresAndMetronome() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)

        model.selectedInstrumentId = "horn"
        model.referencePitchHz = 442.0
        model.setTempo(108)
        model.setMetronomeVolume(0.7)
        model.sessions = [makeSession(name: "Saved recording", cents: [-2, 0, 3])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Saved score")

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)

        XCTAssertEqual(restored.selectedInstrumentId, "horn")
        XCTAssertEqual(restored.referencePitchHz, 442.0)
        XCTAssertEqual(restored.metronome.bpm, 108)
        XCTAssertEqual(restored.metronome.volume, 0.7, accuracy: 0.001)
        XCTAssertFalse(restored.metronome.muted)
        XCTAssertFalse(restored.metronome.visualOnly)
        XCTAssertEqual(restored.sessions.count, 1)
        XCTAssertEqual(restored.sessions.first?.source, .live)
        XCTAssertEqual(restored.scores.count, 1)
        XCTAssertEqual(restored.scores.first?.sourceKind, .photos)
        XCTAssertEqual(restored.activeScoreID, restored.scores.first?.id)
    }

    @MainActor
    func testLegacySilentMetronomeDefaultsMigrateToAudibleDefaults() {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        var legacyMetronome = MetronomeSettings()
        legacyMetronome.muted = true
        legacyMetronome.visualOnly = true
        legacyMetronome.volume = 0
        store.save(
            NativeLocalSnapshot(
                selectedInstrumentId: "trumpet",
                referencePitchHz: 440,
                sessions: [],
                scores: [],
                activeScoreID: nil,
                metronome: legacyMetronome,
                metronomeDefaultsVersion: 1
            )
        )

        let restored = AppModel(persistenceStore: store)

        XCTAssertFalse(restored.metronome.muted)
        XCTAssertFalse(restored.metronome.visualOnly)
        XCTAssertEqual(restored.metronome.volume, 0.6, accuracy: 0.001)
    }

    @MainActor
    func testShippingRestoreQuarantinesLegacyFixtureSessionsAndScores() {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let sampleSession = makeSession(name: "Old test recording", cents: [0], source: .sample)
        let sampleScore = makeSampleScore()
        store.save(
            NativeLocalSnapshot(
                selectedInstrumentId: "trumpet",
                referencePitchHz: 440,
                sessions: [sampleSession],
                scores: [sampleScore],
                activeScoreID: sampleScore.id,
                metronome: MetronomeSettings(),
                metronomeDefaultsVersion: 2
            )
        )

        let restored = AppModel(persistenceStore: store)

        XCTAssertTrue(restored.sessions.isEmpty)
        XCTAssertTrue(restored.scores.isEmpty)
        XCTAssertNil(restored.activeScoreID)
    }

    // MARK: - Play-Along web parity

    func testPlayAlongRatingUsesWebCentsThresholds() {
        XCTAssertEqual(PlayAlongNoteRating(cents: 5), .excellent)
        XCTAssertEqual(PlayAlongNoteRating(cents: -5), .excellent)
        XCTAssertEqual(PlayAlongNoteRating(cents: 15), .good)
        XCTAssertEqual(PlayAlongNoteRating(cents: -15), .good)
        XCTAssertEqual(PlayAlongNoteRating(cents: 30), .close)
        XCTAssertEqual(PlayAlongNoteRating(cents: -30), .close)
        XCTAssertEqual(PlayAlongNoteRating(cents: 30.1), .off)
        XCTAssertEqual(PlayAlongNoteRating(cents: nil), .missed)
        XCTAssertEqual(PlayAlongNoteRating(cents: .nan), .missed)
    }

    func testPlayAlongExerciseCatalogUsesDetectorPitchSpellings() {
        let detectorSpellings = Set(["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"])
        let exerciseNotes = Set(PlayAlongExercise.library.flatMap(\.writtenNotes))

        XCTAssertEqual(PlayAlongExercise.defaultExercise.id, "cmaj")
        XCTAssertEqual(PlayAlongExercise.library.count, 6)
        XCTAssertTrue(exerciseNotes.isSubset(of: detectorSpellings))
        XCTAssertFalse(PlayAlongExercise.library.contains { $0.writtenNotes.isEmpty })
    }

    func testPlayAlongAdvancesAfterSustainedCorrectWrittenPitchClass() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"], holdDurationMs: 400, minimumSamples: 3, attackTrimMs: 0)

        for timestamp in stride(from: 0, through: 500, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 10, timestampMs: timestamp))
        }

        XCTAssertEqual(grader.noteGrades.count, 1)
        XCTAssertEqual(grader.noteGrades[0].writtenNoteName, "C")
        XCTAssertEqual(grader.noteGrades[0].medianCents ?? .nan, 10, accuracy: 0.001)
        XCTAssertEqual(grader.noteGrades[0].rating, .good)
        XCTAssertEqual(grader.currentNoteName, "D")
    }

    func testPlayAlongDoesNotAdvanceOnBriefTouch() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 100))

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
        XCTAssertEqual(grader.heldFraction, 0.25, accuracy: 0.001)
    }

    func testPlayAlongWrongConfidentNoteResetsHold() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 100))
        grader.feed(makePlayAlongFrame(note: "E", cents: 5, timestampMs: 200))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 300))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 400))

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
        XCTAssertEqual(grader.heldFraction, 0.25, accuracy: 0.001)
    }

    func testPlayAlongToleratesBriefLowConfidenceSilence() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: nil, cents: nil, timestampMs: 100, confidence: 0.1, frequencyHz: nil))
        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 200))
        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 440))

        XCTAssertTrue(grader.isComplete)
        XCTAssertEqual(grader.noteGrades.first?.rating, .good)
    }

    func testPlayAlongLongSilenceResetsHoldAfterDropoutGrace() {
        var grader = PlayAlongGrader(
            writtenNotes: ["C"],
            holdDurationMs: 400,
            minimumSamples: 3,
            maximumDropoutMs: 250
        )

        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 100))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 500))

        XCTAssertEqual(grader.heldFraction, 0, accuracy: 0.001)

        for timestamp in stride(from: 600, through: 800, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: timestamp))
        }

        XCTAssertFalse(grader.isComplete)
        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
    }

    func testPlayAlongTrimsBrassAttackTransient() {
        var grader = PlayAlongGrader(
            writtenNotes: ["C"],
            holdDurationMs: 400,
            minimumSamples: 3,
            attackTrimMs: 120
        )

        grader.feed(makePlayAlongFrame(note: "C", cents: 45, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 30, timestampMs: 80))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 200))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 320))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 450))

        XCTAssertEqual(grader.noteGrades.first?.medianCents ?? .nan, 4, accuracy: 0.001)
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testPlayAlongMedianRejectsSingleDetectorOutlier() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3, attackTrimMs: 0)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 120))
        grader.feed(makePlayAlongFrame(note: "C", cents: 60, timestampMs: 240))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 360))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 480))

        XCTAssertEqual(grader.noteGrades.first?.medianCents ?? .nan, 5, accuracy: 0.001)
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testPlayAlongIgnoresFramesBelowConfidenceGate() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 300, minimumSamples: 3)

        for timestamp in stride(from: 0, through: 600, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: timestamp, confidence: 0.4))
        }

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
    }

    func testPlayAlongAcceptsIntermediateConfidenceWithoutRecordingValidity() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 300, minimumSamples: 3)

        for timestamp in stride(from: 0, through: 300, by: 100) {
            let frame = makePlayAlongFrame(
                note: "C",
                cents: 3,
                timestampMs: timestamp,
                confidence: 0.7,
                isValidForRecording: false
            )
            XCTAssertFalse(frame.isValidForRecording)
            grader.feed(frame)
        }

        XCTAssertTrue(grader.isComplete)
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testPlayAlongSkipMarksMissedAndAdvances() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"])

        grader.skipCurrentNote()

        XCTAssertEqual(grader.noteGrades.count, 1)
        XCTAssertEqual(grader.noteGrades[0].rating, .missed)
        XCTAssertNil(grader.noteGrades[0].medianCents)
        XCTAssertEqual(grader.currentNoteName, "D")
    }

    func testPlayAlongCompletesAndSummarizesLikeWebGrader() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"], holdDurationMs: 300, minimumSamples: 3, attackTrimMs: 0)

        for timestamp in stride(from: 0, through: 400, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: timestamp))
        }
        for timestamp in stride(from: 1_000, through: 1_400, by: 100) {
            grader.feed(makePlayAlongFrame(note: "D", cents: 12, timestampMs: timestamp))
        }

        XCTAssertTrue(grader.isComplete)
        let summary = PlayAlongGrade(expectedNoteCount: 2, noteGrades: grader.noteGrades)
        XCTAssertEqual(summary.totalNotes, 2)
        XCTAssertEqual(summary.notesPlayed, 2)
        XCTAssertEqual(summary.inTuneNotes, 2)
        XCTAssertEqual(summary.inTunePercentage, 100)
        XCTAssertEqual(summary.averageAbsoluteCents ?? .nan, 8, accuracy: 0.001)
        XCTAssertEqual(summary.stars, 3)
    }

    func testPlayAlongMatchesWrittenPitchClassAcrossEnharmonicSpellingAndOctave() {
        var grader = PlayAlongGrader(writtenNotes: ["Bb"], holdDurationMs: 300, minimumSamples: 3, attackTrimMs: 0)

        for timestamp in stride(from: 0, through: 300, by: 100) {
            grader.feed(makePlayAlongFrame(note: "A#", cents: 2, timestampMs: timestamp, writtenOctave: 6))
        }

        XCTAssertTrue(grader.isComplete)
        XCTAssertEqual(grader.noteGrades.first?.writtenNoteName, "Bb")
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testDetectedFramesApplyWrittenPitchTranspositionForTrumpetAndHorn() {
        let trumpet = PitchFrame.detected(
            timestampMs: 0,
            frequencyHz: 233.081_880_8,
            confidence: 0.99,
            rms: 0.08,
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        let horn = PitchFrame.detected(
            timestampMs: 0,
            frequencyHz: 174.614_115_7,
            confidence: 0.99,
            rms: 0.08,
            instrumentId: "horn",
            referencePitchHz: 440
        )

        XCTAssertEqual(trumpet.writtenNoteName, "C")
        XCTAssertEqual(trumpet.writtenOctave, 4)
        XCTAssertEqual(horn.writtenNoteName, "C")
        XCTAssertEqual(horn.writtenOctave, 4)
    }

    // MARK: - Pitch detector and BrassTuneCore integration

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
        XCTAssertEqual(BrassTuneCore.tuningStatus(cents: nil, confidence: 0.99, rms: 0.1), .noLock)
    }

    func testNativePitchDetectorLocksSyntheticSineAndAppliesReferencePitch() {
        let sampleRate = 44_100.0
        let frequency = 442.0
        let samples = (0..<4096).map { index in
            Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.2)
        }

        let frame = NativePitchDetector.frame(
            samples: samples,
            sampleRate: sampleRate,
            timestampMs: 120,
            instrumentId: "trumpet",
            referencePitchHz: 442.0
        )

        XCTAssertEqual(frame.tuningStatus, .inTune)
        XCTAssertEqual(frame.writtenNoteName, "B")
        XCTAssertEqual(frame.writtenOctave, 4)
        XCTAssertTrue(frame.isValidForRecording)
        XCTAssertEqual(frame.frequencyHz ?? 0, 442.0, accuracy: 3.0)
        XCTAssertGreaterThan(frame.confidence, 0.95)
    }

    func testNativePitchDetectorReportsSilenceAndNoLock() {
        let silent = NativePitchDetector.frame(
            samples: Array(repeating: Float(0), count: 4096),
            sampleRate: 44_100,
            timestampMs: 1,
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        XCTAssertEqual(silent.tuningStatus, .silence)
        XCTAssertFalse(silent.isValidForRecording)

        var seed: UInt64 = 0xBADC0DE
        let noise = (0..<4096).map { _ -> Float in
            seed = seed &* 6364136223846793005 &+ 1
            let unit = Double((seed >> 33) & 0xFFFF) / 65_535.0
            return Float((unit * 2.0 - 1.0) * 0.025)
        }
        let noLock = NativePitchDetector.frame(
            samples: noise,
            sampleRate: 44_100,
            timestampMs: 2,
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        XCTAssertEqual(noLock.tuningStatus, .noLock)
        XCTAssertFalse(noLock.isValidForRecording)
    }

    // MARK: - Helpers

    @MainActor
    private func makeModel() -> AppModel {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        return AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)
    }

    private func makeSession(
        name: String,
        cents: [Double],
        source: PracticeSessionSource = .live
    ) -> PracticeSession {
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
            retainedRecordingURL: nil,
            source: source
        )
    }

    private func makeSampleScore() -> ImportedScore {
        let page = ScorePage(
            id: UUID(),
            pageNumber: 1,
            titleSuggestion: nil,
            textSuggestions: [],
            thumbnailPNGData: nil
        )
        return ImportedScore(
            id: UUID(),
            title: "Old test score",
            composer: nil,
            sourceKind: .sample,
            localFileName: nil,
            importedAt: Date(timeIntervalSince1970: 1_000),
            pages: [page],
            selectedPageID: page.id
        )
    }

    private func makePlayAlongFrame(
        note: String?,
        cents: Double?,
        timestampMs: Int,
        confidence: Double = 0.9,
        frequencyHz: Double? = 440,
        writtenOctave: Int = 4,
        isValidForRecording: Bool? = nil
    ) -> PitchFrame {
        let rms = note == nil ? 0 : 0.08
        return PitchFrame(
            timestampMs: timestampMs,
            frequencyHz: frequencyHz,
            confidence: confidence,
            rms: rms,
            centsDeviation: cents,
            tuningStatus: BrassTuneCore.tuningStatus(cents: cents, confidence: confidence, rms: rms),
            writtenNoteName: note,
            writtenOctave: note == nil ? nil : writtenOctave,
            isValidForRecording: isValidForRecording ?? (note != nil && cents != nil && confidence >= 0.95)
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
