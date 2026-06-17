import { describe, expect, it } from 'vitest';
import { MIN_RECORDING_CONFIDENCE, midiToFrequency, pitchFrameFromFrequency } from './music';

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
});
