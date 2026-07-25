import { useCallback, useEffect, useRef, useState } from 'react';
import { nextDemoPitchFrame } from '../domain/demoPitch';
import { pitchFrameFromPcm } from '../domain/localPitchDetection';
import { setWebAudioSessionType } from '../domain/webAudioSession';
import type { PitchFrame } from '../domain/types';
import { recordPitchFramesInBatches } from '../api/client';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';

const AUDIO_FRAME_SIZE = 4096;
const PERSIST_BATCH_SIZE = 100;
const PERSIST_FLUSH_INTERVAL_MS = 750;
const MAX_BUFFERED_PERSIST_FRAMES = 1500;
export const MAX_WORKER_BACKLOG = 3;
/** A silent worker must not turn the live callback into a permanent drop-only path. */
export const WORKER_RESPONSE_TIMEOUT_MS = 1_500;
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
  processingLatencyMs: number;
  averageProcessingLatencyMs: number;
  maxProcessingLatencyMs: number;
  audioContextState: AudioContextState | 'demo' | 'unavailable' | 'starting' | 'error';
}

export interface AudioFrameTimingObservation {
  lastCallbackAtMs: number | null;
  processedFrames: number;
  droppedFrames: number;
  averageProcessingLatencyMs: number;
  maxProcessingLatencyMs: number;
}

export type BrowserPitchPipeline = 'worker' | 'script-processor';

/** Keep microphone callbacks cheap when detection cannot keep up. */
export function shouldDropWorkerFrame(pendingFrames: number, maximumBacklog = MAX_WORKER_BACKLOG): boolean {
  return pendingFrames >= maximumBacklog;
}

/** The oldest outstanding request is the only one that can prove a stalled worker. */
export function shouldFallbackFromWorkerWatchdog(
  oldestRequestAtMs: number | null,
  nowMs: number,
  timeoutMs = WORKER_RESPONSE_TIMEOUT_MS,
): boolean {
  return oldestRequestAtMs != null && nowMs - oldestRequestAtMs >= timeoutMs;
}

/** Worker support is optional: older and restricted browsers retain local analysis. */
export function selectBrowserPitchPipeline(workerAvailable: boolean, workerStarted: boolean): BrowserPitchPipeline {
  return workerAvailable && workerStarted ? 'worker' : 'script-processor';
}

export function browserPitchPipelineLabel(pipeline: BrowserPitchPipeline): string {
  return pipeline === 'worker' ? 'browser worker pitch' : 'browser local pitch (fallback)';
}

/** Browser and test MediaStream implementations do not all expose getAudioTracks. */
export function audioTracksForStream(stream: Pick<MediaStream, 'getTracks'> & Partial<Pick<MediaStream, 'getAudioTracks'>>): MediaStreamTrack[] {
  const tracks = typeof stream.getAudioTracks === 'function' ? stream.getAudioTracks() : stream.getTracks().filter((track) => track.kind === 'audio');
  return tracks.filter((track) => track.kind === 'audio');
}

export const EMPTY_AUDIO_FRAME_TIMING: AudioFrameTimingObservation = {
  lastCallbackAtMs: null,
  processedFrames: 0,
  droppedFrames: 0,
  averageProcessingLatencyMs: 0,
  maxProcessingLatencyMs: 0,
};

/** Pure timing reducer used by the browser callback and deterministic tests. */
export function observeAudioFrameTiming(
  previous: AudioFrameTimingObservation,
  callbackAtMs: number,
  processingLatencyMs: number,
  expectedFrameDurationMs: number,
): AudioFrameTimingObservation {
  const safeLatency = Math.max(0, Number.isFinite(processingLatencyMs) ? processingLatencyMs : 0);
  const callbackGap = previous.lastCallbackAtMs == null ? 0 : Math.max(0, callbackAtMs - previous.lastCallbackAtMs);
  const intervals = expectedFrameDurationMs > 0 ? Math.max(1, Math.round(callbackGap / expectedFrameDurationMs)) : 1;
  const dropped = previous.lastCallbackAtMs == null ? 0 : Math.max(0, intervals - 1);
  const processedFrames = previous.processedFrames + 1;
  return {
    lastCallbackAtMs: callbackAtMs,
    processedFrames,
    droppedFrames: previous.droppedFrames + dropped,
    averageProcessingLatencyMs: previous.averageProcessingLatencyMs + (safeLatency - previous.averageProcessingLatencyMs) / processedFrames,
    maxProcessingLatencyMs: Math.max(previous.maxProcessingLatencyMs, safeLatency),
  };
}

