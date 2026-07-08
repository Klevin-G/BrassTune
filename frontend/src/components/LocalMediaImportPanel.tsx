import { CheckCircle2, File as FileIcon, Square, Upload } from 'lucide-react';
import { useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { friendlyUserFacingError, recordPitchFramesInBatches, startSession, stopSession } from '../api/client';
import { createGuestSession, saveGuestSessionFromFrames } from '../domain/guestSessions';
import { analyzeLocalMediaFile } from '../domain/localMediaAnalysis';
import type { PracticeSession } from '../domain/types';
import { useAuth } from '../state/AuthContext';

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
  const libraryInputRef = useRef<HTMLInputElement | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const [status, setStatus] = useState('Ready to analyze a saved recording.');
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
    setStatus('Decoding local media. The original file is not uploaded or stored.');
    try {
      const analysis = await analyzeLocalMediaFile(file, instrumentId, referencePitch, setProgress, controller.signal);
      const validFrames = analysis.frames.filter((frame) => frame.is_valid_for_recording);
      if (validFrames.length === 0) {
        setStatus('No recording-quality pitch frames were found in this local media file.');
        return;
      }
      let stopped: PracticeSession;
      if (auth.isSignedIn) {
        const session = await startSession(instrumentId, referencePitch, 'Imported recording');
        startedSession = session;
        setStatus(`Saving ${validFrames.length} analyzed pitch frames. Source recording remains on this device.`);
        const result = await recordPitchFramesInBatches(session.id, validFrames, {
          signal: controller.signal,
          onProgress: (saved, attempted) => {
            setStatus(`Saving analyzed pitch frames: ${attempted}/${validFrames.length} sent, ${saved} saved.`);
          },
        });
        if (result.rejected > 0) setStatus(`${result.saved} analyzed frames saved; ${result.rejected} frames were outside recording criteria.`);
        stopped = await stopSession(session.id);
      } else {
        const draft = createGuestSession(instrumentId, referencePitch, `Imported ${file.name}`);
        stopped = saveGuestSessionFromFrames(draft, validFrames);
        setStatus(`Saved ${Math.round(analysis.analyzedSeconds)}s from ${file.name} as a guest review. Source recording remains on this device.`);
      }
      setSummary(stopped);
      onImported?.(stopped);
      if (auth.isSignedIn) {
        setStatus(`Analyzed ${Math.round(analysis.analyzedSeconds)}s from ${file.name}. The source recording was not stored by BrassTune.`);
      }
    } catch (error) {
      if (startedSession) {
        stopSession(startedSession.id).catch(() => undefined);
      }
      setStatus(friendlyUserFacingError(error, 'Local media analysis failed. Try a shorter audio or image file.'));
    } finally {
      if (abortRef.current === controller) abortRef.current = null;
      setBusy(false);
      if (libraryInputRef.current) libraryInputRef.current.value = '';
    }
  };

  const cancel = () => {
    abortRef.current?.abort();
    setStatus('Local media analysis was canceled.');
    setBusy(false);
  };

  return (
    <div className="local-media-import">
      <div className="insight-heading">
        <span className="insight-icon">
          <FileIcon size={18} />
        </span>
        <div>
          <h3>Import recording</h3>
          <span>Audio analysis only</span>
        </div>
      </div>
      <p>
        Choose an audio or video file from Photos or Files. BrassTune analyzes the audio track, saves derived pitch frames, and leaves the source file on your device.
      </p>
      <div className="settings-actions">
        <label className={`ghost-button file-action ${busy ? 'disabled' : ''}`}>
          <Upload size={17} />
          Choose audio or video file
          <input ref={libraryInputRef} className="visually-hidden" type="file" accept="audio/*,video/mp4,video/webm,video/quicktime" disabled={busy} onChange={(event) => analyzeFile(event.target.files?.[0])} aria-label="Choose local audio or video file" />
        </label>
        {busy && (
          <button className="ghost-button" type="button" onClick={cancel}>
            <Square size={17} />
            Cancel
          </button>
        )}
      </div>
      {busy && (
        <div
          className="import-progress"
          role="progressbar"
          aria-label="Local media analysis progress"
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
              <h3>Import analyzed</h3>
              <span>{summary.notes_count} note events</span>
            </div>
          </div>
          <p>{summary.average_abs_cents.toFixed(1)} cents average absolute error, {Math.round(summary.in_tune_percentage)}% in tune.</p>
          <Link to={`/sessions/${summary.id}`} className="primary-button">
            Review imported take
          </Link>
        </div>
      )}
    </div>
  );
}
