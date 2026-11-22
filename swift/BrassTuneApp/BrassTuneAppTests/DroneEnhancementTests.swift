import AVFoundation
import BrassTuneCore
import XCTest
@testable import BrassTuneApp

final class DroneEnhancementTests: XCTestCase {
    func testListeningExerciseOffsetsMatchDroneRatios() throws {
        for (interval, expected) in [(TuningInterval.majorThird, -13.686), (.perfectFifth, 1.955)] {
            let equal = try XCTUnwrap(PracticePitchMath.frequency(
                writtenMIDI: 71, interval: interval, instrumentID: "trumpet",
                referencePitchHz: 440, temperament: .equalTemperament
            ))
            let just = try XCTUnwrap(PracticePitchMath.frequency(
                writtenMIDI: 71, interval: interval, instrumentID: "trumpet",
                referencePitchHz: 440, temperament: .justIntonation
            ))
            XCTAssertEqual(DroneListeningExercise.justOffsetCents(for: interval), expected, accuracy: 0.001)
            XCTAssertEqual(DroneListeningExercise.justOffsetCents(for: interval), 1200 * log2(just / equal), accuracy: 0.000_001)
        }
        XCTAssertEqual(DroneListeningExercise.justOffsetLabel(for: .majorThird), "-14")
        XCTAssertEqual(DroneListeningExercise.justOffsetLabel(for: .perfectFifth), "+2")
    }

    func testColorThemeTitlesUseSelectedArabicLocalizationAndRestoreLanguage() {
        let previousLanguage = NativeLocalization.language
        defer { NativeLocalization.language = previousLanguage }

        NativeLocalization.language = .arabic
        XCTAssertEqual(BTColorTheme.system.title, AppLanguage.arabic.localized("System"))
        XCTAssertEqual(BTColorTheme.light.title, AppLanguage.arabic.localized("Light"))
        XCTAssertEqual(BTColorTheme.dark.title, AppLanguage.arabic.localized("Dark"))
        XCTAssertNotEqual(BTColorTheme.light.title, "Light")
        XCTAssertNotEqual(BTColorTheme.dark.title, "Dark")
    }

    func testGeneratedScaleFeedbackRequiresMatchingWrittenOctaveBeforeDirection() {
        let previousLanguage = NativeLocalization.language
        defer { NativeLocalization.language = previousLanguage }
        NativeLocalization.language = .english

        let generatedScale = PlayAlongExercise(
            id: "c-major-c4",
            title: "C major scale",
            detail: "One octave",
            difficulty: "Beginner",
            category: .major,
            writtenNotes: ["C"],
            writtenMIDIs: [60]
        )
        var session = PlayAlongSession(
            exercise: generatedScale,
            holdDurationMs: 300,
            minimumSamples: 3,
            attackTrimMs: 0
        )

        func frame(octave: Int, cents: Double, confidence: Double = 0.99, timestampMs: Int) -> PitchFrame {
            PitchFrame(
                timestampMs: timestampMs,
                frequencyHz: 261.63,
                confidence: confidence,
                rms: 0.08,
                centsDeviation: cents,
                tuningStatus: cents >= 0 ? .sharp : .flat,
                writtenNoteName: "C",
                writtenOctave: octave,
                isValidForRecording: true
            )
        }

        session.feed(frame(octave: 5, cents: 20, timestampMs: 0))
        XCTAssertFalse(session.detectedMatchesTarget)
        XCTAssertEqual(playAlongFeedback(session), "Move to C4")

        session.feed(frame(octave: 4, cents: 20, timestampMs: 100))
        XCTAssertTrue(session.detectedMatchesTarget)
        XCTAssertEqual(playAlongFeedback(session), "20 cents sharp — ease down")

        session.feed(frame(octave: 4, cents: -20, timestampMs: 200))
        XCTAssertTrue(session.detectedMatchesTarget)
        XCTAssertEqual(playAlongFeedback(session), "20 cents flat — lift up")

        session.feed(frame(octave: 4, cents: 20, confidence: 0.2, timestampMs: 300))
        XCTAssertFalse(session.detectedMatchesTarget)
        XCTAssertEqual(playAlongFeedback(session), "Play C4")
    }

    func testLegacyDroneSettingsDecodeToPriorIntervalEqualTemperamentBehavior() throws {
        let data = Data("""
        {"writtenMIDINote":71,"interval":7,"volume":0.22}
        """.utf8)
        let settings = try JSONDecoder().decode(DroneSettings.self, from: data)

        XCTAssertEqual(settings.voicing, .interval)
        XCTAssertEqual(settings.temperament, .equalTemperament)
        XCTAssertEqual(settings.interval, .perfectFifth)
        XCTAssertEqual(settings.volume, 0.22, accuracy: 0.000_001)
    }

