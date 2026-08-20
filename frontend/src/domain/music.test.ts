import { describe, expect, it } from 'vitest';
import { nextDemoPitchFrame } from './demoPitch';
import { EXERCISES } from './playAlong';
import {
  MIN_RECORDING_CONFIDENCE,
  demoProfileDetectorFrequencyRanges,
  demoProfilePracticalMidiRanges,
  midiToFrequency,
  noteLabelToMidi,
  pitchFrameFromFrequency,
} from './music';

function stddev(values: number[]) {
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
  const variance = values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / values.length;
  return Math.sqrt(variance);
}

describe('pitchFrameFromFrequency', () => {
  it('requires at least 95 percent confidence before recording a pitch', () => {
    const lowConfidence = pitchFrameFromFrequency(
      midiToFrequency(69),
      0,
      'trombone',
      440,
      0,
      MIN_RECORDING_CONFIDENCE - 0.01,
      0.1,
    );

    expect(lowConfidence.tuning_status).toBe('unstable');
    expect(lowConfidence.is_valid_for_recording).toBe(false);
  });

  it('keeps clean high-confidence tones recordable', () => {
    const frame = pitchFrameFromFrequency(midiToFrequency(69), 0, 'trombone', 440, 0, MIN_RECORDING_CONFIDENCE, 0.1);

    expect(frame.tuning_status).toBe('in_tune');
    expect(frame.is_valid_for_recording).toBe(true);
  });

  it('rejects high-confidence pitches outside the selected instrument range', () => {
    const trumpetLow = pitchFrameFromFrequency(100, 0, 'trumpet', 440, 0, MIN_RECORDING_CONFIDENCE, 0.1);
    const tubaHigh = pitchFrameFromFrequency(620, 0, 'tuba', 440, 0, MIN_RECORDING_CONFIDENCE, 0.1);

    expect(trumpetLow.is_valid_for_recording).toBe(false);
    expect(trumpetLow.save_eligibility_reason).toBe('outside instrument range');
    expect(tubaHigh.is_valid_for_recording).toBe(false);
    expect(tubaHigh.save_eligibility_reason).toBe('outside instrument range');
  });

  it.each([430, 440, 450])('accepts practical-boundary notes within ten cents at A4 %i', (referencePitch) => {
    const practical = demoProfilePracticalMidiRanges.trombone;
    for (const midi of [practical.minimumMidi - 0.1, practical.maximumMidi + 0.1]) {
      const frame = pitchFrameFromFrequency(
        midiToFrequency(midi, referencePitch),
        0,
        'trombone',
        referencePitch,
        0,
        MIN_RECORDING_CONFIDENCE,
        0.1,
      );
      expect(frame.is_valid_for_recording).toBe(true);
      expect(frame.save_eligibility_reason).toBe('valid for recording');
    }
  });

  it('keeps an outside-practical but inside-detector B-flat treble frame recordable', () => {
    const frame = pitchFrameFromFrequency(
      midiToFrequency(37, 440),
      0,
      'baritone',
      440,
      0,
      MIN_RECORDING_CONFIDENCE,
      0.1,
    );

    expect(frame.frequency_hz).not.toBeNull();
    expect(frame.nearest_midi).toBe(37);
    expect(frame.written_note_name).toBe('Eb');
    expect(frame.written_octave).toBe(3);
    expect(frame.is_valid_for_recording).toBe(true);
    expect(frame.save_eligibility_reason).toBe('valid for recording');
  });

  it('uses inclusive exact detector boundaries before rejecting the next representable frequency', () => {
    for (const [instrumentId, range] of Object.entries(demoProfileDetectorFrequencyRanges)) {
      for (const frequency of [range.minFrequencyHz, range.maxFrequencyHz]) {
        const frame = pitchFrameFromFrequency(frequency, 0, instrumentId, 440, 0, MIN_RECORDING_CONFIDENCE, 0.1);
        expect(frame.frequency_hz, `${instrumentId} ${frequency}`).toBe(frequency);
        expect(frame.nearest_midi, `${instrumentId} ${frequency}`).not.toBeNull();
      }
      const below = pitchFrameFromFrequency(range.minFrequencyHz - Number.EPSILON * range.minFrequencyHz * 2, 0, instrumentId, 440, 0, MIN_RECORDING_CONFIDENCE, 0.1);
      const above = pitchFrameFromFrequency(range.maxFrequencyHz + Number.EPSILON * range.maxFrequencyHz * 2, 0, instrumentId, 440, 0, MIN_RECORDING_CONFIDENCE, 0.1);
      expect(below.nearest_midi, `${instrumentId} below detector minimum`).toBeNull();
      expect(above.nearest_midi, `${instrumentId} above detector maximum`).toBeNull();
    }
  });

  it('keeps high-jitter demo notes recordable while reserving no-lock for silence', () => {
    const frames = Array.from({ length: 18 }, (_, offset) => nextDemoPitchFrame(54 + offset, 'trumpet', 440));
    const recordable = frames.filter((frame) => frame.is_valid_for_recording);
    const noLock = frames.filter((frame) => !frame.is_valid_for_recording);
    const cents = recordable.map((frame) => frame.cents_deviation ?? 0);

    expect(recordable.length).toBeGreaterThan(10);
    expect(recordable.every((frame) => frame.confidence >= MIN_RECORDING_CONFIDENCE)).toBe(true);
    expect(stddev(cents)).toBeGreaterThan(4);
    expect(noLock.length).toBeGreaterThan(0);
    expect(noLock.every((frame) => frame.confidence < MIN_RECORDING_CONFIDENCE)).toBe(true);
  });
});

describe('noteLabelToMidi', () => {
  it('converts edge enharmonic spellings to the correct finite MIDI notes', () => {
    expect(noteLabelToMidi('E#4')).toBe(65);
    expect(noteLabelToMidi('F4')).toBe(65);
    expect(noteLabelToMidi('Cb4')).toBe(59);
    expect(noteLabelToMidi('B3')).toBe(59);
    expect(noteLabelToMidi('Fb4')).toBe(64);
    expect(noteLabelToMidi('B#3')).toBe(60);
    expect(noteLabelToMidi('F♯4')).toBe(66);
    expect(noteLabelToMidi('D♭4')).toBe(61);
    expect(midiToFrequency(noteLabelToMidi('E#4'))).toBeCloseTo(midiToFrequency(noteLabelToMidi('F4')), 10);
    expect(midiToFrequency(noteLabelToMidi('Cb4'))).toBeCloseTo(midiToFrequency(noteLabelToMidi('B3')), 10);
  });

  it('supports every written spelling in the play-along catalog', () => {
    const notes = new Set(EXERCISES.flatMap((exercise) => exercise.notes));
    for (const note of notes) {
      const midi = noteLabelToMidi(`${note}4`);
      expect(Number.isFinite(midi), note).toBe(true);
      expect(Number.isFinite(midiToFrequency(midi)), note).toBe(true);
    }
  });
});
