import { Pause, Play, RotateCcw } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { GUIDED_WARMUP_SECONDS, GUIDED_WARMUP_STEPS, warmupStepAt } from '../../domain/warmup';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';
import { useI18n } from '../../i18n/LocaleContext';
import type { MessageId } from '../../i18n/messages.base';

const GUIDED_WARMUP_MILLISECONDS = GUIDED_WARMUP_SECONDS * 1000;

export interface WarmupTimerState {
  elapsedMilliseconds: number;
  running: boolean;
  visible: boolean;
  activeSinceMilliseconds: number | null;
}

export type WarmupTimerEvent =
  | { type: 'start'; visible: boolean }
  | { type: 'pause' }
  | { type: 'reset' }
  | { type: 'visibility'; visible: boolean }
  | { type: 'tick' };

export function updateWarmupTimer(
  state: WarmupTimerState,
  event: WarmupTimerEvent,
  nowMilliseconds: number,
): WarmupTimerState {
  const segmentMilliseconds = state.activeSinceMilliseconds == null
    ? 0
    : Math.max(0, nowMilliseconds - state.activeSinceMilliseconds);
  let elapsedMilliseconds = Math.min(
    GUIDED_WARMUP_MILLISECONDS,
    state.elapsedMilliseconds + segmentMilliseconds,
  );
  let running = state.running;
  let visible = state.visible;

  if (event.type === 'start') {
    if (elapsedMilliseconds >= GUIDED_WARMUP_MILLISECONDS) elapsedMilliseconds = 0;
    running = true;
    visible = event.visible;
  } else if (event.type === 'pause') {
    running = false;
  } else if (event.type === 'reset') {
    elapsedMilliseconds = 0;
    running = false;
  } else if (event.type === 'visibility') {
    visible = event.visible;
  }

  if (elapsedMilliseconds >= GUIDED_WARMUP_MILLISECONDS) running = false;
  const next = {
    elapsedMilliseconds,
    running,
    visible,
    activeSinceMilliseconds: running && visible ? nowMilliseconds : null,
  };
  return next.elapsedMilliseconds === state.elapsedMilliseconds
    && next.running === state.running
    && next.visible === state.visible
    && next.activeSinceMilliseconds === state.activeSinceMilliseconds
    ? state
    : next;
}

const systemWarmupClock = () => Date.now();

