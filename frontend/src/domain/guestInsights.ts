import {
  GUEST_WORKSPACE_ACCESS,
  buildGuestRecommendations as buildRecommendationsFromStats,
  calculateGuestNoteStats,
  listGuestSessions,
  type GuestSessionDetail,
} from './guestSessions';
import { noteLabelToMidi, midiToNote } from './music';
import type { NoteStats, PracticePlan, ProgressMetrics, Recommendation } from './types';
import type { MessageId } from '../i18n/messages.base';

export interface GuestInsightRange {
  date_from?: string;
  date_to?: string;
}

export interface GuestInsightLocalizer {
  t: (id: MessageId, values?: Record<string, string | number>) => string;
  formatDate: (value: Date | number | string, options?: Intl.DateTimeFormatOptions) => string;
}

const guestHeatmapRanges: Record<string, readonly [string, string]> = {
  trumpet: ['F#3', 'C6'],
  horn: ['F3', 'C6'],
  trombone: ['E2', 'Bb4'],
  euphonium: ['E2', 'Bb4'],
  baritone: ['E3', 'Bb5'],
  'euphonium-treble': ['E3', 'Bb5'],
  tuba: ['D1', 'F4'],
};

function noteLabelsInRange([start, end]: readonly [string, string]) {
  const startMidi = noteLabelToMidi(start);
  const endMidi = noteLabelToMidi(end);
  return Array.from({ length: endMidi - startMidi + 1 }, (_, index) => {
    const note = midiToNote(startMidi + index);
    return `${note.note}${note.octave}`;
  });
}

function inRange(session: GuestSessionDetail, range?: GuestInsightRange) {
  const started = new Date(session.started_at).getTime();
  if (range?.date_from && started < new Date(`${range.date_from}T00:00:00.000`).getTime()) return false;
  if (range?.date_to && started > new Date(`${range.date_to}T23:59:59.999`).getTime()) return false;
  return true;
}

function sessionsForInstrument(instrumentId: string, range?: GuestInsightRange) {
  return listGuestSessions(GUEST_WORKSPACE_ACCESS).filter((session) => session.instrument_id === instrumentId && inRange(session, range));
}

function localizeGuestNoteStats(row: NoteStats, localizer: GuestInsightLocalizer): NoteStats {
  const trendId = row.trend === 'Unstable'
    ? 'progress.wobbly'
    : row.trend === 'Mostly sharp'
      ? 'tuning.sharp'
      : row.trend === 'Mostly flat'
        ? 'tuning.flat'
        : 'sessionReview.centered';
  const severityId = row.severity === 'excellent'
    ? 'playAlong.grade.excellent'
    : row.severity === 'good'
      ? 'playAlong.grade.good'
      : row.severity === 'moderate issue'
        ? 'playAlong.grade.close'
        : 'playAlong.grade.off';
  const trend = localizer.t(trendId);
  return {
    ...row,
    trend,
    severity: localizer.t(severityId),
    recommendation_summary: trend,
  };
}

export function buildGuestNoteStats(instrumentId: string, range?: GuestInsightRange, localizer?: GuestInsightLocalizer): NoteStats[] {
  const stats = calculateGuestNoteStats(sessionsForInstrument(instrumentId, range).flatMap((session) => session.note_events));
  return localizer ? stats.map((row) => localizeGuestNoteStats(row, localizer)) : stats;
}

function emptyHeatmapRow(instrumentId: string, label: string, localizer?: GuestInsightLocalizer): NoteStats {
  const midi = noteLabelToMidi(label);
  const written = midiToNote(midi);
  return {
    written_note: written.note,
    written_octave: written.octave,
    note_label: label,
    avg_signed_cents: 0,
    avg_abs_cents: 0,
    median_cents: 0,
    stddev_cents: 0,
    in_tune_percentage: 0,
    duration_ms: 0,
    duration_seconds: 0,
    sample_count: 0,
    event_count: 0,
    stability_score: 0,
    trend: 'unmeasured',
    severity: 'insufficient',
    problem_severity: 0,
    has_data: false,
    severity_color: 'insufficient',
    recommendation_summary: localizer
      ? localizer.t('progress.notTriedBody')
      : `No guest ${instrumentId} data recorded for ${label} in this browser yet.`,
  };
}

