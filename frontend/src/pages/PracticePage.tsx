import { FileText, Timer } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { Link, useBlocker, useLocation, useSearchParams } from 'react-router-dom';
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
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { usePracticeLibrary } from '../state/PracticeLibraryContext';
import './PracticePage.css';
import { gatewayPathWithReturn } from '../domain/authNavigation';
import { useI18n } from '../i18n/LocaleContext';
import { isReliableTunerFrame } from '../domain/pitchFrameStatus';
import type { PracticeSession } from '../domain/types';

// How many consecutive centered frames count as a full "held in tune" reward.
const HOLD_TARGET_FRAMES = 16;
interface TakeTransitionOperation {
  (): Promise<PracticeSession | null>;
}

export function nextTunerHoldCount(current: number, frame: Parameters<typeof isReliableTunerFrame>[0]): number {
  const centered = isReliableTunerFrame(frame) && Math.abs(frame.cents_deviation!) <= 5;
  return centered ? Math.min(HOLD_TARGET_FRAMES, current + 1) : 0;
}

export function PracticePage() {
  const { locale, t, formatNumber } = useI18n();
  const { instrumentId, referencePitch, demoMode, setDemoMode } = useAppSettings();
  const auth = useAuth();
  const location = useLocation();
  const { recordSavedSession, storageError } = usePracticeLibrary();
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
  const lastSavedIdRef = useRef<string | number | null>(null);
  const recorderRef = useRef(recorder);
  const audioRecorderRef = useRef(audioRecorder);
  const streamRef = useRef<ReturnType<typeof usePitchStream> | null>(null);
  const demoModeRef = useRef(demoMode);
  const activeSessionIdRef = useRef<number | null>(recorder.activeSession?.id ?? null);
  const recordingCloudEnabledRef = useRef(cloudSessionEnabled);
  const recordingDemoModeRef = useRef(demoMode);
  const takeTransitionRef = useRef<Promise<PracticeSession | null> | null>(null);
  const takeTransitionKindRef = useRef<'start' | 'stop' | null>(null);
  const toolSwitchPromiseRef = useRef<Promise<void> | null>(null);
  const stopRef = useRef(async (): Promise<PracticeSession | null> => null);
  const recordSavedSessionRef = useRef(recordSavedSession);
  const navigationIntentRef = useRef(false);
  const blockedNavigationRef = useRef(false);

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
  recorderRef.current = recorder;
  audioRecorderRef.current = audioRecorder;
  recordSavedSessionRef.current = recordSavedSession;
  streamRef.current = stream;
  demoModeRef.current = demoMode;
  if (recorder.activeSession) {
    activeSessionIdRef.current = recorder.activeSession.id;
  } else if (recorder.state === 'idle') {
    activeSessionIdRef.current = null;
  }
  const activeTake = recorder.recording || Boolean(recorder.activeSession) || activeSessionIdRef.current !== null;

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
  useEffect(() => {
    const summary = recorder.lastSummary;
    if (summary && summary.id !== lastSavedIdRef.current) {
      if (recordSavedSession(summary)) lastSavedIdRef.current = summary.id;
    }
  }, [recordSavedSession, recorder.lastSummary]);

  const recordCompletedSession = (summary: PracticeSession) => {
    if (recordSavedSessionRef.current(summary)) lastSavedIdRef.current = summary.id;
  };

  // Grow the in-tune reward the longer the player holds a centered pitch.
  useEffect(() => {
    const frame = stream.currentFrame;
    if (!frame || frame.timestamp_ms === lastFrameTsRef.current) return;
    lastFrameTsRef.current = frame.timestamp_ms;
    holdCountRef.current = nextTunerHoldCount(holdCountRef.current, frame);
    setHoldFraction(holdCountRef.current / HOLD_TARGET_FRAMES);
  }, [stream.currentFrame]);

  const runTakeTransition = (
    kind: 'start' | 'stop',
    operation: TakeTransitionOperation,
  ) => {
    setTransitionBusy(true);
    takeTransitionKindRef.current = kind;
    const promise = operation().finally(() => {
      if (takeTransitionRef.current === promise) {
        takeTransitionRef.current = null;
        takeTransitionKindRef.current = null;
        setTransitionBusy(false);
      }
    });
    takeTransitionRef.current = promise;
    return promise;
  };

  const start = async (): Promise<PracticeSession | null> => {
    if (takeTransitionRef.current) return takeTransitionRef.current;
    if (recorderRef.current.busy || recorderRef.current.recording || activeSessionIdRef.current !== null) {
      return recorderRef.current.activeSession;
    }
    recordingCloudEnabledRef.current = cloudSessionEnabled;
    recordingDemoModeRef.current = demoModeRef.current;
    return runTakeTransition('start', async () => {
      let openedMicrophone = false;
      try {
        const currentStream = streamRef.current;
        const currentDemoMode = recordingDemoModeRef.current;
        const inputStream = currentDemoMode
          ? null
          : currentStream?.micActive
            ? currentStream.mediaStream
            : await currentStream?.startMicrophone();
        openedMicrophone = !currentDemoMode && !currentStream?.micActive && Boolean(inputStream);
        if (!currentDemoMode && !currentStream?.micActive && !inputStream) {
          recorderRef.current.setError(t('practice.errorMicRecord'));
          return null;
        }
        const session = await recorderRef.current.start(`Practice ${new Date().toLocaleDateString()}`);
        activeSessionIdRef.current = session.id;
        await audioRecorderRef.current.start(session.id, currentDemoMode, inputStream);
        return session;
      } catch (error) {
        if (openedMicrophone) streamRef.current?.stopMicrophone();
        recorderRef.current.setError(locale === 'en' ? friendlyUserFacingError(error, t('practice.errorStart')) : t('practice.errorStart'));
        return null;
      }
    });
  };

  const stop = async (): Promise<PracticeSession | null> => {
    // A Drone request can arrive while microphone permission or the backend
    // session start is still pending. Let that single start settle, then close
    // the take. Repeated requests share whichever stop is already in flight.
    while (takeTransitionRef.current) {
      const currentTransition = takeTransitionRef.current;
      const currentKind = takeTransitionKindRef.current;
      const result = await currentTransition;
      if (currentKind === 'stop') return result;
    }

    const sessionId = activeSessionIdRef.current ?? recorderRef.current.activeSession?.id ?? null;
    if (sessionId === null) return null;

    return runTakeTransition('stop', async () => {
      try {
        const currentDemoMode = recordingDemoModeRef.current;
        if (!recordingCloudEnabledRef.current) {
          const guestAudio = await audioRecorderRef.current.stopLocal(currentDemoMode);
          try {
            const summary = await recorderRef.current.stop(guestAudio);
            activeSessionIdRef.current = null;
            if (guestAudio) audioRecorderRef.current.markLocalSaved();
            if (summary) recordCompletedSession(summary);
            return summary;
          } catch (saveError) {
            audioRecorderRef.current.markLocalSaveFailed(t('practice.errorLocalSave'));
            throw saveError;
          }
        }
        if (currentDemoMode) {
          let demoUploadFailed = false;
          const uploadPromise = audioRecorderRef.current.stopAndUpload(sessionId, true);
          const flush = await streamRef.current?.finishPersistingFrames() ?? { saved: 0, rejected: 0, failed: 0 };
          try {
            const uploaded = await uploadPromise;
            if (!uploaded) demoUploadFailed = true;
          } catch {
            demoUploadFailed = true;
          }
          const summary = await recorderRef.current.stop();
          activeSessionIdRef.current = null;
          if (summary) recordCompletedSession(summary);
          if (flush.failed > 0) recorderRef.current.setError(t('practice.errorFrameSync'));
          if (demoUploadFailed) recorderRef.current.setError(t('practice.errorAudioUpload'));
          return summary;
        }
        let uploadFailed = false;
        const uploadPromise = audioRecorderRef.current.stopAndUpload(sessionId, currentDemoMode);
        const flush = await streamRef.current?.finishPersistingFrames() ?? { saved: 0, rejected: 0, failed: 0 };
        try {
          const uploaded = await uploadPromise;
          if (!uploaded) uploadFailed = true;
        } catch {
          uploadFailed = true;
        }
        const summary = await recorderRef.current.stop();
        activeSessionIdRef.current = null;
        if (summary) recordCompletedSession(summary);
        if (flush.failed > 0) recorderRef.current.setError(t('practice.errorFrameSync'));
        if (uploadFailed) recorderRef.current.setError(t('practice.errorAudioUpload'));
        return summary;
      } catch (error) {
        recorderRef.current.setError(locale === 'en' ? friendlyUserFacingError(error, t('practice.errorSave')) : t('practice.errorSave'));
        return null;
      }
    });
  };
  stopRef.current = stop;

  const hasTakeLifecycleToFinalize = () => Boolean(
    takeTransitionRef.current
    || activeSessionIdRef.current !== null
    || recorderRef.current.activeSession
    || recorderRef.current.busy
    || recorderRef.current.recording
    || audioRecorderRef.current.status === 'recording'
    || audioRecorderRef.current.status === 'uploading',
  );

  const navigationBlocker = useBlocker(({ currentLocation, nextLocation }) => (
    currentLocation.pathname !== nextLocation.pathname
    || currentLocation.search !== nextLocation.search
    || currentLocation.hash !== nextLocation.hash
  ) && hasTakeLifecycleToFinalize());

  // The data router blocks before this route unmounts, preserving the current
  // Tuner instance and its Stop/retry surface if finalization fails.
  useEffect(() => {
    if (navigationBlocker.state !== 'blocked' || blockedNavigationRef.current) return;
    blockedNavigationRef.current = true;
    void (async () => {
      await stopRef.current();
      if (activeSessionIdRef.current === null && !takeTransitionRef.current) {
        // A query/hash transition can preserve this page instance. Release the
        // first-intent capture before proceeding so later links remain usable.
        navigationIntentRef.current = false;
        navigationBlocker.proceed();
        return;
      }
      navigationIntentRef.current = false;
      navigationBlocker.reset();
    })().finally(() => {
      blockedNavigationRef.current = false;
    });
  }, [navigationBlocker]);

  // The router owns link and history transitions. This capture listener only
  // suppresses later same-origin link clicks while the first blocked link is
  // being finalized, preventing a second destination from replacing it.
  useEffect(() => {
    const onDocumentClick = (event: MouseEvent) => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const target = event.target;
      if (!(target instanceof Element)) return;
      const anchor = target.closest('a[href]');
      if (!(anchor instanceof HTMLAnchorElement) || anchor.target || anchor.hasAttribute('download')) return;
      const destination = new URL(anchor.href, window.location.href);
      if (destination.origin !== window.location.origin) return;
      const current = `${location.pathname}${location.search}${location.hash}`;
      const next = `${destination.pathname}${destination.search}${destination.hash}`;
      if (next === current || !hasTakeLifecycleToFinalize()) return;

      if (navigationIntentRef.current) {
        event.preventDefault();
        event.stopImmediatePropagation();
        return;
      }
      navigationIntentRef.current = true;
    };

    document.addEventListener('click', onDocumentClick, true);
    return () => {
      document.removeEventListener('click', onDocumentClick, true);
    };
  }, [location.hash, location.pathname, location.search]);

  // Navigation must use the same serialized stop path as the Stop control so
  // an active cloud or guest take is finalized exactly once before this route
  // releases its tuner/audio ownership.
  useEffect(() => () => {
    void stopRef.current();
  }, []);

  const setPracticeTool = (value: 'tuner' | 'drone') => {
    if (value === practiceTool) return;
    if (value === 'tuner') {
      setSearchParams({}, { replace: true });
      return;
    }

    const takeLifecycleActive = Boolean(
      takeTransitionRef.current
      || activeSessionIdRef.current !== null
      || recorderRef.current.activeSession
      || recorderRef.current.busy
      || recorderRef.current.recording
      || audioRecorderRef.current.status === 'recording'
      || audioRecorderRef.current.status === 'uploading',
    );
    if (!takeLifecycleActive) {
      streamRef.current?.stopMicrophone();
      setSearchParams({ tool: 'drone' }, { replace: true });
      return;
    }
    if (toolSwitchPromiseRef.current) return;

    const switchPromise = (async () => {
      await stop();
      // The hook's React state can still expose the just-closed session until
      // the next render. This ref is cleared only after recorder.stop()
      // succeeds, so it is the synchronous source of truth for this handoff.
      if (activeSessionIdRef.current !== null) return;
      streamRef.current?.stopMicrophone();
      setSearchParams({ tool: 'drone' }, { replace: true });
    })().finally(() => {
      if (toolSwitchPromiseRef.current === switchPromise) {
        toolSwitchPromiseRef.current = null;
      }
    });
    toolSwitchPromiseRef.current = switchPromise;
  };

  const setMode = (mode: 'mic' | 'demo') => {
    if (activeTake) return;
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
          onChange={setPracticeTool}
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
            recording={activeTake}
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
          {audioRecorder.pendingReason && (
            <div className="tuner-banner" role="status">
              {t(`audioUpload.${audioRecorder.pendingReason}` as import('../i18n/messages.base').MessageId)}
            </div>
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
