import { useState } from 'react';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';

export function WeeklyGoalCard() {
  const { library, setWeeklyGoal } = usePracticeLibrary();
  const goal = library.weeklyGoal;
  const [draft, setDraft] = useState(goal.targetMinutes);
  const percent = Math.min(100, Math.round((goal.completedMinutes / goal.targetMinutes) * 100));
  return (
    <SectionCard title="Weekly practice goal" eyebrow={`Week of ${goal.week}`}>
      <div className="practice-feature-stack">
        <p className="practice-lead"><strong>{goal.completedMinutes} of {goal.targetMinutes} minutes</strong> · {percent}%</p>
        <progress max={goal.targetMinutes} value={Math.min(goal.completedMinutes, goal.targetMinutes)} aria-label={`${goal.completedMinutes} of ${goal.targetMinutes} weekly practice minutes`} />
        <form className="practice-inline-form" onSubmit={(event) => { event.preventDefault(); setWeeklyGoal(draft); }}>
          <label className="field"><span>Goal in minutes</span><input type="number" min={5} max={600} value={draft} onChange={(event) => setDraft(Number(event.target.value))} /></label>
          <button className="ghost-button" type="submit">Save goal</button>
        </form>
      </div>
    </SectionCard>
  );
}
