import Foundation
import XCTest
import BrassTuneCore
@testable import BrassTuneApp

final class PracticeFeatureTests: XCTestCase {
    func testMetronomeIntervalMatchesSharedTimingContract() throws {
        struct MetronomeCase: Decodable {
            let name: String
            let bpm: Int
            let numerator: Int
            let denominator: Int
            let subdivision: MetronomeSubdivision
            let expectedSeconds: TimeInterval

            enum CodingKeys: String, CodingKey {
                case name, bpm, numerator, denominator, subdivision
                case expectedSeconds = "expected_seconds"
            }
        }
        struct MetronomeContract: Decodable {
            let cases: [MetronomeCase]
        }

        let data = try Data(contentsOf: try sharedFixtureURL(named: "metronome_cases.json"))
        let contract = try JSONDecoder().decode(MetronomeContract.self, from: data)

        for metronomeCase in contract.cases {
            let settings = MetronomeSettings(
                bpm: metronomeCase.bpm,
                beatsPerMeasure: metronomeCase.numerator,
                beatUnit: metronomeCase.denominator,
                subdivision: metronomeCase.subdivision
            )
            XCTAssertEqual(settings.intervalSeconds, metronomeCase.expectedSeconds, accuracy: 0.000_001, metronomeCase.name)
        }
    }

    func testCustomExerciseValidationNormalizesAndBoundsNotes() throws {
        let exercise = try SavedPlayAlongExercise(title: "  Lip slur  ", writtenNotes: ["c", "F♯", "b♭"])
        XCTAssertEqual(exercise.title, "Lip slur")
        XCTAssertEqual(exercise.writtenNotes, ["C", "F#", "Bb"])
        XCTAssertEqual(exercise.exercise.writtenNotes.count, 3)

        XCTAssertThrowsError(try SavedPlayAlongExercise(title: "", writtenNotes: ["C"]))
        XCTAssertThrowsError(try SavedPlayAlongExercise(title: "Too short", writtenNotes: []))
        XCTAssertThrowsError(try SavedPlayAlongExercise(title: "Too long", writtenNotes: Array(repeating: "C", count: 33)))
        XCTAssertThrowsError(try SavedPlayAlongExercise(title: "Bad note", writtenNotes: ["H"]))

        let longTitle = String(repeating: "A", count: 80)
        XCTAssertEqual(try SavedPlayAlongExercise(title: longTitle, writtenNotes: ["C"]).title.count, 60)
    }

    func testPracticePackMissingContentErrorLocalizesTheBlockKind() {
        let originalLanguage = NativeLocalization.language
        defer { NativeLocalization.language = originalLanguage }

        NativeLocalization.language = .english
        XCTAssertEqual(
            PracticePackValidationError.missingExecutableContent(.drone).errorDescription,
            "The Drone block is missing its practice content."
        )

        NativeLocalization.language = .spanish
        XCTAssertEqual(
            PracticePackValidationError.missingExecutableContent(.drone).errorDescription,
            "Al bloque Nota pedal le falta su contenido de práctica."
        )
    }

