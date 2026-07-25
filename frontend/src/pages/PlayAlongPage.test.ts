import { describe, expect, it } from 'vitest';
import {
  canStartReferenceTone,
  playAlongAnnouncementBucket,
  REFERENCE_SEQUENCE_GAP_SECONDS,
  REFERENCE_SEQUENCE_NOTE_SECONDS,
  referenceSequencePlan,
  shouldGradePitchFrame,
  shouldShowPitchRecovery,
} from './PlayAlongPage';
import type { GraderSnapshot } from '../domain/playAlong';
import { WRITTEN_MIDI_MAX, WRITTEN_MIDI_MIN } from '../domain/referenceTone';
import { noteLabelToMidi } from '../domain/music';

describe('Play-Along reference-tone ownership', () => {
  it('never grades frames or starts another tone while speaker output owns audio', () => {
    expect(canStartReferenceTone('idle', false)).toBe(true);
    expect(canStartReferenceTone('idle', true)).toBe(false);
    expect(canStartReferenceTone('running', false)).toBe(false);
    expect(shouldGradePitchFrame('running', false)).toBe(true);
    expect(shouldGradePitchFrame('running', true)).toBe(false);
    expect(shouldGradePitchFrame('idle', false)).toBe(false);
  });

  it('plans every pitch class in ascending order, lifting the returning tonic by an octave', () => {
    const plan = referenceSequencePlan(['C', 'E', 'G', 'C']);
    expect(plan.map((step) => step.writtenNote)).toEqual(['C4', 'E4', 'G4', 'C5']);
    plan.forEach((step, index) => {
      expect(step.startTime).toBeCloseTo(index * (REFERENCE_SEQUENCE_NOTE_SECONDS + REFERENCE_SEQUENCE_GAP_SECONDS));
    });
    for (const step of plan) {
      expect(step.stopTime - step.startTime).toBeCloseTo(REFERENCE_SEQUENCE_NOTE_SECONDS);
    }
  });

  it('retains repeated notes as separate attacks at the same pitch', () => {
    const plan = referenceSequencePlan(['C', 'C']);
    expect(plan.map((step) => step.writtenNote)).toEqual(['C4', 'C4']);
    expect(plan[1].startTime).toBeGreaterThan(plan[0].stopTime);
  });

  it('keeps weak alternating transition drills in their local octave instead of climbing each repetition', () => {
    const plan = referenceSequencePlan(['D', 'C#', 'D', 'C#', 'D', 'C#']);
    expect(plan.map((step) => step.writtenNote)).toEqual(['D4', 'C#4', 'D4', 'C#4', 'D4', 'C#4']);
  });

  it('keeps every long sequence inside the supported written range', () => {
    const ascendingPattern = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    const plan = referenceSequencePlan(Array.from({ length: 32 }, (_, index) => ascendingPattern[index % ascendingPattern.length]));
    expect(plan).toHaveLength(32);
    for (const step of plan) {
      const midi = noteLabelToMidi(step.writtenNote);
      expect(midi).toBeGreaterThanOrEqual(WRITTEN_MIDI_MIN);
      expect(midi).toBeLessThanOrEqual(WRITTEN_MIDI_MAX);
    }
  });

  it('offers microphone recovery after an interruption but not while access is starting', () => {
    expect(shouldShowPitchRecovery(false, 'suspended')).toBe(true);
    expect(shouldShowPitchRecovery(false, 'unavailable')).toBe(true);
    expect(shouldShowPitchRecovery(false, 'starting')).toBe(false);
    expect(shouldShowPitchRecovery(true, 'running')).toBe(false);
  });
});

describe('Play-Along screen-reader announcement throttling', () => {
  it('changes only at meaningful quarter-progress or target boundaries', () => {
    const snapshot: Pick<GraderSnapshot, 'index' | 'currentName' | 'heldFraction'> = { index: 0, currentName: 'C', heldFraction: 0.01 };
    expect(playAlongAnnouncementBucket(snapshot)).toBe('0:C:0');
    expect(playAlongAnnouncementBucket({ ...snapshot, heldFraction: 0.24 })).toBe('0:C:0');
    expect(playAlongAnnouncementBucket({ ...snapshot, heldFraction: 0.26 })).toBe('0:C:25');
    expect(playAlongAnnouncementBucket({ ...snapshot, index: 1, currentName: 'D', heldFraction: 0 })).toBe('1:D:0');
  });
});
