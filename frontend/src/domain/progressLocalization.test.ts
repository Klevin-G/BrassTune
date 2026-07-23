import { describe, expect, it } from 'vitest';
import type { NoteStats, PracticePlan, ProgressMetrics, Recommendation } from './types';
import {
  localizeProgressMetrics,
  localizeProgressNoteStats,
  localizeProgressPlan,
  localizeProgressRecommendations,
} from './progressLocalization';
import type { MessageId } from '../i18n/messages.base';

const localizer = {
  t: (id: MessageId, values?: Record<string, string | number>) => (
    values?.note ? `${id}:${values.note}` : id
  ),
  formatDate: () => '23 jul',
};

const note: NoteStats = {
  written_note: 'B',
  written_octave: 4,
  note_label: 'Bb4',
  avg_signed_cents: 8,
  avg_abs_cents: 8,
  median_cents: 8,
  stddev_cents: 2,
  in_tune_percentage: 72,
  duration_ms: 1000,
  duration_seconds: 1,
  sample_count: 20,
  event_count: 1,
  stability_score: 98,
  trend: 'Mostly sharp',
  severity: 'Backend English severity',
  problem_severity: 10,
  recommendation_summary: 'Backend English recommendation',
};

describe('progress response localization', () => {
  it('replaces backend prose deterministically while preserving note and numeric data', () => {
    const [localized] = localizeProgressNoteStats([note], localizer);
    expect(localized.note_label).toBe('Bb4');
    expect(localized.avg_signed_cents).toBe(8);
    expect(localized.trend).toBe('tuning.sharp');
    expect(localized.severity).toBe('playAlong.grade.good');
    expect(localized.recommendation_summary).toBe('progress.aimGreenBody');
  });

  it('localizes plans and recommendations without changing notes, minutes, or related-note identity', () => {
    const plan: PracticePlan = {
      title: 'Backend English plan',
      coach_message: 'Backend English coach',
      focus_notes: ['Bb4'],
      steps: [{ minutes: 4, label: 'Backend English label', detail: 'Backend English detail' }],
    };
    const recommendation: Recommendation = {
      title: 'Backend English title',
      message: 'Backend English message',
      severity: 'moderate',
      category: 'Backend English category',
      related_note: 'Bb4',
      suggested_exercises: ['Backend English exercise'],
      suggested_focus: 'Backend English focus',
      explanation: 'Backend English explanation',
    };

    const localizedPlan = localizeProgressPlan(plan, localizer);
    const [localizedRecommendation] = localizeProgressRecommendations([recommendation], localizer);
    expect(localizedPlan?.focus_notes).toEqual(['Bb4']);
    expect(localizedPlan?.steps[0].minutes).toBe(4);
    expect(localizedPlan?.title).toBe('progress.plan');
    expect(localizedPlan?.steps[0].label).toBe('warmup.long-tone.title');
    expect(localizedRecommendation.related_note).toBe('Bb4');
    expect(localizedRecommendation.title).toBe('progress.needsMostWork:Bb4');
    expect(localizedRecommendation.suggested_exercises).not.toContain('Backend English exercise');
  });

  it('localizes selected-locale dates, practice-day labels, and nested progress note rows', () => {
    const progress: ProgressMetrics = {
      user_id: 9,
      total_practice_time_seconds: 60,
      session_count: 1,
      average_session_length_seconds: 60,
      timeseries: [{ period: '2026-07-23', sessions: 1, practice_minutes: 1, avg_abs_cents: 8, in_tune_percentage: 72 }],
      consistency: {
        current_week_practice_days: 2,
        days_in_week: 7,
        practice_days_label: '2 of 7 practice days',
        practice_streak_days: 1,
      },
      most_improved_notes: [{ ...note, improvement: 3, previous_avg_abs_cents: 11 }],
      worst_notes: [note],
      most_consistently_sharp_notes: [note],
      most_consistently_flat_notes: [],
    };

    const localized = localizeProgressMetrics(progress, localizer);
    expect(localized.timeseries[0].period).toBe('23 jul');
    expect(localized.consistency.practice_days_label).toBe('guestInsights.practiceDays');
    expect(localized.most_improved_notes[0].note_label).toBe('Bb4');
    expect(localized.worst_notes[0].trend).toBe('tuning.sharp');
  });
});