    func testTemperamentRatiosAreRootRelativeAfterInstrumentTransposition() throws {
        let root = try XCTUnwrap(PracticePitchMath.frequency(
            writtenMIDI: 71,
            instrumentID: "trumpet",
            referencePitchHz: 440
        ))
        XCTAssertEqual(root, 440, accuracy: 0.000_001)

        let justFifth = try XCTUnwrap(PracticePitchMath.frequencies(
            writtenMIDI: 71,
            interval: .perfectFifth,
            voicing: .interval,
            temperament: .justIntonation,
            instrumentID: "trumpet",
            referencePitchHz: 440
        ))
        XCTAssertEqual(justFifth.count, 2)
        XCTAssertEqual(justFifth[0], 440, accuracy: 0.000_001)
        XCTAssertEqual(justFifth[1], 660, accuracy: 0.000_001)

        let equalFifth = try XCTUnwrap(PracticePitchMath.frequencies(
            writtenMIDI: 71,
            interval: .perfectFifth,
            voicing: .interval,
            temperament: .equalTemperament,
            instrumentID: "trumpet",
            referencePitchHz: 440
        ))
        XCTAssertEqual(equalFifth[0], root, accuracy: 0.000_001)
        XCTAssertEqual(equalFifth[1] / root, pow(2, 7.0 / 12.0), accuracy: 0.000_001)
    }

    func testMajorAndMinorTriadsExposeConventionalEqualAndJustRatios() throws {
        let majorJust = try XCTUnwrap(PracticePitchMath.frequencies(
            writtenMIDI: 69,
            interval: .unison,
            voicing: .majorTriad,
            temperament: .justIntonation,
            instrumentID: "trombone",
            referencePitchHz: 440
        ))
        XCTAssertEqual(majorJust.count, 3)
        XCTAssertEqual(majorJust[0], 440, accuracy: 0.000_001)
        XCTAssertEqual(majorJust[1], 550, accuracy: 0.000_001)
        XCTAssertEqual(majorJust[2], 660, accuracy: 0.000_001)

        let minorJust = try XCTUnwrap(PracticePitchMath.frequencies(
            writtenMIDI: 69,
            interval: .unison,
            voicing: .minorTriad,
            temperament: .justIntonation,
            instrumentID: "trombone",
            referencePitchHz: 440
        ))
        XCTAssertEqual(minorJust.count, 3)
        XCTAssertEqual(minorJust[0], 440, accuracy: 0.000_001)
        XCTAssertEqual(minorJust[1], 528, accuracy: 0.000_001)
        XCTAssertEqual(minorJust[2], 660, accuracy: 0.000_001)

        let majorEqual = try XCTUnwrap(PracticePitchMath.frequencies(
            writtenMIDI: 69,
            interval: .unison,
            voicing: .majorTriad,
            temperament: .equalTemperament,
            instrumentID: "trombone",
            referencePitchHz: 440
        ))
        XCTAssertEqual(majorEqual[1] / majorEqual[0], pow(2, 4.0 / 12.0), accuracy: 0.000_001)
        XCTAssertEqual(majorEqual[2] / majorEqual[0], pow(2, 7.0 / 12.0), accuracy: 0.000_001)
    }

    func testThreeVoiceNormalizationAndSafeMaximumRemainBelowFullScale() throws {
        XCTAssertEqual(NativeToneOutputPolicy.clampedUserVolume(2), 0.9, accuracy: 0.000_001)
        XCTAssertEqual(NativeToneOutputPolicy.clampedUserVolume(0), 0.05, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(
            NativeToneOutputPolicy.peakBound(voiceCount: 3, masterVolume: 0.9),
            0.9
        )

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096))
        buffer.frameLength = 4_096
        let state = NativeToneRenderState()
        state.configure(frequenciesHz: [440, 550, 660], volume: 1, sampleRate: format.sampleRate)
        _ = state.render(frameCount: buffer.frameLength, audioBufferList: buffer.mutableAudioBufferList)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).reduce(Float.zero) { max($0, abs(samples[$1])) }
        XCTAssertLessThanOrEqual(peak, 1.000_001)
        XCTAssertLessThanOrEqual(peak * Float(NativeToneOutputPolicy.maximumUserVolume), 0.9 + 0.000_001)
    }
}
