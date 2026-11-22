import Foundation
import BrassTuneCore

/// Local, derived cross-session evidence. This intentionally stores no new
/// user data: every value can be recomputed from saved live pitch captures.
struct IntonationHistory: Equatable {
    static let evidenceWindowDays = 30
    static let minimumFramesPerTake = 8
    static let minimumRecurringTakes = 3
    static let minimumRecurringDays = 2

    enum EqualTemperamentDirection: Equatable {
        case above
        case below
        case centeredOrMixed
    }

    struct Note: Equatable, Identifiable {
        let writtenNote: String
        let writtenOctave: Int
        let medianSignedCents: Double
        let spreadCents: Double
        let takeCount: Int
        let dayCount: Int

        var id: String { "\(writtenNote)\(writtenOctave)" }
        var isRecurring: Bool { takeCount >= IntonationHistory.minimumRecurringTakes && dayCount >= IntonationHistory.minimumRecurringDays }
        var direction: EqualTemperamentDirection {
            guard isRecurring else { return .centeredOrMixed }
            guard abs(medianSignedCents) >= 10 else { return .centeredOrMixed }
            let matching = takeCents.filter { medianSignedCents > 0 ? $0 > 0 : $0 < 0 }.count
            return matching * 3 >= takeCents.count * 2 ? (medianSignedCents > 0 ? .above : .below) : .centeredOrMixed
        }
        var hasActionableBias: Bool { isRecurring && direction != .centeredOrMixed }
        fileprivate let takeCents: [Double]
    }

    let notes: [Note]
    let qualifyingTakeCount: Int
    let windowStart: Date
    let windowEnd: Date

    var prioritizedNotes: [Note] { Array(notes.prefix(6)) }

    init(
        sessions: [PracticeSession],
        instrumentID: String,
        referencePitchHz: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let safeReference = NativeReferencePitch.sanitized(referencePitchHz)
        let end = now
        let start = calendar.date(byAdding: .day, value: -(Self.evidenceWindowDays - 1), to: calendar.startOfDay(for: now)) ?? now
        windowStart = start
        windowEnd = end

        guard InstrumentProfiles.profile(for: instrumentID) != nil else {
            notes = []
            qualifyingTakeCount = 0
            return
        }

        // A duplicate local ID is one take, even if a sync retry has placed it
        // in memory twice. Sorting makes the chosen copy deterministic.
        let uniqueSessions = Dictionary(grouping: sessions, by: \.id).values.compactMap { copies -> PracticeSession? in
            // A retransmission may repeat an identical take. Any difference in
            // pitch evidence or capture metadata makes the ID ambiguous, so
            // exclude it rather than making the result depend on input order.
            guard let first = copies.first,
                  copies.allSatisfy({ Self.hasSameEvidence($0, first) }) else { return nil }
            return first
        }

        let takes = uniqueSessions.flatMap { session -> [Take] in
            guard session.source == .live,
                  session.completion == .completed,
                  session.activity.contributesPitchMetrics,
                  session.isMeaningfulCapturedPractice,
                  session.instrumentId == instrumentID,
                  Self.matchesReference(session.referencePitchHz, safeReference),
                  session.startedAt >= start,
                  session.startedAt <= end,
                  session.startedAt.isFiniteDate else { return [] }
            return Self.take(from: session, instrumentID: instrumentID, calendar: calendar)
        }
        qualifyingTakeCount = Set(takes.map(\.id)).count

        let grouped = Dictionary(grouping: takes, by: { $0.noteID })
        notes = grouped.values.compactMap { group in
            guard let first = group.first else { return nil }
            let sorted = group.sorted { $0.date < $1.date }
            let values = sorted.map(\.averageSignedCents)
            let median = Self.roundedTenth(Self.median(values))
            let spread = Self.populationDeviation(values, mean: values.reduce(0, +) / Double(values.count))
            let days = Set(sorted.map { calendar.startOfDay(for: $0.date) })
            return Note(
                writtenNote: first.writtenNote,
                writtenOctave: first.writtenOctave,
                medianSignedCents: median,
                spreadCents: spread,
                takeCount: sorted.count,
                dayCount: days.count,
                takeCents: values
            )
        }
        .sorted { lhs, rhs in
            if lhs.hasActionableBias != rhs.hasActionableBias { return lhs.hasActionableBias }
            if lhs.isRecurring != rhs.isRecurring { return lhs.isRecurring }
            let leftPriority = abs(lhs.medianSignedCents) + lhs.spreadCents * 0.25
            let rightPriority = abs(rhs.medianSignedCents) + rhs.spreadCents * 0.25
            if leftPriority != rightPriority { return leftPriority > rightPriority }
            return lhs.id < rhs.id
        }
    }

