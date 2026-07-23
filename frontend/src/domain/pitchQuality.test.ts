import { describe, expect, it } from 'vitest';
import qualityContract from '../../../fixtures/pitch_quality_contract.json';
import { estimatePitchFromPcm, nearestMidiForFrequency } from './localPitchDetection';
import { frequencyToMidi } from './music';

function percentile95(values: number[]) {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.max(0, Math.ceil(sorted.length * 0.95) - 1)];
}

function harmonicTone(frequencyHz: number) {
  const { frame_size: frameSize, sample_rate_hz: sampleRate, harmonic_amplitudes: amplitudes } = qualityContract;
  return Float32Array.from({ length: frameSize }, (_, index) => {
    const time = index / sampleRate;
    return amplitudes.reduce((sum, amplitude, harmonic) => sum + amplitude * Math.sin(2 * Math.PI * frequencyHz * (harmonic + 1) * time), 0);
  });
}

describe('synthetic pitch quality gate', () => {
  it('meets note/octave, gross-octave, cents, onset, and cross-platform thresholds', () => {
    const signedErrors: number[] = [];
    const crossPlatformDeltas: number[] = [];
    let correctNoteAndOctave = 0;
    let grossOctaveErrors = 0;

    for (const testCase of qualityContract.cases) {
      const estimate = estimatePitchFromPcm(harmonicTone(testCase.frequency_hz), qualityContract.sample_rate_hz, {
        minFrequencyHz: 30,
        maxFrequencyHz: 1500,
      });
      expect(estimate.frequencyHz, testCase.note).not.toBeNull();
      const frequency = estimate.frequencyHz as number;
      const estimatedMidi = frequencyToMidi(frequency, 440);
      const signedError = (estimatedMidi - testCase.midi) * 100;
      signedErrors.push(signedError);
      crossPlatformDeltas.push(Math.abs(signedError - testCase.expected_python_signed_cents_error));
      if (nearestMidiForFrequency(frequency, 440) === testCase.midi) correctNoteAndOctave += 1;
      if (Math.abs(estimatedMidi - testCase.midi) >= 11.5) grossOctaveErrors += 1;
    }

    const accuracy = (correctNoteAndOctave / qualityContract.cases.length) * 100;
    const grossOctaveRate = (grossOctaveErrors / qualityContract.cases.length) * 100;
    const absoluteErrors = signedErrors.map(Math.abs);
    const sortedErrors = [...absoluteErrors].sort((left, right) => left - right);
    const medianError = (sortedErrors[3] + sortedErrors[4]) / 2;
    const onsetP95Ms = (qualityContract.frame_size / qualityContract.sample_rate_hz) * 1000;

    expect(accuracy).toBeGreaterThanOrEqual(qualityContract.thresholds.steady_note_octave_accuracy_min_percent);
    expect(grossOctaveRate).toBeLessThanOrEqual(qualityContract.thresholds.gross_octave_error_max_percent);
    expect(medianError).toBeLessThanOrEqual(qualityContract.thresholds.median_abs_cents_error_max);
    expect(percentile95(absoluteErrors)).toBeLessThanOrEqual(qualityContract.thresholds.p95_abs_cents_error_max);
    expect(onsetP95Ms).toBeLessThanOrEqual(qualityContract.thresholds.onset_p95_ms_max);
    expect(percentile95(crossPlatformDeltas)).toBeLessThanOrEqual(qualityContract.thresholds.cross_platform_p95_cents_delta_max);
  });
});
