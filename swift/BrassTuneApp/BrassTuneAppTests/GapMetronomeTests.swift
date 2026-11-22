import AVFoundation
import XCTest
@testable import BrassTuneApp

final class GapMetronomeTests: XCTestCase {
    func testLegacyDecodeDefaultsGapTrainerOffAndPresetRoundTripKeepsConfiguration() throws {
        let legacy = Data(#"{"bpm":84,"beatsPerMeasure":3,"beatUnit":4,"subdivision":"quarter","muted":false,"visualOnly":false,"hapticsEnabled":true,"volume":0.5}"#.utf8)
        let legacySettings = try JSONDecoder().decode(MetronomeSettings.self, from: legacy)
        XCTAssertFalse(legacySettings.highClickEveryBeat)
        XCTAssertFalse(legacySettings.gapModeEnabled)
        XCTAssertEqual(legacySettings.gapAudibleBars, 2)
        XCTAssertEqual(legacySettings.gapSilentBars, 1)

        let settings = MetronomeSettings(
            bpm: 108,
            beatsPerMeasure: 6,
            beatUnit: 8,
            subdivision: .eighth,
            hapticsEnabled: true,
            volume: 0.42,
            accentFirstBeat: true,
            countInBeats: 2,
            highClickEveryBeat: true,
            gapModeEnabled: true,
            gapAudibleBars: 4,
            gapSilentBars: 3
        )
        let preset = MetronomePreset(
            id: UUID(uuidString: "F4E3DFE7-226D-46BC-9625-B73F849FA321")!,
            name: "Memory bars",
            settings: settings,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let decoded = try JSONDecoder().decode(
            MetronomePreset.self,
            from: JSONEncoder().encode(preset)
        )
        XCTAssertEqual(decoded, preset)

        var invalid = settings
        invalid.gapAudibleBars = 99
        invalid.gapSilentBars = -2
        invalid.validate()
        XCTAssertEqual(invalid.gapAudibleBars, 4)
        XCTAssertEqual(invalid.gapSilentBars, 1)
    }

    func testHighClickAppliesToEveryGridTickAndCountInButNotGapSilence() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let settings = MetronomeSettings(
            bpm: 120, beatsPerMeasure: 6, beatUnit: 8, subdivision: .eighth,
            accentFirstBeat: false, countInBeats: 1, highClickEveryBeat: true,
            gapModeEnabled: true, gapAudibleBars: 1, gapSilentBars: 1
        )
        let pattern = try NativeMetronomePatternBuffers(
            outputFormat: format, settings: settings, countInGridTicks: 6, startingGridTick: 0
        )
        let measure = try XCTUnwrap(pattern.measure.floatChannelData?[0])
        let countIn = try XCTUnwrap(pattern.countIn?.floatChannelData?[0])
        let framesPerTick = Double(format.sampleRate) * settings.intervalSeconds
        let clicks = try NativeMetronomeClickBuffers(outputFormat: format, intervalSeconds: settings.intervalSeconds)
        let high = try XCTUnwrap(clicks.accent.floatChannelData?[0])
        let regular = try XCTUnwrap(clicks.regular.floatChannelData?[0])
        XCTAssertEqual(measure[30], high[30], accuracy: 0.000_01)
        XCTAssertNotEqual(measure[30], regular[30], accuracy: 0.000_01)
        // A sample inside each click must match the first high click; meter and
        // subdivisions still determine the number and placement of ticks.
        for tick in 0..<pattern.measureGridTicks {
            XCTAssertEqual(measure[Int((Double(tick) * framesPerTick).rounded()) + 30], measure[30], accuracy: 0.000_01)
        }
        for tick in 0..<6 {
            XCTAssertEqual(countIn[Int((Double(tick) * framesPerTick).rounded()) + 30], measure[30], accuracy: 0.000_01)
        }
        assertLiteralSilence(try XCTUnwrap(pattern.silentMeasure))
    }

    func testGapPatternContainsAudibleGridAndLiteralZeroSilentBars() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
        )
        let settings = MetronomeSettings(
            bpm: 120,
            beatsPerMeasure: 4,
            beatUnit: 4,
            subdivision: .eighth,
            gapModeEnabled: true,
            gapAudibleBars: 2,
            gapSilentBars: 1
        )
        let pattern = try NativeMetronomePatternBuffers(
            outputFormat: format,
            settings: settings,
            countInGridTicks: 0,
            startingGridTick: 0
        )

