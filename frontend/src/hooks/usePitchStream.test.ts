import { describe, expect, it } from 'vitest';
import {
  EMPTY_AUDIO_FRAME_TIMING,
  MICROPHONE_PAUSED_MESSAGE,
  audioContextRecoveryStatus,
  enqueuePendingPersistFrame,
  audioTracksForStream,
  browserPitchPipelineLabel,
  hasLiveMicrophoneTrack,
  installMicrophoneEndedHandler,
  observeAudioFrameTiming,
  recordDroppedAudioFrame,
  recordProcessedWorkerFrame,
  requeueFailedPersistFrames,
  selectBrowserPitchPipeline,
  shouldDropWorkerFrame,
  shouldPersistFrameFromFrontend,
} from './usePitchStream';
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

describe('worker pitch pipeline fallback and backlog policy', () => {
  it('uses the Worker only when it is available and has started', () => {
    expect(selectBrowserPitchPipeline(true, true)).toBe('worker');
    expect(selectBrowserPitchPipeline(false, false)).toBe('script-processor');
    expect(selectBrowserPitchPipeline(true, false)).toBe('script-processor');
  });

  it('labels the actual browser pipeline without allowing frame metadata to hide it', () => {
    expect(browserPitchPipelineLabel('worker')).toBe('browser worker pitch');
    expect(browserPitchPipelineLabel('script-processor')).toBe('browser local pitch (fallback)');
  });

  it('bounds the Worker queue and drops stale audio rather than delaying live feedback', () => {
    expect(shouldDropWorkerFrame(2, 3)).toBe(false);
    expect(shouldDropWorkerFrame(3, 3)).toBe(true);
  });

  it('keeps audio timing state resettable after track end or teardown', () => {
    expect({ ...EMPTY_AUDIO_FRAME_TIMING }).toEqual({
      lastCallbackAtMs: null,
      processedFrames: 0,
      droppedFrames: 0,
      averageProcessingLatencyMs: 0,
      maxProcessingLatencyMs: 0,
    });
  });

  it('finds audio tracks in standards-compliant streams and minimal test fixtures', () => {
    const audio = { kind: 'audio' } as MediaStreamTrack;
    const video = { kind: 'video' } as MediaStreamTrack;
    expect(audioTracksForStream({ getTracks: () => [audio, video], getAudioTracks: () => [audio] } as MediaStream)).toEqual([audio]);
    expect(audioTracksForStream({ getTracks: () => [audio, video] } as MediaStream)).toEqual([audio]);
  });
});

describe('browser audio observability', () => {
  it('counts missed callback intervals and tracks processing latency without wall-clock dependencies', () => {
    const first = observeAudioFrameTiming(EMPTY_AUDIO_FRAME_TIMING, 100, 4, 100);
    const second = observeAudioFrameTiming(first, 200, 6, 100);
    const afterGap = observeAudioFrameTiming(second, 500, 10, 100);

    expect(afterGap.processedFrames).toBe(3);
    expect(afterGap.droppedFrames).toBe(2);
    expect(afterGap.averageProcessingLatencyMs).toBeCloseTo(20 / 3, 9);
    expect(afterGap.maxProcessingLatencyMs).toBe(10);
  });

  it('sanitizes invalid latency samples', () => {
    const observed = observeAudioFrameTiming(EMPTY_AUDIO_FRAME_TIMING, 100, Number.NaN, 0);
    expect(observed.averageProcessingLatencyMs).toBe(0);
    expect(observed.droppedFrames).toBe(0);
  });

  it('counts a dropped Worker callback without falsely recording a processed pitch frame', () => {
    const dropped = recordDroppedAudioFrame(EMPTY_AUDIO_FRAME_TIMING);
    expect(dropped.processedFrames).toBe(0);
    expect(dropped.droppedFrames).toBe(1);
  });

  it('records Worker latency only when a Worker result arrives', () => {
    const completed = recordProcessedWorkerFrame(recordDroppedAudioFrame(EMPTY_AUDIO_FRAME_TIMING), 18);
    expect(completed).toMatchObject({ processedFrames: 1, droppedFrames: 1, averageProcessingLatencyMs: 18, maxProcessingLatencyMs: 18 });
  });
});

describe('browser audio recovery', () => {
  it('marks suspended and closed contexts inactive with a recoverable message', () => {
    expect(audioContextRecoveryStatus('suspended')).toEqual({
      micActive: false,
      statusMessage: MICROPHONE_PAUSED_MESSAGE,
    });
    expect(audioContextRecoveryStatus('closed')).toEqual({
      micActive: false,
      statusMessage: 'Microphone audio closed. Select Turn on microphone to reconnect.',
    });
    expect(audioContextRecoveryStatus('running').micActive).toBe(true);
  });

  it('does not reuse a media stream after every track has ended', () => {
    const stream = {
      getTracks: () => [{ kind: 'audio', readyState: 'ended' }, { kind: 'audio', readyState: 'ended' }],
    } as unknown as MediaStream;
    const liveStream = {
      getTracks: () => [{ kind: 'audio', readyState: 'ended' }, { kind: 'audio', readyState: 'live' }],
    } as unknown as MediaStream;

    expect(hasLiveMicrophoneTrack(stream)).toBe(false);
    expect(hasLiveMicrophoneTrack(liveStream)).toBe(true);
  });

  it('binds ended-track recovery to every captured microphone track', () => {
    const tracks = [
      { kind: 'audio', readyState: 'live', onended: null },
      { kind: 'audio', readyState: 'live', onended: null },
    ] as unknown as MediaStreamTrack[];
    const stream = { getTracks: () => tracks } as unknown as MediaStream;
    let endedCount = 0;

    installMicrophoneEndedHandler(stream, () => {
      endedCount += 1;
    });
    tracks[0].onended?.({} as Event);
    tracks[1].onended?.({} as Event);

    expect(endedCount).toBe(2);
  });
});
