import { CheckCircle2, File as FileIcon, Square, Upload } from 'lucide-react';
import { useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { friendlyUserFacingError, recordPitchFramesInBatches, startSession, stopSession } from '../api/client';
import { createGuestSession, saveGuestSessionFromFrames } from '../domain/guestSessions';
import { analyzeLocalMediaFile } from '../domain/localMediaAnalysis';
import type { PracticeSession } from '../domain/types';
import { useAuth } from '../state/AuthContext';
import { useI18n } from '../i18n/LocaleContext';

function bidiIsolate(value: string | number) {
  return `\u2068${value}\u2069`;
}

export function LocalMediaImportPanel({
  instrumentId,
  referencePitch,
  onImported,
}: {
  instrumentId: string;
  referencePitch: number;
  onImported?: (session: PracticeSession) => void;
}) {
  const auth = useAuth();
  const { locale, t, formatNumber } = useI18n();
  const libraryInputRef = useRef<HTMLInputElement | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const [status, setStatus] = useState(() => t('localMedia.ready'));
  const [progress, setProgress] = useState(0);
  const [busy, setBusy] = useState(false);
  const [summary, setSummary] = useState<PracticeSession | null>(null);

  const analyzeFile = async (file?: File | null) => {
    if (!file) return;
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    let startedSession: PracticeSession | null = null;
    setBusy(true);
    setProgress(0);
    setSummary(null);
    setStatus(t('localMedia.decoding'));
    try {
      const analysis = await analyzeLocalMediaFile(file, instrumentId, referencePitch, setProgress, controller.signal);
      const validFrames = analysis.frames.filter((frame) => frame.is_valid_for_recording);
      if (validFrames.length === 0) {
        setStatus(t('localMedia.noFrames'));
        return;
      }
      let stopped: PracticeSession;
      if (auth.isSignedIn) {
        const session = await startSession(instrumentId, referencePitch, t('localMedia.importedRecording'));
        startedSession = session;
        setStatus(t('localMedia.savingFrames', { count: formatNumber(validFrames.length) }));
        const result = await recordPitchFramesInBatches(session.id, validFrames, {
          signal: controller.signal,
          onProgress: (saved, attempted) => {
            setStatus(t('localMedia.savingProgress', { attempted: formatNumber(attempted), total: formatNumber(validFrames.length), saved: formatNumber(saved) }));
          },
        });
        if (result.rejected > 0) setStatus(t('localMedia.rejected', { saved: formatNumber(result.saved), rejected: formatNumber(result.rejected) }));
        stopped = await stopSession(session.id);
      } else {
        const draft = createGuestSession(instrumentId, referencePitch, t('localMedia.importedRecording'));
        stopped = saveGuestSessionFromFrames(draft, validFrames);
        setStatus(t('localMedia.guestSaved', { seconds: formatNumber(Math.round(analysis.analyzedSeconds)), filename: bidiIsolate(file.name) }));
      }
      setSummary(stopped);
      onImported?.(stopped);
      if (auth.isSignedIn) {
        setStatus(t('localMedia.analyzed', { seconds: formatNumber(Math.round(analysis.analyzedSeconds)), filename: bidiIsolate(file.name) }));
      }
    } catch (error) {
      if (startedSession) {
        stopSession(startedSession.id).catch(() => undefined);
      }
      setStatus(locale === 'en' ? friendlyUserFacingError(error, t('localMedia.failed')) : t('localMedia.failed'));
    } finally {
      if (abortRef.current === controller) abortRef.current = null;
      setBusy(false);
      if (libraryInputRef.current) libraryInputRef.current.value = '';
    }
  };

  const cancel = () => {
    abortRef.current?.abort();
    setStatus(t('localMedia.canceled'));
    setBusy(false);
  };

  return (
    <div className="local-media-import">
      <div className="insight-heading">
        <span className="insight-icon">
          <FileIcon size={18} />
        </span>
        <div>
          <h3>{t('localMedia.title')}</h3>
          <span>{t('localMedia.audioOnly')}</span>
        </div>
      </div>
      <p>
        {t('localMedia.description')}
      </p>
      <div className="settings-actions">
        <label className={`ghost-button file-action ${busy ? 'disabled' : ''}`}>
          <Upload size={17} />
          {t('localMedia.choose')}
          <input ref={libraryInputRef} className="visually-hidden" type="file" accept="audio/*,video/mp4,video/webm,video/quicktime" disabled={busy} onChange={(event) => analyzeFile(event.target.files?.[0])} aria-label={t('localMedia.choose')} />
        </label>
        {busy && (
          <button className="ghost-button" type="button" onClick={cancel}>
            <Square size={17} />
            {t('common.cancel')}
          </button>
        )}
      </div>
      {busy && (
        <div
          className="import-progress"
          role="progressbar"
          aria-label={t('localMedia.progress')}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={Math.round(progress * 100)}
        >
          <span style={{ width: `${Math.round(progress * 100)}%` }} />
        </div>
      )}
      <p className="settings-status" aria-live="polite">{status}</p>
      {summary && (
        <div className="saved-session-card compact">
          <div className="insight-heading">
            <span className="insight-icon">
              <CheckCircle2 size={18} />
            </span>
            <div>
              <h3>{t('localMedia.complete')}</h3>
              <span><bdi dir="ltr">{t('localMedia.noteEvents', { count: summary.notes_count })}</bdi></span>
            </div>
          </div>
          <p>{t('localMedia.summary', { cents: formatNumber(summary.average_abs_cents, { maximumFractionDigits: 1 }), percent: formatNumber(Math.round(summary.in_tune_percentage)) })}</p>
          <Link to={`/sessions/${summary.id}`} className="primary-button">
            {t('localMedia.review')}
          </Link>
        </div>
      )}
    </div>
  );
}
