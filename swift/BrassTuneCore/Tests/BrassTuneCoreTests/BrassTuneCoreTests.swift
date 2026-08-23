import Foundation
import Testing
@testable import BrassTuneCore

private struct PitchMathCase: Decodable {
    let frequency_hz: Double
    let reference_pitch_hz: Double
    let expected_nearest_midi: Int
    let expected_cents: Double
}

private struct TranspositionCase: Decodable {
    let instrument_id: String
    let concert_midi: Int
    let expected_written_midi: Int
    let expected_detector_min_frequency_hz: Double
    let expected_detector_max_frequency_hz: Double
}

private let transpositions = [
    "trumpet": 2,
    "horn": 7,
    "trombone": 0,
    "euphonium": 0,
    "baritone": 14,
    "euphonium-treble": 14,
    "tuba": 0
]

private func fixtureURL(_ name: String) throws -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures")
        .appendingPathComponent(name)
}

private func loadFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    let data = try Data(contentsOf: fixtureURL(name))
    return try JSONDecoder().decode(T.self, from: data)
}

@Test func pitchMathFixturesMatchWebCore() throws {
    let cases = try loadFixture("pitch_math_cases.json", as: [PitchMathCase].self)
    for item in cases {
        let midi = BrassTuneCore.frequencyToMidi(item.frequency_hz, referencePitchHz: item.reference_pitch_hz)
        #expect(Int(midi.rounded()) == item.expected_nearest_midi)
        let cents = BrassTuneCore.centsDeviation(frequencyHz: item.frequency_hz, nearestMidi: item.expected_nearest_midi, referencePitchHz: item.reference_pitch_hz)
        #expect(abs(cents - item.expected_cents) < 0.05)
    }
}

@Test func transpositionFixturesMatchWebCore() throws {
    let cases = try loadFixture("transposition_cases.json", as: [TranspositionCase].self)
    for item in cases {
        #expect(BrassTuneCore.transposeConcertToWritten(item.concert_midi, semitones: transpositions[item.instrument_id] ?? 0) == item.expected_written_midi)
        let profile = try #require(InstrumentProfiles.profile(for: item.instrument_id))
        #expect(profile.detectorFrequencyRange.minimumHz == item.expected_detector_min_frequency_hz)
        #expect(profile.detectorFrequencyRange.maximumHz == item.expected_detector_max_frequency_hz)
    }
}

@Test func confidenceSemanticsMatchBrassTune() {
    #expect(BrassTuneCore.tuningStatus(cents: 0, confidence: 0.94, rms: 0.1) == .unstable)
    #expect(BrassTuneCore.tuningStatus(cents: 0, confidence: 0.95, rms: 0.1) == .inTune)
    #expect(BrassTuneCore.tuningStatus(cents: nil, confidence: 0.99, rms: 0.0) == .silence)
    #expect(BrassTuneCore.tuningStatus(cents: 0, confidence: 0.99, rms: 0.0099) == .silence)
    #expect(BrassTuneCore.tuningStatus(cents: nil, confidence: 0.99, rms: 0.01) == .noLock)
}

@Test func instrumentRegistryRetainsKnownIDsAndFailsClosed() {
    let bbSopranoIDs = ["trumpet", "cornet", "flugelhorn"]
    for id in bbSopranoIDs {
        let profile = InstrumentProfiles.profile(for: id)
        #expect(profile?.transpositionSemitones == 2)
        #expect(profile?.displayNotation == "B♭")
        #expect(profile?.preferredClef == .treble)
    }
    for id in ["baritone", "euphonium-treble"] {
        let profile = InstrumentProfiles.profile(for: id)
        #expect(profile?.transpositionSemitones == 14)
        #expect(profile?.displayNotation == "B♭")
        #expect(profile?.preferredClef == .treble)
    }
    #expect(InstrumentProfiles.profile(for: "horn")?.transpositionSemitones == 7)
    #expect(InstrumentProfiles.profile(for: "french-horn")?.id == "horn")
    for id in ["c-trumpet", "trombone", "euphonium", "baritone-concert", "tuba"] {
        #expect(InstrumentProfiles.profile(for: id)?.transpositionSemitones == 0)
    }
    #expect(InstrumentProfiles.profile(for: "mystery-horn") == nil)
    #expect(BrassTuneCore.instrumentProfile(for: "mystery-horn") == nil)
}

