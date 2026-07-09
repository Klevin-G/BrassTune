import { listGuestSessions, type GuestSessionDetail } from './guestSessions';
import { noteLabelToMidi, midiToNote } from './music';
import type { NoteStats, PracticePlan, ProgressMetrics, Recommendation } from './types';

export interface GuestInsightRange {
  date_from?: string;
  date_to?: string;
}

const guestHeatmapNotes: Record<string, string[]> = {
  trumpet: ['F#4', 'G4', 'Ab4', 'A4', 'Bb4', 'B4', 'C5', 'C#5', 'D5', 'Eb5', 'E5', 'F5'],
  horn: ['F4', 'F#4', 'G4', 'Ab4', 'A4', 'Bb4', 'B4', 'C5', 'C#5', 'D5', 'Eb5', 'E5'],
  trombone: ['Bb2', 'C3', 'D3', 'Eb3', 'F3', 'G3', 'Ab3', 'Bb3', 'C4', 'D4', 'F4'],
  euphonium: ['Bb2', 'C3', 'D3', 'Eb3', 'F3', 'G3', 'Bb3', 'C4', 'D4', 'F4'],
  tuba: ['Bb1', 'F2', 'Bb2', 'C3', 'D3', 'Eb3', 'F3', 'G3'],
};

function average(values: number[]) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
}

function severityFor(avgAbs: number): { severity: string; color: NoteStats['severity_color'] } {
  if (avgAbs >= 16) return { severity: 'red', color: 'red' };
  if (avgAbs >= 11) return { severity: 'orange', color: 'orange' };
  if (avgAbs >= 7) return { severity: 'yellow', color: 'yellow' };
  return { severity: 'green', color: 'green' };
}

function inRange(session: GuestSessionDetail, range?: GuestInsightRange) {
  const started = new Date(session.started_at).getTime();
  if (range?.date_from && started < new Date(`${range.date_from}T00:00:00.000`).getTime()) return false;
  if (range?.date_to && started > new Date(`${range.date_to}T23:59:59.999`).getTime()) return false;
  return true;
}

function sessionsForInstrument(instrumentId: string, range?: GuestInsightRange) {
  return listGuestSessions().filter((session) => session.instrument_id === instrumentId && inRange(session, range));
}

export function buildGuestNoteStats(instrumentId: string, range?: GuestInsightRange): NoteStats[] {
  const groups = new Map<string, NoteStats[]>();
  sessionsForInstrument(instrumentId, range).forEach((session) => {
    session.note_stats.forEach((row) => {
      groups.set(row.note_label, [...(groups.get(row.note_label) ?? []), row]);
    });
  });

  return [...groups.values()]
    .map((rows) => {
      const first = rows[0];
      const eventCount = rows.reduce((sum, row) => sum + row.event_count, 0);
      const sampleCount = rows.reduce((sum, row) => sum + row.sample_count, 0);
      const durationMs = rows.reduce((sum, row) => sum + row.duration_ms, 0);
      const avgAbs = average(rows.map((row) => row.avg_abs_cents));
      const severity = severityFor(avgAbs);
      return {
        ...first,
        avg_signed_cents: average(rows.map((row) => row.avg_signed_cents)),
        avg_abs_cents: avgAbs,
        median_cents: average(rows.map((row) => row.median_cents)),
        stddev_cents: average(rows.map((row) => row.stddev_cents)),
        in_tune_percentage: average(rows.map((row) => row.in_tune_percentage)),
        duration_ms: durationMs,
        duration_seconds: durationMs / 1000,
        sample_count: sampleCount,
        event_count: eventCount,
        stability_score: average(rows.map((row) => row.stability_score)),
        trend: 'guest_local',
        severity: severity.severity,
        severity_color: severity.color,
        problem_severity: avgAbs,
        has_data: eventCount > 0,
        recommendation_summary: `${first.note_label} averaged ${avgAbs.toFixed(1)} cents across guest sessions saved in this browser.`,
      } satisfies NoteStats;
    })
    .sort((a, b) => b.problem_severity - a.problem_severity);
}

function emptyHeatmapRow(instrumentId: string, label: string): NoteStats {
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
    recommendation_summary: `No guest ${instrumentId} data recorded for ${label} in this browser yet.`,
  };
}

