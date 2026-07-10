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
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    return () => {
      if (audioUrl?.startsWith('blob:')) URL.revokeObjectURL(audioUrl);
    };
  }, [audioUrl]);

  const loadAudio = async () => {
    if (audioUrl || loading) return;
    setAudioError(null);
    setLoading(true);
    try {
      setAudioUrl(session.guest_audio_data_url ?? await objectUrlFor(`/api/sessions/${session.id}/audio`));
    } catch {
      setAudioError('Audio could not be loaded.');
    } finally {
      setLoading(false);
    }
  };

  // Load as soon as the player is shown — it is only mounted when the user has
  // asked to listen, so the click on "Listen back" should surface a ready
  // player rather than a second "Load playback" button.
  useEffect(() => {
    if (session.audio_available) void loadAudio();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session.id]);

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
