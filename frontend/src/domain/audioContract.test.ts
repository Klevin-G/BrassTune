import { describe, expect, it } from 'vitest';
import dyadCases from '../../../fixtures/drone_dyad_cases.json';
import pitchMathCases from '../../../fixtures/pitch_math_cases.json';
import referenceToneCases from '../../../fixtures/reference_tone_cases.json';
import transpositionCases from '../../../fixtures/transposition_cases.json';
import { nearestMidiForFrequency } from './localPitchDetection';
import { demoProfileFrequencyRanges, demoProfileTransposition, frequencyToMidi, midiToNote } from './music';
import { intervalNoteLabel, referenceToneVoice, writtenNoteFrequency } from './referenceTone';
import { generateWeakTransitionDrill, normalizeWeakDrillNoteLabel } from './transitionDrills';

describe('portable pitch and instrument contract', () => {
  it('uses the same exact half-step rounding expected by Swift', () => {
    for (const testCase of pitchMathCases) {
      expect(nearestMidiForFrequency(testCase.frequency_hz, testCase.reference_pitch_hz), testCase.name).toBe(testCase.expected_nearest_midi);
      expect(Math.round(frequencyToMidi(testCase.frequency_hz, testCase.reference_pitch_hz)), testCase.name).toBe(testCase.expected_nearest_midi);
      const note = midiToNote(testCase.expected_nearest_midi);
      expect(note.note, testCase.name).toBe(testCase.expected_concert_note);
      expect(note.octave, testCase.name).toBe(testCase.expected_concert_octave);
    }
  });

  it('keeps every instrument transposition and acoustic range fixture-aligned', () => {
    for (const testCase of transpositionCases) {
      expect(demoProfileTransposition[testCase.instrument_id], testCase.name).toBe(testCase.expected_written_midi - testCase.concert_midi);
      expect(demoProfileFrequencyRanges[testCase.instrument_id], testCase.name).toEqual({
        minFrequencyHz: testCase.expected_min_frequency_hz,
        maxFrequencyHz: testCase.expected_max_frequency_hz,
      });
    }
  });
});

describe('portable reference tone contract', () => {
  it('uses exact concert frequencies and zero detune for every oscillator voice', () => {
    for (const testCase of referenceToneCases) {
      const frequency = writtenNoteFrequency(
        testCase.written_note,
        testCase.instrument_id,
        testCase.reference_pitch_hz,
        testCase.interval_semitones,
      );
      expect(frequency, testCase.name).not.toBeNull();
      expect(frequency as number, testCase.name).toBeCloseTo(testCase.expected_frequency_hz, 10);
      expect(intervalNoteLabel(testCase.written_note, testCase.interval_semitones), testCase.name).toBe(testCase.expected_interval_note);
      expect(referenceToneVoice(frequency as number, 0)?.detuneCents, testCase.name).toBe(testCase.expected_detune_cents);
      expect(referenceToneVoice(frequency as number, 1)?.detuneCents, testCase.name).toBe(testCase.expected_detune_cents);
    }
  });

  it('keeps both drone voices at the exact fixture frequencies with zero detune', () => {
    for (const testCase of dyadCases) {
      const frequencies = [
        writtenNoteFrequency(testCase.written_note, testCase.instrument_id, testCase.reference_pitch_hz, 0),
        writtenNoteFrequency(testCase.written_note, testCase.instrument_id, testCase.reference_pitch_hz, testCase.interval_semitones),
      ];
      frequencies.forEach((frequency, index) => {
        expect(frequency, testCase.name).toBeCloseTo(testCase.expected_frequencies_hz[index], 10);
        expect(referenceToneVoice(frequency as number, index)?.detuneCents, testCase.name).toBe(testCase.expected_detune_cents[index]);
      });
    }
  });
});

describe('weak transition labels', () => {
  it('strips analytics octaves while preserving normalized accidentals', () => {
    expect(normalizeWeakDrillNoteLabel('B♭3')).toBe('Bb');
    expect(normalizeWeakDrillNoteLabel('f♯5')).toBe('F#');
    expect(normalizeWeakDrillNoteLabel('not-a-note')).toBeNull();

    const result = generateWeakTransitionDrill([
      { note_label: 'C4', avg_signed_cents: 0 }, { note_label: 'D5', avg_signed_cents: 11 },
      { note_label: 'C5', avg_signed_cents: 0 }, { note_label: 'D4', avg_signed_cents: 13 },
      { note_label: 'C3', avg_signed_cents: 0 }, { note_label: 'D6', avg_signed_cents: 15 },
    ]);
    expect(result).toMatchObject({ ready: true, from: 'C', to: 'D', notes: ['C', 'D', 'C', 'D'], evidenceCount: 3 });
  });

  it('treats enharmonic spellings as pitch classes', () => {
    expect(generateWeakTransitionDrill([
      { note_label: 'C#4', avg_signed_cents: 0 }, { note_label: 'D♭5', avg_signed_cents: 20 },
      { note_label: 'D4', avg_signed_cents: 0 }, { note_label: 'C♯5', avg_signed_cents: 11 },
      { note_label: 'D3', avg_signed_cents: 0 }, { note_label: 'D♭6', avg_signed_cents: 13 },
      { note_label: 'D5', avg_signed_cents: 0 }, { note_label: 'C#4', avg_signed_cents: 15 },
    ])).toMatchObject({
      ready: true,
      from: 'D',
      to: 'C#',
      notes: ['D', 'C#', 'D', 'C#'],
      evidenceCount: 3,
    });
  });
});