@Test func instrumentProfilesTransposeWrittenPitchAndPublishPracticalRanges() throws {
    let trumpet = try #require(InstrumentProfiles.profile(for: "trumpet"))
    let horn = try #require(InstrumentProfiles.profile(for: "horn"))
    let trombone = try #require(InstrumentProfiles.profile(for: "trombone"))
    let euphoniumTreble = try #require(InstrumentProfiles.profile(for: "euphonium-treble"))
    #expect(BrassTuneCore.transposeConcertToWritten(60, semitones: trumpet.transpositionSemitones) == 62)
    #expect(BrassTuneCore.transposeConcertToWritten(60, semitones: horn.transpositionSemitones) == 67)
    #expect(BrassTuneCore.transposeConcertToWritten(60, semitones: trombone.transpositionSemitones) == 60)
    #expect(BrassTuneCore.transposeWrittenToConcert(62, semitones: trumpet.transpositionSemitones) == 60)
    #expect(trumpet.practicalWrittenRange.contains(54))
    #expect(trumpet.practicalSoundingRange.contains(52))
    #expect(BrassTuneCore.transposeWrittenToConcert(60, semitones: euphoniumTreble.transpositionSemitones) == 46)
    #expect(BrassTuneCore.transposeConcertToWritten(46, semitones: euphoniumTreble.transpositionSemitones) == 60)
    #expect(euphoniumTreble.practicalWrittenRange == MIDIRange(minimum: 52, maximum: 82))
    #expect(euphoniumTreble.practicalSoundingRange == MIDIRange(minimum: 38, maximum: 68))
}

@Test func detectorWindowsAreBroadFamilyRangesSeparateFromPracticalRegisters() throws {
    let expected: [String: DetectorFrequencyRange] = [
        "trumpet": DetectorFrequencyRange(minimumHz: 130, maximumHz: 1_500),
        "cornet": DetectorFrequencyRange(minimumHz: 130, maximumHz: 1_500),
        "flugelhorn": DetectorFrequencyRange(minimumHz: 130, maximumHz: 1_500),
        "c-trumpet": DetectorFrequencyRange(minimumHz: 130, maximumHz: 1_500),
        "horn": DetectorFrequencyRange(minimumHz: 80, maximumHz: 1_200),
        "trombone": DetectorFrequencyRange(minimumHz: 50, maximumHz: 700),
        "euphonium": DetectorFrequencyRange(minimumHz: 55, maximumHz: 800),
        "baritone-concert": DetectorFrequencyRange(minimumHz: 55, maximumHz: 800),
        "baritone": DetectorFrequencyRange(minimumHz: 55, maximumHz: 800),
        "euphonium-treble": DetectorFrequencyRange(minimumHz: 55, maximumHz: 800),
        "tuba": DetectorFrequencyRange(minimumHz: 30, maximumHz: 500),
    ]

    for (instrumentID, range) in expected {
        let profile = try #require(InstrumentProfiles.profile(for: instrumentID))
        #expect(profile.detectorFrequencyRange == range)
        #expect(range.contains(range.minimumHz))
        #expect(range.contains(range.maximumHz))
        #expect(!range.contains(range.minimumHz.nextDown))
        #expect(!range.contains(range.maximumHz.nextUp))
    }

    let trumpet = try #require(InstrumentProfiles.profile(for: "trumpet"))
    let practicalMinimumHz = BrassTuneCore.midiToFrequency(Double(trumpet.practicalSoundingRange.minimum))
    let practicalMaximumHz = BrassTuneCore.midiToFrequency(Double(trumpet.practicalSoundingRange.maximum))
    #expect(trumpet.detectorFrequencyRange.minimumHz < practicalMinimumHz)
    #expect(trumpet.detectorFrequencyRange.maximumHz > practicalMaximumHz)
}