    static func sustainedToneGoalName(instrumentID: String, note: Note) -> String {
        NativeLocalization.format("%@ · %@ sustained tone", instrumentDisplayName(instrumentID), note.id)
    }

    static func sustainedToneGoalID(instrumentID: String, note: Note) -> UUID {
        // The ID is deliberately based on machine identifiers, rather than
        // localized display copy, so repeat taps cannot create duplicate active goals.
        let input = Array("intonation-goal|\(instrumentID)|\(note.id)".utf8)
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x9e3779b97f4a7c15
        for byte in input {
            first = (first ^ UInt64(byte)) &* 0x100000001b3
            second = (second ^ UInt64(byte)) &* 0x9e3779b185ebca87
        }
        return UUID(uuid: (
            UInt8(truncatingIfNeeded: first >> 56), UInt8(truncatingIfNeeded: first >> 48), UInt8(truncatingIfNeeded: first >> 40), UInt8(truncatingIfNeeded: first >> 32),
            UInt8(truncatingIfNeeded: first >> 24), UInt8(truncatingIfNeeded: first >> 16), UInt8(truncatingIfNeeded: first >> 8), UInt8(truncatingIfNeeded: first),
            UInt8(truncatingIfNeeded: second >> 56), UInt8(truncatingIfNeeded: second >> 48), UInt8(truncatingIfNeeded: second >> 40), UInt8(truncatingIfNeeded: second >> 32),
            UInt8(truncatingIfNeeded: second >> 24), UInt8(truncatingIfNeeded: second >> 16), UInt8(truncatingIfNeeded: second >> 8), UInt8(truncatingIfNeeded: second)
        ))
    }

    static func suggestedSustainSeconds(for note: Note) -> Int {
        min(PracticeGoalCriterion.sustainSecondsRange.upperBound, max(PracticeGoalCriterion.sustainSecondsRange.lowerBound, 8))
    }

    private struct Take {
        let id: UUID
        let noteID: String
        let writtenNote: String
        let writtenOctave: Int
        let averageSignedCents: Double
        let date: Date
    }

    private static func take(from session: PracticeSession, instrumentID: String, calendar _: Calendar) -> [Take] {
        guard let verifiedFrames = verifiedFrames(for: session, instrumentID: instrumentID) else { return [] }
        let events = NativePitchAnalytics.segmentNoteEvents(frames: verifiedFrames)
        let valuesByNote = Dictionary(grouping: events, by: { "\($0.writtenNote)\($0.writtenOctave)" }).compactMapValues { events -> [Double]? in
            let values = events.flatMap { event -> [Double] in
                guard event.durationMs >= 500 else { return [] }
                return frames(in: verifiedFrames, from: event.startedAtMs + 100, through: event.endedAtMs).filter {
                    $0.writtenNoteName == event.writtenNote
                        && $0.writtenOctave == event.writtenOctave
                        && $0.timestampMs >= event.startedAtMs + 100
                        && $0.timestampMs <= event.endedAtMs
                }.compactMap(\.centsDeviation).filter(\.isFinite)
            }
            return values.count >= minimumFramesPerTake ? values : nil
        }
        return valuesByNote.compactMap { noteID, values in
            guard let event = events.first(where: { "\($0.writtenNote)\($0.writtenOctave)" == noteID }) else { return nil }
            return Take(
                id: session.id,
                noteID: noteID,
                writtenNote: event.writtenNote,
                writtenOctave: event.writtenOctave,
                averageSignedCents: median(values),
                date: session.startedAt
            )
        }
    }

