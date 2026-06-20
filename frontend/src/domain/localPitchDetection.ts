import { frequencyToMidi, pitchFrameFromFrequency } from './music';
import type { PitchFrame } from './types';

const DEFAULT_MIN_FREQUENCY = 55;
const DEFAULT_MAX_FREQUENCY = 1300;
const DEFAULT_MIN_RMS = 0.01;
const DEFAULT_MIN_CORRELATION = 0.82;

export interface PitchEstimate {
  frequencyHz: number | null;
  confidence: number;
  rms: number;
}

export interface PitchDetectionOptions {
  minFrequencyHz?: number;
  maxFrequencyHz?: number;
  minRms?: number;
  minCorrelation?: number;
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

export function rmsForSamples(samples: ArrayLike<number>) {
  if (samples.length === 0) return 0;
  let sumSquares = 0;
  for (let index = 0; index < samples.length; index += 1) {
    sumSquares += samples[index] * samples[index];
  }
  return Math.sqrt(sumSquares / samples.length);
}

function meanForSamples(samples: ArrayLike<number>) {
  if (samples.length === 0) return 0;
  let sum = 0;
  for (let index = 0; index < samples.length; index += 1) {
    sum += samples[index];
  }
  return sum / samples.length;
}

function correlationAt(samples: ArrayLike<number>, lag: number, mean: number) {
  let sum = 0;
  let leftPower = 0;
  let rightPower = 0;
  const limit = samples.length - lag;
  for (let index = 0; index < limit; index += 1) {
    const left = samples[index] - mean;
    const right = samples[index + lag] - mean;
    sum += left * right;
    leftPower += left * left;
    rightPower += right * right;
  }
  const denominator = Math.sqrt(leftPower * rightPower);
  return denominator > 0 ? sum / denominator : 0;
}

export function estimatePitchFromPcm(samples: ArrayLike<number>, sampleRate: number, options: PitchDetectionOptions = {}): PitchEstimate {
  const rms = rmsForSamples(samples);
  const minRms = options.minRms ?? DEFAULT_MIN_RMS;
  if (!sampleRate || samples.length < 64 || rms < minRms) {
    return { frequencyHz: null, confidence: 0, rms };
  }

  const minFrequencyHz = options.minFrequencyHz ?? DEFAULT_MIN_FREQUENCY;
  const maxFrequencyHz = options.maxFrequencyHz ?? DEFAULT_MAX_FREQUENCY;
  const minLag = Math.max(2, Math.floor(sampleRate / maxFrequencyHz));
  const maxLag = Math.min(samples.length - 2, Math.ceil(sampleRate / minFrequencyHz));
  const mean = meanForSamples(samples);
  let bestLag = 0;
  let bestCorrelation = 0;

  for (let lag = minLag; lag <= maxLag; lag += 1) {
    const correlation = correlationAt(samples, lag, mean);
    if (correlation > bestCorrelation) {
      bestCorrelation = correlation;
      bestLag = lag;
    }
  }

  const minCorrelation = options.minCorrelation ?? DEFAULT_MIN_CORRELATION;
  if (!bestLag || bestCorrelation < minCorrelation) {
    return { frequencyHz: null, confidence: clamp(bestCorrelation, 0, 0.94), rms };
  }

  const previous = bestLag > minLag ? correlationAt(samples, bestLag - 1, mean) : bestCorrelation;
  const next = bestLag < maxLag ? correlationAt(samples, bestLag + 1, mean) : bestCorrelation;
  const divisor = previous - 2 * bestCorrelation + next;
  const offset = divisor === 0 ? 0 : clamp((previous - next) / (2 * divisor), -0.5, 0.5);
  const refinedLag = bestLag + offset;
  const frequencyHz = sampleRate / refinedLag;

  return {
    frequencyHz,
    confidence: clamp(bestCorrelation, 0, 0.999),
    rms,
  };
}

export function pitchFrameFromPcm(
  samples: ArrayLike<number>,
  sampleRate: number,
  instrumentId: string,
  referencePitch: number,
  timestampMs: number,
): PitchFrame {
  const estimate = estimatePitchFromPcm(samples, sampleRate);
  if (!estimate.frequencyHz) {
    return pitchFrameFromFrequency(null, 0, instrumentId, referencePitch, timestampMs, estimate.confidence, estimate.rms, 'browser_local_pitch');
  }
  const midi = frequencyToMidi(estimate.frequencyHz, referencePitch);
  const cents = (midi - Math.round(midi)) * 100;
  return pitchFrameFromFrequency(
    estimate.frequencyHz,
    cents,
    instrumentId,
    referencePitch,
    timestampMs,
    estimate.confidence,
    estimate.rms,
    'browser_local_pitch',
  );
}