export function GuidedWarmupPanel({ nowMilliseconds = systemWarmupClock }: { nowMilliseconds?: () => number } = {}) {
  const { library, setWarmupProgress, recordRecent, recordActivity } = usePracticeLibrary();
  const { t, formatNumber } = useI18n();
  const initialElapsedSeconds = Math.max(0, Math.min(GUIDED_WARMUP_SECONDS, Math.floor(library.warmup.elapsedSeconds)));
  const initialStepIndex = warmupStepAt(initialElapsedSeconds).index;
  const timerRef = useRef<WarmupTimerState>({
    elapsedMilliseconds: initialElapsedSeconds * 1000,
    running: false,
    visible: typeof document === 'undefined' || !document.hidden,
    activeSinceMilliseconds: null,
  });
  const [timer, setTimer] = useState<WarmupTimerState>(timerRef.current);
  const elapsed = Math.floor(timer.elapsedMilliseconds / 1000);
  const running = timer.running;
  const completionRecordedRef = useRef(elapsed >= GUIDED_WARMUP_SECONDS);
  const persistedProgressRef = useRef({ elapsedSeconds: initialElapsedSeconds, stepIndex: initialStepIndex });
  const position = warmupStepAt(elapsed);
  const step = GUIDED_WARMUP_STEPS[position.index];
  const complete = elapsed >= GUIDED_WARMUP_SECONDS;

  const transitionTimer = useCallback((event: WarmupTimerEvent) => {
    const current = timerRef.current;
    if (!current.running && event.type === 'visibility') return;
    const next = updateWarmupTimer(current, event, nowMilliseconds());
    if (next === current) return;
    timerRef.current = next;
    setTimer(next);
  }, [nowMilliseconds]);

  useEffect(() => {
    if (!running || !timer.visible) return undefined;
    const intervalId = window.setInterval(() => {
      transitionTimer({ type: 'tick' });
    }, 1000);
    return () => window.clearInterval(intervalId);
  }, [running, timer.visible, transitionTimer]);

  useEffect(() => {
    const handleVisibility = () => transitionTimer({ type: 'visibility', visible: !document.hidden });
    const handlePageHide = () => transitionTimer({ type: 'visibility', visible: false });
    const handlePageShow = () => transitionTimer({ type: 'visibility', visible: !document.hidden });
    document.addEventListener('visibilitychange', handleVisibility);
    window.addEventListener('pagehide', handlePageHide);
    window.addEventListener('pageshow', handlePageShow);
    return () => {
      document.removeEventListener('visibilitychange', handleVisibility);
      window.removeEventListener('pagehide', handlePageHide);
      window.removeEventListener('pageshow', handlePageShow);
    };
  }, [transitionTimer]);

  useEffect(() => {
    if (
      persistedProgressRef.current.elapsedSeconds !== elapsed
      || persistedProgressRef.current.stepIndex !== position.index
    ) {
      persistedProgressRef.current = { elapsedSeconds: elapsed, stepIndex: position.index };
      setWarmupProgress({ elapsedSeconds: elapsed, stepIndex: position.index });
    }
    if (elapsed >= GUIDED_WARMUP_SECONDS) {
      if (!completionRecordedRef.current) {
        completionRecordedRef.current = true;
        recordActivity(5, { kind: 'warmup', id: 'guided-5' });
      }
    }
  }, [elapsed, position.index, recordActivity, setWarmupProgress]);

  const start = () => {
    if (complete) {
      completionRecordedRef.current = false;
    }
    recordRecent({ kind: 'warmup', id: 'guided-5', label: '5-minute warm-up', href: '/practice#warmup' });
    transitionTimer({ type: 'start', visible: !document.hidden });
  };

  const reset = () => {
    completionRecordedRef.current = false;
    transitionTimer({ type: 'reset' });
  };

  const remaining = Math.max(0, GUIDED_WARMUP_SECONDS - elapsed);
  return (
    <SectionCard title={t('warmup.title')} eyebrow={t('warmup.eyebrow')} action={<span className="practice-time">{formatNumber(Math.floor(remaining / 60), { minimumIntegerDigits: 1 })}:{formatNumber(remaining % 60, { minimumIntegerDigits: 2, useGrouping: false })}</span>}>
      <div id="warmup" className="practice-feature-stack">
        <p className="practice-lead"><strong>{complete ? t('warmup.complete') : `${formatNumber(position.index + 1)}. ${t(`warmup.${step.id}.title` as MessageId)}`}</strong></p>
        <p>{complete ? t('warmup.completeBody') : t(`warmup.${step.id}.instruction` as MessageId)}</p>
        <progress max={GUIDED_WARMUP_SECONDS} value={elapsed} aria-label={t('warmup.progress', { elapsed, total: GUIDED_WARMUP_SECONDS })} />
        <div className="practice-actions">
          <button
            className="primary-button"
            type="button"
            onClick={running
              ? () => {
                transitionTimer({ type: 'pause' });
              }
              : start}
          >
            {running ? <Pause size={18} /> : <Play size={18} />}
            {running ? t('common.pause') : elapsed > 0 && !complete ? t('common.resume') : complete ? t('common.repeat') : t('warmup.start')}
          </button>
          {elapsed > 0 && <button className="ghost-button" type="button" onClick={reset}><RotateCcw size={17} />{t('common.reset')}</button>}
        </div>
      </div>
    </SectionCard>
  );
}
