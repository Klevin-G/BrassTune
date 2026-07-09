import { describe, expect, it } from 'vitest';
import { enqueuePendingPersistFrame, requeueFailedPersistFrames, shouldPersistFrameFromFrontend } from './usePitchStream';
import type { PitchFrame } from '../domain/types';

const validFrame = { is_valid_for_recording: true } as PitchFrame;

describe('shouldPersistFrameFromFrontend', () => {
  it('persists browser-generated demo frames', () => {
    expect(shouldPersistFrameFromFrontend(true, true, 42, validFrame)).toBe(true);
  });

  it('persists browser-generated microphone frames', () => {
    expect(shouldPersistFrameFromFrontend(false, true, 42, { ...validFrame, detector_source: 'browser_local_pitch' })).toBe(true);
  });

  it('does not persist returned microphone WebSocket frames', () => {
    expect(shouldPersistFrameFromFrontend(false, true, 42, validFrame)).toBe(false);
  });

  it('does not persist invalid frames', () => {
    expect(shouldPersistFrameFromFrontend(true, true, 42, { is_valid_for_recording: false } as PitchFrame)).toBe(false);
  });

  it('does not persist local guest demo frames to backend', () => {
    expect(shouldPersistFrameFromFrontend(true, true, -42, validFrame, false)).toBe(false);
  });

  it('drops failed final-stop frames instead of carrying them into a later session', () => {
    const frameA = { ...validFrame, timestamp_ms: 1 } as PitchFrame;
    const frameB = { ...validFrame, timestamp_ms: 2 } as PitchFrame;
    const frameC = { ...validFrame, timestamp_ms: 3 } as PitchFrame;
    const failedFinal = requeueFailedPersistFrames(
      { sessionId: 42, frames: [] },
      42,
      [frameA, frameB],
      { currentSessionId: 42, persistenceClosed: true },
    );

    expect(failedFinal).toEqual({ sessionId: null, frames: [] });
    expect(enqueuePendingPersistFrame(failedFinal, 43, frameC)).toEqual({ sessionId: 43, frames: [frameC] });
  });

  it('keeps retryable frames scoped to the same active session', () => {
    const frameA = { ...validFrame, timestamp_ms: 1 } as PitchFrame;
    const frameB = { ...validFrame, timestamp_ms: 2 } as PitchFrame;
    const requeued = requeueFailedPersistFrames(
      { sessionId: 42, frames: [frameB] },
      42,
      [frameA],
      { currentSessionId: 42, persistenceClosed: false },
    );

    expect(requeued).toEqual({ sessionId: 42, frames: [frameA, frameB] });
  });

  it('does not prepend failed old-session frames to a new session queue', () => {
    const oldFrame = { ...validFrame, timestamp_ms: 1 } as PitchFrame;
    const newFrame = { ...validFrame, timestamp_ms: 2 } as PitchFrame;
    const queue = requeueFailedPersistFrames(
      { sessionId: 43, frames: [newFrame] },
      42,
      [oldFrame],
      { currentSessionId: 43, persistenceClosed: false },
    );

    expect(queue).toEqual({ sessionId: 43, frames: [newFrame] });
  });
});
