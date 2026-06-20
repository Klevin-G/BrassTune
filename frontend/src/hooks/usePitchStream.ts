import { useCallback, useEffect, useRef, useState } from 'react';
import { pitchWebSocketAuthPayload, pitchWebSocketUrl, recordPitchFrame } from '../api/client';
import { nextDemoPitchFrame } from '../domain/demoPitch';
import type { PitchFrame } from '../domain/types';

const AUDIO_FRAME_SIZE = 4096;

export interface PitchStreamInfo {
  frameSize: number;
  sampleRate: number | null;
  sentFrames: number;
  droppedFrames: number;
  detectorSource: string;
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
  return persistToBackend && demoMode && recording && Boolean(sessionId) && Number(sessionId) > 0 && frame.is_valid_for_recording;
}

function friendlyPitchMessage(message: string) {
  if (/auth|token|unauthor/i.test(message)) {
    return 'Sign in is required to sync microphone sessions. You can still use guest demo practice on this device.';
  }
  if (/backend|websocket|server/i.test(message)) {
    return 'Cloud practice is unavailable right now. Demo mode still works on this device.';
  }
  return message;
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
  const wsRef = useRef<WebSocket | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const processorRef = useRef<ScriptProcessorNode | null>(null);
  const sourceRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const microphoneStartingRef = useRef(false);
  const indexRef = useRef(0);
  const recordingRef = useRef(recording);
  const sessionIdRef = useRef(sessionId);
  const onFrameRef = useRef(onFrame);
  const demoModeRef = useRef(demoMode);
  const persistDemoFramesToBackendRef = useRef(persistDemoFramesToBackend);

  useEffect(() => {
    recordingRef.current = recording;
    sessionIdRef.current = sessionId;
    onFrameRef.current = onFrame;
    demoModeRef.current = demoMode;
    persistDemoFramesToBackendRef.current = persistDemoFramesToBackend;
  }, [recording, sessionId, onFrame, demoMode, persistDemoFramesToBackend]);

  const handleFrame = useCallback((frame: PitchFrame) => {
    setCurrentFrame(frame);
    setStreamInfo((old) => ({ ...old, detectorSource: frame.detector_source ?? (demoModeRef.current ? 'guest demo' : old.detectorSource) }));
    setHistory((old) => [frame, ...old.filter((item) => item.is_valid_for_recording)].slice(0, 8));
    onFrameRef.current?.(frame);
    // Demo frames are generated in the browser, so signed-in demo recordings
    // persist them from the frontend. Microphone frames are saved by the cloud
    // pitch stream when a session_id is present.
    const currentSessionId = sessionIdRef.current;
    if (shouldPersistFrameFromFrontend(demoModeRef.current, recordingRef.current, currentSessionId, frame, persistDemoFramesToBackendRef.current) && currentSessionId !== undefined) {
      recordPitchFrame(currentSessionId, frame).catch(() => {
        setStatusMessage('Pitch is visible, but cloud sync could not save this frame. Guest practice still works on this device.');
      });
    }
  }, []);

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
    mediaStreamRef.current?.getTracks().forEach((track) => track.stop());
    audioContextRef.current?.close().catch(() => undefined);
    processorRef.current = null;
    sourceRef.current = null;
    mediaStreamRef.current = null;
    audioContextRef.current = null;
    wsRef.current = null;
    microphoneStartingRef.current = false;
    setMicActive(false);
    if (message) setStatusMessage(message);
    setStreamInfo((old) => ({ ...old, sampleRate: null, detectorSource: demoModeRef.current ? 'guest demo' : 'cloud pitch detector' }));
  }, []);

  const stopMicrophone = useCallback(() => {
    const ws = wsRef.current;
    cleanupMicrophone();
    if (ws && ws.readyState !== WebSocket.CLOSED && ws.readyState !== WebSocket.CLOSING) {
      ws.close();
    }
  }, [cleanupMicrophone]);

  const startMicrophone = useCallback(async () => {
    if (demoMode || micActive || microphoneStartingRef.current) return;
    if (!navigator.mediaDevices?.getUserMedia || !window.AudioContext) {
      setStatusMessage('Microphone input is unavailable in this browser. Guest demo practice still works on this device.');
      return;
    }
    microphoneStartingRef.current = true;
    setStatusMessage('Requesting microphone permission.');
    try {
      const [url, authPayload] = await Promise.all([pitchWebSocketUrl(), pitchWebSocketAuthPayload()]);
      setStatusMessage('Connecting to the pitch server.');
      const ws = new WebSocket(url);
      wsRef.current = ws;
      ws.onopen = () => {
        if (authPayload && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify(authPayload));
        }
        setStatusMessage('Pitch server connected. Waiting for microphone audio.');
      };
      ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data);
          if (message.type === 'pitch_frame') {
            handleFrame(message.frame as PitchFrame);
            setMicActive(true);
            setStatusMessage((message.frame as PitchFrame).is_valid_for_recording ? 'Sound detected. Tracking pitch now.' : 'Listening for sound. No pitch lock yet.');
          } else if (message.type === 'error') {
            setStatusMessage(friendlyPitchMessage(message.message ?? 'Pitch stream error.'));
          }
        } catch {
          setStatusMessage('The pitch stream returned an unreadable message.');
        }
      };
      ws.onerror = () => cleanupMicrophone('Pitch stream disconnected. You can retry the microphone or keep using guest demo practice.');
      ws.onclose = () => {
        if (wsRef.current === ws) {
          cleanupMicrophone('Pitch stream disconnected. You can retry the microphone or keep using guest demo practice.');
        }
      };
      const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
      mediaStreamRef.current = stream;
      const audioContext = new AudioContext();
      audioContextRef.current = audioContext;
      setStreamInfo((old) => ({ ...old, sampleRate: audioContext.sampleRate, detectorSource: 'cloud pitch detector', sentFrames: 0, droppedFrames: 0 }));
      const source = audioContext.createMediaStreamSource(stream);
      const processor = audioContext.createScriptProcessor(AUDIO_FRAME_SIZE, 1, 1);
      source.connect(processor);
      processor.connect(audioContext.destination);
      sourceRef.current = source;
      processorRef.current = processor;
      processor.onaudioprocess = (event) => {
        if (ws.readyState !== WebSocket.OPEN) {
          setStreamInfo((old) => ({ ...old, droppedFrames: old.droppedFrames + 1 }));
          return;
        }
        const pcm = Array.from(event.inputBuffer.getChannelData(0));
        setStreamInfo((old) => ({ ...old, sentFrames: old.sentFrames + 1 }));
        ws.send(
          JSON.stringify({
            type: 'audio_frame',
            session_id: sessionIdRef.current,
            instrument_id: instrumentId,
            reference_pitch_hz: referencePitch,
            sample_rate: audioContext.sampleRate,
            pcm,
          }),
        );
      };
      microphoneStartingRef.current = false;
      setStatusMessage(ws.readyState === WebSocket.OPEN ? 'Listening for sound. Play a steady note.' : 'Microphone permission granted. Connecting to the pitch server.');
    } catch (error) {
      cleanupMicrophone('Microphone permission was denied or no microphone was available. Guest demo practice still works on this device.');
    }
  }, [cleanupMicrophone, demoMode, handleFrame, instrumentId, micActive, referencePitch]);

  useEffect(() => {
    if (demoMode) {
      stopMicrophone();
    }
    return () => stopMicrophone();
  }, [demoMode, stopMicrophone]);

  return { currentFrame, history, statusMessage, micActive, streamInfo, startMicrophone, stopMicrophone };
}
