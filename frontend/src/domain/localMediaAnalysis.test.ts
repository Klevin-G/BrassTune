import { describe, expect, it } from 'vitest';
import { MIN_RECORDING_CONFIDENCE } from './music';
import { yinPitchForSamples } from './localMediaAnalysis';

describe('local media analysis detector', () => {
  it('detects a clean local A4 tone without uploading source media', () => {
    const sampleRate = 48000;
    const samples = new Float32Array(4096);
    for (let index = 0; index < samples.length; index += 1) {
      samples[index] = 0.8 * Math.sin((2 * Math.PI * 440 * index) / sampleRate);
    }
    const estimate = yinPitchForSamples(samples, sampleRate, 80, 1000);
    expect(estimate.confidence).toBeGreaterThanOrEqual(MIN_RECORDING_CONFIDENCE);
    expect(Math.abs(estimate.frequencyHz - 440)).toBeLessThan(2);
  });
});
