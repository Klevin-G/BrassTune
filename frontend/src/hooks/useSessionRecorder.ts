import { useEffect, useState } from 'react';
import { startSession, stopSession } from '../api/client';
import type { PracticeSession } from '../domain/types';

export function useSessionRecorder(instrumentId: string, referencePitch: number) {
  const [recording, setRecording] = useState(false);
  const [activeSession, setActiveSession] = useState<PracticeSession | null>(null);
  const [lastSummary, setLastSummary] = useState<PracticeSession | null>(null);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!recording || !activeSession) return;
    const started = new Date(activeSession.started_at).getTime();
    const timer = window.setInterval(() => {
      setElapsedSeconds(Math.max(0, Math.floor((Date.now() - started) / 1000)));
    }, 500);
    return () => window.clearInterval(timer);
  }, [recording, activeSession]);

  const start = async (name?: string) => {
    setError(null);
    const session = await startSession(instrumentId, referencePitch, name);
    setActiveSession(session);
    setRecording(true);
    setLastSummary(null);
    setElapsedSeconds(0);
    return session;
  };

  const stop = async () => {
    if (!activeSession) return null;
    setError(null);
    setRecording(false);
    const summary = await stopSession(activeSession.id);
    setLastSummary(summary);
    setActiveSession(null);
    return summary;
  };

  return { recording, activeSession, lastSummary, elapsedSeconds, error, setError, start, stop };
}

