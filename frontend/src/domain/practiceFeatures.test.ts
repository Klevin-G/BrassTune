import { describe, expect, it } from 'vitest';
import {
  INTERVALS,
  intervalNoteLabel,
  intervalWrittenMidiLabel,
  writtenMidiFrequency,
  writtenMidiLabel,
  writtenNoteFrequency,
} from './referenceTone';
import { generateWeakTransitionDrill } from './transitionDrills';
import { GUIDED_WARMUP_SECONDS, GUIDED_WARMUP_STEPS, warmupStepAt } from './warmup';

describe('guided warm-up', () => {
  it('is exactly five minutes and resolves resumable positions', () => {
    expect(GUIDED_WARMUP_SECONDS).toBe(300);
    expect(GUIDED_WARMUP_STEPS).toHaveLength(5);
    expect(GUIDED_WARMUP_STEPS.map((step) => step.seconds)).toEqual([45, 45, 75, 75, 60]);
    expect(warmupStepAt(46)).toEqual({ index: 1, elapsedInStep: 1 });
    expect(warmupStepAt(300)).toEqual({ index: 4, elapsedInStep: 60 });
  });
});

describe('transition drills', () => {
  const event = (note_label: string, avg_signed_cents: number) => ({ note_label, avg_signed_cents });
  it('requires three examples of a transition', () => {
    expect(generateWeakTransitionDrill([event('C', 0), event('D', 12), event('C', 0), event('D', 14)])).toMatchObject({ ready: false });
    expect(generateWeakTransitionDrill([event('C', 0), event('D', 12), event('C', 0), event('D', 14), event('C', 0), event('D', 16)])).toMatchObject({ ready: true, from: 'C', to: 'D', evidenceCount: 3, notes: ['C', 'D', 'C', 'D', 'C', 'D'] });
  });

  it('selects the highest-error supported pair deterministically', () => {
    const events = [event('C', 0), event('D', 10), event('C', 30), event('D', 10), event('C', 30), event('D', 10), event('C', 30)];
    expect(generateWeakTransitionDrill(events)).toMatchObject({ ready: true, from: 'D', to: 'C', averageError: 30 });
  });

  it('breaks exact score and evidence ties by numeric pitch class', () => {
    const events = [
      event('F', 0), event('G', 20), event('F', 0), event('G', 20), event('F', 0), event('G', 20),
      event('C', 0), event('D', 20), event('C', 0), event('D', 20), event('C', 0), event('D', 20),
    ];
    expect(generateWeakTransitionDrill(events)).toMatchObject({ ready: true, from: 'C', to: 'D' });
  });
});

describe('reference tones', () => {
  it('transposes written notes for known instruments and fails closed for unknown instruments', () => {
    expect(writtenNoteFrequency('C', 'trumpet', 440)).toBeCloseTo(233.08, 1);
    expect(writtenNoteFrequency('C', 'trombone', 440)).toBeCloseTo(261.63, 1);
    expect(writtenNoteFrequency('C', 'mystery-horn', 440)).toBeNull();
    expect(intervalNoteLabel('C', 7)).toBe('G');
  });

  it('covers written MIDI 36–84 and the complete interval set without guessing unknown instruments', () => {
    expect(INTERVALS.map((item) => item.semitones)).toEqual([0, 2, 4, 5, 7, 12]);
    expect(writtenMidiLabel(36)).toBe('C2');
    expect(writtenMidiLabel(84)).toBe('C6');
    expect(intervalWrittenMidiLabel(70, 2)).toBe('C5');
    expect(writtenMidiFrequency(36, 'trombone', 440)).toBeCloseTo(65.406, 3);
    expect(writtenMidiFrequency(84, 'trombone', 440)).toBeCloseTo(1046.502, 3);
    expect(writtenMidiFrequency(70, 'trumpet', 440, 2)).toBeCloseTo(466.1637615180899, 8);
    expect(writtenMidiFrequency(35, 'trombone', 440)).toBeNull();
    expect(writtenMidiFrequency(85, 'trombone', 440)).toBeNull();
    expect(writtenMidiFrequency(60, 'mystery-horn', 440)).toBeNull();
  });
});
