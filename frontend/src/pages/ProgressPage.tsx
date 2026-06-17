import { Award, CalendarDays, Clock, TrendingDown } from 'lucide-react';
import { useEffect, useState } from 'react';
import { getProgress } from '../api/client';
import { AccuracyLineChart, PracticeBarChart } from '../components/ProgressChart';
import { InsightCard, MetricTile, PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
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
    <ScreenContainer>
      <PageHeader
        eyebrow="Progress"
        title="Weekly pulse"
        description="Track whether the tuning work is getting steadier, not just whether one note looked good for a moment."
        meta={<StatusBadge tone="gold">{progress?.period?.current ?? 'Current period'}</StatusBadge>}
      />
      <div className="stats-grid">
        <MetricTile label="Current error" value={`${latestPoint?.avg_abs_cents.toFixed(1) ?? '0.0'}c`} detail="average deviation" icon={TrendingDown} tone="gold" />
        <MetricTile label="In tune" value={`${Math.round(latestPoint?.in_tune_percentage ?? 0)}%`} detail="recent period" icon={Award} tone="green" />
        <MetricTile label="Total practice" value={`${Math.round((progress?.total_practice_time_seconds ?? 0) / 60)} min`} detail={`${progress?.session_count ?? 0} sessions`} icon={Clock} />
        <MetricTile
          label="Consistency"
          value={progress?.consistency.practice_days_label ?? '0 of 7'}
          detail={`${progress?.consistency.practice_streak_days ?? 0} day streak`}
          icon={CalendarDays}
        />
      </div>
      <div className="two-column-grid">
        <SectionCard title="Average deviation" eyebrow="Trend">
          <AccuracyLineChart data={progress?.timeseries ?? []} />
        </SectionCard>
        <SectionCard title="Practice minutes" eyebrow="Volume">
          <PracticeBarChart data={progress?.timeseries ?? []} />
        </SectionCard>
      </div>
      <div className="insight-grid">
        <InsightCard
          title={improved?.note_label ?? 'Most improved note'}
          detail={improved ? `${improved.improvement.toFixed(1)} cents better` : 'More paired data needed'}
          body={improved ? `Previous average was ${improved.previous_avg_abs_cents.toFixed(1)} cents. Keep this as a confidence anchor.` : 'Record in both comparison periods to unlock improvement cards.'}
          icon={Award}
          tone="green"
        />
        <InsightCard
          title={issue?.note_label ?? 'Biggest current issue'}
          detail={issue ? `${issue.avg_abs_cents.toFixed(1)} cents avg abs` : 'No issue detected'}
          body={issue?.recommendation_summary ?? 'The next coach plan will use the highest severity note with enough data.'}
          icon={TrendingDown}
          tone="red"
        />
      </div>
    </ScreenContainer>
  );
}
