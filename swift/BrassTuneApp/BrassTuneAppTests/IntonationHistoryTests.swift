import XCTest
@testable import BrassTuneApp
import BrassTuneCore

final class IntonationHistoryTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_730_000_000)

    func testMonthOfPracticeAnalysisPerformance() {
        let sessions = (0..<150).map { index in
            take(dayOffset: -1 - index % 29, cents: 16, frameCount: 2700)
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(options: options) {
            let result = IntonationHistory(sessions: sessions, instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
            XCTAssertEqual(result.qualifyingTakeCount, 150)
            XCTAssertEqual(result.notes.first?.takeCount, 150)
        }
    }

    func testFiltersMixedMetadataAndRequiresIndependentDays() throws {
        let included = [take(dayOffset: -8, cents: 9), take(dayOffset: -5, cents: 11), take(dayOffset: -1, cents: 10)]
        let excluded = [
            take(dayOffset: -2, cents: 40, instrument: "horn"),
            take(dayOffset: -2, cents: 40, reference: 442),
            take(dayOffset: -2, cents: 40, source: .sample),
            take(dayOffset: 1, cents: 40),
            take(dayOffset: -31, cents: 40),
            take(dayOffset: -2, cents: 40, completion: .discarded),
        ]
        let history = IntonationHistory(sessions: included + excluded, instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        let note = try XCTUnwrap(history.notes.first)
        XCTAssertEqual(note.takeCount, 3)
        XCTAssertEqual(note.dayCount, 3)
        XCTAssertTrue(note.isRecurring)
        XCTAssertEqual(note.medianSignedCents, 10, accuracy: 0.001)
    }

    func testEqualTakeWeightAndDuplicateIDsDoNotInflateLongCapture() throws {
        let id = UUID()
        let long = take(dayOffset: -7, cents: 30, frameCount: 40, id: id)
        let duplicate = take(dayOffset: -7, cents: 30, frameCount: 40, id: id)
        let history = IntonationHistory(sessions: [long, duplicate, take(dayOffset: -5, cents: 0), take(dayOffset: -1, cents: 0)], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        let note = try XCTUnwrap(history.notes.first)
        XCTAssertEqual(note.takeCount, 3)
        XCTAssertEqual(note.medianSignedCents, 0, accuracy: 0.001)
    }

    func testRejectsInvalidSparseAndInconsistentTransposedFrames() {
        var invalid = take(dayOffset: -2, cents: 10, frameCount: 8)
        invalid.frames = invalid.frames.map { frame in
            PitchFrame(timestampMs: frame.timestampMs, frequencyHz: .nan, confidence: frame.confidence, rms: frame.rms, centsDeviation: .nan, tuningStatus: .sharp, writtenNoteName: frame.writtenNoteName, writtenOctave: frame.writtenOctave, isValidForRecording: true)
        }
        let sparse = take(dayOffset: -1, cents: 10, frameCount: 2)
        var mismapped = take(dayOffset: -3, cents: 10, instrument: "horn")
        mismapped.frames = mismapped.frames.map { frame in
            PitchFrame(timestampMs: frame.timestampMs, frequencyHz: frame.frequencyHz, confidence: frame.confidence, rms: frame.rms, centsDeviation: frame.centsDeviation, tuningStatus: frame.tuningStatus, writtenNoteName: "C", writtenOctave: 4, isValidForRecording: true)
        }
        XCTAssertTrue(IntonationHistory(sessions: [invalid, sparse], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar).notes.isEmpty)
        XCTAssertTrue(IntonationHistory(sessions: [mismapped], instrumentID: "horn", referencePitchHz: 440, now: now, calendar: calendar).notes.isEmpty)
    }

    func testRejectsLowConfidenceSilenceAndConflictingDuplicateSessionsRegardlessOfOrder() {
        var lowConfidence = take(dayOffset: -3, cents: 12)
        lowConfidence.frames = lowConfidence.frames.map { frame in
            PitchFrame(timestampMs: frame.timestampMs, frequencyHz: frame.frequencyHz, confidence: 0.1, rms: frame.rms, centsDeviation: frame.centsDeviation, tuningStatus: .sharp, writtenNoteName: frame.writtenNoteName, writtenOctave: frame.writtenOctave, isValidForRecording: true)
        }
        var silence = take(dayOffset: -2, cents: 12)
        silence.frames = silence.frames.map { frame in
            PitchFrame(timestampMs: frame.timestampMs, frequencyHz: frame.frequencyHz, confidence: frame.confidence, rms: 0, centsDeviation: frame.centsDeviation, tuningStatus: .sharp, writtenNoteName: frame.writtenNoteName, writtenOctave: frame.writtenOctave, isValidForRecording: true)
        }
        XCTAssertTrue(IntonationHistory(sessions: [lowConfidence, silence], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar).notes.isEmpty)

        let id = UUID()
        let first = take(dayOffset: -5, cents: 12, id: id)
        let conflict = take(dayOffset: -5, cents: -12, id: id)
        let forward = IntonationHistory(sessions: [first, conflict], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        let reversed = IntonationHistory(sessions: [conflict, first], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        XCTAssertTrue(forward.notes.isEmpty)
        XCTAssertTrue(reversed.notes.isEmpty)
    }

    func testDistinctTimestampAndCaptureDurationGates() {
        let eightSamples = take(dayOffset: -3, cents: 12, frameCount: 8)
        XCTAssertTrue(IntonationHistory(sessions: [eightSamples], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar).notes.isEmpty)

        var duplicateTimestamp = take(dayOffset: -3, cents: 12, frameCount: 9)
        duplicateTimestamp.frames.append(duplicateTimestamp.frames[8])
        XCTAssertEqual(IntonationHistory(sessions: [duplicateTimestamp], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar).notes.first?.takeCount, 1)

        var largeOffset = take(dayOffset: -3, cents: 12)
        largeOffset.frames = largeOffset.frames.map { frame in
            PitchFrame(timestampMs: frame.timestampMs + 60_000, frequencyHz: frame.frequencyHz, confidence: frame.confidence, rms: frame.rms, centsDeviation: frame.centsDeviation, tuningStatus: frame.tuningStatus, writtenNoteName: frame.writtenNoteName, writtenOctave: frame.writtenOctave, isValidForRecording: frame.isValidForRecording)
        }
        XCTAssertEqual(IntonationHistory(sessions: [largeOffset], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar).notes.first?.takeCount, 1)

        var oversizedSpan = take(dayOffset: -3, cents: 12)
        let last = oversizedSpan.frames.count - 1
        let frame = oversizedSpan.frames[last]
        oversizedSpan.frames[last] = PitchFrame(timestampMs: 10_000, frequencyHz: frame.frequencyHz, confidence: frame.confidence, rms: frame.rms, centsDeviation: frame.centsDeviation, tuningStatus: frame.tuningStatus, writtenNoteName: frame.writtenNoteName, writtenOctave: frame.writtenOctave, isValidForRecording: frame.isValidForRecording)
        XCTAssertTrue(IntonationHistory(sessions: [oversizedSpan], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar).notes.isEmpty)
    }

    func testCalibrationBoundaryPriorityAndGoalIdentity() throws {
        let accepted = IntonationHistory(sessions: [take(dayOffset: -3, cents: 12, reference: 440.0500001)], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        XCTAssertEqual(accepted.notes.first?.takeCount, 1)
        XCTAssertTrue(IntonationHistory(sessions: [take(dayOffset: -3, cents: 12, reference: 440.051)], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar).notes.isEmpty)

        let recurring = [take(dayOffset: -8, cents: 12), take(dayOffset: -5, cents: 12), take(dayOffset: -1, cents: 12)]
        let sparseOutlier = take(dayOffset: -2, cents: -80, concertMIDI: 71)
        let history = IntonationHistory(sessions: recurring + [sparseOutlier], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        let note = try XCTUnwrap(history.notes.first)
        XCTAssertTrue(note.hasActionableBias)
        XCTAssertEqual(IntonationHistory.suggestedSustainSeconds(for: note), 8)
        XCTAssertNotEqual(IntonationHistory.sustainedToneGoalID(instrumentID: "trumpet", note: note), IntonationHistory.sustainedToneGoalID(instrumentID: "horn", note: note))
    }

    func testDirectionThresholdAndGoalBoundsAreSafe() throws {
        let history = IntonationHistory(sessions: [take(dayOffset: -8, cents: 18), take(dayOffset: -6, cents: 16), take(dayOffset: -3, cents: 14), take(dayOffset: -1, cents: 16)], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        let note = try XCTUnwrap(history.notes.first)
        XCTAssertEqual(note.direction, .above)
        XCTAssertTrue(note.hasActionableBias)
        XCTAssertTrue(PracticeGoalCriterion.sustainSecondsRange.contains(IntonationHistory.suggestedSustainSeconds(for: note)))
        XCTAssertEqual(
            IntonationHistory.sustainedToneGoalID(instrumentID: "trumpet", note: note),
            IntonationHistory.sustainedToneGoalID(instrumentID: "trumpet", note: note)
        )

        let mixed = IntonationHistory(sessions: [take(dayOffset: -8, cents: 18), take(dayOffset: -7, cents: 16), take(dayOffset: -6, cents: 14), take(dayOffset: -3, cents: -12), take(dayOffset: -1, cents: -10)], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(mixed.notes.first).direction, .centeredOrMixed)

        let twoThirds = IntonationHistory(sessions: [take(dayOffset: -8, cents: 12), take(dayOffset: -6, cents: 11), take(dayOffset: -1, cents: -14)], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(twoThirds.notes.first).direction, .above)

        let roundedBoundary = IntonationHistory(sessions: [take(dayOffset: -8, cents: 9.96), take(dayOffset: -6, cents: 9.96), take(dayOffset: -1, cents: 9.96)], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(roundedBoundary.notes.first).medianSignedCents, 10.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(roundedBoundary.notes.first).direction, .above)

        let sparse = IntonationHistory(sessions: [take(dayOffset: -1, cents: 40)], instrumentID: "trumpet", referencePitchHz: 440, now: now, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(sparse.notes.first).direction, .centeredOrMixed)
    }

    func testGoalMergePreservesConflictingHistoriesAndSkipsIdAgnosticReplays() {
        let sharedID = UUID()
        let account = goal(id: sharedID, passage: "Account", attemptNote: "Account attempt")
        let guest = goal(id: sharedID, passage: "Guest", attemptNote: "Guest attempt")
        let merged = PracticeGoal.mergingPreservingHistories(existing: [account], incoming: [guest])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.map(\.id)).count, 2)
        XCTAssertTrue(merged.contains(where: { $0.attempts.first?.reflection == "Account attempt" }))
        XCTAssertTrue(merged.contains(where: { $0.attempts.first?.reflection == "Guest attempt" }))

        let replay = PracticeGoal(id: UUID(), passage: account.passage, skill: account.skill,
                                  criterion: account.criterion, strategy: account.strategy,
                                  attempts: account.attempts, completedAt: account.completedAt,
                                  nextReviewAt: account.nextReviewAt, updatedAt: account.updatedAt)
        XCTAssertEqual(PracticeGoal.mergingPreservingHistories(existing: [account], incoming: [replay]).count, 1)
        XCTAssertEqual(PracticeGoal.mergingPreservingHistories(existing: merged, incoming: [guest]), merged)
        XCTAssertEqual(PracticeGoal.mergingPreservingHistories(existing: [account], incoming: [account]).count, 1)
    }

    private func take(
        dayOffset: Int,
        cents: Double,
        frameCount: Int = 16,
        concertMIDI: Int = 69,
        id: UUID = UUID(),
        instrument: String = "trumpet",
        reference: Double = 440,
        source: PracticeSessionSource = .live,
        completion: PracticeSessionCompletion = .completed
    ) -> PracticeSession {
        let started = calendar.date(byAdding: .day, value: dayOffset, to: now)!
        let profile = InstrumentProfiles.profile(for: instrument)!
        let written = BrassTuneCore.transposeConcertToWritten(concertMIDI, semitones: profile.transpositionSemitones)
        let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        let frequency = BrassTuneCore.midiToFrequency(Double(concertMIDI), referencePitchHz: reference) * pow(2, cents / 1_200)
        let frames = (0..<frameCount).map { index in
            PitchFrame(timestampMs: index * 110, frequencyHz: frequency, confidence: 0.98, rms: 0.1, centsDeviation: cents, tuningStatus: cents >= 0 ? .sharp : .flat, writtenNoteName: names[written % 12], writtenOctave: written / 12 - 1, isValidForRecording: true)
        }
        return PracticeSession(id: id, name: "Live", instrumentId: instrument, referencePitchHz: reference, startedAt: started, endedAt: started.addingTimeInterval(max(2, Double(frameCount) * 0.110)), frames: frames, retainedRecordingURL: nil, source: source, completion: completion)
    }

    private func goal(id: UUID, passage: String, attemptNote: String) -> PracticeGoal {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        return PracticeGoal(
            id: id,
            passage: passage,
            skill: .tone,
            criterion: PracticeGoalCriterion(kind: .sustainedTone, targetSustainSeconds: 8),
            strategy: .listenFirst,
            attempts: [PracticeGoalAttempt(outcome: .improving, reflection: attemptNote, nextAdjustment: "Listen", createdAt: timestamp)],
            nextReviewAt: timestamp,
            updatedAt: timestamp
        )
    }
}