export function buildGuestHeatmap(instrumentId: string, stats: NoteStats[], localizer?: GuestInsightLocalizer): NoteStats[] {
  const range = guestHeatmapRanges[instrumentId] ?? guestHeatmapRanges.trumpet;
  const startMidi = noteLabelToMidi(range[0]);
  const endMidi = noteLabelToMidi(range[1]);
  const byMidi = new Map<number, NoteStats>();
  for (const row of stats) {
    const midi = noteLabelToMidi(row.note_label);
    if (!Number.isInteger(midi)) continue;
    const current = byMidi.get(midi);
    if (!current || row.sample_count > current.sample_count) byMidi.set(midi, row);
  }
  const midiValues = Array.from(
    { length: endMidi - startMidi + 1 },
    (_, index) => startMidi + index,
  );
  // Older local takes may contain a valid note outside a profile's current
  // written range. Keep that observation visible instead of silently dropping it.
  for (const midi of byMidi.keys()) {
    if (midi < startMidi || midi > endMidi) midiValues.push(midi);
  }
  midiValues.sort((left, right) => left - right);
  return midiValues.map((midi) => {
    const note = midiToNote(midi);
    const label = `${note.note}${note.octave}`;
    const observed = byMidi.get(midi);
    return observed
      ? {
          ...observed,
          written_note: note.note,
          written_octave: note.octave,
          note_label: label,
        }
      : emptyHeatmapRow(instrumentId, label, localizer);
  });
}

export function buildGuestRecommendations(stats: NoteStats[], localizer?: GuestInsightLocalizer): Recommendation[] {
  if (!localizer) return buildRecommendationsFromStats(stats, 8);
  return [...stats]
    .sort((left, right) => right.problem_severity - left.problem_severity)
    .slice(0, 8)
    .map((row) => ({
      title: localizer.t('progress.needsMostWork', { note: row.note_label }),
      message: localizer.t('progress.aimGreenBody'),
      severity: row.severity,
      category: localizer.t('progress.recommended'),
      related_note: row.note_label,
      suggested_exercises: [
        localizer.t('warmup.long-tone.instruction'),
        localizer.t('packs.daily.drone.instruction'),
        localizer.t('progress.aimGreenBody'),
      ],
      suggested_focus: row.trend,
      explanation: localizer.t('progress.aimGreenBody'),
    }));
}

export function buildGuestPracticePlan(stats: NoteStats[], instrumentId: string, localizer?: GuestInsightLocalizer): PracticePlan | null {
  const focus = [...stats].sort((left, right) => right.problem_severity - left.problem_severity).slice(0, 2);
  if (!focus.length) return null;
  return {
    title: localizer?.t('progress.plan') ?? 'Guest intonation plan',
    focus_notes: focus.map((row) => row.note_label),
    coach_message: localizer?.t('progress.planEmpty')
      ?? `Use the local ${instrumentId} takes saved in this browser to center one or two notes before widening the range.`,
    steps: [
      { minutes: 2, label: localizer?.t('warmup.long-tone.title') ?? 'Anchor', detail: localizer?.t('warmup.long-tone.instruction') ?? 'Play an easy centered note and match the same air speed on every entrance.' },
      { minutes: 4, label: localizer?.t('progress.needsMostWork', { note: focus[0].note_label }) ?? `Isolate ${focus[0].note_label}`, detail: localizer?.t('progress.aimGreenBody') ?? 'Repeat the highest-priority guest note slowly.' },
      { minutes: 3, label: localizer?.t('transition.title') ?? 'Transfer', detail: localizer?.t('transition.noEvidence') ?? 'Move between the anchor and focus note without changing volume or pressure.' },
      { minutes: 1, label: localizer?.t('common.repeat') ?? 'Check', detail: localizer?.t('progress.moreForTrend') ?? 'Record another guest take and compare the average absolute cents.' },
    ],
  };
}

