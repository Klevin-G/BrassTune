import { describe, expect, it } from 'vitest';
import { shouldPersistFrameFromFrontend } from './usePitchStream';
import type { PitchFrame } from '../domain/types';

const validFrame = { is_valid_for_recording: true } as PitchFrame;

describe('shouldPersistFrameFromFrontend', () => {
  it('persists browser-generated demo frames', () => {
    expect(shouldPersistFrameFromFrontend(true, true, 42, validFrame)).toBe(true);
  });

  it('does not persist returned microphone WebSocket frames', () => {
    expect(shouldPersistFrameFromFrontend(false, true, 42, validFrame)).toBe(false);
  });

  it('does not persist invalid frames', () => {
    expect(shouldPersistFrameFromFrontend(true, true, 42, { is_valid_for_recording: false } as PitchFrame)).toBe(false);
  });
});
