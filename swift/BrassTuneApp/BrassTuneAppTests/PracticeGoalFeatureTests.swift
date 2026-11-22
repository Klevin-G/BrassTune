import Foundation
import XCTest
@testable import BrassTuneApp

final class PracticeGoalFeatureTests: XCTestCase {
    func testTempoLadderReachesExactTargetAndCanStepBackOrRepeat() {
        var ladder = PracticeTempoLadder(startBPM: 72, targetBPM: 84, stepBPM: 5)
        XCTAssertEqual(ladder.currentBPM, 72)
        ladder.advance()
        XCTAssertEqual(ladder.currentBPM, 77)
        ladder.advance()
        XCTAssertEqual(ladder.currentBPM, 82)
        ladder.advance()
        XCTAssertEqual(ladder.currentBPM, 84)
        ladder.advance()
        XCTAssertEqual(ladder.currentBPM, 84)
        ladder.stepBack()
        XCTAssertEqual(ladder.currentBPM, 82)
        ladder.stepBack()
        XCTAssertEqual(ladder.currentBPM, 77)
        ladder.stepBack()
        ladder.stepBack()
        XCTAssertEqual(ladder.currentBPM, 72)
        ladder.setStep(3)
        ladder.advance()
        XCTAssertEqual(ladder.currentBPM, 75)
        ladder.setStart(80)
        XCTAssertEqual(ladder.currentBPM, 80)
        ladder.advance()
        ladder.advance()
        XCTAssertEqual(ladder.currentBPM, 84)
    }

    func testTempoLadderSuggestedStartUsesLowerRecordedTempoOrSlowerDefault() {
        XCTAssertEqual(PracticeTempoLadder.suggestedStart(targetBPM: 80, recordedBPM: nil), 65)
        XCTAssertEqual(PracticeTempoLadder.suggestedStart(targetBPM: 80, recordedBPM: 70), 70)
        XCTAssertEqual(PracticeTempoLadder.suggestedStart(targetBPM: 80, recordedBPM: 90), 65)
        XCTAssertEqual(PracticeTempoLadder.suggestedStart(targetBPM: 35, recordedBPM: nil), 30)
    }

    func testTempoLadderClampsLegacyRecordedTempoAndBounds() {
        let aboveTarget = PracticeTempoLadder(startBPM: 120, targetBPM: 80, stepBPM: 0)
        XCTAssertEqual(aboveTarget.startBPM, 80)
        XCTAssertEqual(aboveTarget.stepBPM, 1)
        var low = PracticeTempoLadder(startBPM: -1, targetBPM: 30, stepBPM: 99)
        XCTAssertEqual(low.startBPM, 30)
        XCTAssertEqual(low.stepBPM, 20)
        low.advance()
        XCTAssertEqual(low.currentBPM, 30)
    }

    func testFailedAttemptPreservesZeroMeasurementsWithoutLoweringTargetMinimums() throws {
        let attempt = PracticeGoalAttempt(
            outcome: .notYet, reflection: "Restarted before completing the phrase.", nextAdjustment: "Try a shorter section.",
            achievedTempoBPM: 60, achievedCleanRepetitions: 0, achievedSustainSeconds: 0
        )
        let restored = try JSONDecoder().decode(PracticeGoalAttempt.self, from: JSONEncoder().encode(attempt))
        XCTAssertEqual(restored.achievedCleanRepetitions, 0)
        XCTAssertEqual(restored.achievedSustainSeconds, 0)
        XCTAssertEqual(PracticeGoalCriterion(targetCleanRepetitions: 0).targetCleanRepetitions, 1)
        XCTAssertEqual(PracticeGoalCriterion(targetSustainSeconds: 0).targetSustainSeconds, 2)
    }