    private static func isVerified(frame: PitchFrame, instrumentID: String, referencePitchHz: Double) -> Bool {
        guard frame.isValidForRecording,
              frame.timestampMs >= 0,
              frame.confidence.isFinite,
              frame.rms.isFinite,
              [.flat, .inTune, .sharp].contains(frame.tuningStatus),
              let cents = frame.centsDeviation, cents.isFinite,
              let frequency = frame.frequencyHz, frequency.isFinite,
              let note = frame.writtenNoteName,
              let octave = frame.writtenOctave,
              InstrumentAcousticRange.forInstrument(instrumentID).contains(frequency) else { return false }
        let expected = PitchFrame.detected(
            timestampMs: frame.timestampMs,
            frequencyHz: frequency,
            confidence: frame.confidence,
            rms: frame.rms,
            instrumentId: instrumentID,
            referencePitchHz: referencePitchHz
        )
        return expected.isValidForRecording
            && note == expected.writtenNoteName
            && octave == expected.writtenOctave
            && abs(cents - (expected.centsDeviation ?? .infinity)) < 0.001
    }

    private static func matchesReference(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs.isFinite && rhs.isFinite && abs(lhs - rhs) <= 0.05 + 0.000_001
    }

    private static func hasSameEvidence(_ lhs: PracticeSession, _ rhs: PracticeSession) -> Bool {
        lhs.instrumentId == rhs.instrumentId
            && lhs.referencePitchHz == rhs.referencePitchHz
            && lhs.startedAt == rhs.startedAt
            && lhs.endedAt == rhs.endedAt
            && lhs.source == rhs.source
            && lhs.activity == rhs.activity
            && lhs.completion == rhs.completion
            && lhs.frames == rhs.frames
    }

    private static func verifiedFrames(for session: PracticeSession, instrumentID: String) -> [PitchFrame]? {
        // `timestampMs` comes from AVAudioTime.sampleTime. A tuner can run
        // before a saved take begins, so only the span is session-relative.
        // The one-second allowance covers the pipeline drain after stop.
        guard let endedAt = session.endedAt,
              session.startedAt.isFiniteDate,
              endedAt.isFiniteDate else { return nil }
        let duration = endedAt.timeIntervalSince(session.startedAt)
        let maximumSpan = duration * 1_000 + 1_000
        guard duration.isFinite, duration >= 0, maximumSpan.isFinite else { return nil }
        let groups = Dictionary(grouping: session.frames, by: \.timestampMs)
        guard groups.values.allSatisfy({ frames in
            guard let first = frames.first else { return false }
            return frames.allSatisfy { $0 == first }
        }) else { return nil }
        let timestamps = groups.keys
        guard let minimumTimestamp = timestamps.min(),
              let maximumTimestamp = timestamps.max(),
              minimumTimestamp >= 0,
              Double(maximumTimestamp) - Double(minimumTimestamp) <= maximumSpan else { return nil }
        return groups.values.compactMap(\.first).filter { frame in
            isVerified(frame: frame, instrumentID: instrumentID, referencePitchHz: session.referencePitchHz)
        }.sorted { $0.timestampMs < $1.timestampMs }
    }

