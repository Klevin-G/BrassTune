import { describe, expect, it } from 'vitest';
import { nextDemoPitchFrame } from './demoPitch';
import { MIN_RECORDING_CONFIDENCE, midiToFrequency, pitchFrameFromFrequency } from './music';

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
