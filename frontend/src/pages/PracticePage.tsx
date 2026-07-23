import { FileText, Timer } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { Link, useLocation, useSearchParams } from 'react-router-dom';
import { friendlyUserFacingError } from '../api/client';
import { NoteDisplay } from '../components/NoteDisplay';
import { SessionControls } from '../components/SessionControls';
import { TuningMeter } from '../components/TuningMeter';
import { SessionAudioPlayer } from '../components/SessionAudioPlayer';
import { DroneIntervalPanel } from '../components/practice/DroneIntervalPanel';
import { GuidedWarmupPanel } from '../components/practice/GuidedWarmupPanel';
import { PracticePackPanel } from '../components/practice/PracticePackPanel';
import { PracticeShortcuts } from '../components/practice/PracticeShortcuts';
import { WeeklyGoalCard } from '../components/practice/WeeklyGoalCard';
import { ScreenContainer, SegmentedControl } from '../components/ui/AppPrimitives';
import { useAudioRecorder } from '../hooks/useAudioRecorder';
import { usePitchStream } from '../hooks/usePitchStream';
import { useSessionRecorder } from '../hooks/useSessionRecorder';
import { recordPracticeActivity } from '../domain/practiceStreak';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { usePracticeLibrary } from '../state/PracticeLibraryContext';
import './PracticePage.css';
import { gatewayPathWithReturn } from '../domain/authNavigation';
import { useI18n } from '../i18n/LocaleContext';

// How many consecutive centered frames count as a full "held in tune" reward.
const HOLD_TARGET_FRAMES = 16;

