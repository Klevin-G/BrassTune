import { ArrowRight, Gauge, History, Mic, Timer } from 'lucide-react';
import { Link } from 'react-router-dom';
import { NoteDisplay } from '../components/NoteDisplay';
import { SessionControls } from '../components/SessionControls';
import { SignalMeter } from '../components/SignalMeter';
import { TunerNeedle } from '../components/TunerNeedle';
import { EmptyActionState, ScreenContainer, StatusBadge } from '../components/ui/AppPrimitives';
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
  const latestValid = stream.history.find((frame) => frame.is_valid_for_recording);

  return (
    <ScreenContainer>
      <div className="practice-layout">
        <section className="tuner-surface">
          <div className="tuner-header">
            <div>
              <p className="eyebrow">Live tuner cockpit</p>
              <h1>{latestValid?.written_note_name ? `${latestValid.written_note_name}${latestValid.written_octave}` : 'Ready'}</h1>
              <p>{stream.statusMessage}</p>
            </div>
            <span className={`record-dot ${recorder.recording ? 'on' : ''}`}>{recorder.recording ? 'Recording' : demoMode ? 'Demo ready' : 'Mic ready'}</span>
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
        <aside className="section-card side-panel">
          <div className="section-card-heading">
            <div>
              <p className="eyebrow">Run state</p>
              <h2>Recording lane</h2>
            </div>
            <StatusBadge tone={recorder.recording ? 'red' : 'gold'}>{recorder.recording ? 'Active' : 'Standby'}</StatusBadge>
          </div>
          <div className="insight-grid">
            <article className="insight-card tone-gold">
              <div className="insight-heading">
                <span className="insight-icon">
                  <Gauge size={18} />
                </span>
                <div>
                  <h3>A4 reference</h3>
                  <span>{referencePitch} Hz</span>
                </div>
              </div>
              <p>{demoMode ? 'Demo mode generates stable brass-like samples for repeatable review.' : 'Microphone mode streams audio to the backend detector.'}</p>
            </article>
            <article className="insight-card">
              <div className="insight-heading">
                <span className="insight-icon">
                  <Timer size={18} />
                </span>
                <div>
                  <h3>Session timer</h3>
                  <span>{Math.floor(recorder.elapsedSeconds / 60)}:{String(recorder.elapsedSeconds % 60).padStart(2, '0')}</span>
                </div>
              </div>
              <p>Short blocks make the note-level analytics easier to trust and compare.</p>
            </article>
          </div>
          <div className="inline-panel">
            <div className="section-card-heading">
              <div>
                <p className="eyebrow">Signal trail</p>
                <h2>Last detected notes</h2>
              </div>
            </div>
            {stream.history.length === 0 && <EmptyActionState title="No notes detected" body="Start demo playback or enable the microphone to see recent pitch frames." icon={Mic} />}
            <div className="note-history">
              {stream.history.slice(0, 8).map((frame, index) => (
                <div className="history-row" key={`${frame.timestamp_ms}-${index}`}>
                  <span>
                    {frame.written_note_name}
                    {frame.written_octave}
                  </span>
                  <strong>
                    {frame.cents_deviation && frame.cents_deviation > 0 ? '+' : ''}
                    {Math.round(frame.cents_deviation ?? 0)}c
                  </strong>
                  <em>{frame.tuning_status.replace('_', ' ')}</em>
                </div>
              ))}
            </div>
          </div>
          {recorder.lastSummary && (
            <div className="saved-session-card">
              <div className="insight-heading">
                <span className="insight-icon">
                  <History size={18} />
                </span>
                <div>
                  <h3>Session saved</h3>
                  <span>{recorder.lastSummary.notes_count} note events</span>
                </div>
              </div>
              <p>{recorder.lastSummary.average_abs_cents.toFixed(1)} cents average absolute error, {Math.round(recorder.lastSummary.in_tune_percentage)}% in tune.</p>
              <Link to={`/sessions/${recorder.lastSummary.id}`} className="primary-button">
                Review session
                <ArrowRight size={18} />
              </Link>
            </div>
          )}
        </aside>
      </div>
    </ScreenContainer>
  );
}