@Test func referencePitchBoundariesPreservePitchMathAndDetectorEndpoints() throws {
    let trumpet = try #require(InstrumentProfiles.profile(for: "trumpet"))
    for referencePitchHz in [430.0, 440.0, 450.0] {
        #expect(abs(BrassTuneCore.frequencyToMidi(referencePitchHz, referencePitchHz: referencePitchHz) - 69) < 1e-12)
        #expect(abs(BrassTuneCore.centsDeviation(frequencyHz: referencePitchHz, nearestMidi: 69, referencePitchHz: referencePitchHz)) < 1e-12)
        #expect(trumpet.detectorFrequencyRange.contains(trumpet.detectorFrequencyRange.minimumHz))
        #expect(trumpet.detectorFrequencyRange.contains(trumpet.detectorFrequencyRange.maximumHz))
    }
}

@Test func everyRootTypeDirectionAndOctaveGeneratesDeterministically() throws {
    for root in ScaleRoot.allCases {
        for type in ScaleType.allCases {
            for direction in ScaleDirection.allCases {
                for octaves in ScaleOctaves.allCases {
                    let scale = try #require(ScaleGenerator.generate(
                        root: root, type: type, octaves: octaves, direction: direction
                    ))
                    let expectedAscendingCount = type == .chromatic ? (12 * octaves.rawValue) + 1 : (7 * octaves.rawValue) + 1
                    let expectedCount = direction == .both ? (expectedAscendingCount * 2) - 1 : expectedAscendingCount
                    #expect(scale.notes.count == expectedCount)
                    #expect(scale.notes.allSatisfy { $0.soundingMIDI == $0.writtenMIDI })
                }
            }
        }
    }
}

@Test func scaleSpellingsAndMelodicMinorDescentAreMusicallySensible() throws {
    let bbMajor = try #require(ScaleGenerator.generate(root: .bb, type: .major, direction: .ascending))
    #expect(bbMajor.notes.map(\.writtenName) == ["B♭", "C", "D", "E♭", "F", "G", "A", "B♭"])
    let fsMajor = try #require(ScaleGenerator.generate(root: .fs, type: .major, direction: .ascending))
    #expect(fsMajor.notes.map(\.writtenName) == ["F♯", "G♯", "A♯", "B", "C♯", "D♯", "E♯", "F♯"])
    let aMelodic = try #require(ScaleGenerator.generate(root: .a, type: .melodicMinor, direction: .both))
    #expect(aMelodic.notes.map(\.writtenName) == ["A", "B", "C", "D", "E", "F♯", "G♯", "A", "G", "F", "E", "D", "C", "B", "A"])
}

@Test func rangePolicyRejectsImpossibleRequestedRegisterAndCanAdapt() throws {
    let tuba = try #require(InstrumentProfiles.profile(for: "tuba"))
    #expect(ScaleGenerator.generate(root: .b, type: .major, octaves: .two, profile: tuba, rangePolicy: .reject) == nil)
    let adapted = try #require(ScaleGenerator.generate(root: .b, type: .major, octaves: .two, profile: tuba, rangePolicy: .adapt))
    #expect(adapted.notes.allSatisfy { tuba.practicalWrittenRange.contains($0.writtenMIDI) })
    #expect(adapted.notes.first?.writtenMIDI == 35)
}

