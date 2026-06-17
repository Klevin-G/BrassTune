import { demoProfileTransposition, midiToFrequency, noteLabelToMidi, pitchFrameFromFrequency } from './music';
import type { PitchFrame } from './types';

const patterns: Record<string, Array<{ note: string; center: number; spread: number }>> = {
  trumpet: [
    { note: 'G4', center: -4, spread: 2 },
    { note: 'A4', center: 3, spread: 3 },
    { note: 'D5', center: 14, spread: 3 },
    { note: 'C5', center: 0, spread: 11 },
    { note: 'E5', center: 7, spread: 3 },
  ],
  horn: [
    { note: 'G4', center: 8, spread: 5 },
    { note: 'C5', center: -10, spread: 4 },
    { note: 'E5', center: 2, spread: 10 },
    { note: 'A4', center: 6, spread: 4 },
  ],
  trombone: [
    { note: 'Bb3', center: -3, spread: 3 },
    { note: 'F3', center: 11, spread: 4 },
    { note: 'D4', center: -8, spread: 4 },
    { note: 'Ab3', center: 4, spread: 5 },
  ],
  euphonium: [
    { note: 'Bb3', center: 3, spread: 3 },
    { note: 'F3', center: 8, spread: 4 },
    { note: 'D4', center: -7, spread: 5 },
    { note: 'G3', center: 1, spread: 7 },
  ],
  tuba: [
    { note: 'Bb2', center: -10, spread: 4 },
    { note: 'F2', center: -6, spread: 4 },
    { note: 'C3', center: 3, spread: 3 },
    { note: 'Eb3', center: 13, spread: 5 },
  ],
};

function pseudoNoise(index: number) {
  return Math.sin(index * 12.9898) * 43758.5453 % 1;
}

export function nextDemoPitchFrame(index: number, instrumentId: string, referencePitch: number): PitchFrame {
  const plan = patterns[instrumentId] ?? patterns.trumpet;
  const current = plan[Math.floor(index / 18) % plan.length];
  const restBeat = index % 60;
  if (restBeat === 58 || restBeat === 59) {
    return pitchFrameFromFrequency(null, 0, instrumentId, referencePitch, index * 110, 0, 0.002);
  }
  const noise = (pseudoNoise(index) - 0.5) * current.spread;
  const cents = current.center + noise;
  const writtenMidi = noteLabelToMidi(current.note);
  const concertMidi = writtenMidi - (demoProfileTransposition[instrumentId] ?? 0);
  const frequency = midiToFrequency(concertMidi, referencePitch) * 2 ** (cents / 1200);
  const confidence = current.spread > 9 ? 0.9 : 0.97 + Math.min(0.02, Math.max(0, 5 - Math.abs(noise)) / 250);
  return pitchFrameFromFrequency(frequency, cents, instrumentId, referencePitch, index * 110, confidence, 0.07 + Math.abs(noise) / 400);
}