export function buildGuestHeatmap(instrumentId: string, stats: NoteStats[]): NoteStats[] {
  const byLabel = new Map(stats.map((row) => [row.note_label, row]));
  const labels = guestHeatmapNotes[instrumentId] ?? guestHeatmapNotes.trumpet;
  return labels.map((label) => byLabel.get(label) ?? emptyHeatmapRow(instrumentId, label));
}

export function buildGuestRecommendations(stats: NoteStats[]): Recommendation[] {
  return stats.slice(0, 4).map((row) => ({
    title: `${row.note_label}: center the pitch before adding speed`,
    message: `${row.note_label} is averaging ${row.avg_abs_cents.toFixed(1)} cents of absolute error in guest practice.`,
    severity: row.severity,
    category: 'guest_practice',
    related_note: row.note_label,
    suggested_exercises: [
      'Hold the note for four slow counts against a steady air stream',
      'Reset the breath and repeat until the attack matches the sustain',
      'Move from the anchor note into the problem note without changing embouchure pressure',
    ],
    suggested_focus: row.avg_signed_cents > 0 ? 'Let the pitch settle slightly lower.' : 'Support the air and bring the center slightly higher.',
    explanation: 'This recommendation is derived from guest sessions stored in this browser.',
  }));
}

export function buildGuestPracticePlan(stats: NoteStats[], instrumentId: string): PracticePlan | null {
  const focus = stats.slice(0, 2);
  if (!focus.length) return null;
  return {
    title: 'Guest intonation plan',
    focus_notes: focus.map((row) => row.note_label),
    coach_message: `Use the local ${instrumentId} takes saved in this browser to center one or two notes before widening the range.`,
    steps: [
      { minutes: 2, label: 'Anchor', detail: 'Play an easy centered note and match the same air speed on every entrance.' },
      { minutes: 4, label: `Isolate ${focus[0].note_label}`, detail: focus[0].recommendation_summary ?? 'Repeat the highest-priority guest note slowly.' },
      { minutes: 3, label: 'Transfer', detail: 'Move between the anchor and focus note without changing volume or pressure.' },
      { minutes: 1, label: 'Check', detail: 'Record another guest take and compare the average absolute cents.' },
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

export function buildGuestProgress(instrumentId: string, stats: NoteStats[]): ProgressMetrics {
  const sessions = sessionsForInstrument(instrumentId);
  const sorted = [...sessions].sort((a, b) => new Date(a.started_at).getTime() - new Date(b.started_at).getTime());
  const currentWeekStart = startOfDay(new Date());
  currentWeekStart.setDate(currentWeekStart.getDate() - 6);
  const currentWeekDays = new Set(
    sorted
      .filter((session) => new Date(session.started_at) >= currentWeekStart)
      .map((session) => startOfDay(new Date(session.started_at)).getTime()),
  );
  const timeseries = sorted.slice(-8).map((session) => ({
    period: new Date(session.started_at).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }),
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
      practice_days_label: `${currentWeekDays.size} of 7`,
      practice_streak_days: practiceStreakDays(sorted),
    },
    most_improved_notes: mostImproved,
    worst_notes: stats.slice(0, 5),
    most_consistently_sharp_notes: [...stats].filter((row) => row.avg_signed_cents > 5).sort((a, b) => b.avg_signed_cents - a.avg_signed_cents),
    most_consistently_flat_notes: [...stats].filter((row) => row.avg_signed_cents < -5).sort((a, b) => a.avg_signed_cents - b.avg_signed_cents),
    period: { current: 'Guest browser data' },
  };
}

function aggregateSessionStats(sessions: GuestSessionDetail[]) {
  const groups = new Map<string, NoteStats[]>();
  sessions.forEach((session) => {
    session.note_stats.forEach((row) => groups.set(row.note_label, [...(groups.get(row.note_label) ?? []), row]));
  });
  return [...groups.values()].map((rows) => {
    const first = rows[0];
    const avgAbs = average(rows.map((row) => row.avg_abs_cents));
    const severity = severityFor(avgAbs);
    return {
      ...first,
      avg_signed_cents: average(rows.map((row) => row.avg_signed_cents)),
      avg_abs_cents: avgAbs,
      in_tune_percentage: average(rows.map((row) => row.in_tune_percentage)),
      problem_severity: avgAbs,
      severity: severity.severity,
      severity_color: severity.color,
    };
  });
}