        XCTAssertEqual(pattern.measureGridTicks, 8)
        XCTAssertEqual(pattern.cycleBarCount, 3)
        XCTAssertLessThanOrEqual(
            pattern.renderedByteCount,
            NativeMetronomePatternBuffers.maximumRenderedBufferBytes
        )
        assertGridHasClicks(pattern.measure, ticks: 8)
        assertLiteralSilence(try XCTUnwrap(pattern.silentMeasure))
        XCTAssertTrue(pattern.buffer(forCycleBar: 0) === pattern.measure)
        XCTAssertTrue(pattern.buffer(forCycleBar: 1) === pattern.measure)
        XCTAssertTrue(pattern.buffer(forCycleBar: 2) === pattern.silentMeasure)
        XCTAssertTrue(pattern.buffer(forCycleBar: 3) === pattern.measure)

        let audible = try XCTUnwrap(pattern.measure.floatChannelData?[0])
        let silent = try XCTUnwrap(pattern.silentMeasure?.floatChannelData?[0])
        XCTAssertEqual(silent[Int(pattern.silentMeasure!.frameLength) - 1], 0)
        XCTAssertEqual(audible[0], 0, accuracy: 0.000_001)
        XCTAssertTrue((1..<min(1_500, Int(pattern.measure.frameLength))).contains { abs(audible[$0]) > 0.000_1 })

