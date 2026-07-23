import { ArrowLeft, ArrowRight, X } from 'lucide-react';
import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { PRACTICE_AUDIO_PAUSE_EVENT } from '../../domain/practiceLibrary';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { useI18n } from '../../i18n/LocaleContext';
import type { MessageId } from '../../i18n/messages.base';

const packNameMessages: Record<string, MessageId> = {
  'daily-foundations': 'packs.daily.name',
  'steady-time': 'packs.time.name',
};

const stepMessages: Record<string, [MessageId, MessageId]> = {
  'daily-foundations:guided-5': ['packs.daily.warmup.label', 'packs.daily.warmup.instruction'],
  'daily-foundations:concert-bb': ['packs.daily.drone.label', 'packs.daily.drone.instruction'],
  'daily-foundations:cmaj': ['packs.daily.scale.label', 'packs.daily.scale.instruction'],
  'steady-time:steady-80': ['packs.time.metronome.label', 'packs.time.metronome.instruction'],
  'steady-time:longtones': ['packs.time.longtones.label', 'packs.time.longtones.instruction'],
};

export function FocusedWorkspaceBar() {
  const navigate = useNavigate();
  const {
    workspace,
    moveWorkspace,
    addWorkspaceElapsed,
    completeWorkspaceStep,
    exitWorkspace,
  } = usePracticeLibrary();
  const { formatNumber, t } = useI18n();

  useEffect(() => {
    if (!workspace) return undefined;
    let timer: number | null = null;
    const stopTimer = () => {
      if (timer != null) window.clearInterval(timer);
      timer = null;
    };
    const startTimer = () => {
      stopTimer();
      if (!document.hidden) timer = window.setInterval(() => addWorkspaceElapsed(1), 1_000);
    };
    const pauseForBackground = () => {
      stopTimer();
      window.dispatchEvent(new Event(PRACTICE_AUDIO_PAUSE_EVENT));
    };
    const handleVisibility = () => {
      if (document.hidden) pauseForBackground();
      else startTimer();
    };
    const handlePageShow = () => startTimer();
    document.addEventListener('visibilitychange', handleVisibility);
    window.addEventListener('pagehide', pauseForBackground);
    window.addEventListener('pageshow', handlePageShow);
    startTimer();
    return () => {
      stopTimer();
      document.removeEventListener('visibilitychange', handleVisibility);
      window.removeEventListener('pagehide', pauseForBackground);
      window.removeEventListener('pageshow', handlePageShow);
    };
  }, [addWorkspaceElapsed, workspace?.pack.id, workspace?.stepIndex]);

  if (!workspace) return null;
  const step = workspace.pack.steps[workspace.stepIndex];
  const localizedStep = stepMessages[`${workspace.pack.id}:${step.id}`];
  const packName = packNameMessages[workspace.pack.id] ? t(packNameMessages[workspace.pack.id]) : workspace.pack.name;
  const stepLabel = localizedStep ? t(localizedStep[0]) : step.label;
  const stepInstruction = localizedStep ? t(localizedStep[1]) : step.instruction;
  const completed = workspace.completedStepIds.length;
  const currentCompleted = workspace.completedStepIds.includes(step.id);
  const elapsed = workspace.elapsedSecondsByStep[step.id] ?? 0;
  const progressLabel = t('workspace.progress', {
    elapsed: formatNumber(elapsed, { style: 'unit', unit: 'second', unitDisplay: 'short' }),
    completed: formatNumber(completed),
    total: formatNumber(workspace.pack.steps.length),
  });
  const go = (index: number) => {
    moveWorkspace(index);
    navigate(workspace.pack.steps[index].href);
  };
  return (
    <aside className="focus-workspace" aria-label={t('workspace.label')}>
      <div>
        <small>{t('workspace.step', { name: packName, current: formatNumber(workspace.stepIndex + 1), total: formatNumber(workspace.pack.steps.length) })}</small>
        <strong>{stepLabel}</strong>
        <span>{stepInstruction}</span>
        <span className="focus-workspace-progress" role="status">{progressLabel}</span>
        <progress aria-label={progressLabel} max={workspace.pack.steps.length} value={completed} />
      </div>
      <div className="focus-workspace-actions">
        <button className="ghost-button" type="button" disabled={workspace.stepIndex === 0} onClick={() => go(workspace.stepIndex - 1)} aria-label={t('workspace.previous')}><ArrowLeft size={17} /></button>
        {workspace.stepIndex === workspace.pack.steps.length - 1 ? (
          <button className="primary-button" type="button" disabled={currentCompleted} onClick={completeWorkspaceStep}>
            {t(currentCompleted ? 'workspace.completed' : 'workspace.complete')}
          </button>
        ) : (
          <button className="primary-button" type="button" onClick={() => go(workspace.stepIndex + 1)}>{t('workspace.next')} <ArrowRight size={17} /></button>
        )}
        <button className="ghost-button" type="button" onClick={exitWorkspace}><X size={17} /> {t('workspace.exit')}</button>
      </div>
    </aside>
  );
}
