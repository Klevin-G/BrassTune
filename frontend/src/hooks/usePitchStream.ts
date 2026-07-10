import { useCallback, useEffect, useRef, useState } from 'react';
import { nextDemoPitchFrame } from '../domain/demoPitch';
import { pitchFrameFromPcm } from '../domain/localPitchDetection';
import type { PitchFrame } from '../domain/types';
import { recordPitchFramesInBatches } from '../api/client';

const AUDIO_FRAME_SIZE = 4096;
const PERSIST_BATCH_SIZE = 100;
const PERSIST_FLUSH_INTERVAL_MS = 750;
const MAX_BUFFERED_PERSIST_FRAMES = 1500;
// Detection runs at full rate locally (~85ms/frame); only a downsampled
// stream is persisted to the cloud to keep storage lean. Server-side note
// segmentation merges gaps up to 340ms, so 150ms spacing is safely inside it.
export const MIN_PERSIST_SPACING_MS = 150;

export interface PendingPersistFrameQueue {
  sessionId: number | null;
  frames: PitchFrame[];
}

export function enqueuePendingPersistFrame(queue: PendingPersistFrameQueue, sessionId: number, frame: PitchFrame): PendingPersistFrameQueue {
  const frames = queue.sessionId === sessionId ? [...queue.frames, frame] : [frame];
  return { sessionId, frames: frames.slice(-MAX_BUFFERED_PERSIST_FRAMES) };
}

export function requeueFailedPersistFrames(
  queue: PendingPersistFrameQueue,
  failedSessionId: number,
  frames: PitchFrame[],
  { currentSessionId, persistenceClosed }: { currentSessionId?: number; persistenceClosed: boolean },
): PendingPersistFrameQueue {
  if (persistenceClosed || currentSessionId !== failedSessionId) {
    return queue.sessionId === failedSessionId ? { sessionId: null, frames: [] } : queue;
  }
  if (queue.sessionId !== null && queue.sessionId !== failedSessionId) {
    return queue;
  }
  return { sessionId: failedSessionId, frames: [...frames, ...queue.frames].slice(-MAX_BUFFERED_PERSIST_FRAMES) };
}

export interface PitchStreamInfo {
  frameSize: number;
  sampleRate: number | null;
  sentFrames: number;
  droppedFrames: number;
  detectorSource: string;
}

export interface PitchFrameFlushResult {
  flushed: number;
  failed: number;
}

interface UsePitchStreamOptions {
  enabled: boolean;
  demoMode: boolean;
  instrumentId: string;
  referencePitch: number;
  recording: boolean;
  sessionId?: number;
  persistDemoFramesToBackend?: boolean;
  onFrame?: (frame: PitchFrame) => void;
}

export function shouldPersistFrameFromFrontend(demoMode: boolean, recording: boolean, sessionId: number | undefined, frame: PitchFrame, persistToBackend = true) {
  const browserGenerated = demoMode || frame.detector_source === 'browser_local_pitch' || frame.detector_source === 'browser_demo';
  return persistToBackend && browserGenerated && recording && Boolean(sessionId) && Number(sessionId) > 0 && frame.is_valid_for_recording;
}

function audioContextConstructor() {
  return window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
}

