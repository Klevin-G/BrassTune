export type Subdivision = 'quarter' | 'eighth' | 'triplet' | 'sixteenth';

export interface TimeSignature {
  numerator: number;
  denominator: number;
}

export interface MetronomeTick {
  time: number;
  beatIndex: number;
  subdivisionIndex: number;
  accented: boolean;
}

export const BPM_MIN = 20;
export const BPM_MAX = 300;

export function clampBpm(value: number) {
  if (!Number.isFinite(value)) return 120;
  return Math.min(BPM_MAX, Math.max(BPM_MIN, Math.round(value)));
}

export function normalizeTimeSignature(numerator: number, denominator: number): TimeSignature {
  const safeNumerator = Math.min(16, Math.max(1, Math.round(Number.isFinite(numerator) ? numerator : 4)));
  const safeDenominator = [2, 4, 8, 16].includes(denominator) ? denominator : 4;
  return { numerator: safeNumerator, denominator: safeDenominator };
}

export function subdivisionFactor(subdivision: Subdivision) {
  if (subdivision === 'eighth') return 2;
  if (subdivision === 'triplet') return 3;
  if (subdivision === 'sixteenth') return 4;
  return 1;
}

export function secondsPerBeat(bpm: number, denominator = 4) {
  const quarterNoteSeconds = 60 / clampBpm(bpm);
  return quarterNoteSeconds * (4 / denominator);
}

export function secondsPerTick(bpm: number, signature: TimeSignature, subdivision: Subdivision) {
  return secondsPerBeat(bpm, signature.denominator) / subdivisionFactor(subdivision);
}

export function ticksPerBar(signature: TimeSignature, subdivision: Subdivision) {
  return signature.numerator * subdivisionFactor(subdivision);
}

export function buildScheduledTicks({
  startTime,
  bpm,
  signature,
  subdivision,
  bars,
}: {
  startTime: number;
  bpm: number;
  signature: TimeSignature;
  subdivision: Subdivision;
  bars: number;
}): MetronomeTick[] {
  const normalized = normalizeTimeSignature(signature.numerator, signature.denominator);
  const factor = subdivisionFactor(subdivision);
  const interval = secondsPerTick(bpm, normalized, subdivision);
  const count = ticksPerBar(normalized, subdivision) * Math.max(1, Math.round(bars));
  return Array.from({ length: count }, (_, index) => {
    const subdivisionIndex = index % factor;
    const beatIndex = Math.floor(index / factor) % normalized.numerator;
    return {
      time: startTime + index * interval,
      beatIndex,
      subdivisionIndex,
      accented: beatIndex === 0 && subdivisionIndex === 0,
    };
  });
}

export function tapTempoBpm(taps: number[]) {
  const recent = taps.slice(-5);
  if (recent.length < 2) return null;
  const intervals = recent.slice(1).map((tap, index) => tap - recent[index]).filter((interval) => interval > 180 && interval < 3000);
  if (intervals.length === 0) return null;
  const average = intervals.reduce((sum, interval) => sum + interval, 0) / intervals.length;
  return clampBpm(60000 / average);
}

export function nextRampBpm(current: number, target: number, step: number) {
  const safeCurrent = clampBpm(current);
  const safeTarget = clampBpm(target);
  const safeStep = Math.max(1, Math.round(Math.abs(step)));
  if (safeCurrent === safeTarget) return safeCurrent;
  return safeCurrent < safeTarget ? Math.min(safeTarget, safeCurrent + safeStep) : Math.max(safeTarget, safeCurrent - safeStep);
}

export function timingStats(times: number[]) {
  if (times.length < 2) return { intervals: 0, averageMs: 0, maxJitterMs: 0 };
  const intervals = times.slice(1).map((time, index) => (time - times[index]) * 1000);
  const average = intervals.reduce((sum, interval) => sum + interval, 0) / intervals.length;
  const maxJitter = Math.max(...intervals.map((interval) => Math.abs(interval - average)));
  return { intervals: intervals.length, averageMs: average, maxJitterMs: maxJitter };
}