export function PracticePage() {
  const { locale, t, formatNumber } = useI18n();
  const { instrumentId, referencePitch, demoMode, setDemoMode } = useAppSettings();
  const auth = useAuth();
  const location = useLocation();
  const { ownerId, recordActivity, storageError } = usePracticeLibrary();
  const [searchParams, setSearchParams] = useSearchParams();
  const practiceTool = searchParams.get('tool') === 'drone' ? 'drone' : 'tuner';
  const cloudSessionEnabled = auth.isSignedIn;
  const recorder = useSessionRecorder(instrumentId, referencePitch, { cloudEnabled: cloudSessionEnabled });
  const audioRecorder = useAudioRecorder();
  const [transitionBusy, setTransitionBusy] = useState(false);
  const [holdFraction, setHoldFraction] = useState(0);
  const holdCountRef = useRef(0);
  const lastFrameTsRef = useRef<number | null>(null);
  const micRequestedRef = useRef(false);

  const stream = usePitchStream({
    enabled: practiceTool === 'tuner',
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
    if (practiceTool !== 'tuner' || demoMode) {
      if (practiceTool !== 'tuner' && stream.micActive) stream.stopMicrophone();
      micRequestedRef.current = false;
      return;
    }
    if (micRequestedRef.current || stream.micActive) return;
    micRequestedRef.current = true;
    stream.startMicrophone().catch(() => undefined);
  }, [demoMode, practiceTool, stream]);

  // Count a completed take toward the practice streak.
  const lastSavedIdRef = useRef<string | number | null>(null);
  useEffect(() => {
    const summary = recorder.lastSummary;
    if (summary && summary.id !== lastSavedIdRef.current) {
      lastSavedIdRef.current = summary.id;
      const minutes = Math.max(1, Math.round((summary.duration_seconds ?? 0) / 60));
      if (ownerId) recordPracticeActivity(ownerId, minutes);
      recordActivity(minutes);
    }
  }, [ownerId, recordActivity, recorder.lastSummary]);

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
      const inputStream = demoMode ? null : stream.micActive ? stream.mediaStream : await stream.startMicrophone();
      openedMicrophone = !demoMode && !stream.micActive && Boolean(inputStream);
      if (!demoMode && !stream.micActive && !inputStream) {
        recorder.setError(t('practice.errorMicRecord'));
        return;
      }
      const session = await recorder.start(`Practice ${new Date().toLocaleDateString()}`);
      await audioRecorder.start(session.id, demoMode, inputStream);
    } catch (error) {
      if (openedMicrophone) stream.stopMicrophone();
      recorder.setError(locale === 'en' ? friendlyUserFacingError(error, t('practice.errorStart')) : t('practice.errorStart'));
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
          audioRecorder.markLocalSaveFailed(t('practice.errorLocalSave'));
          throw saveError;
        }
      }
      if (sessionId && demoMode) {
        let demoUploadFailed = false;
        const uploadPromise = audioRecorder.stopAndUpload(sessionId, true);
        const flush = await stream.finishPersistingFrames();
        try {
          const uploaded = await uploadPromise;
          if (!uploaded) demoUploadFailed = true;
        } catch {
          demoUploadFailed = true;
        }
        const summary = await recorder.stop();
        if (flush.failed > 0) recorder.setError(t('practice.errorFrameSync'));
        if (demoUploadFailed) recorder.setError(t('practice.errorAudioUpload'));
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
      if (frameSyncFailed) recorder.setError(t('practice.errorFrameSync'));
      if (uploadFailed) recorder.setError(t('practice.errorAudioUpload'));
      return summary;
    } catch (error) {
      recorder.setError(locale === 'en' ? friendlyUserFacingError(error, t('practice.errorSave')) : t('practice.errorSave'));
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
        <SegmentedControl
          ariaLabel={t('practice.tool')}
          value={practiceTool}
          onChange={(value) => setSearchParams(value === 'drone' ? { tool: 'drone' } : {}, { replace: true })}
          options={[
            { value: 'tuner', label: t('nav.tuner') },
            { value: 'drone', label: t('practice.droneIntervals') },
          ]}
        />
        {practiceTool === 'tuner' ? (
          <>
        <div className="tuner-topline">
          <SegmentedControl
            ariaLabel={t('practice.soundSource')}
            value={demoMode ? 'demo' : 'mic'}
            onChange={(value) => setMode(value as 'mic' | 'demo')}
            options={[
              { value: 'mic', label: t('practice.liveMic') },
              { value: 'demo', label: t('practice.demo') },
            ]}
          />
          <span className="tuner-ref">A = {referencePitch} Hz</span>
        </div>

        {micDenied && (
          <div className="tuner-banner" role="status">
            {t('practice.micDeniedBefore')} <button type="button" className="link-button" onClick={() => setMode('demo')}>{t('practice.demo')}</button>{t('practice.micDeniedAfter')}
          </div>
        )}

        <section className="tuner-stage" aria-label={t('practice.liveTuner')}>
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
          {audioRecorder.error && audioRecorder.error !== recorder.error && (
            <div className="alert" role="alert">{audioRecorder.error}</div>
          )}
        </section>

        <div className="tuner-tools" aria-label={t('practice.tools')}>
          <Link className="tuner-tool" to="/metronome">
            <Timer size={18} />
            <span>{t('practice.metronome')}</span>
          </Link>
          <Link className="tuner-tool" to="/practice/score">
            <FileText size={18} />
            <span>{t('practice.sheetMusic')}</span>
          </Link>
        </div>

        {!cloudSessionEnabled && (
          <p className="tuner-signin-note">
            <Link to={gatewayPathWithReturn(`${location.pathname}${location.search}${location.hash}`)} onClick={auth.exitGuest}>{t('nav.signIn')}</Link> {t('practice.signInBenefit')}
          </p>
        )}

        {recorder.lastSummary && (
          <div className="tuner-saved">
            <div>
              <strong>{t('practice.percentInTune', { percent: formatNumber(Math.round(recorder.lastSummary.in_tune_percentage)) })}</strong>
              <span>{t('practice.notesSaved', { count: recorder.lastSummary.notes_count })}</span>
            </div>
            {recorder.lastSummary.audio_available && <SessionAudioPlayer session={recorder.lastSummary} compact />}
            <Link to={`/sessions/${recorder.lastSummary.id}`} className="ghost-button">
              {t('practice.seeResults')}
            </Link>
          </div>
        )}
          </>
        ) : <DroneIntervalPanel />}

        {storageError && <div className="alert" role="alert">{t('error.storage')}</div>}
        <GuidedWarmupPanel />
        <PracticeShortcuts />
        <WeeklyGoalCard />
        <PracticePackPanel />
      </div>
    </ScreenContainer>
  );
}
