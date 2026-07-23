import { Play, Volume2 } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { objectUrlFor } from '../api/client';
import type { PracticeSession } from '../domain/types';

function formatBytes(size?: number | null) {
  if (!size) return 'No file size';
  if (size < 1024 * 1024) return `${Math.round(size / 1024)} KB`;
  return `${(size / 1024 / 1024).toFixed(1)} MB`;
}

export function SessionAudioPlayer({ session, compact = false }: { session: PracticeSession; compact?: boolean }) {
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [audioError, setAudioError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const audioUrlRef = useRef<string | null>(null);
  const loadingRef = useRef(false);
  const mountedRef = useRef(true);
  const sessionIdRef = useRef(session.id);
  const requestGenerationRef = useRef(0);

  const replaceAudioUrl = useCallback((nextUrl: string | null) => {
    const previous = audioUrlRef.current;
    if (previous && previous !== nextUrl && previous.startsWith('blob:')) URL.revokeObjectURL(previous);
    audioUrlRef.current = nextUrl;
    setAudioUrl(nextUrl);
  }, []);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      requestGenerationRef.current += 1;
      loadingRef.current = false;
      if (audioUrlRef.current?.startsWith('blob:')) URL.revokeObjectURL(audioUrlRef.current);
      audioUrlRef.current = null;
    };
  }, []);

  const loadAudio = useCallback(async () => {
    if (!session.audio_available || audioUrlRef.current || loadingRef.current) return;
    const sessionId = session.id;
    const generation = ++requestGenerationRef.current;
    loadingRef.current = true;
    setAudioError(null);
    setLoading(true);
    try {
      const nextUrl = session.guest_audio_data_url ?? await objectUrlFor(`/api/sessions/${sessionId}/audio`);
      if (!mountedRef.current || generation !== requestGenerationRef.current || sessionIdRef.current !== sessionId) {
        if (nextUrl.startsWith('blob:')) URL.revokeObjectURL(nextUrl);
        return;
      }
      replaceAudioUrl(nextUrl);
    } catch {
      if (mountedRef.current && generation === requestGenerationRef.current && sessionIdRef.current === sessionId) {
        setAudioError('Audio could not be loaded.');
      }
    } finally {
      if (generation === requestGenerationRef.current) {
        loadingRef.current = false;
        if (mountedRef.current) setLoading(false);
      }
    }
  }, [replaceAudioUrl, session.audio_available, session.guest_audio_data_url, session.id]);

  // Load as soon as the player is shown — it is only mounted when the user has
  // asked to listen, so the click on "Listen back" should surface a ready
  // player rather than a second "Load playback" button.
  useEffect(() => {
    requestGenerationRef.current += 1;
    sessionIdRef.current = session.id;
    loadingRef.current = false;
    replaceAudioUrl(null);
    setAudioError(null);
    setLoading(false);
    if (session.audio_available) void loadAudio();
  }, [loadAudio, replaceAudioUrl, session.audio_available, session.id]);

  if (!session.audio_available) {
    return (
      <div className={`audio-player-card ${compact ? 'compact' : ''} unavailable`}>
        <span className="insight-icon">
          <Volume2 size={17} />
        </span>
        <div>
          <strong>No audio</strong>
          <em>This session was saved without audio.</em>
        </div>
      </div>
    );
  }
  return (
    <div className={`audio-player-card ${compact ? 'compact' : ''}`}>
      <div className="audio-player-heading">
        <span className="insight-icon">
          <Play size={17} />
        </span>
        <div>
          <strong>Listen back</strong>
          <em>
            {Math.round(session.audio_duration_seconds ?? session.duration_seconds)}s · {formatBytes(session.audio_size_bytes)}
          </em>
        </div>
      </div>
      {audioError && <em>{audioError}</em>}
      {audioUrl ? (
        <audio src={audioUrl} controls preload="none">
          <track kind="captions" />
        </audio>
      ) : (
        <button className="ghost-button" type="button" onClick={loadAudio} disabled={loading}>
          <Play size={17} />
          {loading ? 'Preparing playback...' : 'Load playback'}
        </button>
      )}
    </div>
  );
}