        var queueCursor = NativeMetronomeGapQueueCursor(cycleBarCount: pattern.cycleBarCount)
        XCTAssertEqual(
            (0..<7).map { _ in queueCursor.consumeNextBar() },
            [0, 1, 2, 0, 1, 2, 0],
            "Completion tasks only notify consumption; the actor-owned cursor must preserve cycle order."
        )
    }

    func testCompoundSixEightSubdivisionAndCountInUseExactPCMGrid() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
        )
        let settings = MetronomeSettings(
            bpm: 120,
            beatsPerMeasure: 6,
            beatUnit: 8,
            subdivision: .eighth,
            countInBeats: 2,
            gapModeEnabled: true,
            gapAudibleBars: 1,
            gapSilentBars: 2
        )
        // Two dotted-quarter count-in pulses span six written eighth notes;
        // eighth subdivision therefore renders twelve exact grid ticks.
        let countInGridTicks = 2 * 3 * settings.subdivision.ticksPerBeat
        let pattern = try NativeMetronomePatternBuffers(
            outputFormat: format,
            settings: settings,
            countInGridTicks: countInGridTicks,
            startingGridTick: 0
        )

        XCTAssertEqual(pattern.measureGridTicks, 12)
        assertGridHasClicks(try XCTUnwrap(pattern.countIn), ticks: 12)
        assertGridHasClicks(pattern.measure, ticks: 12)
        assertLiteralSilence(try XCTUnwrap(pattern.silentMeasure))
        XCTAssertTrue(pattern.buffer(forCycleBar: 2) === pattern.silentMeasure)
        XCTAssertTrue(
            pattern.buffer(forCycleBar: 3) === pattern.measure,
            "The loop must re-enter on the audible downbeat, which carries the configured first-beat accent."
        )
    }

    func testTwelveEightBarDurationKeepsDottedQuarterTempoContract() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
        )
        let settings = MetronomeSettings(
            bpm: 120,
            beatsPerMeasure: 12,
            beatUnit: 8,
            subdivision: .sixteenth,
            gapModeEnabled: true,
            gapAudibleBars: 1,
            gapSilentBars: 1
        )
        let pattern = try NativeMetronomePatternBuffers(
            outputFormat: format,
            settings: settings,
            countInGridTicks: 0,
            startingGridTick: 0
        )
        XCTAssertEqual(pattern.measureGridTicks, 48)
        XCTAssertEqual(
            Double(pattern.measure.frameLength) / pattern.measure.format.sampleRate,
            2,
            accuracy: 1.0 / format.sampleRate,
            "At 120 dotted-quarter BPM, a 12/8 bar contains four half-second primary pulses."
        )
        assertGridHasClicks(pattern.measure, ticks: 48)
        assertLiteralSilence(try XCTUnwrap(pattern.silentMeasure))
    }

    func testGapSequenceExcludesCountInAndRestartsAtExplicitAudibleBoundary() {
        let settings = MetronomeSettings(
            gapModeEnabled: true,
            gapAudibleBars: 2,
            gapSilentBars: 2
        )
        var sequence = MetronomeGapSequence()
        sequence.start(settings: settings, hasCountIn: true)
        XCTAssertEqual(sequence.phase, .countIn)
        sequence.countInDidAdvance(settings: settings, ticksRemaining: 4)
        XCTAssertEqual(sequence.phase, .countIn)
        sequence.countInDidAdvance(settings: settings, ticksRemaining: 0)
        XCTAssertEqual(sequence.phase, .audible(bar: 1, total: 2))
        sequence.measureDidComplete(settings: settings)
        XCTAssertEqual(sequence.phase, .audible(bar: 2, total: 2))
        sequence.measureDidComplete(settings: settings)
        XCTAssertEqual(sequence.phase, .silent(bar: 1, total: 2))
        sequence.measureDidComplete(settings: settings)
        XCTAssertEqual(sequence.phase, .silent(bar: 2, total: 2))
        sequence.measureDidComplete(settings: settings)
        XCTAssertEqual(sequence.phase, .audible(bar: 1, total: 2))

        sequence.measureDidComplete(settings: settings)
        sequence.measureDidComplete(settings: settings)
        XCTAssertTrue(sequence.phase.isSilent)
        sequence.start(settings: settings, hasCountIn: false)
        XCTAssertEqual(
            sequence.phase,
            .audible(bar: 1, total: 2),
            "A mid-cycle settings handoff deliberately starts the replacement pattern at a documented audible-bar boundary."
        )
        sequence.reset()
        XCTAssertEqual(sequence.phase, .inactive)
    }

    func testAbsolutePulseJumpCrossesCountInAudibleSilentAndAudibleWithoutCatchupReplay() {
        let settings = MetronomeSettings(
            beatsPerMeasure: 2,
            beatUnit: 4,
            subdivision: .quarter,
            countInBeats: 2,
            gapModeEnabled: true,
            gapAudibleBars: 1,
            gapSilentBars: 1
        )
        let countInTicks = 2
        XCTAssertEqual(
            MetronomeAbsolutePulseTimeline.position(
                settings: settings,
                countInGridTicks: countInTicks,
                pulseIndex: 1
            ).gapPhase,
            .countIn
        )
        let skippedToSilent = MetronomeAbsolutePulseTimeline.position(
            settings: settings,
            countInGridTicks: countInTicks,
            pulseIndex: 4
        )
        XCTAssertEqual(skippedToSilent.gapPhase, .silent(bar: 1, total: 1))
        XCTAssertEqual(skippedToSilent.measureTick, 0)
        XCTAssertFalse(skippedToSilent.isAudible)
        let skippedBackToAudible = MetronomeAbsolutePulseTimeline.position(
            settings: settings,
            countInGridTicks: countInTicks,
            pulseIndex: 6
        )
        XCTAssertEqual(skippedBackToAudible.gapPhase, .audible(bar: 1, total: 1))
        XCTAssertEqual(skippedBackToAudible.measureTick, 0)
        XCTAssertTrue(skippedBackToAudible.isAudible)

        XCTAssertEqual(
            MetronomeAbsolutePulseTimeline.recentUnregisteredIndices(
                after: 1,
                through: 20,
                maximumCount: 6
            ),
            15...20
        )
    }

    @MainActor
    func testAppModelAbsoluteJumpDoesNotReplaySkippedVisualPulses() {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GapMetronomeJumpTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: {},
            deactivateSession: {},
            deactivationDelay: .zero
        )
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            audioSessionCoordinator: coordinator
        )
        model.metronome = MetronomeSettings(
            bpm: 20,
            beatsPerMeasure: 2,
            muted: true,
            visualOnly: true,
            hapticsEnabled: true,
            volume: 0,
            countInBeats: 2,
            gapModeEnabled: true,
            gapAudibleBars: 1,
            gapSilentBars: 1
        )
        model.startMetronome()
        let initialSequence = model.metronomePulseSequence
        model.advanceMetronomeClock(pulseIndex: 4, emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .silent(bar: 1, total: 1))
        XCTAssertEqual(model.metronomePulseSequence, initialSequence)
        XCTAssertEqual(model.metronomePulseScale, 1)
        model.advanceMetronomeClock(pulseIndex: 6, emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .audible(bar: 1, total: 1))
        XCTAssertEqual(model.metronomePulseSequence, initialSequence + 1)
        XCTAssertTrue(model.metronomeLastPulseWasAccented)
        model.stopMetronome()
        XCTAssertEqual(model.metronomeGapPhase, .inactive)
    }

    @MainActor
    func testPendingPreferencesDoNotReinterpretAcceptedAudioBeforeHandoffBoundary() {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GapMetronomeHandoffTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: {},
            deactivateSession: {},
            deactivationDelay: .zero
        )
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            audioSessionCoordinator: coordinator
        )
        let accepted = MetronomeSettings(
            bpm: 60,
            beatsPerMeasure: 4,
            muted: true,
            visualOnly: true,
            volume: 0,
            gapModeEnabled: false
        )
        let pending = MetronomeSettings(
            bpm: 240,
            beatsPerMeasure: 2,
            muted: true,
            visualOnly: true,
            volume: 0,
            gapModeEnabled: true,
            gapAudibleBars: 1,
            gapSilentBars: 1
        )
        model.metronome = accepted
        model.startMetronome()
        model.metronome = pending

        // Pulse two is still part of the accepted 4/4 continuous-click bar.
        // Reading pending 2/4 gap settings here would falsely label it silent.
        model.advanceMetronomeClock(pulseIndex: 2, emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .inactive)
        XCTAssertEqual(model.metronomeTick, 3)

        XCTAssertFalse(
            model.promoteMetronomeRuntimeSettings(
                pending,
                countInGridTicks: 0,
                generation: UUID()
            ),
            "A stale replacement callback must not promote pending preferences."
        )
        model.advanceMetronomeClock(pulseIndex: 3, emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .inactive)
        XCTAssertTrue(model.promoteMetronomeRuntimeSettings(pending, countInGridTicks: 0))
        model.advanceMetronomeClock(pulseIndex: 0, emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .audible(bar: 1, total: 1))
        XCTAssertEqual(model.metronomeTick, 1)
        model.advanceMetronomeClock(pulseIndex: 2, emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .silent(bar: 1, total: 1))
        model.stopMetronome()
    }

    func testGapTrainerProvidesCleanTunerCaptureWindow() {
        var settings = MetronomeSettings(
            bpm: 300,
            subdivision: .sixteenth,
            gapModeEnabled: true,
            gapAudibleBars: 1,
            gapSilentBars: 1
        )
        XCTAssertFalse(
            MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(for: settings)
        )
        settings.gapModeEnabled = false
        XCTAssertTrue(
            MetronomeTunerAudibleCaptureCompatibility.audibleClicksLeaveNoCleanCapture(for: settings)
        )
    }

    @MainActor
    func testStoppedOutgoingClockBlocksTunerFramesUntilAcceptedBoundary() async throws {
        var handoff = MetronomeAudioHandoffState()
        let staleToken = handoff.begin()
        let currentToken = handoff.begin()
        XCTAssertTrue(handoff.blocksTunerFrames)
        XCTAssertFalse(handoff.finish(token: staleToken))
        XCTAssertTrue(handoff.blocksTunerFrames)
        XCTAssertTrue(handoff.finish(token: currentToken))
        XCTAssertFalse(handoff.blocksTunerFrames)

        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GapMetronomePendingHandoffTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: {},
            deactivateSession: {},
            deactivationDelay: .zero
        )
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            audioSessionCoordinator: coordinator
        )
        model.metronome = MetronomeSettings(
            bpm: 20,
            muted: true,
            visualOnly: true,
            volume: 0
        )
        model.startMetronome()
        model.metronome = MetronomeSettings(
            bpm: 240,
            beatsPerMeasure: 2,
            muted: true,
            visualOnly: true,
            volume: 0,
            gapModeEnabled: true
        )
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertTrue(model.metronomeTunerFramesBlockedForHandoff)
        XCTAssertEqual(model.metronomeGapPhase, .inactive)
        model.stopMetronome()
        XCTAssertFalse(model.metronomeTunerFramesBlockedForHandoff)
    }

    @MainActor
    func testAppModelPublishesOnlyBarLevelStateDuringSilentMeasure() {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GapMetronomeTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: {},
            deactivateSession: {},
            deactivationDelay: .zero
        )
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            audioSessionCoordinator: coordinator
        )
        model.metronome = MetronomeSettings(
            bpm: 20,
            beatsPerMeasure: 2,
            beatUnit: 4,
            subdivision: .quarter,
            muted: true,
            visualOnly: true,
            hapticsEnabled: true,
            volume: 0,
            countInBeats: 2,
            gapModeEnabled: true,
            gapAudibleBars: 1,
            gapSilentBars: 1
        )

        model.startMetronome()
        XCTAssertEqual(model.metronomeGapPhase, .countIn)
        XCTAssertEqual(model.metronomeCountInRemaining, 1)
        model.advanceMetronomeClock(emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .countIn)
        XCTAssertEqual(model.metronomeCountInRemaining, 0)
        model.advanceMetronomeClock(emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .audible(bar: 1, total: 1))
        model.advanceMetronomeClock(emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .audible(bar: 1, total: 1))
        model.advanceMetronomeClock(emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .silent(bar: 1, total: 1))
        let sequenceAtSilentEntry = model.metronomePulseSequence
        XCTAssertEqual(model.metronomePulseScale, 1)

        model.advanceMetronomeClock(emitAudio: false)
        XCTAssertEqual(model.metronomePulseSequence, sequenceAtSilentEntry)
        XCTAssertEqual(model.metronomePulseScale, 1)
        XCTAssertEqual(model.metronomeGapPhase, .silent(bar: 1, total: 1))
        model.advanceMetronomeClock(emitAudio: false)
        XCTAssertEqual(model.metronomeGapPhase, .audible(bar: 1, total: 1))
        XCTAssertEqual(model.metronomePulseSequence, sequenceAtSilentEntry + 1)
        model.stopMetronome()
        XCTAssertEqual(model.metronomeGapPhase, .inactive)
    }

    @MainActor
    func testSilentGapSuppressesHapticAndOneShotAudioAcrossMuteAndRestart() async throws {
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: {},
            deactivateSession: {},
            deactivationDelay: .zero
        )
        var haptics: [Bool] = []
        var scheduledClicks = 0
        let output = NativeMetronomeOutput(
            audioSessionCoordinator: coordinator,
            scheduleOverride: { _, _, _, completion in
                scheduledClicks += 1
                completion(.success(()))
            },
            playHaptic: { haptics.append($0) }
        )
        var settings = MetronomeSettings(
            muted: true,
            visualOnly: true,
            hapticsEnabled: true,
            volume: 0,
            gapModeEnabled: true
        )
        output.playTick(settings: settings, accent: false, gapPhaseIsSilent: true)
        XCTAssertTrue(haptics.isEmpty)
        XCTAssertEqual(scheduledClicks, 0)

        output.playTick(settings: settings, accent: true, gapPhaseIsSilent: false)
        XCTAssertEqual(haptics, [true])
        XCTAssertEqual(scheduledClicks, 0, "Muted/visual-only mode must stay off the audible scheduler.")
        output.stop()
        await coordinator.flush()

        settings.visualOnly = false
        settings.muted = false
        settings.volume = 0.5
        output.playTick(settings: settings, accent: true, gapPhaseIsSilent: false)
        for _ in 0..<50 where scheduledClicks == 0 { await Task.yield() }
        XCTAssertEqual(scheduledClicks, 1)
        XCTAssertEqual(haptics, [true, true])
        output.stop()
        await coordinator.flush()

        output.playTick(settings: settings, accent: false, gapPhaseIsSilent: true)
        XCTAssertEqual(scheduledClicks, 1, "A silent-bar restart must not submit a one-shot fallback click.")
        XCTAssertEqual(haptics, [true, true])
    }

    @MainActor
    func testCaptureDuplexOnlySchedulesConfiguredAudibleGapPulses() async throws {
        let coordinator = NativeAudioSessionCoordinator(
            activateSession: {},
            deactivateSession: {},
            deactivationDelay: .zero
        )
        _ = try await coordinator.acquire(.capture, configuration: .capture)
        var scheduledClicks = 0
        let output = NativeMetronomeOutput(
            audioSessionCoordinator: coordinator,
            scheduleOverride: { _, _, _, completion in
                scheduledClicks += 1
                completion(.success(()))
            }
        )
        let settings = MetronomeSettings(gapModeEnabled: true)

        output.playTick(
            settings: settings,
            accent: false,
            allowAudibleDuringCapture: true,
            gapPhaseIsSilent: true
        )
        XCTAssertEqual(scheduledClicks, 0)
        output.playTick(
            settings: settings,
            accent: false,
            allowAudibleDuringCapture: false,
            gapPhaseIsSilent: false
        )
        XCTAssertEqual(scheduledClicks, 0)
        output.playTick(
            settings: settings,
            accent: true,
            allowAudibleDuringCapture: true,
            gapPhaseIsSilent: false
        )
        for _ in 0..<50 where scheduledClicks == 0 { await Task.yield() }
        XCTAssertEqual(scheduledClicks, 1)

        output.stop()
        coordinator.release(.capture, deactivation: .immediate)
        await coordinator.flush()
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
    }

    func testPatternPreflightRejectsResidentPCMAboveSixtyFourMegabytes() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 96_000, channels: 2)
        )
        let settings = MetronomeSettings(
            bpm: 20,
            beatsPerMeasure: 12,
            beatUnit: 4,
            subdivision: .quarter,
            countInBeats: 16,
            gapModeEnabled: true,
            gapAudibleBars: 4,
            gapSilentBars: 4
        )
        let countInTicks = settings.countInBeats * settings.subdivision.ticksPerBeat
        let estimate = try NativeMetronomePatternBuffers.estimatedByteCount(
            outputFormat: format,
            settings: settings,
            countInGridTicks: countInTicks
        )
        XCTAssertGreaterThan(estimate, NativeMetronomePatternBuffers.maximumRenderedBufferBytes)
        XCTAssertThrowsError(
            try NativeMetronomePatternBuffers(
                outputFormat: format,
                settings: settings,
                countInGridTicks: countInTicks,
                startingGridTick: 0
            )
        )
        XCTAssertTrue(
            NativeMetronomeResidentPCMPolicy.canAllocateReplacement(
                activePatternBytes: 20 * 1_024 * 1_024,
                retiringPatternBytes: 12 * 1_024 * 1_024,
                replacementPatternBytes: 28 * 1_024 * 1_024,
                cachedClickBytes: 1 * 1_024 * 1_024
            )
        )
        XCTAssertFalse(
            NativeMetronomeResidentPCMPolicy.canAllocateReplacement(
                activePatternBytes: 20 * 1_024 * 1_024,
                retiringPatternBytes: 20 * 1_024 * 1_024,
                replacementPatternBytes: 24 * 1_024 * 1_024,
                cachedClickBytes: 1
            ),
            "Active, retiring, replacement, and both temporary/cached click pairs must share one 64 MiB ceiling."
        )
    }

    private func assertGridHasClicks(
        _ buffer: AVAudioPCMBuffer,
        ticks: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let samples = buffer.floatChannelData?[0] else {
            XCTFail("Expected float PCM", file: file, line: line)
            return
        }
        let framesPerTick = Double(buffer.frameLength) / Double(ticks)
        for tick in 0..<ticks {
            let start = Int((Double(tick) * framesPerTick).rounded())
            let end = min(Int(buffer.frameLength), start + max(2, Int(framesPerTick * 0.55)))
            XCTAssertTrue(
                (start..<end).contains { abs(samples[$0]) > 0.000_1 },
                "Missing click at grid tick \(tick)",
                file: file,
                line: line
            )
        }
    }

    private func assertLiteralSilence(
        _ buffer: AVAudioPCMBuffer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let channels = buffer.floatChannelData else {
            XCTFail("Expected float PCM", file: file, line: line)
            return
        }
        for channel in 0..<Int(buffer.format.channelCount) {
            XCTAssertTrue(
                (0..<Int(buffer.frameLength)).allSatisfy { channels[channel][$0] == 0 },
                "Silent gap PCM must contain only exact zero samples.",
                file: file,
                line: line
            )
        }
    }
}
