import { Camera, CheckCircle2, FileVideo, Upload } from 'lucide-react';
import { useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { recordPitchFrames, startSession, stopSession } from '../api/client';
import { analyzeLocalMediaFile } from '../domain/localMediaAnalysis';
import type { PracticeSession } from '../domain/types';

export function LocalMediaImportPanel({
  instrumentId,
  referencePitch,
  onImported,
}: {
  instrumentId: string;
  referencePitch: number;
  onImported?: (session: PracticeSession) => void;
}) {
  const libraryInputRef = useRef<HTMLInputElement | null>(null);
  const cameraInputRef = useRef<HTMLInputElement | null>(null);
  const [status, setStatus] = useState('Ready for local video or audio analysis.');
  const [progress, setProgress] = useState(0);
  const [busy, setBusy] = useState(false);
  const [summary, setSummary] = useState<PracticeSession | null>(null);

  const analyzeFile = async (file?: File | null) => {
    if (!file) return;
    setBusy(true);
    setProgress(0);
    setSummary(null);
    setStatus('Decoding local media. The original file is not uploaded or stored.');
    try {
      const analysis = await analyzeLocalMediaFile(file, instrumentId, referencePitch, setProgress);
      const validFrames = analysis.frames.filter((frame) => frame.is_valid_for_recording);
      if (validFrames.length === 0) {
        setStatus('No recording-quality pitch frames were found in this local media file.');
        return;
      }
      const session = await startSession(instrumentId, referencePitch, `Imported ${file.name}`);
      setStatus(`Saving ${validFrames.length} analyzed pitch frames. Source media remains local.`);
      await recordPitchFrames(session.id, validFrames);
      const stopped = await stopSession(session.id);
      setSummary(stopped);
      onImported?.(stopped);
      setStatus(`Analyzed ${Math.round(analysis.analyzedSeconds)}s from ${file.name}. Video/audio was not stored by BrassTune.`);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : 'Local media analysis failed.');
    } finally {
      setBusy(false);
      if (libraryInputRef.current) libraryInputRef.current.value = '';
      if (cameraInputRef.current) cameraInputRef.current.value = '';
    }
  };

  return (
    <div className="local-media-import">
      <div className="insight-heading">
        <span className="insight-icon">
          <FileVideo size={18} />
        </span>
        <div>
          <h3>Analyze local video/audio</h3>
          <span>No video storage, pitch analytics only</span>
        </div>
      </div>
      <p>
        Upload a video from Photos/Files or use the phone camera picker. BrassTune decodes audio in the browser, saves derived pitch frames, and leaves the source media on your device.
      </p>
      <div className="settings-actions">
        <button className="ghost-button" type="button" disabled={busy} onClick={() => libraryInputRef.current?.click()}>
          <Upload size={17} />
          Choose file
        </button>
        <button className="ghost-button" type="button" disabled={busy} onClick={() => cameraInputRef.current?.click()}>
          <Camera size={17} />
          Camera
        </button>
      </div>
      <input ref={libraryInputRef} className="visually-hidden" type="file" accept="audio/*,video/*" onChange={(event) => analyzeFile(event.target.files?.[0])} />
      <input ref={cameraInputRef} className="visually-hidden" type="file" accept="video/*" capture="environment" onChange={(event) => analyzeFile(event.target.files?.[0])} />
      {busy && (
        <div className="import-progress" aria-label="Local media analysis progress">
          <span style={{ width: `${Math.round(progress * 100)}%` }} />
        </div>
      )}
      <p className="settings-status">{status}</p>
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
