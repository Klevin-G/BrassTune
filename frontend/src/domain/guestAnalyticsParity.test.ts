import { describe, expect, it } from 'vitest';
import segmentationCases from '../../../fixtures/note_segmentation_cases.json';
import recommendationCases from '../../../fixtures/recommendation_cases.json';
import problemScoreRoundingCases from '../../../fixtures/problem_score_rounding_cases.json';
import {
  buildGuestNoteEvents,
  calculateGuestNoteStats,
  classifyGuestNoteTrend,
  generateGuestNoteRecommendation,
  guestProblemScore,
} from './guestSessions';
import type { NoteEvent, NoteStats, PitchFrame } from './types';

function fixtureFrame(item: (typeof segmentationCases)[number]['frames'][number]): PitchFrame {
  const valid = 'is_valid_for_recording' in item ? item.is_valid_for_recording !== false : true;
  return {
    timestamp_ms: item.timestamp_ms,
    frequency_hz: valid ? 440 : null,
    confidence: valid ? 0.99 : 0.1,
    rms: 0.1,
    midi_note_float: valid ? 69 : null,
    nearest_midi: valid ? 69 : null,
    concert_note_name: item.concert_note_name,
    concert_octave: item.concert_octave,
    written_note_name: item.written_note_name,
    written_octave: item.written_octave,
    cents_deviation: item.cents_deviation,
    tuning_status: item.tuning_status as PitchFrame['tuning_status'],
    instrument_id: 'trumpet',
    reference_pitch_hz: 440,
    is_valid_for_recording: valid,
  };
}

function recommendationStats(input: Record<string, number | string | undefined>): NoteStats {
  const noteLabel = String(input.note_label);
  return {
    written_note: noteLabel.replace(/-?\d+$/, ''),
    written_octave: Number(noteLabel.match(/-?\d+$/)?.[0] ?? 4),
    note_label: noteLabel,
    avg_signed_cents: Number(input.avg_signed_cents ?? 0),
    avg_abs_cents: Number(input.avg_abs_cents ?? 0),
    median_cents: Number(input.avg_signed_cents ?? 0),
    stddev_cents: Number(input.stddev_cents ?? 0),
    in_tune_percentage: Number(input.in_tune_percentage ?? 0),
    duration_ms: Number(input.duration_seconds ?? 0) * 1000,
    duration_seconds: Number(input.duration_seconds ?? 0),
    sample_count: 20,
    event_count: 1,
    stability_score: Number(input.stability_score ?? 100),
    trend: '',
    severity: '',
    problem_severity: Number(input.avg_abs_cents ?? 0),
  };
}

function analyticsEvent(
  id: number,
  durationMs: number,
  averageSignedCents: number,
  averageAbsoluteCents = Math.abs(averageSignedCents),
): NoteEvent {
  return {
    id,
    session_id: -7,
    instrument_id: 'trumpet',
    written_note: 'D',
    written_octave: 4,
    note_label: 'D4',
    concert_note: 'C',
    concert_octave: 4,
    started_at_ms: 0,
    ended_at_ms: Math.max(0, durationMs),
    duration_ms: durationMs,
    duration_seconds: durationMs / 1_000,
    sample_count: 10,
    avg_signed_cents: averageSignedCents,
    avg_abs_cents: averageAbsoluteCents,
    median_cents: averageSignedCents,
    stddev_cents: 2,
    min_cents: averageSignedCents,
    max_cents: averageSignedCents,
    in_tune_percentage: 70,
    stability_score: 90,
    created_at: '2026-07-23T00:00:00.000Z',
  };
}