    @MainActor
    func testNarrativeOnlyAndMeasuredFailedAttemptsPersistDistinctEvidence() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeGoalMeasurementEvidence-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let model = makeModel(at: stateURL)
        let goalID = UUID()
        model.savePracticeGoal(
            id: goalID,
            passage: "Opening attacks",
            skill: .articulation,
            criterion: PracticeGoalCriterion(kind: .cleanRepetitions, targetTempoBPM: 80, targetCleanRepetitions: 3),
            strategy: .slowPractice,
            nextReviewAt: Date(timeIntervalSince1970: 2_000),
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertTrue(model.logPracticeGoalAttempt(
            goalID: goalID,
            outcome: .improving,
            reflection: "The starts felt easier.",
            nextAdjustment: "Keep the phrase short.",
            achievedTempoBPM: nil,
            achievedCleanRepetitions: nil,
            achievedSustainSeconds: nil,
            now: Date(timeIntervalSince1970: 1_100)
        ))
        XCTAssertTrue(model.logPracticeGoalAttempt(
            goalID: goalID,
            outcome: .notYet,
            reflection: "Stopped after the first attack.",
            nextAdjustment: "Begin with one note.",
            achievedTempoBPM: nil,
            achievedCleanRepetitions: 0,
            achievedSustainSeconds: nil,
            now: Date(timeIntervalSince1970: 1_200)
        ))
        model.flushPendingPersistence()

        let restored = makeModel(at: stateURL)
        let attempts = try XCTUnwrap(restored.practiceFeatures.measurableGoals.first?.attempts)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[0].outcome, .notYet)
        XCTAssertNil(attempts[0].achievedTempoBPM)
        XCTAssertEqual(attempts[0].achievedCleanRepetitions, 0)
        XCTAssertNil(attempts[1].achievedTempoBPM)
        XCTAssertNil(attempts[1].achievedCleanRepetitions)
        XCTAssertEqual(attempts[1].criterionSnapshot?.targetTempoBPM, 80)
        XCTAssertEqual(restored.practiceFeatures.measurableGoals.first?.recommendedMetronomeTempoBPM, 80)
    }

    func testNextReviewGoalPrioritizesDueActiveGoalWithDeterministicOrdering() {
        let dueEarlier = PracticeGoal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            passage: "Due first", skill: .tone, criterion: PracticeGoalCriterion(), strategy: .listenFirst,
            nextReviewAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 20)
        )
        let dueLater = PracticeGoal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            passage: "Due later", skill: .tone, criterion: PracticeGoalCriterion(), strategy: .listenFirst,
            nextReviewAt: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 30)
        )
        let completed = PracticeGoal(
            passage: "Completed", skill: .tone, criterion: PracticeGoalCriterion(), strategy: .listenFirst,
            completedAt: Date(timeIntervalSince1970: 50), nextReviewAt: Date(timeIntervalSince1970: 10)
        )
        let next = PracticeGoal.nextReviewGoal(in: [dueLater, completed, dueEarlier], now: Date(timeIntervalSince1970: 500))
        XCTAssertEqual(next?.id, dueEarlier.id)
    }

    func testReviewIsDueForTheSelectedCalendarDayRegardlessOfStoredTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dueLaterToday = PracticeGoal(
            passage: "Same-day review", skill: .rhythm, criterion: PracticeGoalCriterion(), strategy: .chunking,
            nextReviewAt: DateComponents(calendar: calendar, year: 2026, month: 10, day: 22, hour: 23, minute: 59).date!
        )
        let tomorrow = PracticeGoal(
            passage: "Tomorrow", skill: .rhythm, criterion: PracticeGoalCriterion(), strategy: .chunking,
            nextReviewAt: DateComponents(calendar: calendar, year: 2026, month: 10, day: 23, hour: 0).date!
        )
        let morning = DateComponents(calendar: calendar, year: 2026, month: 10, day: 22, hour: 8).date!

        XCTAssertTrue(dueLaterToday.isDueForReview(now: morning, calendar: calendar))
        XCTAssertEqual(
            PracticeGoal.nextReviewGoal(in: [tomorrow, dueLaterToday], now: morning, calendar: calendar)?.id,
            dueLaterToday.id
        )
    }

    func testReviewPriorityOrdersActiveGoalsAndKeepsFocusedGoalFirstWithoutMutatingInput() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ day: Int, _ hour: Int = 0) -> Date {
            DateComponents(calendar: calendar, year: 2026, month: 10, day: day, hour: hour).date!
        }
        func goal(_ number: Int, day: Int, hour: Int = 0, updated: Int = 0, completed: Bool = false) -> PracticeGoal {
            PracticeGoal(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
                passage: "Goal \(number)", skill: .tone, criterion: PracticeGoalCriterion(targetTempoBPM: 81),
                strategy: .listenFirst, completedAt: completed ? date(20) : nil,
                nextReviewAt: date(day, hour), updatedAt: date(20, updated)
            )
        }
        let overdue = goal(1, day: 21)
        let todayEarly = goal(2, day: 22, hour: 8)
        let todayTieLaterUpdate = goal(3, day: 22, hour: 8, updated: 2)
        let todayTieSameUpdate = goal(4, day: 22, hour: 8, updated: 2)
        let future = goal(5, day: 23)
        let completed = goal(6, day: 19, completed: true)
        let input = [future, completed, todayTieSameUpdate, todayEarly, overdue, todayTieLaterUpdate]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encodedBefore = try encoder.encode(input)
        let ordered = PracticeGoal.reviewPriority(in: input)
        XCTAssertEqual(ordered.map(\.id), [overdue, todayTieLaterUpdate, todayTieSameUpdate, todayEarly, future, completed].map(\.id))
        XCTAssertEqual(PracticeGoal.reviewPriority(in: input, focusedGoalID: future.id).map(\.id),
                       [future, overdue, todayTieLaterUpdate, todayTieSameUpdate, todayEarly, completed].map(\.id))
        XCTAssertEqual(PracticeGoal.reviewPriority(in: input, focusedGoalID: completed.id).first?.id, completed.id)
        XCTAssertEqual(PracticeGoal.nextReviewGoal(in: input, now: date(22), calendar: calendar)?.id, overdue.id)
        XCTAssertTrue(todayEarly.isDueForReview(now: date(22), calendar: calendar))
        XCTAssertFalse(completed.isDueForReview(now: date(22), calendar: calendar))
        XCTAssertEqual(try encoder.encode(input), encodedBefore)
        XCTAssertEqual(try JSONDecoder().decode([PracticeGoal].self, from: encodedBefore), input)
        XCTAssertEqual(input.first?.criterion.targetTempoBPM, 81)
    }

    func testOnlyRepetitionGoalsOfferMetronomePractice() {
        let repetitions = PracticeGoal(
            passage: "Articulation", skill: .articulation,
            criterion: PracticeGoalCriterion(kind: .cleanRepetitions), strategy: .slowPractice
        )
        let sustainedTone = PracticeGoal(
            passage: "Long tone", skill: .tone,
            criterion: PracticeGoalCriterion(kind: .sustainedTone), strategy: .listenFirst
        )

        XCTAssertTrue(repetitions.supportsMetronomePractice)
        XCTAssertFalse(sustainedTone.supportsMetronomePractice)
    }

    @MainActor
    func testAttemptReschedulesReviewToTomorrowOrSelectedDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(calendar: calendar, year: 2026, month: 10, day: 22, hour: 12).date!
        let selectedReview = DateComponents(calendar: calendar, year: 2026, month: 10, day: 25, hour: 23).date!
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeGoalReviewSchedule-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let model = makeModel(at: stateURL)
        let goalID = UUID()
        model.savePracticeGoal(
            id: goalID, passage: "Due today", skill: .rhythm, criterion: PracticeGoalCriterion(),
            strategy: .chunking, nextReviewAt: now, now: now
        )

        XCTAssertTrue(model.logPracticeGoalAttempt(
            goalID: goalID, outcome: .notYet, reflection: "Not steady yet.", nextAdjustment: "Slow down.",
            achievedTempoBPM: nil, achievedCleanRepetitions: nil, achievedSustainSeconds: nil,
            now: now, calendar: calendar
        ))
        let tomorrow = try! XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        XCTAssertEqual(model.practiceFeatures.measurableGoals[0].nextReviewAt, tomorrow)
        XCTAssertFalse(model.practiceFeatures.measurableGoals[0].isDueForReview(now: now, calendar: calendar))

        XCTAssertTrue(model.logPracticeGoalAttempt(
            goalID: goalID, outcome: .improving, reflection: "More even.", nextAdjustment: "Repeat it.",
            achievedTempoBPM: nil, achievedCleanRepetitions: nil, achievedSustainSeconds: nil,
            nextReviewAt: selectedReview, now: now, calendar: calendar
        ))
        XCTAssertEqual(model.practiceFeatures.measurableGoals[0].nextReviewAt, selectedReview)
        model.flushPendingPersistence()
        XCTAssertEqual(makeModel(at: stateURL).practiceFeatures.measurableGoals.first?.nextReviewAt, selectedReview)
    }

    func testRecommendedMetronomeTempoUsesLatestRecordedTempoEvenAfterNarrativeAttempt() {
        let goal = PracticeGoal(
            passage: "Articulation", skill: .articulation,
            criterion: PracticeGoalCriterion(kind: .cleanRepetitions, targetTempoBPM: 80),
            strategy: .slowPractice,
            attempts: [
                PracticeGoalAttempt(
                    outcome: .improving, reflection: "Narrative only.", nextAdjustment: "Keep going.",
                    createdAt: Date(timeIntervalSince1970: 200)
                ),
                PracticeGoalAttempt(
                    outcome: .notYet, reflection: "Measured tempo.", nextAdjustment: "Slow down.",
                    achievedTempoBPM: 72, achievedCleanRepetitions: 0,
                    createdAt: Date(timeIntervalSince1970: 100)
                ),
            ]
        )

        XCTAssertEqual(goal.mostRecentRecordedTempoBPM, 72)
        XCTAssertEqual(goal.recommendedMetronomeTempoBPM, 72)
    }

    func testGoalStateMigratesMissingReviewDateAndSkipsUnknownFutureGoal() throws {
        let data = Data(#"""
        {
          "measurableGoals": [
            {"id":"00000000-0000-0000-0000-000000000001","passage":"Future","skill":"future_skill","criterion":{"kind":"clean_repetitions","targetTempoBPM":90,"targetCleanRepetitions":3,"targetSustainSeconds":8},"strategy":"slow_practice","attempts":[],"updatedAt":"2026-10-12T00:00:00Z"},
            {"id":"00000000-0000-0000-0000-000000000002","passage":"Etude 4","skill":"articulation","criterion":{"kind":"clean_repetitions","targetTempoBPM":999,"targetCleanRepetitions":0,"targetSustainSeconds":999},"strategy":"slow_practice","attempts":[],"updatedAt":"2026-10-12T00:00:00Z"}
          ]
        }
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(PracticeFeatureState.self, from: data)

        let goal = try XCTUnwrap(state.measurableGoals.first)
        XCTAssertEqual(state.measurableGoals.count, 1)
        XCTAssertEqual(goal.passage, "Etude 4")
        XCTAssertEqual(goal.criterion.targetTempoBPM, PracticeGoalCriterion.tempoRange.upperBound)
        XCTAssertEqual(goal.criterion.targetCleanRepetitions, PracticeGoalCriterion.repetitionRange.lowerBound)
        XCTAssertEqual(goal.criterion.targetSustainSeconds, PracticeGoalCriterion.sustainSecondsRange.upperBound)
        XCTAssertGreaterThan(goal.nextReviewAt, goal.updatedAt)
    }

    @MainActor
    func testGoalAttemptPersistsSelfReportedMeasurementsAndHistoricalSnapshots() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeGoalFeatureTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let model = makeModel(at: stateURL)
        let goalID = UUID()
        let reviewDate = Date(timeIntervalSince1970: 2_000)
        model.savePracticeGoal(
            id: goalID,
            passage: "Opening phrase",
            skill: .articulation,
            criterion: PracticeGoalCriterion(kind: .cleanRepetitions, targetTempoBPM: 96, targetCleanRepetitions: 4),
            strategy: .chunking,
            nextReviewAt: reviewDate,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertTrue(model.logPracticeGoalAttempt(
            goalID: goalID,
            outcome: .improving,
            reflection: "Attacks were clearer after a reset.",
            nextAdjustment: "Repeat the last two beats slowly.",
            achievedTempoBPM: 88,
            achievedCleanRepetitions: 3,
            achievedSustainSeconds: nil,
            nextReviewAt: reviewDate,
            now: Date(timeIntervalSince1970: 1_100)
        ))
        XCTAssertTrue(model.logPracticeGoalAttempt(
            goalID: goalID,
            outcome: .met,
            reflection: "The phrase stayed clean at the target tempo.",
            nextAdjustment: "Revisit the same target tomorrow.",
            achievedTempoBPM: 96,
            achievedCleanRepetitions: 4,
            achievedSustainSeconds: nil,
            nextReviewAt: reviewDate,
            now: Date(timeIntervalSince1970: 1_150)
        ))
        model.completePracticeGoal(id: goalID, now: Date(timeIntervalSince1970: 1_200))
        XCTAssertTrue(model.practiceFeatures.measurableGoals[0].isCompleted)
        model.reopenPracticeGoal(id: goalID, now: Date(timeIntervalSince1970: 1_300))
        XCTAssertFalse(model.practiceFeatures.measurableGoals[0].isCompleted)
        model.flushPendingPersistence()

        let restored = makeModel(at: stateURL)
        let attempt = try XCTUnwrap(restored.practiceFeatures.measurableGoals.first?.attempts.first)
        XCTAssertEqual(restored.practiceFeatures.measurableGoals.first?.attempts.count, 2)
        XCTAssertEqual(attempt.achievedTempoBPM, 96)
        XCTAssertEqual(attempt.achievedCleanRepetitions, 4)
        XCTAssertEqual(attempt.criterionSnapshot?.targetTempoBPM, 96)
        XCTAssertEqual(attempt.strategySnapshot, .chunking)
        XCTAssertEqual(restored.practiceFeatures.measurableGoals.first?.nextReviewAt, reviewDate)
    }

    func testAccountScopedPersistenceDoesNotShareGoals() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeGoalAccountIsolation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = NativePersistenceStore.ephemeral(fileURL: directory.appendingPathComponent("native-local-state.json"))
        var features = PracticeFeatureState()
        features.measurableGoals = [
            PracticeGoal(passage: "Solo excerpt", skill: .tone, criterion: PracticeGoalCriterion(), strategy: .listenFirst)
        ]
        let snapshot = NativeLocalSnapshot(
            selectedInstrumentId: "trumpet",
            referencePitchHz: 440,
            sessions: [],
            scores: [],
            activeScoreID: nil,
            metronome: MetronomeSettings(),
            practiceFeatures: features
        )
        try base.scoped(to: .account(userID: "account-a")).saveOrThrow(snapshot)

        XCTAssertEqual(try base.scoped(to: .account(userID: "account-a")).load()?.practiceFeatures?.measurableGoals.count, 1)
        XCTAssertNil(try base.scoped(to: .account(userID: "account-b")).load())
    }

    @MainActor
    func testGoalCreationCapRejectsOnlyNewGoals() {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeGoalLimit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let model = makeModel(at: stateURL)
        for index in 0..<PracticeGoal.maximumGoals {
            XCTAssertTrue(model.savePracticeGoal(
                passage: "Target \(index)",
                skill: .accuracy,
                criterion: PracticeGoalCriterion(),
                strategy: .slowPractice,
                nextReviewAt: Date()
            ))
        }
        XCTAssertFalse(model.savePracticeGoal(
            passage: "Over limit",
            skill: .accuracy,
            criterion: PracticeGoalCriterion(),
            strategy: .slowPractice,
            nextReviewAt: Date()
        ))
        XCTAssertEqual(model.practiceFeatures.measurableGoals.count, PracticeGoal.maximumGoals)
    }

    func testPersistenceRetainsMergedGoalHistoryBeyondCreationCap() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeGoalMergedHistory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativePersistenceStore.ephemeral(fileURL: directory.appendingPathComponent("native-local-state.json"))
        var features = PracticeFeatureState()
        features.measurableGoals = (0..<48).map { index in
            PracticeGoal(
                passage: "Merged excerpt \(index)",
                skill: .rhythm,
                criterion: PracticeGoalCriterion(),
                strategy: .slowPractice,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        try store.saveOrThrow(NativeLocalSnapshot(
            selectedInstrumentId: "trumpet",
            referencePitchHz: 440,
            sessions: [],
            scores: [],
            activeScoreID: nil,
            metronome: MetronomeSettings(),
            practiceFeatures: features
        ))

        XCTAssertEqual(try store.load()?.practiceFeatures?.measurableGoals.count, 48)
    }

    @MainActor
    func testExportIncludesMeasurableGoalsWithoutCredentialFields() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeGoalExport-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let model = makeModel(at: stateURL)
        model.savePracticeGoal(
            passage: "Cadenza",
            skill: .tone,
            criterion: PracticeGoalCriterion(kind: .sustainedTone, targetSustainSeconds: 10),
            strategy: .listenFirst,
            nextReviewAt: Date(timeIntervalSince1970: 1_000)
        )
        let data = try XCTUnwrap(model.exportDataText().data(using: .utf8))
        let export = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let goals = try XCTUnwrap(export["measurableGoals"] as? [[String: Any]])

        XCTAssertEqual(export["schemaVersion"] as? Int, 2)
        XCTAssertEqual(goals.count, 1)
        XCTAssertEqual(goals.first?["passage"] as? String, "Cadenza")
        XCTAssertNil(export["accessToken"])
        XCTAssertNil(export["refreshToken"])
    }

    @MainActor
    private func makeModel(at url: URL) -> AppModel {
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: url),
            scoreStorageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        model.enterGuestDemo(presentTutorial: false)
        return model
    }
}