    private static func populationDeviation(_ values: [Double], mean: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        return sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func roundedTenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// `verifiedFrames` is timestamp-sorted. Slice each event with binary
    /// searches so a long capture is not rescanned once per detected event.
    private static func frames(in frames: [PitchFrame], from lower: Int, through upper: Int) -> ArraySlice<PitchFrame> {
        func lowerBound(_ timestamp: Int) -> Int {
            var low = 0
            var high = frames.count
            while low < high {
                let mid = (low + high) / 2
                if frames[mid].timestampMs < timestamp { low = mid + 1 } else { high = mid }
            }
            return low
        }
        func upperBound(_ timestamp: Int) -> Int {
            var low = 0
            var high = frames.count
            while low < high {
                let mid = (low + high) / 2
                if frames[mid].timestampMs <= timestamp { low = mid + 1 } else { high = mid }
            }
            return low
        }
        let start = lowerBound(lower)
        let end = upperBound(upper)
        return frames[start..<end]
    }

}

private extension Date {
    var isFiniteDate: Bool { timeIntervalSinceReferenceDate.isFinite }
}

extension PracticeGoal {
    /// Combines guest and account goals without treating an ID collision as
    /// proof that their attempt histories are interchangeable. Exact replay
    /// records are ignored even when their transport IDs differ.
    static func mergingPreservingHistories(existing: [PracticeGoal], incoming: [PracticeGoal]) -> [PracticeGoal] {
        var merged = existing
        for goal in incoming {
            guard !merged.contains(where: { $0.sameEvidence(as: goal) }) else { continue }
            if merged.contains(where: { $0.id == goal.id }) {
                var ordinal = 1
                var replacement = goal.reidentified(using: collisionID(for: goal, ordinal: ordinal))
                while merged.contains(where: { $0.id == replacement.id }) {
                    ordinal += 1
                    replacement = goal.reidentified(using: collisionID(for: goal, ordinal: ordinal))
                }
                merged.append(replacement)
            } else {
                merged.append(goal)
            }
        }
        return merged
    }

    private func sameEvidence(as other: PracticeGoal) -> Bool {
        passage == other.passage
            && skill == other.skill
            && criterion == other.criterion
            && strategy == other.strategy
            && attempts == other.attempts
            && completedAt == other.completedAt
            && nextReviewAt == other.nextReviewAt
            && updatedAt == other.updatedAt
    }

    private func reidentified(using id: UUID) -> PracticeGoal {
        PracticeGoal(id: id, passage: passage, skill: skill, criterion: criterion, strategy: strategy, attempts: attempts, completedAt: completedAt, nextReviewAt: nextReviewAt, updatedAt: updatedAt)
    }

    private static func collisionID(for goal: PracticeGoal, ordinal: Int) -> UUID {
        let source = Array("goal-collision|\(goal.id.uuidString)|\(goal.updatedAt.timeIntervalSinceReferenceDate)|\(ordinal)".utf8)
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x9e3779b97f4a7c15
        for byte in source {
            first = (first ^ UInt64(byte)) &* 0x100000001b3
            second = (second ^ UInt64(byte)) &* 0x9e3779b185ebca87
        }
        return UUID(uuid: (UInt8(truncatingIfNeeded: first >> 56), UInt8(truncatingIfNeeded: first >> 48), UInt8(truncatingIfNeeded: first >> 40), UInt8(truncatingIfNeeded: first >> 32), UInt8(truncatingIfNeeded: first >> 24), UInt8(truncatingIfNeeded: first >> 16), UInt8(truncatingIfNeeded: first >> 8), UInt8(truncatingIfNeeded: first), UInt8(truncatingIfNeeded: second >> 56), UInt8(truncatingIfNeeded: second >> 48), UInt8(truncatingIfNeeded: second >> 40), UInt8(truncatingIfNeeded: second >> 32), UInt8(truncatingIfNeeded: second >> 24), UInt8(truncatingIfNeeded: second >> 16), UInt8(truncatingIfNeeded: second >> 8), UInt8(truncatingIfNeeded: second)))
    }
}

extension IntonationHistory {
    /// Synthetic history is only reachable from the isolated UI-test reset.
    static func uiTestSessions(now: Date = Date()) -> [PracticeSession] {
        guard NativeTestFixtures.areEnabled() else { return [] }
        return [-3, -2, -1].map { day in
            let start = Calendar.current.date(byAdding: .day, value: day, to: now)!
            let frequency = BrassTuneCore.midiToFrequency(58, referencePitchHz: 440) * pow(2, 16.0 / 1200)
            let frames = (0..<40).map { index in
                PitchFrame.detected(timestampMs: index * 100, frequencyHz: frequency,
                                    confidence: 0.99, rms: 0.1, instrumentId: "trumpet", referencePitchHz: 440)
            }
            return PracticeSession(id: UUID(), name: "History QA", instrumentId: "trumpet", referencePitchHz: 440,
                                   startedAt: start, endedAt: start.addingTimeInterval(4), frames: frames,
                                   retainedRecordingURL: nil, source: .live, completion: .completed)
        }
    }
}