/** A Worker backlog drop is intentionally not a completed pitch frame. */
export function recordDroppedAudioFrame(previous: AudioFrameTimingObservation): AudioFrameTimingObservation {
  return { ...previous, droppedFrames: previous.droppedFrames + 1 };
}

/** Worker results, unlike callbacks, are the only frames that completed analysis. */
export function recordProcessedWorkerFrame(previous: AudioFrameTimingObservation, processingLatencyMs: number): AudioFrameTimingObservation {
  const safeLatency = Math.max(0, Number.isFinite(processingLatencyMs) ? processingLatencyMs : 0);
  const processedFrames = previous.processedFrames + 1;
  return {
    ...previous,
    processedFrames,
    averageProcessingLatencyMs: previous.averageProcessingLatencyMs + (safeLatency - previous.averageProcessingLatencyMs) / processedFrames,
    maxProcessingLatencyMs: Math.max(previous.maxProcessingLatencyMs, safeLatency),
  };
}

export interface PitchFrameFlushResult {
  flushed: number;
  failed: number;
}

export const MICROPHONE_DISCONNECTED_MESSAGE = 'practice.micDisconnected' as const;
export const MICROPHONE_PAUSED_MESSAGE = 'practice.micPaused' as const;

export function hasLiveMicrophoneTrack(stream: Pick<MediaStream, 'getTracks'> | null): boolean {
  if (!stream) return false;
  return audioTracksForStream(stream as MediaStream).some((track) => track.readyState !== 'ended');
}

export function installMicrophoneEndedHandler(
  stream: Pick<MediaStream, 'getTracks'>,
  onEnded: (event: Event) => void,
): void {
  audioTracksForStream(stream as MediaStream).forEach((track) => {
    track.onended = onEnded;
  });
}

