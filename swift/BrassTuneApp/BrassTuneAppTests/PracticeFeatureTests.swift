import Foundation
import XCTest
@testable import BrassTuneApp

final class PracticeFeatureTests: XCTestCase {
    func testCustomExerciseValidationNormalizesAndBoundsNotes() throws {
        let exercise = try SavedPlayAlongExercise(title: "  Lip slur  ", writtenNotes: ["c", "F♯", "b♭"])
        XCTAssertEqual(exercise.title, "Lip slur")
        XCTAssertEqual(exercise.writtenNotes, ["C", "F#", "Bb"])
        XCTAssertEqual(exercise.exercise.writtenNotes.count, 3)

        XCTAssertThrowsError(try SavedPlayAlongExercise(title: "", writtenNotes: ["C"]))
        XCTAssertThrowsError(try SavedPlayAlongExercise(title: "Too short", writtenNotes: []))
        XCTAssertThrowsError(try SavedPlayAlongExercise(title: "Too long", writtenNotes: Array(repeating: "C", count: 33)))
        XCTAssertThrowsError(try SavedPlayAlongExercise(title: "Bad note", writtenNotes: ["H"]))
    }

    func testFeatureStateDecodesWhenEveryNewFieldIsAbsent() throws {
        let state = try JSONDecoder().decode(PracticeFeatureState.self, from: Data("{}".utf8))
        XCTAssertEqual(state, PracticeFeatureState())
        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertTrue(state.customExercises.isEmpty)
        XCTAssertNil(state.warmupCheckpoint)
    }

    @MainActor
    func testSnapshotRoundTripPersistsAllLocalFeatureTypes() throws {
        let model = makeModel()
        _ = model.saveCustomExercise(title: "My notes", notes: ["C", "D", "E"])
        model.metronome = MetronomeSettings(bpm: 108, beatsPerMeasure: 3, beatUnit: 4, subdivision: .eighth, muted: false, visualOnly: false, hapticsEnabled: true, volume: 0.35)
        XCTAssertTrue(model.saveMetronomePreset(name: "Waltz"))
        model.updateWeeklyGoal(minutes: 90, sessions: 4)
        model.startOrResumeWarmup(now: Date(timeIntervalSince1970: 1_000))
        model.pauseWarmup(now: Date(timeIntervalSince1970: 1_045))

        let restored = makeModel(at: modelTestURL)
        XCTAssertEqual(restored.practiceFeatures.customExercises.count, 1)
        XCTAssertEqual(restored.practiceFeatures.metronomePresets.first?.settings, model.metronome)
        XCTAssertEqual(restored.practiceFeatures.weeklyGoal, WeeklyPracticeGoal(targetMinutes: 90, targetSessions: 4))
        XCTAssertEqual(try XCTUnwrap(restored.currentWarmupCheckpoint).accumulatedSeconds, 45, accuracy: 0.001)
        XCTAssertNil(restored.currentWarmupCheckpoint?.runningSince, "A restored checkpoint must be paused, never silently playing audio.")
    }

    @MainActor
    func testWarmupUsesInjectedDatesAndCompletesExactlyOnce() {
        let model = makeModel()
        let start = Date(timeIntervalSince1970: 5_000)
        model.startOrResumeWarmup(now: start)
        model.advanceWarmup(now: start.addingTimeInterval(299))
        XCTAssertTrue(model.sessions.isEmpty)

        model.advanceWarmup(now: start.addingTimeInterval(300))
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions[0].durationSeconds, 300, accuracy: 0.001)
        XCTAssertTrue(model.currentWarmupCheckpoint?.completed == true)

