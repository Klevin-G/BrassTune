import { describe, expect, it } from 'vitest';
import { estimatePitchFromPcm, pitchFrameFromPcm } from './localPitchDetection';
import { midiToFrequency } from './music';

function sineSamples(frequency: number, sampleRate: number, durationSeconds = 0.25, amplitude = 0.3) {
  const sampleCount = Math.floor(sampleRate * durationSeconds);
  return Float32Array.from({ length: sampleCount }, (_, index) => amplitude * Math.sin((2 * Math.PI * frequency * index) / sampleRate));
}

describe('local pitch detection', () => {
  it('rejects silence without a pitch lock', () => {
    const frame = pitchFrameFromPcm(new Float32Array(4096), 48000, 'trombone', 440, 0);

    expect(frame.frequency_hz).toBeNull();
    expect(frame.tuning_status).toBe('silence');
    expect(frame.is_valid_for_recording).toBe(false);
  });

  it('detects A4 from browser PCM without backend help', () => {
    const frame = pitchFrameFromPcm(sineSamples(440, 48000), 48000, 'trombone', 440, 120);

    expect(frame.frequency_hz ?? 0).toBeCloseTo(440, 0);
    expect(frame.written_note_name).toBe('A');
    expect(frame.written_octave).toBe(4);
    expect(frame.tuning_status).toBe('in_tune');
    expect(frame.is_valid_for_recording).toBe(true);
    expect(frame.detector_source).toBe('browser_local_pitch');
  });

  it('uses the selected instrument range for browser-local frames', () => {
    const frame = pitchFrameFromPcm(sineSamples(40, 48000, 1), 48000, 'tuba', 440, 120);

    expect(frame.frequency_hz ?? 0).toBeGreaterThan(30);
    expect(frame.frequency_hz ?? 0).toBeLessThan(50);
    expect(frame.is_valid_for_recording).toBe(true);
    expect(frame.detector_source).toBe('browser_local_pitch');
  });

  it('keeps cent deviation at 44.1 kHz and 48 kHz sample rates', () => {
    const sharpA = midiToFrequency(69 + 10 / 100, 440);
    const frame441 = pitchFrameFromPcm(sineSamples(sharpA, 44100), 44100, 'trombone', 440, 0);
    const frame480 = pitchFrameFromPcm(sineSamples(sharpA, 48000), 48000, 'trombone', 440, 0);

    expect(frame441.cents_deviation ?? 0).toBeGreaterThan(6);
    expect(frame441.cents_deviation ?? 0).toBeLessThan(14);
    expect(frame480.cents_deviation ?? 0).toBeGreaterThan(6);
    expect(frame480.cents_deviation ?? 0).toBeLessThan(14);
    expect(frame441.tuning_status).toBe('sharp');
    expect(frame480.tuning_status).toBe('sharp');
  });

  it('treats very low input as silence', () => {
    const estimate = estimatePitchFromPcm(sineSamples(440, 48000, 0.2, 0.002), 48000);

    expect(estimate.frequencyHz).toBeNull();
    expect(estimate.rms).toBeLessThan(0.01);
  });
});