function startOfDay(value: Date) {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

function practiceStreakDays(sessions: GuestSessionDetail[]) {
  const days = new Set(sessions.map((session) => startOfDay(new Date(session.started_at)).getTime()));
  let streak = 0;
  const cursor = startOfDay(new Date());
  while (days.has(cursor.getTime())) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}

export function buildGuestProgress(instrumentId: string, stats: NoteStats[], range?: GuestInsightRange, localizer?: GuestInsightLocalizer): ProgressMetrics {
  const sessions = sessionsForInstrument(instrumentId, range);
  const sorted = [...sessions].sort((a, b) => new Date(a.started_at).getTime() - new Date(b.started_at).getTime());
  const currentWeekStart = startOfDay(new Date());
  currentWeekStart.setDate(currentWeekStart.getDate() - 6);
  const currentWeekDays = new Set(
    sorted
      .filter((session) => new Date(session.started_at) >= currentWeekStart)
      .map((session) => startOfDay(new Date(session.started_at)).getTime()),
  );
  const timeseries = sorted.slice(-8).map((session) => ({
    period: localizer
      ? localizer.formatDate(session.started_at, { month: 'short', day: 'numeric' })
      : new Date(session.started_at).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }),
    sessions: 1,
    practice_minutes: Number((session.duration_seconds / 60).toFixed(1)),
    avg_abs_cents: session.average_abs_cents,
    in_tune_percentage: session.in_tune_percentage,
  }));

  const midpoint = Math.floor(sorted.length / 2);
  const previousStats = aggregateSessionStats(sorted.slice(0, midpoint));
  const currentStats = aggregateSessionStats(sorted.slice(midpoint));
  const mostImproved: Array<NoteStats & { improvement: number; previous_avg_abs_cents: number }> = currentStats
    .flatMap((row) => {
    const previous = previousStats.find((old) => old.note_label === row.note_label);
    if (!previous) return [];
    if (row.duration_seconds < 3 || previous.duration_seconds < 3) return [];
      const improvement = previous.avg_abs_cents - row.avg_abs_cents;
      return improvement > 0 ? [{ ...row, improvement, previous_avg_abs_cents: previous.avg_abs_cents }] : [];
    })
    .sort((a, b) => b.improvement - a.improvement);

  const totalPractice = sorted.reduce((sum, session) => sum + session.duration_seconds, 0);
  return {
    user_id: 0,
    total_practice_time_seconds: totalPractice,
    session_count: sorted.length,
    average_session_length_seconds: sorted.length ? totalPractice / sorted.length : 0,
    timeseries,
    consistency: {
      current_week_practice_days: currentWeekDays.size,
      days_in_week: 7,
      practice_days_label: localizer
        ? localizer.t('guestInsights.practiceDays', { completed: currentWeekDays.size, total: 7 })
        : `${currentWeekDays.size} of 7`,
      practice_streak_days: practiceStreakDays(sorted),
    },
    most_improved_notes: mostImproved,
    worst_notes: [...stats].sort((left, right) => right.avg_abs_cents - left.avg_abs_cents).slice(0, 5),
    most_consistently_sharp_notes: [...stats].filter((row) => row.avg_signed_cents > 0).sort((a, b) => b.avg_signed_cents - a.avg_signed_cents).slice(0, 5),
    most_consistently_flat_notes: [...stats].filter((row) => row.avg_signed_cents < 0).sort((a, b) => a.avg_signed_cents - b.avg_signed_cents).slice(0, 5),
    period: { current: localizer?.t('nav.guest') ?? 'Guest browser data' },
  };
}

function aggregateSessionStats(sessions: GuestSessionDetail[]) {
  return calculateGuestNoteStats(sessions.flatMap((session) => session.note_events));
}
