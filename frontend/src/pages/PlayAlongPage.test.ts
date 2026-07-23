import { describe, expect, it } from 'vitest';
import { canStartReferenceTone, shouldGradePitchFrame, shouldShowPitchRecovery } from './PlayAlongPage';

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
