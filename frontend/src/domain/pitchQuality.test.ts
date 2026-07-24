import { describe, expect, it } from 'vitest';
import qualityContract from '../../../fixtures/pitch_quality_contract.json';
import { estimatePitchFromPcm, nearestMidiForFrequency } from './localPitchDetection';
import { frequencyToMidi, midiToFrequency } from './music';

function percentile95(values: number[]) {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.max(0, Math.ceil(sorted.length * 0.95) - 1)];
}

function harmonicTone(frequencyHz: number, amplitudeMultiplier = 1) {
  const { frame_size: frameSize, sample_rate_hz: sampleRate, harmonic_amplitudes: amplitudes } = qualityContract;
  return Float32Array.from({ length: frameSize }, (_, index) => {
    const time = index / sampleRate;
    return amplitudes.reduce(
      (sum, amplitude, harmonic) => sum + amplitude * amplitudeMultiplier * Math.sin(2 * Math.PI * frequencyHz * (harmonic + 1) * time),
      0,
    );
  });
}

describe('synthetic pitch quality gate', () => {
  it('uses shared nearest-note accuracy and inclusive 600-cent gross-error semantics', () => {
    expect(qualityContract.benchmark_policy.accuracy_definition)
      .toBe('nearest_midi_half_up_equals_expected_midi');

    for (const testCase of qualityContract.benchmark_semantics_cases) {
      const frequency = midiToFrequency(testCase.detected_midi, 440);
      const signedErrorCents = (testCase.detected_midi - testCase.expected_midi) * 100;
      expect(
        nearestMidiForFrequency(frequency, 440) === testCase.expected_midi,
        `${testCase.name}: accuracy`,
      ).toBe(testCase.expected_accurate);
      expect(
        Math.abs(signedErrorCents) >= qualityContract.benchmark_policy.gross_octave_error_cents_inclusive,
        `${testCase.name}: gross octave error`,
      ).toBe(testCase.expected_gross_octave_error);
    }
  });

  it('meets steady note/octave, gross-octave, cents, and cross-platform thresholds', () => {
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
      if (Math.abs(signedError) >= qualityContract.benchmark_policy.gross_octave_error_cents_inclusive) {
        grossOctaveErrors += 1;
      }
    }

    const accuracy = (correctNoteAndOctave / qualityContract.cases.length) * 100;
    const grossOctaveRate = (grossOctaveErrors / qualityContract.cases.length) * 100;
    const absoluteErrors = signedErrors.map(Math.abs);
    const sortedErrors = [...absoluteErrors].sort((left, right) => left - right);
    const medianError = (sortedErrors[3] + sortedErrors[4]) / 2;

    expect(accuracy).toBeGreaterThanOrEqual(qualityContract.thresholds.steady_note_octave_accuracy_min_percent);
    expect(grossOctaveRate).toBeLessThanOrEqual(qualityContract.thresholds.gross_octave_error_max_percent);
    expect(medianError).toBeLessThanOrEqual(qualityContract.thresholds.median_abs_cents_error_max);
    expect(percentile95(absoluteErrors)).toBeLessThanOrEqual(qualityContract.thresholds.p95_abs_cents_error_max);
    expect(percentile95(crossPlatformDeltas)).toBeLessThanOrEqual(qualityContract.thresholds.cross_platform_p95_cents_delta_max);
  });

  it('measures a deterministic synthetic onset time-to-first-lock p95 distribution', () => {
    const protocol = qualityContract.synthetic_onset_protocol;
    const frameDurationMs = (qualityContract.frame_size / qualityContract.sample_rate_hz) * 1000;
    const onsetLatenciesMs: number[] = [];

    expect(protocol.evidence_kind).toContain('deterministic synthetic amplitude ramps');
    expect(protocol.evidence_kind).toContain('not physical microphone');

    for (const testCase of qualityContract.cases) {
      const onsetFrame = testCase.onset_amplitude_multipliers.findIndex((amplitude) => amplitude > 0);
      let firstLockFrame = -1;

      for (const [frameIndex, amplitude] of testCase.onset_amplitude_multipliers.entries()) {
        const estimate = estimatePitchFromPcm(harmonicTone(testCase.frequency_hz, amplitude), qualityContract.sample_rate_hz, {
          minFrequencyHz: 30,
          maxFrequencyHz: 1500,
        });
        const centsError =
          estimate.frequencyHz == null ? Number.POSITIVE_INFINITY : Math.abs(1200 * Math.log2(estimate.frequencyHz / testCase.frequency_hz));
        if (
          estimate.frequencyHz != null &&
          estimate.confidence >= protocol.lock_confidence_min &&
          centsError <= protocol.lock_frequency_tolerance_cents_max
        ) {
          firstLockFrame = frameIndex;
          break;
        }
      }

      expect(onsetFrame, `${testCase.note}: onset frame`).toBeGreaterThanOrEqual(0);
      expect(firstLockFrame, `${testCase.note}: first lock frame`).toBeGreaterThanOrEqual(onsetFrame);
      onsetLatenciesMs.push((firstLockFrame - onsetFrame + 1) * frameDurationMs);
    }

    expect(onsetLatenciesMs).toHaveLength(qualityContract.cases.length);
    expect(percentile95(onsetLatenciesMs)).toBeLessThanOrEqual(qualityContract.thresholds.onset_p95_ms_max);
  });
});
