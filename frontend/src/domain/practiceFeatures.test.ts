import { describe, expect, it } from 'vitest';
import { intervalNoteLabel, writtenNoteFrequency } from './referenceTone';
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
    expect(generateWeakTransitionDrill([event('C', 0), event('D', 12), event('C', 0), event('D', 14), event('C', 0), event('D', 16)])).toMatchObject({ ready: true, from: 'C', to: 'D', evidenceCount: 3, notes: ['C', 'D', 'C', 'D'] });
  });

  it('selects the highest-error supported pair deterministically', () => {
    const events = [event('C', 0), event('D', 10), event('C', 30), event('D', 10), event('C', 30), event('D', 10), event('C', 30)];
    expect(generateWeakTransitionDrill(events)).toMatchObject({ ready: true, from: 'D', to: 'C', averageError: 30 });
  });
});

describe('reference tones', () => {
  it('transposes written notes for known instruments and fails closed for unknown instruments', () => {
    expect(writtenNoteFrequency('C', 'trumpet', 440)).toBeCloseTo(233.08, 1);
    expect(writtenNoteFrequency('C', 'trombone', 440)).toBeCloseTo(261.63, 1);
    expect(writtenNoteFrequency('C', 'mystery-horn', 440)).toBeNull();
    expect(intervalNoteLabel('C', 7)).toBe('G');
  });
});
