import { Play, Volume2 } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { objectUrlFor } from '../api/client';
import type { PracticeSession } from '../domain/types';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';

function formatBytes(
  size: number | null | undefined,
  t: (id: MessageId, values?: Record<string, string | number>) => string,
  formatNumber: (value: number, options?: Intl.NumberFormatOptions) => string,
) {
  if (!size) return t('sessionAudio.sizeUnavailable');
  if (size < 1024 * 1024) return t('sessionAudio.kilobytes', { count: formatNumber(Math.round(size / 1024)) });
  return t('sessionAudio.megabytes', { count: formatNumber(size / 1024 / 1024, { minimumFractionDigits: 1, maximumFractionDigits: 1 }) });
}

export function retryAudioPlayback(audio: Pick<HTMLAudioElement, 'load'> | null): boolean {
  if (!audio) return false;
  audio.load();
  return true;
}

export function SessionAudioPlayer({ session, compact = false }: { session: PracticeSession; compact?: boolean }) {
  const { t, formatNumber } = useI18n();
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [audioError, setAudioError] = useState<string | null>(null);
  const [playbackError, setPlaybackError] = useState(false);
  const [loading, setLoading] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);
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
    setPlaybackError(false);
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
        setAudioError(t('sessionAudio.loadError'));
      }
    } finally {
      if (generation === requestGenerationRef.current) {
        loadingRef.current = false;
        if (mountedRef.current) setLoading(false);
      }
    }
  }, [replaceAudioUrl, session.audio_available, session.guest_audio_data_url, session.id, t]);

  // Load as soon as the player is shown — it is only mounted when the user has
  // asked to listen, so the click on "Listen back" should surface a ready
  // player rather than a second "Load playback" button.
  useEffect(() => {
    requestGenerationRef.current += 1;
    sessionIdRef.current = session.id;
    loadingRef.current = false;
    replaceAudioUrl(null);
    setAudioError(null);
    setPlaybackError(false);
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
          <strong>{t('sessionAudio.noAudio')}</strong>
          <em>{t('sessionAudio.noAudioBody')}</em>
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
          <strong>{t('sessionAudio.listenBack')}</strong>
          <em>
            <bdi>{t('sessionAudio.metadata', {
              seconds: formatNumber(Math.round(session.audio_duration_seconds ?? session.duration_seconds)),
              size: formatBytes(session.audio_size_bytes, t, formatNumber),
            })}</bdi>
          </em>
        </div>
      </div>
      {audioError && <em role="alert">{audioError}</em>}
      {audioUrl ? (
        <>
          {playbackError && <em role="alert">{t('sessionAudio.unsupported')}</em>}
          <audio
            ref={audioRef}
            src={audioUrl}
            controls
            preload="metadata"
            aria-label={t('sessionAudio.listenBack')}
            onError={() => setPlaybackError(true)}
            onLoadedMetadata={() => setPlaybackError(false)}
          >
            <track kind="captions" />
            {t('sessionAudio.unsupported')}
          </audio>
          {playbackError && (
            <button
              className="ghost-button"
              type="button"
              onClick={() => {
                setPlaybackError(false);
                retryAudioPlayback(audioRef.current);
              }}
            >
              <Play size={17} />
              {t('sessionAudio.loadPlayback')}
            </button>
          )}
        </>
      ) : (
        <button className="ghost-button" type="button" onClick={loadAudio} disabled={loading}>
          <Play size={17} />
          {t(loading ? 'sessionAudio.preparingPlayback' : 'sessionAudio.loadPlayback')}
        </button>
      )}
    </div>
  );
}
