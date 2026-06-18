import { describe, expect, it } from 'vitest';
import { MIN_RECORDING_CONFIDENCE } from './music';
import { MAX_LOCAL_MEDIA_BYTES, validateLocalMediaFile, yinPitchForSamples } from './localMediaAnalysis';

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

  it('rejects empty and oversized files before decoding', () => {
    expect(() => validateLocalMediaFile(new File([], 'empty.wav', { type: 'audio/wav' }))).toThrow(/non-empty/i);
    const oversized = { size: MAX_LOCAL_MEDIA_BYTES + 1, type: 'audio/wav' } as File;
    expect(() => validateLocalMediaFile(oversized)).toThrow(/smaller than 250 MB/i);
  });

  it('rejects unsupported file types before decoding', () => {
    const file = new File(['not media'], 'notes.txt', { type: 'text/plain' });
    expect(() => validateLocalMediaFile(file)).toThrow(/audio or video/i);
  });
});
