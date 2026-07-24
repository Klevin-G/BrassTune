import { describe, expect, it } from 'vitest';
import { canStartReferenceTone, playAlongAnnouncementBucket, shouldGradePitchFrame, shouldShowPitchRecovery } from './PlayAlongPage';
import type { GraderSnapshot } from '../domain/playAlong';

describe('Play-Along reference-tone ownership', () => {
  it('never grades frames or starts another tone while speaker output owns audio', () => {
    expect(canStartReferenceTone('idle', false)).toBe(true);
    expect(canStartReferenceTone('idle', true)).toBe(false);
    expect(canStartReferenceTone('running', false)).toBe(false);
    expect(shouldGradePitchFrame('running', false)).toBe(true);
    expect(shouldGradePitchFrame('running', true)).toBe(false);
    expect(shouldGradePitchFrame('idle', false)).toBe(false);
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
