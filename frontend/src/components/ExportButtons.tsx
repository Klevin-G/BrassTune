import { Download } from 'lucide-react';
import { useState } from 'react';
import { downloadExport } from '../api/client';
import type { GuestSessionDetail } from '../domain/guestSessions';

function downloadBlob(content: string, filename: string, type = 'application/json') {
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

function csvEscape(value: unknown) {
  return `"${String(value ?? '').replace(/"/g, '""')}"`;
}

function guestSamplesCsv(session: GuestSessionDetail) {
  const header = ['timestamp_ms', 'written_note', 'written_octave', 'cents_deviation', 'confidence', 'rms', 'tuning_status'];
  const rows = session.frames.map((frame) => [
    frame.timestamp_ms,
    frame.written_note_name,
    frame.written_octave,
    frame.cents_deviation,
    frame.confidence,
    frame.rms,
    frame.tuning_status,
  ]);
  return [header, ...rows].map((row) => row.map(csvEscape).join(',')).join('\n');
}

function guestEventsCsv(session: GuestSessionDetail) {
  const header = ['note_label', 'duration_seconds', 'sample_count', 'avg_signed_cents', 'avg_abs_cents', 'in_tune_percentage'];
  const rows = session.note_events.map((event) => [
    event.note_label,
    event.duration_seconds,
    event.sample_count,
    event.avg_signed_cents,
    event.avg_abs_cents,
    event.in_tune_percentage,
  ]);
  return [header, ...rows].map((row) => row.map(csvEscape).join(',')).join('\n');
}

function audioExtension(mimeType?: string | null) {
  if (!mimeType) return 'webm';
  if (mimeType.includes('wav')) return 'wav';
  if (mimeType.includes('mp4') || mimeType.includes('m4a')) return 'm4a';
  if (mimeType.includes('ogg')) return 'ogg';
  if (mimeType.includes('mpeg') || mimeType.includes('mp3')) return 'mp3';
  if (mimeType.includes('webm')) return 'webm';
  return 'audio';
}

export function ExportButtons({ sessionId, guestSession }: { sessionId: number; guestSession?: GuestSessionDetail | null }) {
  const [status, setStatus] = useState<string | null>(null);
  const download = (path: string, filename: string) => {
    setStatus(null);
    downloadExport(path, filename)
      .then(() => setStatus(`${filename} export started.`))
      .catch(() => setStatus('Export is unavailable right now. Try again after reconnecting.'));
  };

  if (guestSession) {
    return (
      <div className="export-buttons">
        <button className="ghost-button" type="button" onClick={() => downloadBlob(guestSamplesCsv(guestSession), `guest-session-${Math.abs(sessionId)}-samples.csv`, 'text/csv')}>
          <Download size={17} />
          Pitch data (CSV)
        </button>
        <button className="ghost-button" type="button" onClick={() => downloadBlob(guestEventsCsv(guestSession), `guest-session-${Math.abs(sessionId)}-note-events.csv`, 'text/csv')}>
          <Download size={17} />
          Notes (CSV)
        </button>
        <button className="ghost-button" type="button" onClick={() => downloadBlob(JSON.stringify(guestSession, null, 2), `guest-session-${Math.abs(sessionId)}.json`)}>
          <Download size={17} />
          All data (JSON)
        </button>
        {guestSession.guest_audio_data_url && (
          <a className="ghost-button" href={guestSession.guest_audio_data_url} download={`guest-session-${Math.abs(sessionId)}-audio.${audioExtension(guestSession.audio_mime_type)}`}>
            <Download size={17} />
            Audio file
          </a>
        )}
        {status && <p className="settings-status" aria-live="polite">{status}</p>}
      </div>
    );
  }

  return (
    <div className="export-buttons">
      <button className="ghost-button" type="button" onClick={() => download(`/api/export/session/${sessionId}.csv`, `session-${sessionId}-samples.csv`)}>
        <Download size={17} />
        Pitch data (CSV)
      </button>
      <button className="ghost-button" type="button" onClick={() => download(`/api/export/note-events/${sessionId}.csv`, `session-${sessionId}-note-events.csv`)}>
        <Download size={17} />
        Notes (CSV)
      </button>
      <button className="ghost-button" type="button" onClick={() => download(`/api/export/session/${sessionId}.json`, `session-${sessionId}.json`)}>
        <Download size={17} />
        All data (JSON)
      </button>
      <button className="ghost-button" type="button" onClick={() => download(`/api/export/session/${sessionId}.zip`, `session-${sessionId}-export.zip`)}>
        <Download size={17} />
        Everything (ZIP)
      </button>
      <button className="ghost-button" type="button" onClick={() => download(`/api/export/session/${sessionId}/audio`, `session-${sessionId}-audio`)}>
        <Download size={17} />
        Audio file
      </button>
      {status && <p className="settings-status" aria-live="polite">{status}</p>}
    </div>
  );
}
