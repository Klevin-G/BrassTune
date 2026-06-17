import { Play, Volume2 } from 'lucide-react';
import { useEffect, useState } from 'react';
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

  useEffect(() => {
    if (!session.audio_available) return undefined;
    let revoked = false;
    let localUrl: string | null = null;
    objectUrlFor(`/api/sessions/${session.id}/audio`)
      .then((url) => {
        if (revoked) {
          URL.revokeObjectURL(url);
          return;
        }
        localUrl = url;
        setAudioUrl(url);
      })
      .catch(() => setAudioError('Audio could not be loaded.'));
    return () => {
      revoked = true;
      if (localUrl) URL.revokeObjectURL(localUrl);
    };
  }, [session.audio_available, session.id]);

  if (!session.audio_available) {
    return (
      <div className={`audio-player-card ${compact ? 'compact' : ''} unavailable`}>
        <span className="insight-icon">
          <Volume2 size={17} />
        </span>
        <div>
          <strong>No audio saved</strong>
          <em>Future recordings can include playback.</em>
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
          <strong>Relisten</strong>
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
        <em>Preparing playback...</em>
      )}
    </div>
  );
}