export function usePitchStream({ enabled, demoMode, instrumentId, referencePitch, recording, sessionId, persistDemoFramesToBackend = true, onFrame }: UsePitchStreamOptions) {
  const [currentFrame, setCurrentFrame] = useState<PitchFrame | null>(null);
  const [history, setHistory] = useState<PitchFrame[]>([]);
  const [statusMessage, setStatusMessage] = useState('Guest demo mode is ready. Pitch data is simulated on this device.');
  const [micActive, setMicActive] = useState(false);
  const [streamInfo, setStreamInfo] = useState<PitchStreamInfo>({
    frameSize: AUDIO_FRAME_SIZE,
    sampleRate: null,
    sentFrames: 0,
    droppedFrames: 0,
    detectorSource: 'guest demo',
  });
  const [mediaStream, setMediaStream] = useState<MediaStream | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const processorRef = useRef<ScriptProcessorNode | null>(null);
  const sourceRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const monitorGainRef = useRef<GainNode | null>(null);
  const microphoneStartingRef = useRef(false);
  const analyzedMsRef = useRef(0);
  const indexRef = useRef(0);
  const recordingRef = useRef(recording);
  const sessionIdRef = useRef(sessionId);
  const onFrameRef = useRef(onFrame);
  const demoModeRef = useRef(demoMode);
  const instrumentIdRef = useRef(instrumentId);
  const referencePitchRef = useRef(referencePitch);
  const persistDemoFramesToBackendRef = useRef(persistDemoFramesToBackend);
  const persistenceClosedRef = useRef(false);
  const lastPersistTsRef = useRef<number | null>(null);
  const pendingPersistQueueRef = useRef<PendingPersistFrameQueue>({ sessionId: null, frames: [] });
  const flushTimerRef = useRef<number | null>(null);
  const flushPromiseRef = useRef<Promise<PitchFrameFlushResult> | null>(null);

  useEffect(() => {
    recordingRef.current = recording;
    sessionIdRef.current = sessionId;
    onFrameRef.current = onFrame;
    demoModeRef.current = demoMode;
    instrumentIdRef.current = instrumentId;
    referencePitchRef.current = referencePitch;
    persistDemoFramesToBackendRef.current = persistDemoFramesToBackend;
    if (recording) {
      persistenceClosedRef.current = false;
      if (sessionId && pendingPersistQueueRef.current.sessionId && pendingPersistQueueRef.current.sessionId !== sessionId) {
        pendingPersistQueueRef.current = { sessionId: null, frames: [] };
      }
    }
  }, [recording, sessionId, onFrame, demoMode, instrumentId, referencePitch, persistDemoFramesToBackend]);

  const clearFlushTimer = useCallback(() => {
    if (flushTimerRef.current !== null) {
      window.clearTimeout(flushTimerRef.current);
      flushTimerRef.current = null;
    }
  }, []);

  const flushPendingFrames = useCallback(async function flushPendingFrames(): Promise<PitchFrameFlushResult> {
    clearFlushTimer();
    let result: PitchFrameFlushResult = { flushed: 0, failed: 0 };
    if (flushPromiseRef.current) {
      result = await flushPromiseRef.current;
      if (pendingPersistQueueRef.current.frames.length === 0) return result;
    }

    const currentSessionId = pendingPersistQueueRef.current.sessionId;
    if (!currentSessionId || currentSessionId !== sessionIdRef.current || pendingPersistQueueRef.current.frames.length === 0) return result;

    const frames = pendingPersistQueueRef.current.frames;
    pendingPersistQueueRef.current = { sessionId: currentSessionId, frames: [] };
    let flush: Promise<PitchFrameFlushResult> = Promise.resolve(result);
    let attempted = 0;
    let saved = 0;
    flush = recordPitchFramesInBatches(currentSessionId, frames, {
      batchSize: PERSIST_BATCH_SIZE,
      onProgress: (savedCount, attemptedCount) => {
        saved = savedCount;
        attempted = attemptedCount;
      },
    })
      .then((batchResult) => ({ flushed: batchResult.saved, failed: batchResult.rejected }))
      .catch(() => {
        const retryFrames = frames.slice(attempted);
        pendingPersistQueueRef.current = requeueFailedPersistFrames(pendingPersistQueueRef.current, currentSessionId, retryFrames, {
          currentSessionId: sessionIdRef.current,
          persistenceClosed: persistenceClosedRef.current,
        });
        const retryable = pendingPersistQueueRef.current.sessionId === currentSessionId && pendingPersistQueueRef.current.frames.length > 0;
        setStatusMessage(
          retryable
            ? 'Pitch is visible, but cloud sync could not save the latest frames. Guest practice still works on this device.'
            : 'Session stopped before the latest pitch frames could sync. New recordings will start with a clean frame queue.',
        );
        if (retryable && flushTimerRef.current === null) {
          flushTimerRef.current = window.setTimeout(() => {
            flushTimerRef.current = null;
            void flushPendingFrames();
          }, PERSIST_FLUSH_INTERVAL_MS);
        }
        return { flushed: saved, failed: retryFrames.length };
      })
      .finally(() => {
        if (flushPromiseRef.current === flush) {
          flushPromiseRef.current = null;
        }
      });
    flushPromiseRef.current = flush;
    const attempt = await flush;
    result = { flushed: result.flushed + attempt.flushed, failed: result.failed + attempt.failed };
    if (attempt.failed === 0 && pendingPersistQueueRef.current.sessionId === currentSessionId && pendingPersistQueueRef.current.frames.length === 0) {
      pendingPersistQueueRef.current = { sessionId: null, frames: [] };
    }
    if (attempt.failed === 0 && pendingPersistQueueRef.current.frames.length > 0) {
      const next = await flushPendingFrames();
      result = { flushed: result.flushed + next.flushed, failed: result.failed + next.failed };
    }
    return result;
  }, [clearFlushTimer]);

  const schedulePersistFlush = useCallback(() => {
    if (flushTimerRef.current !== null || flushPromiseRef.current) return;
    flushTimerRef.current = window.setTimeout(() => {
      flushTimerRef.current = null;
      void flushPendingFrames().catch(() => undefined);
    }, PERSIST_FLUSH_INTERVAL_MS);
  }, [flushPendingFrames]);

  const finishPersistingFrames = useCallback(async () => {
    persistenceClosedRef.current = true;
    recordingRef.current = false;
    return flushPendingFrames();
  }, [flushPendingFrames]);

  const handleFrame = useCallback((frame: PitchFrame) => {
    setCurrentFrame(frame);
    setStreamInfo((old) => ({ ...old, detectorSource: frame.detector_source ?? (demoModeRef.current ? 'guest demo' : old.detectorSource) }));
    setHistory((old) => [frame, ...old.filter((item) => item.is_valid_for_recording)].slice(0, 8));
    onFrameRef.current?.(frame);
    // Demo frames are generated in the browser, so signed-in demo recordings
    // persist them from the frontend. Microphone frames are saved by the cloud
    // pitch stream when a session_id is present.
    const currentSessionId = sessionIdRef.current;
    if (!persistenceClosedRef.current && shouldPersistFrameFromFrontend(demoModeRef.current, recordingRef.current, currentSessionId, frame, persistDemoFramesToBackendRef.current) && currentSessionId !== undefined) {
      // Downsample the persisted stream: local detection/UI stay full-rate,
      // but the cloud only needs ~150ms-spaced frames for analytics.
      const last = pendingPersistQueueRef.current.sessionId === currentSessionId ? lastPersistTsRef.current : null;
      if (last !== null && frame.timestamp_ms - last < MIN_PERSIST_SPACING_MS) {
        return;
      }
      lastPersistTsRef.current = frame.timestamp_ms;
      pendingPersistQueueRef.current = enqueuePendingPersistFrame(pendingPersistQueueRef.current, currentSessionId, frame);
      if (pendingPersistQueueRef.current.frames.length >= PERSIST_BATCH_SIZE) {
        void flushPendingFrames().catch(() => undefined);
      } else {
        schedulePersistFlush();
      }
    }
  }, [flushPendingFrames, schedulePersistFlush]);

  useEffect(() => {
    if (!enabled || !demoMode) return;
    setStatusMessage('Guest demo mode is ready. Pitch data is simulated on this device.');
    setStreamInfo((old) => ({ ...old, sampleRate: null, detectorSource: 'guest demo' }));
    const timer = window.setInterval(() => {
      const frame = nextDemoPitchFrame(indexRef.current, instrumentId, referencePitch);
      indexRef.current += 1;
      handleFrame(frame);
    }, 110);
    return () => window.clearInterval(timer);
  }, [demoMode, enabled, handleFrame, instrumentId, referencePitch]);

  const cleanupMicrophone = useCallback((message?: string) => {
    processorRef.current?.disconnect();
    sourceRef.current?.disconnect();
    monitorGainRef.current?.disconnect();
    mediaStreamRef.current?.getTracks().forEach((track) => track.stop());
    audioContextRef.current?.close().catch(() => undefined);
    processorRef.current = null;
    sourceRef.current = null;
    monitorGainRef.current = null;
    mediaStreamRef.current = null;
    audioContextRef.current = null;
    microphoneStartingRef.current = false;
    analyzedMsRef.current = 0;
    setMediaStream(null);
    setMicActive(false);
    if (message) setStatusMessage(message);
    setStreamInfo((old) => ({ ...old, sampleRate: null, detectorSource: demoModeRef.current ? 'guest demo' : 'browser local pitch' }));
  }, []);

  const stopMicrophone = useCallback(() => {
    cleanupMicrophone();
  }, [cleanupMicrophone]);

  const startMicrophone = useCallback(async () => {
    if (demoMode) return null;
    if (mediaStreamRef.current && micActive) return mediaStreamRef.current;
    if (microphoneStartingRef.current) return mediaStreamRef.current;
    const AudioContextClass = audioContextConstructor();
    if (!navigator.mediaDevices?.getUserMedia || !AudioContextClass) {
      setStatusMessage('Microphone input is unavailable in this browser. Guest demo practice still works on this device.');
      return null;
    }
    microphoneStartingRef.current = true;
    setStatusMessage('Asking for microphone access.');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
      mediaStreamRef.current = stream;
      setMediaStream(stream);
      const audioContext = new AudioContextClass();
      audioContextRef.current = audioContext;
      if (audioContext.state === 'suspended') await audioContext.resume().catch(() => undefined);
      setStreamInfo((old) => ({ ...old, sampleRate: audioContext.sampleRate, detectorSource: 'browser local pitch', sentFrames: 0, droppedFrames: 0 }));
      const source = audioContext.createMediaStreamSource(stream);
      const processor = audioContext.createScriptProcessor(AUDIO_FRAME_SIZE, 1, 1);
      const monitorGain = audioContext.createGain();
      monitorGain.gain.value = 0;
      source.connect(processor);
      processor.connect(monitorGain);
      monitorGain.connect(audioContext.destination);
      sourceRef.current = source;
      processorRef.current = processor;
      monitorGainRef.current = monitorGain;
      processor.onaudioprocess = (event) => {
        const input = event.inputBuffer.getChannelData(0);
        const pcm = new Float32Array(input);
        analyzedMsRef.current += (pcm.length / audioContext.sampleRate) * 1000;
        const frame = pitchFrameFromPcm(
          pcm,
          audioContext.sampleRate,
          instrumentIdRef.current,
          referencePitchRef.current,
          Math.round(analyzedMsRef.current),
        );
        setStreamInfo((old) => ({ ...old, sentFrames: old.sentFrames + 1 }));
        handleFrame(frame);
        if (frame.is_valid_for_recording) {
          setStatusMessage('Sound detected. Tracking pitch now.');
        } else if (frame.tuning_status === 'silence') {
          setStatusMessage('Listening. No stable pitch yet.');
        } else {
          setStatusMessage('Sound detected. No stable pitch yet.');
        }
      };
      microphoneStartingRef.current = false;
      setMicActive(true);
      setStatusMessage('Listening. Play a steady note.');
      return stream;
    } catch (error) {
      cleanupMicrophone('Microphone blocked or unavailable. Guest demo practice still works on this device.');
      return null;
    }
  }, [cleanupMicrophone, demoMode, handleFrame, micActive]);

  useEffect(() => {
    if (demoMode) {
      stopMicrophone();
    }
    return () => {
      clearFlushTimer();
      void flushPendingFrames().catch(() => undefined);
      stopMicrophone();
    };
  }, [clearFlushTimer, demoMode, flushPendingFrames, stopMicrophone]);

  return { currentFrame, history, statusMessage, micActive, mediaStream, streamInfo, startMicrophone, stopMicrophone, flushPendingFrames, finishPersistingFrames };
}
