import { useCallback, useEffect, useRef, useState } from 'react';
import { pitchWebSocketUrl, recordPitchFrame } from '../api/client';
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
  onFrame?: (frame: PitchFrame) => void;
}

export function shouldPersistFrameFromFrontend(demoMode: boolean, recording: boolean, sessionId: number | undefined, frame: PitchFrame) {
  return demoMode && recording && Boolean(sessionId) && frame.is_valid_for_recording;
}

export function usePitchStream({ enabled, demoMode, instrumentId, referencePitch, recording, sessionId, onFrame }: UsePitchStreamOptions) {
  const [currentFrame, setCurrentFrame] = useState<PitchFrame | null>(null);
  const [history, setHistory] = useState<PitchFrame[]>([]);
  const [statusMessage, setStatusMessage] = useState('Demo mode is on, so pitch data is simulated.');
  const [micActive, setMicActive] = useState(false);
  const [streamInfo, setStreamInfo] = useState<PitchStreamInfo>({
    frameSize: AUDIO_FRAME_SIZE,
    sampleRate: null,
    sentFrames: 0,
    droppedFrames: 0,
    detectorSource: 'browser_demo',
  });
  const wsRef = useRef<WebSocket | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const processorRef = useRef<ScriptProcessorNode | null>(null);
  const sourceRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const indexRef = useRef(0);
  const recordingRef = useRef(recording);
  const sessionIdRef = useRef(sessionId);
  const onFrameRef = useRef(onFrame);
  const demoModeRef = useRef(demoMode);

  useEffect(() => {
    recordingRef.current = recording;
    sessionIdRef.current = sessionId;
    onFrameRef.current = onFrame;
    demoModeRef.current = demoMode;
  }, [recording, sessionId, onFrame, demoMode]);

  const handleFrame = useCallback((frame: PitchFrame) => {
    setCurrentFrame(frame);
    setStreamInfo((old) => ({ ...old, detectorSource: frame.detector_source ?? (demoModeRef.current ? 'browser_demo' : old.detectorSource) }));
    setHistory((old) => [frame, ...old.filter((item) => item.is_valid_for_recording)].slice(0, 8));
    onFrameRef.current?.(frame);
    // Demo frames are generated in the browser, so the frontend persists them.
    // Microphone frames are detected and saved by the backend WebSocket when a
    // session_id is present; POSTing them here would double-save the same frame.
    const currentSessionId = sessionIdRef.current;
    if (shouldPersistFrameFromFrontend(demoModeRef.current, recordingRef.current, currentSessionId, frame) && currentSessionId !== undefined) {
      recordPitchFrame(currentSessionId, frame).catch(() => {
        setStatusMessage('Pitch is visible, but the backend could not save this frame.');
      });
    }
  }, []);

  useEffect(() => {
    if (!enabled || !demoMode) return;
    setStatusMessage('Demo mode is on, so pitch data is simulated.');
    setStreamInfo((old) => ({ ...old, sampleRate: null, detectorSource: 'browser_demo' }));
    const timer = window.setInterval(() => {
      const frame = nextDemoPitchFrame(indexRef.current, instrumentId, referencePitch);
      indexRef.current += 1;
      handleFrame(frame);
    }, 110);
    return () => window.clearInterval(timer);
  }, [demoMode, enabled, handleFrame, instrumentId, referencePitch]);

  const stopMicrophone = useCallback(() => {
    processorRef.current?.disconnect();
    sourceRef.current?.disconnect();
    mediaStreamRef.current?.getTracks().forEach((track) => track.stop());
    wsRef.current?.close();
    audioContextRef.current?.close().catch(() => undefined);
    processorRef.current = null;
    sourceRef.current = null;
    mediaStreamRef.current = null;
    audioContextRef.current = null;
    wsRef.current = null;
    setMicActive(false);
    setStreamInfo((old) => ({ ...old, sampleRate: null, detectorSource: demoModeRef.current ? 'browser_demo' : 'backend detector unknown' }));
  }, []);

  const startMicrophone = useCallback(async () => {
    if (demoMode) return;
    if (!navigator.mediaDevices?.getUserMedia || !window.AudioContext) {
      setStatusMessage('This browser does not support the audio APIs needed for live microphone tuning.');
      return;
    }
    try {
      const ws = new WebSocket(await pitchWebSocketUrl());
      wsRef.current = ws;
      ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data);
          if (message.type === 'pitch_frame') {
            handleFrame(message.frame as PitchFrame);
          } else if (message.type === 'error') {
            setStatusMessage(message.message);
          }
        } catch {
          setStatusMessage('The pitch stream returned an unreadable message.');
        }
      };
      ws.onerror = () => setStatusMessage('The pitch WebSocket disconnected. Demo mode still works without the backend.');
      const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
      mediaStreamRef.current = stream;
      const audioContext = new AudioContext();
      audioContextRef.current = audioContext;
      setStreamInfo((old) => ({ ...old, sampleRate: audioContext.sampleRate, detectorSource: 'backend detector unknown', sentFrames: 0, droppedFrames: 0 }));
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
      setMicActive(true);
      setStatusMessage('Microphone is connected. Play a steady note.');
    } catch (error) {
      setStatusMessage('Microphone permission was denied or no microphone was available.');
      stopMicrophone();
    }
  }, [demoMode, handleFrame, instrumentId, referencePitch, stopMicrophone]);

  useEffect(() => {
    if (demoMode) {
      stopMicrophone();
    }
    return () => stopMicrophone();
  }, [demoMode, stopMicrophone]);

  return { currentFrame, history, statusMessage, micActive, streamInfo, startMicrophone, stopMicrophone };
}