        model.advanceWarmup(now: start.addingTimeInterval(600))
        XCTAssertEqual(model.sessions.count, 1)
    }

    @MainActor
    func testMetronomePresetStoresFullSettingsAndNamesAreUnique() {
        let model = makeModel()
        model.metronome = MetronomeSettings(bpm: 137, beatsPerMeasure: 7, beatUnit: 8, subdivision: .triplet, muted: true, visualOnly: true, hapticsEnabled: true, volume: 0.2)
        XCTAssertTrue(model.saveMetronomePreset(name: "Odd meter"))
        XCTAssertFalse(model.saveMetronomePreset(name: "odd METER"))

        model.metronome = MetronomeSettings()
        let id = try! XCTUnwrap(model.practiceFeatures.metronomePresets.first?.id)
        model.applyMetronomePreset(id: id)
        XCTAssertEqual(model.metronome.bpm, 137)
        XCTAssertEqual(model.metronome.beatsPerMeasure, 7)
        XCTAssertEqual(model.metronome.beatUnit, 8)
        XCTAssertEqual(model.metronome.subdivision, .triplet)
        XCTAssertTrue(model.metronome.visualOnly)
        XCTAssertTrue(model.metronome.hapticsEnabled)
        XCTAssertEqual(model.metronome.volume, 0.2, accuracy: 0.001)
    }

    @MainActor
    func testFavoritesDoNotCreateRecentsAndRecentsAreBoundedMRU() {
        let model = makeModel()
        let favorite = PracticeShortcut(kind: .playAlongExercise, referenceID: "cmaj", title: "C major scale")
        model.toggleFavorite(favorite)
        XCTAssertTrue(model.practiceFeatures.recents.isEmpty)

        for index in 0..<12 {
            model.recordPracticeStart(
                PracticeShortcut(kind: .playAlongExercise, referenceID: "exercise-\(index)", title: "Exercise \(index)"),
                now: Date(timeIntervalSince1970: Double(index))
            )
        }
        XCTAssertEqual(model.practiceFeatures.recents.count, 10)
        XCTAssertEqual(model.practiceFeatures.recents.first?.referenceID, "exercise-11")
        XCTAssertFalse(model.practiceFeatures.recents.contains(where: { $0.referenceID == "exercise-0" }))
    }

    func testWeeklyProgressUsesCalendarWeekAndExcludesNextWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 12))!
        let start = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let sessions = [
            makeSession(startedAt: start.addingTimeInterval(60), duration: 600),
            makeSession(startedAt: start.addingTimeInterval(86_400), duration: 900),
            makeSession(startedAt: start.addingTimeInterval(7 * 86_400 + 60), duration: 9_999),
        ]

        let progress = WeeklyPracticeProgress.calculate(sessions: sessions, now: now, calendar: calendar)
        XCTAssertEqual(progress.minutes, 25)
        XCTAssertEqual(progress.sessionCount, 2)
    }

    func testWeakTransitionRequiresThreeSamplesAndRanksDeterministically() {
        let twoAttempts = [attempt(destinationRating: .off, cents: 42), attempt(destinationRating: .off, cents: 38)]
        XCTAssertNil(WeakTransitionAnalyzer.insight(from: twoAttempts))

        let insight = WeakTransitionAnalyzer.insight(from: twoAttempts + [attempt(destinationRating: .missed, cents: nil)])
        XCTAssertEqual(insight?.fromNote, "D")
        XCTAssertEqual(insight?.toNote, "F#")
        XCTAssertEqual(insight?.evidenceCount, 3)
        XCTAssertEqual(insight?.exercise.writtenNotes, ["D", "F#", "D", "F#", "D", "F#"])
    }

    func testToneMathCoversAliasesAndFailsClosedForUnknownInstrument() throws {
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "trumpet"), 2)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "cornet"), 2)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "flugelhorn"), 2)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "baritone"), 2)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "horn"), 7)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "french-horn"), 7)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "trombone"), 0)
        XCTAssertNil(PracticePitchMath.transpositionSemitones(for: "mystery-horn"))
        XCTAssertNil(PracticePitchMath.frequency(writtenMIDI: 69, instrumentID: "mystery-horn", referencePitchHz: 440))

        let trumpetA = try XCTUnwrap(PracticePitchMath.frequency(writtenMIDI: 71, instrumentID: "trumpet", referencePitchHz: 440))
        XCTAssertEqual(trumpetA, 440, accuracy: 0.01)
        let hornFifth = try XCTUnwrap(PracticePitchMath.frequency(writtenMIDI: 60, interval: .perfectFifth, instrumentID: "horn", referencePitchHz: 440))
        XCTAssertEqual(hornFifth, 261.625, accuracy: 0.01)
    }

    func testBuiltInPackAndBlockIDsAreStableAndUnique() {
        let first = PracticePack.builtIns
        let second = PracticePack.builtIns
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.flatMap(\.blocks).map(\.id), second.flatMap(\.blocks).map(\.id))
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        let blockIDs = first.flatMap(\.blocks).map(\.id)
        XCTAssertEqual(Set(blockIDs).count, blockIDs.count)
    }

    @MainActor
    func testWorkspaceMovesOneBlockAtATimeAndSavesCompletion() {
        let model = makeModel()
        let pack = PracticePack.builtIns[0]
        let start = Date(timeIntervalSince1970: 20_000)
        model.startWorkspace(pack: pack, now: start)
        XCTAssertEqual(model.currentWorkspaceCheckpoint?.blockIndex, 0)
        XCTAssertEqual(model.practiceFeatures.recents.first?.referenceID, pack.id)

        model.moveWorkspace(by: 1, now: start.addingTimeInterval(10))
        XCTAssertEqual(model.currentWorkspaceCheckpoint?.blockIndex, 1)
        model.moveWorkspace(by: 99, now: start.addingTimeInterval(20))
        XCTAssertEqual(model.currentWorkspaceCheckpoint?.blockIndex, pack.blocks.count - 1)

        model.finishWorkspace(now: start.addingTimeInterval(60))
        XCTAssertTrue(model.currentWorkspaceCheckpoint?.completed == true)
        XCTAssertEqual(model.sessions.first?.name, pack.name)
    }

    private var modelTestURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PracticeFeatureTests-state.json")
    }

    @MainActor
    private func makeModel(at url: URL? = nil) -> AppModel {
        let fileURL = url ?? modelTestURL
        if url == nil { try? FileManager.default.removeItem(at: fileURL) }
        return AppModel(
            persistenceStore: .ephemeral(fileURL: fileURL),
            scoreStorageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
    }

    private func makeSession(startedAt: Date, duration: TimeInterval) -> PracticeSession {
        PracticeSession(
            id: UUID(),
            name: "Practice",
            instrumentId: "trumpet",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            frames: [],
            retainedRecordingURL: nil,
            source: .live
        )
    }

    private func attempt(destinationRating: PlayAlongNoteRating, cents: Double?) -> PlayAlongAttemptSummary {
        PlayAlongAttemptSummary(
            exercise: PlayAlongExercise(
                id: UUID().uuidString,
                title: "Transition",
                detail: "Test",
                difficulty: "Test",
                category: .practicePattern,
                writtenNotes: ["D", "F#"]
            ),
            noteGrades: [
                PlayAlongNoteGrade(writtenNoteName: "D", medianCents: 0, sampleCount: 10, rating: .excellent),
                PlayAlongNoteGrade(writtenNoteName: "F#", medianCents: cents, sampleCount: cents == nil ? 0 : 10, rating: destinationRating),
            ]
        )
    }
}