export function audioContextRecoveryStatus(state: AudioContextState): { micActive: boolean; statusMessage: typeof MICROPHONE_PAUSED_MESSAGE | 'practice.micReady' | 'practice.micClosed' } {
  if (state === 'running') {
    return { micActive: true, statusMessage: 'practice.micReady' };
  }
  return {
    micActive: false,
    statusMessage: state === 'closed'
      ? 'practice.micClosed'
      : MICROPHONE_PAUSED_MESSAGE,
  };
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
  const { t } = useI18n();
  const [currentFrame, setCurrentFrame] = useState<PitchFrame | null>(null);
  const [history, setHistory] = useState<PitchFrame[]>([]);
  const [statusMessageId, setStatusMessage] = useState<MessageId>('practice.demoReady');
  const statusMessage = t(statusMessageId);
  const [micActive, setMicActive] = useState(false);
  const [streamInfo, setStreamInfo] = useState<PitchStreamInfo>({
    frameSize: AUDIO_FRAME_SIZE,
    sampleRate: null,
    sentFrames: 0,
    droppedFrames: 0,
    detectorSource: 'guest demo',
    processingLatencyMs: 0,
    averageProcessingLatencyMs: 0,
    maxProcessingLatencyMs: 0,
    audioContextState: 'demo',
  });
  const [mediaStream, setMediaStream] = useState<MediaStream | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const processorRef = useRef<ScriptProcessorNode | null>(null);
  const workerRef = useRef<Worker | null>(null);
  const workerPendingRef = useRef(0);
  const workerRequestTimesRef = useRef(new Map<number, number>());
  const sourceRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const monitorGainRef = useRef<GainNode | null>(null);
  const microphoneStartingRef = useRef(false);
  const microphoneStartPromiseRef = useRef<Promise<MediaStream | null> | null>(null);
  const microphoneGenerationRef = useRef(0);
  const mountedRef = useRef(true);
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
  const audioFrameTimingRef = useRef<AudioFrameTimingObservation>(EMPTY_AUDIO_FRAME_TIMING);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      microphoneGenerationRef.current += 1;
    };
  }, []);

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
          retryable ? 'practice.pitchSyncPending' : 'practice.pitchSyncStopped',
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

  const handleFrame = useCallback((frame: PitchFrame, pipeline?: BrowserPitchPipeline) => {
    setCurrentFrame(frame);
    setStreamInfo((old) => ({
      ...old,
      detectorSource: pipeline ? browserPitchPipelineLabel(pipeline) : (demoModeRef.current ? 'guest demo' : (frame.detector_source ?? old.detectorSource)),
    }));
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
    setStatusMessage('practice.demoReady');
    setStreamInfo((old) => ({ ...old, sampleRate: null, detectorSource: 'guest demo', audioContextState: 'demo' }));
    const timer = window.setInterval(() => {
      const frame = nextDemoPitchFrame(indexRef.current, instrumentId, referencePitch);
      indexRef.current += 1;
      handleFrame(frame);
    }, 110);
    return () => window.clearInterval(timer);
  }, [demoMode, enabled, handleFrame, instrumentId, referencePitch]);

  useEffect(() => {
    setCurrentFrame(null);
    setHistory([]);
  }, [demoMode]);

  const cleanupMicrophone = useCallback((message?: MessageId, finalState?: PitchStreamInfo['audioContextState']) => {
    microphoneGenerationRef.current += 1;
    if (processorRef.current) processorRef.current.onaudioprocess = null;
    if (workerRef.current) {
      workerRef.current.onmessage = null;
      workerRef.current.onerror = null;
      workerRef.current.terminate();
    }
    processorRef.current?.disconnect();
    sourceRef.current?.disconnect();
    monitorGainRef.current?.disconnect();
    mediaStreamRef.current?.getTracks().forEach((track) => {
      track.onended = null;
      track.stop();
    });
    if (audioContextRef.current) audioContextRef.current.onstatechange = null;
    audioContextRef.current?.close().catch(() => undefined);
    processorRef.current = null;
    workerRef.current = null;
    workerPendingRef.current = 0;
    workerRequestTimesRef.current.clear();
    sourceRef.current = null;
    monitorGainRef.current = null;
    mediaStreamRef.current = null;
    audioContextRef.current = null;
    microphoneStartingRef.current = false;
    microphoneStartPromiseRef.current = null;
    setWebAudioSessionType('auto');
    analyzedMsRef.current = 0;
    audioFrameTimingRef.current = EMPTY_AUDIO_FRAME_TIMING;
    if (mountedRef.current) {
      setMediaStream(null);
      setMicActive(false);
      if (message) setStatusMessage(message);
      setStreamInfo((old) => ({
        ...old,
        sampleRate: null,
        detectorSource: demoModeRef.current ? 'guest demo' : 'browser local pitch',
        sentFrames: 0,
        droppedFrames: 0,
        processingLatencyMs: 0,
        averageProcessingLatencyMs: 0,
        maxProcessingLatencyMs: 0,
        audioContextState: finalState ?? (demoModeRef.current ? 'demo' : 'closed'),
      }));
    }
  }, []);

  const stopMicrophone = useCallback(() => {
    cleanupMicrophone();
  }, [cleanupMicrophone]);

  const startMicrophone = useCallback(async () => {
    if (demoModeRef.current || !mountedRef.current) return null;
    if (microphoneStartPromiseRef.current) return microphoneStartPromiseRef.current;

    const existingStream = mediaStreamRef.current;
    const existingContext = audioContextRef.current;
    if (existingStream && existingContext && existingContext.state !== 'closed' && hasLiveMicrophoneTrack(existingStream)) {
      if (existingContext.state !== 'running') {
        await existingContext.resume().catch(() => undefined);
      }
      if (existingContext.state === 'running') {
        setMicActive(true);
        setStatusMessage('practice.micReady');
        return existingStream;
      }
      setMicActive(false);
      setStatusMessage('practice.micPaused');
      return null;
    }
    if (existingStream || existingContext) cleanupMicrophone();

    const AudioContextClass = audioContextConstructor();
    if (!navigator.mediaDevices?.getUserMedia || !AudioContextClass) {
      setStreamInfo((old) => ({ ...old, audioContextState: 'unavailable' }));
      setStatusMessage('practice.micUnavailable');
      return null;
    }
    const generation = ++microphoneGenerationRef.current;
    microphoneStartingRef.current = true;
    setStreamInfo((old) => ({ ...old, audioContextState: 'starting' }));
    setStatusMessage('practice.micRequesting');
    const promise = (async (): Promise<MediaStream | null> => {
      let stream: MediaStream | null = null;
      let audioContext: AudioContext | null = null;
      try {
        setWebAudioSessionType('play-and-record');
        stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
        if (!mountedRef.current || demoModeRef.current || generation !== microphoneGenerationRef.current) {
          stream.getTracks().forEach((track) => track.stop());
          return null;
        }

        audioContext = new AudioContextClass();
        audioContext.onstatechange = () => {
          if (mountedRef.current && generation === microphoneGenerationRef.current) {
            const contextState = audioContext?.state ?? 'closed';
            const recovery = audioContextRecoveryStatus(contextState);
            setStreamInfo((old) => ({ ...old, audioContextState: contextState }));
            setMicActive(recovery.micActive && hasLiveMicrophoneTrack(stream));
            setStatusMessage(recovery.statusMessage);
          }
        };
        const source = audioContext.createMediaStreamSource(stream);
        const processor = audioContext.createScriptProcessor(AUDIO_FRAME_SIZE, 1, 1);
        const monitorGain = audioContext.createGain();
        monitorGain.gain.value = 0;
        source.connect(processor);
        processor.connect(monitorGain);
        monitorGain.connect(audioContext.destination);

        let worker: Worker | null = null;
        const fallBackToLocalPitch = (activeWorker: Worker | null) => {
          if (!activeWorker) return;
          activeWorker.onmessage = null;
          activeWorker.onerror = null;
          activeWorker.terminate();
          if (workerRef.current === activeWorker) workerRef.current = null;
          const abandonedFrames = workerPendingRef.current;
          workerPendingRef.current = 0;
          workerRequestTimesRef.current.clear();
          audioFrameTimingRef.current = Array.from({ length: abandonedFrames }).reduce(recordDroppedAudioFrame, audioFrameTimingRef.current);
          setStreamInfo((old) => ({
            ...old,
            detectorSource: browserPitchPipelineLabel('script-processor'),
            droppedFrames: audioFrameTimingRef.current.droppedFrames,
          }));
        };
        try {
          worker = new Worker(new URL('../workers/pitchDetection.worker.ts', import.meta.url), { type: 'module' });
          worker.onmessage = (workerEvent: MessageEvent<{ type: 'frame'; timestampMs: number; frame: PitchFrame }>) => {
            if (!mountedRef.current || generation !== microphoneGenerationRef.current) return;
            workerPendingRef.current = Math.max(0, workerPendingRef.current - 1);
            const requestedAt = workerRequestTimesRef.current.get(workerEvent.data.timestampMs);
            workerRequestTimesRef.current.delete(workerEvent.data.timestampMs);
            const latencyMs = requestedAt == null ? 0 : Math.max(0, performance.now() - requestedAt);
            const timing = recordProcessedWorkerFrame(audioFrameTimingRef.current, latencyMs);
            audioFrameTimingRef.current = timing;
            setStreamInfo((old) => ({
              ...old,
              sentFrames: timing.processedFrames,
              droppedFrames: timing.droppedFrames,
              processingLatencyMs: latencyMs,
              averageProcessingLatencyMs: timing.averageProcessingLatencyMs,
              maxProcessingLatencyMs: timing.maxProcessingLatencyMs,
              detectorSource: browserPitchPipelineLabel('worker'),
            }));
            handleFrame(workerEvent.data.frame, 'worker');
            if (workerEvent.data.frame.is_valid_for_recording) {
              setStatusMessage('practice.micTracking');
            } else if (workerEvent.data.frame.tuning_status === 'silence') {
              setStatusMessage('practice.micListening');
            } else {
              setStatusMessage('practice.micUnstable');
            }
          };
          worker.onerror = () => {
            // The processor callback below remains a safe local fallback if a
            // browser creates a Worker but later blocks its module execution.
            fallBackToLocalPitch(worker);
          };
          workerRef.current = worker;
        } catch {
          worker = null;
          setStreamInfo((old) => ({ ...old, detectorSource: browserPitchPipelineLabel('script-processor') }));
        }

        if (!mountedRef.current || demoModeRef.current || generation !== microphoneGenerationRef.current) {
          processor.disconnect();
          source.disconnect();
          monitorGain.disconnect();
          stream.getTracks().forEach((track) => track.stop());
          await audioContext.close().catch(() => undefined);
          return null;
        }

        mediaStreamRef.current = stream;
        audioContextRef.current = audioContext;
        sourceRef.current = source;
        processorRef.current = processor;
        monitorGainRef.current = monitorGain;
        installMicrophoneEndedHandler(stream, () => {
          if (
            mountedRef.current
            && generation === microphoneGenerationRef.current
            && mediaStreamRef.current === stream
          ) {
            cleanupMicrophone(MICROPHONE_DISCONNECTED_MESSAGE, 'unavailable');
          }
        });
        setMediaStream(stream);
        audioFrameTimingRef.current = EMPTY_AUDIO_FRAME_TIMING;
        setStreamInfo((old) => ({
          ...old,
          sampleRate: audioContext?.sampleRate ?? null,
          detectorSource: browserPitchPipelineLabel(selectBrowserPitchPipeline(Boolean(worker), Boolean(workerRef.current))),
          sentFrames: 0,
          droppedFrames: 0,
          processingLatencyMs: 0,
          averageProcessingLatencyMs: 0,
          maxProcessingLatencyMs: 0,
          audioContextState: audioContext?.state ?? 'closed',
        }));

        processor.onaudioprocess = (event) => {
          if (!mountedRef.current || generation !== microphoneGenerationRef.current) return;
          const callbackAtMs = performance.now();
          const input = event.inputBuffer.getChannelData(0);
          const pcm = new Float32Array(input);
          analyzedMsRef.current += (pcm.length / audioContext!.sampleRate) * 1000;
          const timestampMs = Math.round(analyzedMsRef.current);
          let activeWorker = workerRef.current;
          const oldestRequestAtMs = activeWorker && workerRequestTimesRef.current.size > 0
            ? Math.min(...workerRequestTimesRef.current.values())
            : null;
          if (activeWorker && shouldFallbackFromWorkerWatchdog(oldestRequestAtMs, callbackAtMs)) {
            // Once the bounded queue is full, a worker that never responds
            // otherwise turns every later audio callback into a dropped frame.
            // Terminate it deterministically and analyze this current PCM locally.
            fallBackToLocalPitch(activeWorker);
            activeWorker = null;
          }
          if (activeWorker && !shouldDropWorkerFrame(workerPendingRef.current)) {
            try {
              workerPendingRef.current += 1;
              workerRequestTimesRef.current.set(timestampMs, callbackAtMs);
              activeWorker.postMessage({
                type: 'detect',
                pcm: pcm.buffer,
                sampleRate: audioContext!.sampleRate,
                instrumentId: instrumentIdRef.current,
                referencePitch: referencePitchRef.current,
                timestampMs,
              }, [pcm.buffer]);
            } catch {
              fallBackToLocalPitch(activeWorker);
            }
          } else if (activeWorker) {
            // Drop stale PCM rather than queuing it: an old pitch estimate is
            // less useful than a current one and can corrupt note timing.
            audioFrameTimingRef.current = recordDroppedAudioFrame(audioFrameTimingRef.current);
            setStreamInfo((old) => ({ ...old, droppedFrames: audioFrameTimingRef.current.droppedFrames }));
          } else {
            const frame = pitchFrameFromPcm(pcm, audioContext!.sampleRate, instrumentIdRef.current, referencePitchRef.current, timestampMs);
            const processingLatencyMs = Math.max(0, performance.now() - callbackAtMs);
            const timing = observeAudioFrameTiming(audioFrameTimingRef.current, callbackAtMs, processingLatencyMs, (AUDIO_FRAME_SIZE / audioContext!.sampleRate) * 1000);
            audioFrameTimingRef.current = timing;
            setStreamInfo((old) => ({
              ...old,
              sentFrames: timing.processedFrames,
              droppedFrames: timing.droppedFrames,
              processingLatencyMs,
              averageProcessingLatencyMs: timing.averageProcessingLatencyMs,
              maxProcessingLatencyMs: timing.maxProcessingLatencyMs,
              detectorSource: browserPitchPipelineLabel('script-processor'),
            }));
            handleFrame(frame, 'script-processor');
            if (frame.is_valid_for_recording) {
              setStatusMessage('practice.micTracking');
            } else if (frame.tuning_status === 'silence') {
              setStatusMessage('practice.micListening');
            } else {
              setStatusMessage('practice.micUnstable');
            }
          }
        };

        if (audioContext.state !== 'running') {
          await audioContext.resume().catch(() => undefined);
        }
        if (!mountedRef.current || demoModeRef.current || generation !== microphoneGenerationRef.current) {
          cleanupMicrophone();
          return null;
        }
        if (audioContext.state !== 'running') {
          setMicActive(false);
          setStatusMessage('practice.micPaused');
          return null;
        }
        setMicActive(true);
        setStatusMessage('practice.micReady');
        return stream;
      } catch {
        if (generation === microphoneGenerationRef.current) {
          cleanupMicrophone('practice.micBlocked', 'error');
        } else {
          stream?.getTracks().forEach((track) => track.stop());
          await audioContext?.close().catch(() => undefined);
        }
        return null;
      } finally {
        if (generation === microphoneGenerationRef.current) {
          microphoneStartingRef.current = false;
          microphoneStartPromiseRef.current = null;
        }
      }
    })();
    microphoneStartPromiseRef.current = promise;
    return promise;
  }, [cleanupMicrophone, handleFrame]);

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