@Test func threeOctaveScalesNeverClipToAnInstrumentRange() throws {
    let tuba = try #require(InstrumentProfiles.profile(for: "tuba"))
    let threeOctave = try #require(ScaleGenerator.generate(
        root: .d, type: .major, octaves: .three, direction: .both, profile: tuba, rangePolicy: .adapt
    ))
    #expect(threeOctave.notes.count == 43)
    #expect(threeOctave.notes.map(\.writtenMIDI).min() == 26)
    #expect(threeOctave.notes.map(\.writtenMIDI).max() == 62)
    #expect(threeOctave.notes.allSatisfy { tuba.practicalWrittenRange.contains($0.writtenMIDI) })

    let narrowRange = InstrumentProfile(
        id: "narrow", displayName: "Narrow", displayNotation: "C", transpositionSemitones: 0,
        notationPreference: .concert, preferredClef: .bass,
        practicalWrittenRange: MIDIRange(minimum: 60, maximum: 83),
        practicalSoundingRange: MIDIRange(minimum: 60, maximum: 83)
    )
    #expect(ScaleGenerator.generate(root: .c, type: .major, octaves: .three, profile: narrowRange, rangePolicy: .adapt) == nil)
}

@Test func exhaustiveProfileScaleMatrixPreservesRangeAndTranspositionContracts() {
    // 11 registered profiles × 12 roots × 5 types × 3 octave choices × 3
    // directions = 5,940 generated-scale requests. Exercise both policies so
    // any range adaptation remains an explicit octave move rather than an
    // accidental out-of-range sequence.
    var requestCount = 0
    var adaptedRequestCount = 0
    var impossibleRequestCount = 0

    for profile in InstrumentProfiles.all {
        for root in ScaleRoot.allCases {
            for type in ScaleType.allCases {
                for octaves in ScaleOctaves.allCases {
                    for direction in ScaleDirection.allCases {
                        requestCount += 1
                        let requestedRootMIDI = 60 + root.pitchClass
                        let rejected = ScaleGenerator.generate(
                            root: root,
                            type: type,
                            octaves: octaves,
                            direction: direction,
                            profile: profile,
                            rangePolicy: .reject
                        )
                        let resolved = ScaleGenerator.generate(
                            root: root,
                            type: type,
                            octaves: octaves,
                            direction: direction,
                            profile: profile,
                            rangePolicy: .adapt
                        )

                        if let rejected {
                            #expect(rejected.notes.allSatisfy { profile.practicalWrittenRange.contains($0.writtenMIDI) })
                            #expect(rejected.notes.map(\.writtenMIDI).min() == requestedRootMIDI)
                        }

                        guard let resolved else {
                            impossibleRequestCount += 1
                            #expect(rejected == nil)
                            continue
                        }

                        #expect(resolved.notes.allSatisfy { profile.practicalWrittenRange.contains($0.writtenMIDI) })
                        #expect(resolved.notes.map(\.writtenMIDI).min().map { ($0 - requestedRootMIDI).isMultiple(of: 12) } == true)
                        for note in resolved.notes {
                            #expect(note.soundingMIDI == note.writtenMIDI - profile.transpositionSemitones)
                            #expect(BrassTuneCore.transposeWrittenToConcert(note.writtenMIDI, semitones: profile.transpositionSemitones) == note.soundingMIDI)
                            #expect(BrassTuneCore.transposeConcertToWritten(note.soundingMIDI, semitones: profile.transpositionSemitones) == note.writtenMIDI)
                        }

                        if rejected == nil {
                            adaptedRequestCount += 1
                            #expect(resolved.notes.map(\.writtenMIDI).min() != requestedRootMIDI)
                        }
                    }
                }
            }
        }
    }

    #expect(requestCount == InstrumentProfiles.all.count * ScaleRoot.allCases.count * ScaleType.allCases.count * ScaleOctaves.allCases.count * ScaleDirection.allCases.count)
    #expect(adaptedRequestCount > 0)
    // Narrow profiles legitimately cannot accommodate some multi-octave forms;
    // those requests are valid only when both policies explicitly return nil.
    #expect(impossibleRequestCount > 0)
}