describe('guest/backend fixture parity', () => {
  it('matches backend segmentation duration, median, dropout, and stability values', () => {
    for (const testCase of segmentationCases) {
      const events = buildGuestNoteEvents(-42, testCase.frames.map(fixtureFrame));
      expect(events, testCase.name).toHaveLength(testCase.expected_events.length);
      events.forEach((event, index) => {
        const expected = testCase.expected_events[index];
        expect(event.written_note, testCase.name).toBe(expected.written_note);
        expect(event.written_octave, testCase.name).toBe(expected.written_octave);
        expect(event.duration_ms, testCase.name).toBe(expected.duration_ms);
        expect(event.sample_count, testCase.name).toBe(expected.sample_count);
        expect(event.avg_signed_cents, testCase.name).toBeCloseTo(expected.avg_signed_cents, 9);
        expect(event.median_cents, testCase.name).toBeCloseTo(expected.median_cents, 9);
        expect(event.stddev_cents, testCase.name).toBeCloseTo(expected.stddev_cents, 9);
        expect(event.in_tune_percentage, testCase.name).toBeCloseTo(expected.in_tune_percentage, 9);
        expect(event.stability_score, testCase.name).toBeCloseTo(expected.stability_score, 9);
      });
    }
  });

  it('matches backend recommendation categories and rejects unstable-centered fallthrough', () => {
    for (const testCase of recommendationCases) {
      const recommendation = generateGuestNoteRecommendation(recommendationStats(testCase.note_stats));
      expect(recommendation.category, testCase.name).toBe(testCase.expected_category);
      expect(recommendation.related_note, testCase.name).toBe(testCase.expected_related_note);
      if (testCase.expected_category === 'Inconsistent pitch') {
        expect(recommendation.message.toLowerCase(), testCase.name).not.toContain('is generally centered');
      }
    }
  });

  it.each([
    { cents: -5.01, trend: 'Mostly flat', category: 'Flat tendency' },
    { cents: -5, trend: 'Centered', category: 'Good progress' },
    { cents: 5, trend: 'Centered', category: 'Good progress' },
    { cents: 5.01, trend: 'Mostly sharp', category: 'Sharp tendency' },
  ])('uses the backend inclusive ±5 centered boundary at $cents cents', ({ cents, trend, category }) => {
    const stats = recommendationStats({
      note_label: 'D4',
      avg_signed_cents: cents,
      avg_abs_cents: Math.abs(cents),
      stddev_cents: 2,
      in_tune_percentage: 70,
      stability_score: 90,
      duration_seconds: 10,
    });
    expect(classifyGuestNoteTrend(stats)).toBe(trend);
    expect(generateGuestNoteRecommendation(stats).category).toBe(category);
  });

  it('duration-weights aggregate centers, medians, and population deviation', () => {
    const events = buildGuestNoteEvents(-7, [
      ...Array.from({ length: 11 }, (_, index) => fixtureFrame({
        timestamp_ms: index * 100,
        written_note_name: 'D', written_octave: 4, concert_note_name: 'C', concert_octave: 4,
        cents_deviation: 12, tuning_status: 'sharp',
      })),
      ...Array.from({ length: 31 }, (_, index) => fixtureFrame({
        timestamp_ms: 2_000 + index * 100,
        written_note_name: 'D', written_octave: 4, concert_note_name: 'C', concert_octave: 4,
        cents_deviation: 0, tuning_status: 'in_tune',
      })),
    ]);
    const stats = calculateGuestNoteStats(events)[0];
    expect(events).toHaveLength(2);
    expect(stats.avg_signed_cents).toBeCloseTo(22 / 7, 9);
    expect(stats.median_cents).toBe(0);
    expect(stats.stddev_cents).toBeCloseTo(
      Math.sqrt((1_100 * (12 - 22 / 7) ** 2 + 3_100 * (22 / 7) ** 2) / 4_200),
      9,
    );
    expect(stats.duration_ms).toBe(4_200);
  });

  it('excludes nonpositive legacy durations from mixed weighted aggregates', () => {
    const stats = calculateGuestNoteStats([
      analyticsEvent(1, 4_000, 5.01),
      analyticsEvent(2, 0, 100),
      analyticsEvent(3, -1_000, -100),
    ])[0];

    expect(stats.avg_signed_cents).toBeCloseTo(5.01, 9);
    expect(stats.avg_abs_cents).toBeCloseTo(5.01, 9);
    expect(stats.median_cents).toBeCloseTo(5.01, 9);
    expect(stats.stddev_cents).toBe(0);
    expect(stats.in_tune_percentage).toBe(70);
    expect(stats.stability_score).toBe(90);
    expect(stats.duration_ms).toBe(4_000);
  });

  it('preserves the backend even-mean fallback when every duration is legacy', () => {
    const stats = calculateGuestNoteStats([
      analyticsEvent(1, 0, 4),
      analyticsEvent(2, -1_000, 10),
    ])[0];

    expect(stats.avg_signed_cents).toBe(7);
    expect(stats.avg_abs_cents).toBe(7);
    expect(stats.median_cents).toBe(7);
    expect(stats.stddev_cents).toBe(3);
    expect(stats.duration_ms).toBe(0);
  });

  it('rounds nonnegative problem severity half up at two decimals', () => {
    for (const testCase of problemScoreRoundingCases) {
      expect(guestProblemScore(testCase.note_stats), testCase.name)
        .toBe(testCase.expected_problem_severity);
    }
  });
});
