import { Link } from 'react-router-dom';
import { NoteDisplay } from '../components/NoteDisplay';
import { SessionControls } from '../components/SessionControls';
import { SignalMeter } from '../components/SignalMeter';
import { TunerNeedle } from '../components/TunerNeedle';
import { usePitchStream } from '../hooks/usePitchStream';
import { useSessionRecorder } from '../hooks/useSessionRecorder';
import { useAppSettings } from '../state/AppSettingsContext';

export function PracticePage() {
  const { instrumentId, referencePitch, demoMode } = useAppSettings();
  const recorder = useSessionRecorder(instrumentId, referencePitch);
  const stream = usePitchStream({
    enabled: true,
    demoMode,
    instrumentId,
    referencePitch,
    recording: recorder.recording,
    sessionId: recorder.activeSession?.id,
  });

  const start = () => recorder.start(`Practice ${new Date().toLocaleDateString()}`).catch((error) => recorder.setError(String(error)));
  const stop = () => recorder.stop().catch((error) => recorder.setError(String(error)));

  return (
    <div className="practice-layout">
      <section className="tuner-surface">
        <div className="tuner-header">
          <div>
            <h2>Real-time tuner</h2>
            <p>{stream.statusMessage}</p>
          </div>
          <span className={`record-dot ${recorder.recording ? 'on' : ''}`}>{recorder.recording ? 'Recording' : 'Ready'}</span>
        </div>
        <NoteDisplay frame={stream.currentFrame} />
        <TunerNeedle frame={stream.currentFrame} />
        <SignalMeter frame={stream.currentFrame} />
        <SessionControls
          recording={recorder.recording}
          elapsedSeconds={recorder.elapsedSeconds}
          demoMode={demoMode}
          micActive={stream.micActive}
          onStart={start}
          onStop={stop}
          onMicStart={stream.startMicrophone}
        />
        {recorder.error && <div className="alert">{recorder.error}</div>}
      </section>
      <aside className="panel side-panel">
        <h2>Detected notes</h2>
        <div className="note-history">
          {stream.history.map((frame, index) => (
            <div className="history-row" key={`${frame.timestamp_ms}-${index}`}>
              <span>{frame.written_note_name}{frame.written_octave}</span>
              <strong>{frame.cents_deviation && frame.cents_deviation > 0 ? '+' : ''}{Math.round(frame.cents_deviation ?? 0)}c</strong>
              <em>{frame.tuning_status.replace('_', ' ')}</em>
            </div>
          ))}
        </div>
        {recorder.lastSummary && (
          <div className="summary-box">
            <h3>Session saved</h3>
            <p>{recorder.lastSummary.notes_count} note events, {recorder.lastSummary.average_abs_cents.toFixed(1)} cents avg abs.</p>
            <Link to={`/sessions/${recorder.lastSummary.id}`} className="primary-button">Review session</Link>
          </div>
        )}
      </aside>
    </div>
  );
}