    func testInstrumentDisplayNamesUseArabicCatalogValuesInsteadOfCoreFixtureCopy() {
        let originalLanguage = NativeLocalization.language
        defer { NativeLocalization.language = originalLanguage }

        NativeLocalization.language = .arabic
        for profile in InstrumentProfiles.all {
            let localizedName = instrumentDisplayName(profile.id)
            XCTAssertFalse(localizedName.isEmpty, "\(profile.id) must have a localized display name.")
            XCTAssertNotEqual(
                localizedName,
                profile.displayName,
                "\(profile.id) exposed the English shared-domain fixture instead of catalog-backed Arabic copy."
            )
        }
        XCTAssertEqual(instrumentDisplayName("french-horn"), instrumentDisplayName("horn"), "Aliases must resolve through the same localized profile name.")
        XCTAssertEqual(NativeLocalization.string("Unavailable"), "غير متاح")
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
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeFeatureTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let model = makeModel(at: stateURL)
        _ = model.saveCustomExercise(title: "My notes", notes: ["C", "D", "E"])
        model.metronome = MetronomeSettings(bpm: 108, beatsPerMeasure: 3, beatUnit: 4, subdivision: .eighth, muted: false, visualOnly: false, hapticsEnabled: true, volume: 0.35)
        XCTAssertTrue(model.saveMetronomePreset(name: "Waltz"))
        model.updateWeeklyGoal(minutes: 90, sessions: 4)
        model.startOrResumeWarmup(now: Date(timeIntervalSince1970: 1_000))
        model.pauseWarmup(now: Date(timeIntervalSince1970: 1_045))
        model.flushPendingPersistence()

        let restored = makeModel(at: stateURL)
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
    func testPausedWarmupRecordsOnlyActiveTimeAndWeeklyProgress() throws {
        let model = makeModel()
        let start = Date(timeIntervalSince1970: 100_000)
        model.startOrResumeWarmup(now: start)
        model.pauseWarmup(now: start.addingTimeInterval(120))

        let resume = start.addingTimeInterval(10_000)
        model.startOrResumeWarmup(now: resume)
        model.advanceWarmup(now: resume.addingTimeInterval(180))

        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(session.durationSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(session.startedAt, resume.addingTimeInterval(-120))
        let progress = WeeklyPracticeProgress.calculate(
            sessions: model.sessions,
            now: resume.addingTimeInterval(180)
        )
        XCTAssertEqual(progress.minutes, 5)
        XCTAssertEqual(progress.sessionCount, 1)
    }

    func testGuidedWarmupMatchesFiveStepFiveMinuteContract() {
        XCTAssertEqual(GuidedWarmupPlan.fiveMinute.steps.map(\.id), ["breathe", "buzz", "long-tone", "slur", "scale"])
        XCTAssertEqual(GuidedWarmupPlan.fiveMinute.steps.map(\.durationSeconds), [45, 45, 75, 75, 60])
        XCTAssertEqual(GuidedWarmupPlan.fiveMinute.steps.map(\.kind), [.breathe, .buzz, .longTone, .slur, .scale])
        XCTAssertEqual(GuidedWarmupPlan.fiveMinute.durationSeconds, 300)
    }

    func testWarmupStepMigratesMissingKindAndBreathingPhasesAreDeterministic() throws {
        let legacy = Data("""
        {"id":"breathe","title":"Easy breaths","instruction":"Breathe","durationSeconds":45}
        """.utf8)
        XCTAssertEqual(try JSONDecoder().decode(GuidedWarmupStep.self, from: legacy).kind, .breathe)

        XCTAssertEqual(GuidedWarmupBreathingCycle(elapsedInStep: 0).phase, .inhale)
        XCTAssertEqual(GuidedWarmupBreathingCycle(elapsedInStep: 3.999).phase, .inhale)
        XCTAssertEqual(GuidedWarmupBreathingCycle(elapsedInStep: 4).phase, .hold)
        XCTAssertEqual(GuidedWarmupBreathingCycle(elapsedInStep: 5).phase, .exhale)
        XCTAssertEqual(GuidedWarmupBreathingCycle(elapsedInStep: 13).phase, .inhale)
        XCTAssertEqual(GuidedWarmupBreathingCycle(elapsedInStep: 26).cycleNumber, 3)
    }

    func testWarmupCheckpointDerivesStepAndProgressFromOneTimeline() {
        let start = Date(timeIntervalSince1970: 10_000)
        let checkpoint = GuidedWarmupCheckpoint(
            planID: GuidedWarmupPlan.fiveMinute.id,
            firstStartedAt: start,
            accumulatedSeconds: 0,
            runningSince: start,
            completed: false
        )
        let breath = start.addingTimeInterval(17)
        XCTAssertEqual(checkpoint.currentStepIndex(at: breath), 0)
        XCTAssertEqual(checkpoint.elapsedInCurrentStep(at: breath), 17, accuracy: 0.001)
        XCTAssertEqual(checkpoint.stepProgress(at: breath), 17.0 / 45.0, accuracy: 0.001)
        XCTAssertEqual(checkpoint.totalProgress(at: breath), 17.0 / 300.0, accuracy: 0.001)
        XCTAssertEqual(checkpoint.breathingCycle(at: breath)?.phase, .hold)

        let boundary = start.addingTimeInterval(45)
        XCTAssertEqual(checkpoint.currentStepIndex(at: boundary), 1)
        XCTAssertEqual(checkpoint.elapsedInCurrentStep(at: boundary), 0, accuracy: 0.001)
        XCTAssertNil(checkpoint.breathingCycle(at: boundary))
    }

    @MainActor
    func testWarmupStepNavigationPreservesRunningAndPausedSemantics() throws {
        let model = makeModel()
        let start = Date(timeIntervalSince1970: 20_000)
        model.startOrResumeWarmup(now: start)
        model.moveWarmupStep(by: 1, now: start.addingTimeInterval(10))
        XCTAssertEqual(try XCTUnwrap(model.currentWarmupCheckpoint).elapsed(at: start.addingTimeInterval(10)), 45, accuracy: 0.001)
        XCTAssertTrue(model.currentWarmupCheckpoint?.isRunning == true)

        model.pauseWarmup(now: start.addingTimeInterval(20))
        model.skipWarmupStep(now: start.addingTimeInterval(2_000))
        let paused = try XCTUnwrap(model.currentWarmupCheckpoint)
        XCTAssertEqual(paused.accumulatedSeconds, 90, accuracy: 0.001)
        XCTAssertNil(paused.runningSince)
        XCTAssertEqual(paused.currentStepIndex(at: start.addingTimeInterval(9_000)), 2)

        model.moveWarmupStep(by: -1, now: start.addingTimeInterval(9_001))
        XCTAssertEqual(try XCTUnwrap(model.currentWarmupCheckpoint).accumulatedSeconds, 45, accuracy: 0.001)
    }

    @MainActor
    func testWarmupDiscardAndRestartClearOnlyCheckpointAndNeverDuplicateCompletion() {
        let model = makeModel()
        let start = Date(timeIntervalSince1970: 30_000)
        model.startOrResumeWarmup(now: start)
        model.pauseWarmup(now: start.addingTimeInterval(12))
        model.discardWarmup()
        XCTAssertNil(model.currentWarmupCheckpoint)
        XCTAssertTrue(model.sessions.isEmpty)

        model.startOrResumeWarmup(now: start.addingTimeInterval(100))
        model.resetWarmup()
        XCTAssertNil(model.currentWarmupCheckpoint)
        model.startOrResumeWarmup(now: start.addingTimeInterval(200))
        model.advanceWarmup(now: start.addingTimeInterval(500))
        model.advanceWarmup(now: start.addingTimeInterval(800))
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertTrue(model.currentWarmupCheckpoint?.completed == true)
    }

    @MainActor
    func testReflectionCanBeCreatedUpdatedAndDeleted() {
        let model = makeModel()
        let session = makeSession(startedAt: Date(timeIntervalSince1970: 100), duration: 60)
        model.sessions = [session]

        model.saveReflection(sessionID: session.id, mood: .focused, note: "Centered", now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(model.reflection(for: session.id)?.note, "Centered")
        model.saveReflection(sessionID: session.id, mood: .challenging, note: "Needs air", now: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(model.practiceFeatures.reflections.count, 1)
        XCTAssertEqual(model.reflection(for: session.id)?.mood, .challenging)
        model.deleteReflection(sessionID: session.id)
        XCTAssertNil(model.reflection(for: session.id))
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

    func testPracticeStreakUsesLocalCalendarDaysAndIgnoresInvalidOrFutureSessions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 12))!
        let march9Late = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 23, minute: 30))!
        let march10 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 9))!
        let march11 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 8))!
        let march12 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 8))!
        let zeroDuration = PracticeSession(
            id: UUID(), name: "Incomplete", instrumentId: "trumpet", startedAt: march10,
            endedAt: march10, frames: [], retainedRecordingURL: nil
        )

        let summary = PracticeStreakSummary.calculate(
            sessions: [
                makeSession(startedAt: march9Late, duration: 90),
                makeSession(startedAt: march10, duration: 90),
                makeSession(startedAt: march11, duration: 90),
                makeSession(startedAt: march12, duration: 90),
                zeroDuration,
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.currentStreakDays, 3)
        XCTAssertEqual(summary.longestStreakDays, 3)
        XCTAssertEqual(summary.recentDays.count, 7)
        XCTAssertEqual(summary.recentDays.filter(\.practiced).count, 3)
        XCTAssertEqual(calendar.component(.day, from: summary.recentDays.last!.date), 11)
    }

    func testPracticeStreakRemainsActiveWhenYesterdayEndsTheRun() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 10))!
        let april5 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 9))!
        let april6 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 6, hour: 9))!
        let april7 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 7, hour: 9))!

        let summary = PracticeStreakSummary.calculate(
            sessions: [
                makeSession(startedAt: april5, duration: 60),
                makeSession(startedAt: april6, duration: 60),
                makeSession(startedAt: april7, duration: 60),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.currentStreakDays, 3)
        XCTAssertEqual(summary.longestStreakDays, 3)
    }

    func testPracticeStreakYesterdayOnlyIsActiveWithFixedCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 8))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 19))!

        let summary = PracticeStreakSummary.calculate(
            sessions: [makeSession(startedAt: yesterday, duration: 60)],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.currentStreakDays, 1)
        XCTAssertEqual(summary.longestStreakDays, 1)
    }

    func testWeakTransitionRequiresThreeSamplesAndRanksDeterministically() {
        let twoAttempts = [attempt(destinationRating: .off, cents: 42), attempt(destinationRating: .off, cents: 38)]
        XCTAssertNil(WeakTransitionAnalyzer.insight(from: twoAttempts))

        let insight = WeakTransitionAnalyzer.insight(from: twoAttempts + [attempt(destinationRating: .missed, cents: 50)])
        XCTAssertEqual(insight?.fromNote, "D")
        XCTAssertEqual(insight?.toNote, "F#")
        XCTAssertEqual(insight?.evidenceCount, 3)
        XCTAssertEqual(insight?.exercise.writtenNotes, ["D", "F#", "D", "F#", "D", "F#"])
    }

    func testToneMathCoversAliasesAndFailsClosedForUnknownInstrument() throws {
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "trumpet"), 2)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "cornet"), 2)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "flugelhorn"), 2)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "baritone"), 14)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "euphonium-treble"), 14)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "horn"), 7)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "french-horn"), 7)
        XCTAssertEqual(PracticePitchMath.transpositionSemitones(for: "trombone"), 0)
        XCTAssertNil(PracticePitchMath.transpositionSemitones(for: "mystery-horn"))
        XCTAssertNil(PracticePitchMath.frequency(writtenMIDI: 69, instrumentID: "mystery-horn", referencePitchHz: 440))

        let trumpetA = try XCTUnwrap(PracticePitchMath.frequency(writtenMIDI: 71, instrumentID: "trumpet", referencePitchHz: 440))
        XCTAssertEqual(trumpetA, 440, accuracy: 0.01)
        let hornFifth = try XCTUnwrap(PracticePitchMath.frequency(writtenMIDI: 60, interval: .perfectFifth, instrumentID: "horn", referencePitchHz: 440))
        XCTAssertEqual(hornFifth, 261.625, accuracy: 0.01)

        XCTAssertEqual(TuningInterval.allCases, [.unison, .majorSecond, .majorThird, .perfectFourth, .perfectFifth, .octave])
        let unison = try XCTUnwrap(PracticePitchMath.frequencies(writtenMIDI: 71, interval: .unison, instrumentID: "trumpet", referencePitchHz: 440))
        XCTAssertEqual(unison.count, 1)
        XCTAssertEqual(unison[0], 440, accuracy: 0.01)
        let fifth = try XCTUnwrap(PracticePitchMath.frequencies(writtenMIDI: 71, interval: .perfectFifth, instrumentID: "trumpet", referencePitchHz: 440))
        XCTAssertEqual(fifth.count, 2)
        XCTAssertEqual(fifth[0], 440, accuracy: 0.01)
        XCTAssertEqual(fifth[1], 659.255, accuracy: 0.01)
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
    func testWorkspaceMovesOneBlockAtATimeAndSavesCompletion() async {
        let model = makeModel()
        let pack = PracticePack(
            id: "workspace-navigation-test",
            name: "Workspace navigation test",
            detail: "Two instruction-only blocks avoid starting audio in a clock/navigation test.",
            blocks: [
                PracticePackBlock(
                    title: "Block one",
                    instruction: "Practice deliberately.",
                    kind: .instruction,
                    durationSeconds: 120
                ),
                PracticePackBlock(
                    title: "Block two",
                    instruction: "Continue deliberately.",
                    kind: .instruction,
                    durationSeconds: 120
                ),
            ],
            isBuiltIn: false
        )
        let start = Date(timeIntervalSince1970: 20_000)
        model.startWorkspace(pack: pack, now: start)
        XCTAssertEqual(model.currentWorkspaceCheckpoint?.blockIndex, 0)
        XCTAssertEqual(model.practiceFeatures.recents.first?.referenceID, pack.id)

        await model.beginWorkspaceCurrentBlock(now: start)
        model.moveWorkspace(by: 1, now: start.addingTimeInterval(30))
        XCTAssertEqual(model.currentWorkspaceCheckpoint?.blockIndex, 1)
        await model.beginWorkspaceCurrentBlock(now: start.addingTimeInterval(30))
        model.moveWorkspace(by: 99, now: start.addingTimeInterval(60))
        XCTAssertEqual(model.currentWorkspaceCheckpoint?.blockIndex, pack.blocks.count - 1)

        model.finishWorkspace(now: start.addingTimeInterval(60))
        XCTAssertTrue(model.currentWorkspaceCheckpoint?.completed == true)
        XCTAssertEqual(model.sessions.first?.name, pack.name)
    }

    @MainActor
    func testPausedWorkspaceRecordsActiveTimeAcrossBlocksInsteadOfWallClock() async throws {
        let model = makeModel()
        let pack = PracticePack(
            id: "active-time-test",
            name: "Active time test",
            detail: "Two instruction blocks",
            blocks: [
                PracticePackBlock(
                    title: "Block one",
                    instruction: "Play",
                    kind: .instruction,
                    durationSeconds: 100
                ),
                PracticePackBlock(
                    title: "Block two",
                    instruction: "Play",
                    kind: .instruction,
                    durationSeconds: 100
                ),
            ],
            isBuiltIn: false
        )
        let start = Date(timeIntervalSince1970: 200_000)
        model.startWorkspace(pack: pack, now: start)
        await model.beginWorkspaceCurrentBlock(now: start)
        model.pauseWorkspace(now: start.addingTimeInterval(30))

        let secondBlockStart = start.addingTimeInterval(10_000)
        model.moveWorkspace(by: 1, now: secondBlockStart)
        await model.beginWorkspaceCurrentBlock(now: secondBlockStart)
        model.finishWorkspace(now: secondBlockStart.addingTimeInterval(40))

        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(session.durationSeconds, 70, accuracy: 0.001)
        XCTAssertEqual(session.startedAt, secondBlockStart.addingTimeInterval(-30))
        let progress = WeeklyPracticeProgress.calculate(
            sessions: model.sessions,
            now: secondBlockStart.addingTimeInterval(40)
        )
        XCTAssertEqual(progress.minutes, 1)
        XCTAssertEqual(progress.sessionCount, 1)
    }

    @MainActor
    private func makeModel(at url: URL? = nil) -> AppModel {
        let fileURL = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeFeatureTests-\(UUID().uuidString).json")
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: fileURL),
            scoreStorageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        model.enterGuestDemo(presentTutorial: false)
        return model
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

    private func sharedFixtureURL(named name: String) throws -> URL {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["BRASSTUNE_SHARED_FIXTURES_DIR"] {
            let url = URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("fixtures", isDirectory: true).appendingPathComponent(name)
        guard fileManager.fileExists(atPath: url.path) else {
            throw XCTSkip("Shared fixture \(name) is not present in this isolated worktree.")
        }
        return url
    }
}
