import { ArrowRight, FileText, Gauge, History, Mic, Play, Timer, UploadCloud } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { LocalMediaImportPanel } from '../components/LocalMediaImportPanel';
import { NoteDisplay } from '../components/NoteDisplay';
import { SessionControls } from '../components/SessionControls';
import { SignalMeter } from '../components/SignalMeter';
import { SessionAudioPlayer } from '../components/SessionAudioPlayer';
import { TunerNeedle } from '../components/TunerNeedle';
import { EmptyActionState, ScreenContainer, StatusBadge } from '../components/ui/AppPrimitives';
import { describeSaveEligibility } from '../domain/pitchFrameStatus';
import { useAudioRecorder } from '../hooks/useAudioRecorder';
import { usePitchStream } from '../hooks/usePitchStream';
import { useSessionRecorder } from '../hooks/useSessionRecorder';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';

export function PracticePage() {
  const { instrumentId, referencePitch, demoMode } = useAppSettings();
  const auth = useAuth();
  const cloudSessionEnabled = auth.isSignedIn;
  const recorder = useSessionRecorder(instrumentId, referencePitch, { cloudEnabled: cloudSessionEnabled });
  const audioRecorder = useAudioRecorder();
  const [transitionBusy, setTransitionBusy] = useState(false);
  const stream = usePitchStream({
    enabled: true,
    demoMode,
    instrumentId,
    referencePitch,
    recording: recorder.recording,
    sessionId: recorder.activeSession?.id,
    persistDemoFramesToBackend: cloudSessionEnabled,
    onFrame: recorder.captureFrame,
  });

  const start = async () => {
    if (transitionBusy || recorder.busy || recorder.recording) return;
    setTransitionBusy(true);
    try {
      const inputStream = demoMode ? null : await stream.startMicrophone();
      if (!demoMode && !inputStream) {
        recorder.setError('Microphone access is needed for live recording. You can switch to guided mode or retry microphone access.');
        return;
      }
      const session = await recorder.start(`Practice ${new Date().toLocaleDateString()}`);
      await audioRecorder.start(session.id, demoMode, inputStream);
    } catch (error) {
      recorder.setError(String(error));
    } finally {
      setTransitionBusy(false);
    }
  };
  const stop = async () => {
    if (transitionBusy || recorder.busy || !recorder.activeSession) return null;
    setTransitionBusy(true);
    try {
      const sessionId = recorder.activeSession?.id;
      if (!cloudSessionEnabled) {
        const guestAudio = await audioRecorder.stopLocal(demoMode);
        try {
          const summary = await recorder.stop(guestAudio);
          if (guestAudio) audioRecorder.markLocalSaved();
          return summary;
        } catch (saveError) {
          audioRecorder.markLocalSaveFailed('Guest audio was captured, but the local session could not be saved on this device.');
          throw saveError;
        }
      }
      if (sessionId && demoMode) {
        const uploadPromise = audioRecorder.stopAndUpload(sessionId, true);
        const summary = await recorder.stop();
        void uploadPromise.catch(() => undefined);
        return summary;
      }
      if (sessionId) {
        await audioRecorder.stopAndUpload(sessionId, demoMode);
      }
      const summary = await recorder.stop();
      return summary;
    } catch (error) {
      recorder.setError(String(error));
      return null;
    } finally {
      setTransitionBusy(false);
    }
  };
  const latestValid = stream.history.find((frame) => frame.is_valid_for_recording);
  const eligibility = describeSaveEligibility(stream.currentFrame);
  const microphoneLabel = stream.micActive ? 'Listening' : stream.statusMessage.startsWith('Requesting') || stream.statusMessage.startsWith('Connecting') ? 'Connecting' : 'Mic';

  return (
    <ScreenContainer>
      <div className="practice-layout">
        <section className="tuner-surface">
          <div className="tuner-header">
            <div>
              <p className="eyebrow">Live tuner cockpit</p>
              <h1>{latestValid?.written_note_name ? `${latestValid.written_note_name}${latestValid.written_octave}` : 'Ready'}</h1>
              <p>{stream.statusMessage}</p>
              {!cloudSessionEnabled && <p className="muted-copy">Guest sessions stay on this device. Sign in to sync practice history and ensemble features.</p>}
            </div>
            <span className={`record-dot ${recorder.recording ? 'on' : ''}`}>{recorder.recording ? 'Recording' : demoMode ? 'Guest demo ready' : 'Microphone optional'}</span>
          </div>
          <NoteDisplay frame={stream.currentFrame} />
          <TunerNeedle frame={stream.currentFrame} />
          <SessionControls
            recording={recorder.recording}
            elapsedSeconds={recorder.elapsedSeconds}
            demoMode={demoMode}
            micActive={stream.micActive}
            microphoneLabel={microphoneLabel}
            busy={transitionBusy || recorder.busy || audioRecorder.status === 'uploading'}
            onStart={start}
            onStop={stop}
            onMicStart={stream.startMicrophone}
          />
          <SignalMeter frame={stream.currentFrame} />
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
              <p>{demoMode ? 'Guest demo mode generates stable brass-like samples for repeatable review.' : 'Microphone mode listens for pitch and saves cloud sessions only after sign-in.'}</p>
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
            <article className={`insight-card tone-${eligibility.tone}`}>
              <div className="insight-heading">
                <span className="insight-icon">
                  <Mic size={18} />
                </span>
                <div>
                  <h3>Save eligibility</h3>
                  <span>{eligibility.label}</span>
                </div>
              </div>
              <p>{eligibility.detail}</p>
            </article>
            <article className={`insight-card ${audioRecorder.status === 'failed' ? 'tone-red' : audioRecorder.status === 'uploaded' ? 'tone-green' : ''}`}>
              <div className="insight-heading">
                <span className="insight-icon">
                  <UploadCloud size={18} />
                </span>
                <div>
                  <h3>Relisten audio</h3>
                  <span>{audioRecorder.status}</span>
                </div>
              </div>
              <p>{audioRecorder.error ?? (cloudSessionEnabled ? 'Audio is captured for playback when a recording stops.' : 'Guest playback stays in this browser and is not uploaded.')}</p>
            </article>
          </div>
          <div className="inline-panel">
            <div className="section-card-heading">
              <div>
                <p className="eyebrow">Practice tools</p>
                <h2>Tempo and score</h2>
              </div>
            </div>
            <div className="settings-actions">
              <Link className="ghost-button" to="/metronome">
                <Timer size={18} />
                Open metronome
              </Link>
              <Link className="ghost-button" to="/practice/score">
                <FileText size={18} />
                Open score practice
              </Link>
            </div>
            <p className="muted-copy">Use count-ins, tempo ramps, and local score pages alongside the tuner. Automatic score following remains a separate validation item.</p>
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
          <div className="inline-panel">
            <LocalMediaImportPanel instrumentId={instrumentId} referencePitch={referencePitch} />
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
              {recorder.lastSummary.audio_available && <SessionAudioPlayer session={recorder.lastSummary} compact />}
              {!recorder.lastSummary.audio_available && audioRecorder.status === 'uploaded' && (
                <p className="muted-copy">
                  <Play size={15} /> Audio uploaded. Open review for playback.
                </p>
              )}
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
