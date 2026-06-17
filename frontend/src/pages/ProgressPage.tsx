import { Award, CalendarDays, Clock, TrendingDown } from 'lucide-react';
import { useEffect, useState } from 'react';
import { getProgress } from '../api/client';
import { AccuracyLineChart, PracticeBarChart } from '../components/ProgressChart';
import { StatCard } from '../components/StatCard';
import type { ProgressMetrics } from '../domain/types';
import { useAppSettings } from '../state/AppSettingsContext';

export function ProgressPage() {
  const { instrumentId } = useAppSettings();
  const [progress, setProgress] = useState<ProgressMetrics | null>(null);
  useEffect(() => {
    getProgress(instrumentId).then(setProgress);
  }, [instrumentId]);
  const latestPoint = progress?.timeseries[progress.timeseries.length - 1];
  const improved = progress?.most_improved_notes?.[0];
  const issue = progress?.worst_notes?.[0];
  return (
    <div className="page-grid">
      <div className="stats-grid">
        <StatCard label="This week" value={`${latestPoint?.avg_abs_cents.toFixed(1) ?? '0.0'}c`} detail="average error" icon={TrendingDown} />
        <StatCard label="In-tune" value={`${Math.round(latestPoint?.in_tune_percentage ?? 0)}%`} detail="recent period" icon={Award} />
        <StatCard label="Total practice" value={`${Math.round((progress?.total_practice_time_seconds ?? 0) / 60)} min`} detail={`${progress?.session_count ?? 0} sessions`} icon={Clock} />
        <StatCard label="Consistency" value={progress?.consistency.practice_days_label ?? '0 of 7 days practiced'} detail={`${progress?.consistency.practice_streak_days ?? 0} day streak`} icon={CalendarDays} />
      </div>
      <section className="panel wide">
        <h2>Average deviation over time</h2>
        <AccuracyLineChart data={progress?.timeseries ?? []} />
      </section>
      <section className="panel wide">
        <h2>Practice minutes</h2>
        <PracticeBarChart data={progress?.timeseries ?? []} />
      </section>
      <section className="panel">
        <h2>Most improved note</h2>
        <div className="spotlight-note">
          <strong>{improved?.note_label ?? '--'}</strong>
          <span>{improved ? `${improved.improvement.toFixed(1)} cents better` : 'More paired data needed'}</span>
        </div>
      </section>
      <section className="panel">
        <h2>Biggest current issue</h2>
        <div className="spotlight-note warning">
          <strong>{issue?.note_label ?? '--'}</strong>
          <span>{issue ? `${issue.avg_abs_cents.toFixed(1)} cents avg abs` : 'No issue detected'}</span>
        </div>
      </section>
    </div>
  );
}
