import { useCallback, useRef, useState } from 'react';
import { uploadSessionAudio } from '../api/client';

type UploadStatus = 'idle' | 'recording' | 'uploading' | 'uploaded' | 'failed' | 'unavailable';

function wavFromSine(durationSeconds = 4, frequency = 440, sampleRate = 16000) {
  const sampleCount = Math.floor(durationSeconds * sampleRate);
  const bytesPerSample = 2;
  const buffer = new ArrayBuffer(44 + sampleCount * bytesPerSample);
  const view = new DataView(buffer);
  const writeString = (offset: number, value: string) => {
    for (let index = 0; index < value.length; index += 1) {
      view.setUint8(offset + index, value.charCodeAt(index));
    }
  };
  writeString(0, 'RIFF');
  view.setUint32(4, 36 + sampleCount * bytesPerSample, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * bytesPerSample, true);
  view.setUint16(32, bytesPerSample, true);
  view.setUint16(34, 8 * bytesPerSample, true);
  writeString(36, 'data');
  view.setUint32(40, sampleCount * bytesPerSample, true);
  for (let index = 0; index < sampleCount; index += 1) {
    const envelope = Math.min(1, index / 800, (sampleCount - index) / 800);
    const wobble = Math.sin((2 * Math.PI * index) / sampleRate / 1.5) * 4;
    const sample = Math.sin((2 * Math.PI * (frequency + wobble) * index) / sampleRate) * 0.32 * envelope;
    view.setInt16(44 + index * bytesPerSample, Math.max(-1, Math.min(1, sample)) * 0x7fff, true);
  }
  return new Blob([buffer], { type: 'audio/wav' });
}

export function useAudioRecorder() {
  const [status, setStatus] = useState<UploadStatus>('idle');
  const [error, setError] = useState<string | null>(null);
  const [lastSessionId, setLastSessionId] = useState<number | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const streamRef = useRef<MediaStream | null>(null);
  const startedAtRef = useRef<number>(0);
  const startPromiseRef = useRef<Promise<void> | null>(null);
  const stopPromiseRef = useRef<Promise<unknown> | null>(null);

  const start = useCallback(async (sessionId: number, demoMode: boolean) => {
    if (startPromiseRef.current) return startPromiseRef.current;
    if (status === 'recording') return undefined;
    setError(null);
    setLastSessionId(sessionId);
    startedAtRef.current = Date.now();
    chunksRef.current = [];
    const promise = (async () => {
      try {
        if (demoMode) {
          setStatus('recording');
          return;
        }
        if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
          setStatus('unavailable');
          setError('Audio playback capture is unavailable in this browser.');
          return;
        }
        const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
        streamRef.current = stream;
        const recorder = new MediaRecorder(stream);
        recorder.ondataavailable = (event) => {
          if (event.data.size > 0) chunksRef.current.push(event.data);
        };
        recorderRef.current = recorder;
        recorder.start();
        setStatus('recording');
      } catch {
        setStatus('unavailable');
        setError('Microphone permission was denied, so this session may not include playback audio.');
      } finally {
        startPromiseRef.current = null;
      }
    })();
    startPromiseRef.current = promise;
    return promise;
  }, [status]);

  const stopAndUpload = useCallback(async (sessionId: number, demoMode: boolean) => {
    if (stopPromiseRef.current) return stopPromiseRef.current;
    const durationSeconds = Math.max(1, (Date.now() - startedAtRef.current) / 1000);
    setStatus('uploading');
    const promise = (async () => {
    try {
      let blob: Blob;
      if (demoMode) {
        blob = wavFromSine(Math.min(8, Math.max(3, durationSeconds)));
      } else {
        const recorder = recorderRef.current;
        if (!recorder) {
          setStatus('unavailable');
          return null;
        }
        blob = await new Promise<Blob>((resolve) => {
          recorder.onstop = () => resolve(new Blob(chunksRef.current, { type: recorder.mimeType || 'audio/webm' }));
          recorder.stop();
        });
      }
      streamRef.current?.getTracks().forEach((track) => track.stop());
      const result = await uploadSessionAudio(sessionId, blob, durationSeconds);
      setStatus('uploaded');
      return result.audio;
    } catch (uploadError) {
      setStatus('failed');
      setError(uploadError instanceof Error ? uploadError.message : 'Audio upload failed.');
      return null;
    } finally {
      recorderRef.current = null;
      streamRef.current = null;
      chunksRef.current = [];
      stopPromiseRef.current = null;
    }
    })();
    stopPromiseRef.current = promise;
    return promise;
  }, []);

  return { status, error, lastSessionId, start, stopAndUpload };
}
