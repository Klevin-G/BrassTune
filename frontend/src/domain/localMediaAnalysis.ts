import { frequencyToMidi, midiToFrequency, pitchFrameFromFrequency } from './music';
import type { PitchFrame } from './types';

const FRAME_SIZE = 4096;
const HOP_SIZE = 4096;
const MAX_ANALYSIS_SECONDS = 240;

const instrumentBounds: Record<string, { min: number; max: number }> = {
  trumpet: { min: 130, max: 1500 },
  horn: { min: 80, max: 1200 },
  trombone: { min: 50, max: 700 },
  euphonium: { min: 55, max: 800 },
  tuba: { min: 30, max: 500 },
};

export interface LocalMediaAnalysisResult {
  frames: PitchFrame[];
  durationSeconds: number;
  analyzedSeconds: number;
  sourceName: string;
  sourceType: string;
}

export async function analyzeLocalMediaFile(
  file: File,
  instrumentId: string,
  referencePitch: number,
  onProgress?: (progress: number) => void,
): Promise<LocalMediaAnalysisResult> {
  const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
  if (!AudioContextClass) {
    throw new Error('This browser cannot decode local audio/video for analysis.');
  }
  const audioContext = new AudioContextClass();
  try {
    const buffer = await audioContext.decodeAudioData(await file.arrayBuffer());
    const mono = downmix(buffer);
    const sampleRate = buffer.sampleRate;
    const maxSamples = Math.min(mono.length, Math.floor(sampleRate * MAX_ANALYSIS_SECONDS));
    const bounds = instrumentBounds[instrumentId] ?? instrumentBounds.trumpet;
    const frames: PitchFrame[] = [];
    for (let start = 0; start + FRAME_SIZE <= maxSamples; start += HOP_SIZE) {
      const slice = mono.subarray(start, start + FRAME_SIZE);
      const rms = calculateRms(slice);
      const timestampMs = Math.round((start / sampleRate) * 1000);
      if (rms < 0.005) {
        frames.push(pitchFrameFromFrequency(null, 0, instrumentId, referencePitch, timestampMs, 0, rms, 'browser_local_yin'));
      } else {
        const { frequencyHz, confidence } = yinPitchForSamples(slice, sampleRate, bounds.min, bounds.max);
        const cents = frequencyHz > 0 ? centsForFrequency(frequencyHz, referencePitch) : 0;
        frames.push(
          pitchFrameFromFrequency(
            frequencyHz > 0 ? frequencyHz : null,
            cents,
            instrumentId,
            referencePitch,
            timestampMs,
            confidence,
            rms,
            'browser_local_yin',
          ),
        );
      }
      if (start % (HOP_SIZE * 12) === 0) {
        onProgress?.(Math.min(1, start / Math.max(1, maxSamples - FRAME_SIZE)));
        await new Promise((resolve) => window.setTimeout(resolve, 0));
      }
    }
    onProgress?.(1);
    return {
      frames,
      durationSeconds: buffer.duration,
      analyzedSeconds: Math.min(buffer.duration, MAX_ANALYSIS_SECONDS),
      sourceName: file.name,
      sourceType: file.type || 'local media',
    };
  } catch (error) {
    throw new Error(
      error instanceof Error && error.message
        ? `Could not decode this local media file. Try an audio export or a browser-supported MP4/WebM/M4A file. ${error.message}`
        : 'Could not decode this local media file.',
    );
  } finally {
    await audioContext.close().catch(() => undefined);
  }
}

function downmix(buffer: AudioBuffer) {
  const output = new Float32Array(buffer.length);
  for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
    const data = buffer.getChannelData(channel);
    for (let index = 0; index < data.length; index += 1) {
      output[index] += data[index] / buffer.numberOfChannels;
    }
  }
  return output;
}

function calculateRms(samples: Float32Array) {
  let sum = 0;
  for (let index = 0; index < samples.length; index += 1) {
    sum += samples[index] * samples[index];
  }
  return Math.sqrt(sum / samples.length);
}

function centsForFrequency(frequencyHz: number, referencePitch: number) {
  const nearest = Math.round(frequencyToMidi(frequencyHz, referencePitch));
  const target = midiToFrequency(nearest, referencePitch);
  return 1200 * Math.log2(frequencyHz / target);
}

export function yinPitchForSamples(samplesInput: Float32Array, sampleRate: number, minFrequencyHz: number, maxFrequencyHz: number) {
  const samples = new Float32Array(samplesInput.length);
  let mean = 0;
  for (let index = 0; index < samplesInput.length; index += 1) mean += samplesInput[index];
  mean /= samplesInput.length;
  let peak = 0;
  for (let index = 0; index < samplesInput.length; index += 1) {
    const value = samplesInput[index] - mean;
    samples[index] = value;
    peak = Math.max(peak, Math.abs(value));
  }
  if (peak <= 0 || samples.length < 64) return { frequencyHz: 0, confidence: 0 };
  for (let index = 0; index < samples.length; index += 1) samples[index] /= peak;

  const minTau = Math.max(2, Math.floor(sampleRate / maxFrequencyHz));
  const maxTau = Math.min(samples.length - 2, Math.floor(sampleRate / minFrequencyHz));
  if (maxTau <= minTau) return { frequencyHz: 0, confidence: 0 };

  const difference = new Float64Array(maxTau + 1);
  for (let tau = 1; tau <= maxTau; tau += 1) {
    let sum = 0;
    for (let index = 0; index < samples.length - tau; index += 1) {
      const delta = samples[index] - samples[index + tau];
      sum += delta * delta;
    }
    difference[tau] = sum;
  }

  const cmnd = new Float64Array(maxTau + 1);
  cmnd[0] = 1;
  let cumulative = 0;
  for (let tau = 1; tau <= maxTau; tau += 1) {
    cumulative += difference[tau];
    cmnd[tau] = cumulative > 0 ? (difference[tau] * tau) / cumulative : 1;
  }

  let tau = 0;
  for (let candidate = minTau; candidate < maxTau; candidate += 1) {
    if (cmnd[candidate] < 0.14) {
      while (candidate + 1 <= maxTau && cmnd[candidate + 1] < cmnd[candidate]) candidate += 1;
      tau = candidate;
      break;
    }
  }
  if (tau === 0) {
    let best = minTau;
    for (let candidate = minTau + 1; candidate <= maxTau; candidate += 1) {
      if (cmnd[candidate] < cmnd[best]) best = candidate;
    }
    tau = best;
    if (cmnd[tau] > 0.55) return { frequencyHz: 0, confidence: Math.max(0, Math.min(1 - cmnd[tau], 1)) };
  }

  const refinedTau = parabolicTau(cmnd, tau);
  const frequencyHz = refinedTau > 0 ? sampleRate / refinedTau : 0;
  const confidence = Math.max(0, Math.min(1 - cmnd[tau], 1));
  if (confidence < 0.25 || frequencyHz < minFrequencyHz || frequencyHz > maxFrequencyHz) {
    return { frequencyHz: 0, confidence };
  }
  return { frequencyHz, confidence };
}

function parabolicTau(values: Float64Array, tau: number) {
  if (tau <= 0 || tau >= values.length - 1) return tau;
  const left = values[tau - 1];
  const center = values[tau];
  const right = values[tau + 1];
  const denominator = left - 2 * center + right;
  if (Math.abs(denominator) < 1e-12) return tau;
  return tau + 0.5 * (left - right) / denominator;
}
