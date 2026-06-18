import { useEffect, useRef, useState } from 'react';
import { startSession, stopSession } from '../api/client';
import type { PracticeSession } from '../domain/types';

export type SessionRecorderState = 'idle' | 'starting' | 'recording' | 'stopping' | 'failed';

export function useSessionRecorder(instrumentId: string, referencePitch: number) {
  const [state, setState] = useState<SessionRecorderState>('idle');
  const [activeSession, setActiveSession] = useState<PracticeSession | null>(null);
  const [lastSummary, setLastSummary] = useState<PracticeSession | null>(null);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const activeSessionRef = useRef<PracticeSession | null>(null);
  const startPromiseRef = useRef<Promise<PracticeSession> | null>(null);
  const stopPromiseRef = useRef<Promise<PracticeSession | null> | null>(null);
  const recording = state === 'recording' || state === 'stopping';

  useEffect(() => {
    if (state !== 'recording' || !activeSession) return;
    const started = new Date(activeSession.started_at).getTime();
    const timer = window.setInterval(() => {
      setElapsedSeconds(Math.max(0, Math.floor((Date.now() - started) / 1000)));
    }, 500);
    return () => window.clearInterval(timer);
  }, [state, activeSession]);

  const start = async (name?: string) => {
    if (startPromiseRef.current) return startPromiseRef.current;
    if (activeSessionRef.current) return activeSessionRef.current;
    setError(null);
    setState('starting');
    const promise = startSession(instrumentId, referencePitch, name)
      .then((session) => {
        activeSessionRef.current = session;
        setActiveSession(session);
        setState('recording');
        setLastSummary(null);
        setElapsedSeconds(0);
        return session;
      })
      .catch((startError) => {
        setState('failed');
        setError(startError instanceof Error ? startError.message : String(startError));
        throw startError;
      })
      .finally(() => {
        startPromiseRef.current = null;
      });
    startPromiseRef.current = promise;
    return promise;
  };

  const stop = async () => {
    if (stopPromiseRef.current) return stopPromiseRef.current;
    const session = activeSessionRef.current;
    if (!session) return null;
    setError(null);
    setState('stopping');
    const promise = stopSession(session.id)
      .then((summary) => {
        setLastSummary(summary);
        activeSessionRef.current = null;
        setActiveSession(null);
        setElapsedSeconds(0);
        setState('idle');
        return summary;
      })
      .catch((stopError) => {
        setState('failed');
        setError(stopError instanceof Error ? stopError.message : String(stopError));
        throw stopError;
      })
      .finally(() => {
        stopPromiseRef.current = null;
      });
    stopPromiseRef.current = promise;
    return promise;
  };

  return { state, recording, busy: state === 'starting' || state === 'stopping', activeSession, lastSummary, elapsedSeconds, error, setError, start, stop };
}
