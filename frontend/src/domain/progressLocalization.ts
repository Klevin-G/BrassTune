import type { MessageId } from '../i18n/messages.base';
import type { NoteStats, PracticePlan, ProgressMetrics, Recommendation } from './types';

export interface ProgressLocalizer {
  t: (id: MessageId, values?: Record<string, string | number>) => string;
  formatDate: (value: Date | number | string, options?: Intl.DateTimeFormatOptions) => string;
}

function hasMeasuredPitch(row: NoteStats) {
  return row.has_data !== false && (row.sample_count > 0 || row.duration_ms > 0);
}

function localizedTrend(row: NoteStats, localizer: ProgressLocalizer) {
  if (!hasMeasuredPitch(row)) return localizer.t('progress.notTried');
  if (row.stddev_cents >= 12) return localizer.t('progress.wobbly');
  if (row.avg_signed_cents >= 5) return localizer.t('tuning.sharp');
  if (row.avg_signed_cents <= -5) return localizer.t('tuning.flat');
  return localizer.t('sessionReview.centered');
}

function localizedSeverity(row: NoteStats, localizer: ProgressLocalizer) {
  if (!hasMeasuredPitch(row)) return localizer.t('progress.notTried');
  if (row.in_tune_percentage >= 85) return localizer.t('playAlong.grade.excellent');
  if (row.in_tune_percentage >= 65) return localizer.t('playAlong.grade.good');
  if (row.in_tune_percentage >= 40) return localizer.t('playAlong.grade.close');
  return localizer.t('playAlong.grade.off');
}

export function localizeProgressNoteStats(rows: NoteStats[], localizer: ProgressLocalizer): NoteStats[] {
  return rows.map((row) => ({
    ...row,
    trend: localizedTrend(row, localizer),
    severity: localizedSeverity(row, localizer),
    recommendation_summary: hasMeasuredPitch(row)
      ? localizer.t('progress.aimGreenBody')
      : localizer.t('progress.notTriedBody'),
  }));
}

function localizedPlanStep(
  index: number,
  focusNotes: string[],
  localizer: ProgressLocalizer,
) {
  const focusNote = focusNotes[Math.min(index, Math.max(0, focusNotes.length - 1))] ?? '—';
  if (index === 0) {
    return {
      label: localizer.t('warmup.long-tone.title'),
      detail: localizer.t('warmup.long-tone.instruction'),
    };
  }
  if (index === 1) {
    return {
      label: localizer.t('progress.needsMostWork', { note: focusNote }),
      detail: localizer.t('progress.aimGreenBody'),
    };
  }
  if (index === 2) {
    return {
      label: localizer.t('transition.title'),
      detail: localizer.t('transition.noEvidence'),
    };
  }
  return {
    label: localizer.t('common.repeat'),
    detail: localizer.t('progress.moreForTrend'),
  };
}

export function localizeProgressPlan(plan: PracticePlan | null, localizer: ProgressLocalizer): PracticePlan | null {
  if (!plan) return null;
  return {
    ...plan,
    title: localizer.t('progress.plan'),
    coach_message: localizer.t('progress.aimGreenBody'),
    steps: plan.steps.map((step, index) => ({
      ...step,
      ...localizedPlanStep(index, plan.focus_notes, localizer),
    })),
  };
}

export function localizeProgressRecommendations(
  recommendations: Recommendation[],
  localizer: ProgressLocalizer,
): Recommendation[] {
  return recommendations.map((recommendation) => ({
    ...recommendation,
    title: localizer.t('progress.needsMostWork', { note: recommendation.related_note || '—' }),
    message: localizer.t('progress.aimGreenBody'),
    severity: localizer.t('playAlong.grade.close'),
    category: localizer.t('progress.recommended'),
    suggested_exercises: [
      localizer.t('warmup.long-tone.instruction'),
      localizer.t('packs.daily.drone.instruction'),
      localizer.t('progress.aimGreenBody'),
    ],
    suggested_focus: localizer.t('progress.aimGreenBody'),
    explanation: localizer.t('progress.aimGreenBody'),
  }));
}

function localizePeriod(value: string, localizer: ProgressLocalizer) {
  if (!/^\d{4}-\d{2}-\d{2}(?:T|$)/.test(value)) return value;
  const date = new Date(value.length === 10 ? `${value}T12:00:00` : value);
  if (Number.isNaN(date.getTime())) return value;
  return localizer.formatDate(date, { month: 'short', day: 'numeric' });
}

export function localizeProgressMetrics(
  progress: ProgressMetrics,
  localizer: ProgressLocalizer,
): ProgressMetrics {
  return {
    ...progress,
    timeseries: progress.timeseries.map((point) => ({
      ...point,
      period: localizePeriod(point.period, localizer),
    })),
    consistency: {
      ...progress.consistency,
      practice_days_label: localizer.t('guestInsights.practiceDays', {
        completed: progress.consistency.current_week_practice_days,
        total: progress.consistency.days_in_week,
      }),
    },
    most_improved_notes: localizeProgressNoteStats(progress.most_improved_notes, localizer) as ProgressMetrics['most_improved_notes'],
    worst_notes: localizeProgressNoteStats(progress.worst_notes, localizer),
    most_consistently_sharp_notes: localizeProgressNoteStats(progress.most_consistently_sharp_notes, localizer),
    most_consistently_flat_notes: localizeProgressNoteStats(progress.most_consistently_flat_notes, localizer),
  };
}
