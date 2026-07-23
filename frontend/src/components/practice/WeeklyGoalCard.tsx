import { useState } from 'react';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';
import { useI18n } from '../../i18n/LocaleContext';

export function WeeklyGoalCard() {
  const { library, setWeeklyGoal } = usePracticeLibrary();
  const { t, formatDate, formatNumber } = useI18n();
  const goal = library.weeklyGoal;
  const [minutesDraft, setMinutesDraft] = useState(goal.targetMinutes);
  const [sessionsDraft, setSessionsDraft] = useState(goal.targetSessions);
  const percent = Math.min(100, Math.round((goal.completedMinutes / goal.targetMinutes) * 100));
  return (
    <SectionCard title={t('weekly.title')} eyebrow={t('weekly.weekOf', { date: formatDate(new Date(`${goal.week}T00:00:00`), { dateStyle: 'medium' }) })}>
      <div className="practice-feature-stack">
        <p className="practice-lead"><strong>{t('weekly.summary', { completedMinutes: formatNumber(goal.completedMinutes), targetMinutes: formatNumber(goal.targetMinutes), completedSessions: formatNumber(goal.completedSessions), targetSessions: formatNumber(goal.targetSessions), percent: formatNumber(percent) })}</strong></p>
        <progress max={goal.targetMinutes} value={Math.min(goal.completedMinutes, goal.targetMinutes)} aria-label={t('weekly.progress', { completed: formatNumber(goal.completedMinutes), target: formatNumber(goal.targetMinutes) })} />
        <form className="practice-inline-form" onSubmit={(event) => { event.preventDefault(); setWeeklyGoal(minutesDraft, sessionsDraft); }}>
          <label className="field"><span>{t('weekly.minutes')}</span><input type="number" min={5} max={600} value={minutesDraft} onChange={(event) => setMinutesDraft(Number(event.target.value))} /></label>
          <label className="field"><span>{t('weekly.sessions')}</span><input type="number" min={1} max={21} value={sessionsDraft} onChange={(event) => setSessionsDraft(Number(event.target.value))} /></label>
          <button className="ghost-button" type="submit">{t('weekly.save')}</button>
        </form>
      </div>
    </SectionCard>
  );
}
