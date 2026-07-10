import { FileText, Timer } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { friendlyUserFacingError } from '../api/client';
import { NoteDisplay } from '../components/NoteDisplay';
import { SessionControls } from '../components/SessionControls';
import { TuningMeter } from '../components/TuningMeter';
import { SessionAudioPlayer } from '../components/SessionAudioPlayer';
import { ScreenContainer, SegmentedControl } from '../components/ui/AppPrimitives';
import { useAudioRecorder } from '../hooks/useAudioRecorder';
import { usePitchStream } from '../hooks/usePitchStream';
import { useSessionRecorder } from '../hooks/useSessionRecorder';
import { recordPracticeActivity } from '../domain/practiceStreak';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import './PracticePage.css';

// How many consecutive centered frames count as a full "held in tune" reward.
const HOLD_TARGET_FRAMES = 16;

export function PracticePage() {
  const { instrumentId, referencePitch, demoMode, setDemoMode } = useAppSettings();
  const auth = useAuth();
  const cloudSessionEnabled = auth.isSignedIn;
  const recorder = useSessionRecorder(instrumentId, referencePitch, { cloudEnabled: cloudSessionEnabled });
  const audioRecorder = useAudioRecorder();
  const [transitionBusy, setTransitionBusy] = useState(false);
  const [holdFraction, setHoldFraction] = useState(0);
  const holdCountRef = useRef(0);
  const lastFrameTsRef = useRef<number | null>(null);
  const micRequestedRef = useRef(false);

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

  // Live-on-open: request the microphone as soon as the tuner mounts in mic mode
  // (and whenever the user switches back to mic), so the tuner just works.
  useEffect(() => {
    if (demoMode) {
      micRequestedRef.current = false;
      return;
    }
    if (micRequestedRef.current || stream.micActive) return;
    micRequestedRef.current = true;
    stream.startMicrophone().catch(() => undefined);
  }, [demoMode, stream]);

  // Count a completed take toward the practice streak.
  const lastSavedIdRef = useRef<string | number | null>(null);
  useEffect(() => {
    const summary = recorder.lastSummary;
    if (summary && summary.id !== lastSavedIdRef.current) {
      lastSavedIdRef.current = summary.id;
      recordPracticeActivity(Math.max(1, Math.round((summary.duration_seconds ?? 0) / 60)));
    }
  }, [recorder.lastSummary]);

  // Grow the in-tune reward the longer the player holds a centered pitch.
  useEffect(() => {
    const frame = stream.currentFrame;
    if (!frame || frame.timestamp_ms === lastFrameTsRef.current) return;
    lastFrameTsRef.current = frame.timestamp_ms;
    const centered = frame.tuning_status !== 'silence' && frame.cents_deviation != null && Math.abs(frame.cents_deviation) <= 5;
    holdCountRef.current = centered ? Math.min(HOLD_TARGET_FRAMES, holdCountRef.current + 1) : 0;
    setHoldFraction(holdCountRef.current / HOLD_TARGET_FRAMES);
  }, [stream.currentFrame]);

  const start = async () => {
    if (transitionBusy || recorder.busy || recorder.recording) return;
    setTransitionBusy(true);
    let openedMicrophone = false;
    try {
      const inputStream = demoMode ? null : stream.micActive ? null : await stream.startMicrophone();
      openedMicrophone = !demoMode && Boolean(inputStream);
      if (!demoMode && !stream.micActive && !inputStream) {
        recorder.setError('We need your microphone to record. Turn it on, or switch to Demo above.');
        return;
      }
      const session = await recorder.start(`Practice ${new Date().toLocaleDateString()}`);
      await audioRecorder.start(session.id, demoMode, inputStream);
    } catch (error) {
      if (openedMicrophone) stream.stopMicrophone();
      recorder.setError(friendlyUserFacingError(error, 'Recording could not start. Guest practice still works on this device.'));
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
          audioRecorder.markLocalSaveFailed('Your take was recorded, but it could not be saved on this device.');
          throw saveError;
        }
      }
      if (sessionId && demoMode) {
        const uploadPromise = audioRecorder.stopAndUpload(sessionId, true);
        const flush = await stream.finishPersistingFrames();
        const summary = await recorder.stop();
        uploadPromise
          .then((audio) => {
            if (!audio) recorder.setError('Take saved, but the audio upload failed. Your results are still here.');
          })
          .catch(() => recorder.setError('Take saved, but the audio upload failed. Your results are still here.'));
        if (flush.failed > 0) recorder.setError('Take saved, but the last few notes may not have synced. Record again if the summary looks short.');
        return summary;
      }
      let uploadFailed = false;
      let frameSyncFailed = false;
      if (sessionId) {
        const uploadPromise = audioRecorder.stopAndUpload(sessionId, demoMode);
        const flush = await stream.finishPersistingFrames();
        try {
          const uploaded = await uploadPromise;
          if (!uploaded) uploadFailed = true;
        } catch {
          uploadFailed = true;
        }
        frameSyncFailed = flush.failed > 0;
      }
      const summary = await recorder.stop();
      if (frameSyncFailed) recorder.setError('Take saved, but the last few notes may not have synced. Record again if the summary looks short.');
      if (uploadFailed) recorder.setError('Take saved, but the audio upload failed. Your results are still here.');
      return summary;
    } catch (error) {
      recorder.setError(friendlyUserFacingError(error, 'Your take could not be saved. Try again in a moment.'));
      return null;
    } finally {
      setTransitionBusy(false);
    }
  };

  const setMode = (mode: 'mic' | 'demo') => {
    if (recorder.recording) return;
    if (mode === 'demo') {
      if (stream.micActive) stream.stopMicrophone();
      setDemoMode(true);
    } else {
      setDemoMode(false);
    }
    recorder.setError(null);
  };

  const micDenied = !demoMode && !stream.micActive && /denied|blocked|not allowed|need/i.test(stream.statusMessage);

  return (
    <ScreenContainer>
      <div className="tuner-page">
        <div className="tuner-topline">
          <SegmentedControl
            ariaLabel="Sound source"
            value={demoMode ? 'demo' : 'mic'}
            onChange={(value) => setMode(value as 'mic' | 'demo')}
            options={[
              { value: 'mic', label: 'Live mic' },
              { value: 'demo', label: 'Demo' },
            ]}
          />
          <span className="tuner-ref">A = {referencePitch} Hz</span>
        </div>

        {micDenied && (
          <div className="tuner-banner" role="status">
            We can’t hear your microphone yet. Allow mic access in your browser, or switch to <button type="button" className="link-button" onClick={() => setMode('demo')}>Demo</button>.
          </div>
        )}

        <section className="tuner-stage" aria-label="Live tuner">
          <NoteDisplay frame={stream.currentFrame} />
          <TuningMeter frame={stream.currentFrame} holdFraction={holdFraction} />
          <SessionControls
            recording={recorder.recording}
            elapsedSeconds={recorder.elapsedSeconds}
            demoMode={demoMode}
            micActive={stream.micActive}
            busy={transitionBusy || recorder.busy || audioRecorder.status === 'uploading'}
            onStart={start}
            onStop={stop}
            onMicStart={stream.startMicrophone}
            onMicStop={stream.stopMicrophone}
          />
          {recorder.error && <div className="alert" role="alert">{recorder.error}</div>}
        </section>

        <div className="tuner-tools" aria-label="Practice tools">
          <Link className="tuner-tool" to="/metronome">
            <Timer size={18} />
            <span>Metronome</span>
          </Link>
          <Link className="tuner-tool" to="/practice/score">
            <FileText size={18} />
            <span>Sheet music</span>
          </Link>
        </div>

        {!cloudSessionEnabled && (
          <p className="tuner-signin-note">
            <Link to="/">Sign in</Link> to save your practice history and join your class.
          </p>
        )}

        {recorder.lastSummary && (
          <div className="tuner-saved">
            <div>
              <strong>{Math.round(recorder.lastSummary.in_tune_percentage)}% in tune</strong>
              <span>{recorder.lastSummary.notes_count} notes · saved</span>
            </div>
            {recorder.lastSummary.audio_available && <SessionAudioPlayer session={recorder.lastSummary} compact />}
            <Link to={`/sessions/${recorder.lastSummary.id}`} className="ghost-button">
              See results
            </Link>
          </div>
        )}
      </div>
    </ScreenContainer>
  );
}
