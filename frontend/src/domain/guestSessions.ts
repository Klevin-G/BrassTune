import type { NoteEvent, NoteStats, PitchFrame, PracticeSession, Recommendation } from './types';

const GUEST_SESSIONS_KEY = 'brasstune.guestSessions.v1';
const GUEST_USER_ID = 0;
let memoryGuestSessions: GuestSessionDetail[] = [];

export interface GuestAudio {
  dataUrl: string;
  mimeType: string;
  durationSeconds: number;
  sizeBytes: number;
}

export type GuestSessionDetail = PracticeSession & {
  samples_count: number;
  note_events: NoteEvent[];
  note_stats: NoteStats[];
  heatmap: NoteStats[];
  recommendations: Recommendation[];
  frames: PitchFrame[];
};

export interface GuestSessionDraft extends PracticeSession {
  guest_session: true;
}

function readStored(): GuestSessionDetail[] {
  if (typeof localStorage === 'undefined') return memoryGuestSessions;
  try {
    const raw = localStorage.getItem(GUEST_SESSIONS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeStored(sessions: GuestSessionDetail[]) {
  const next = sessions.slice(0, 30);
  if (typeof localStorage === 'undefined') {
    memoryGuestSessions = next;
    return;
  }
  localStorage.setItem(GUEST_SESSIONS_KEY, JSON.stringify(next));
}

function guestId() {
  return -Math.max(1, Date.now());
}

function validFrames(frames: PitchFrame[]) {
  return frames.filter((frame) => frame.is_valid_for_recording && frame.cents_deviation !== null && frame.written_note_name && frame.written_octave !== null);
}

function average(values: number[]) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
}

function noteLabel(frame: PitchFrame) {
  return `${frame.written_note_name ?? 'Note'}${frame.written_octave ?? ''}`;
}

function buildNoteEvents(sessionId: number, frames: PitchFrame[]) {
  const events: NoteEvent[] = [];
  let current: PitchFrame[] = [];
  let currentLabel = '';
  const flush = () => {
    if (current.length === 0) return;
    const cents = current.map((frame) => frame.cents_deviation ?? 0);
    const first = current[0];
    const last = current[current.length - 1];
    const label = noteLabel(first);
    events.push({
      id: sessionId * 1000 - events.length - 1,
      session_id: sessionId,
      instrument_id: first.instrument_id,
      written_note: first.written_note_name ?? 'Note',
      written_octave: first.written_octave ?? 0,
      note_label: label,
      concert_note: first.concert_note_name ?? first.written_note_name ?? 'Note',
      concert_octave: first.concert_octave ?? first.written_octave ?? 0,
      started_at_ms: first.timestamp_ms,
      ended_at_ms: last.timestamp_ms,
      duration_ms: Math.max(110, last.timestamp_ms - first.timestamp_ms + 110),
      duration_seconds: Math.max(0.1, (last.timestamp_ms - first.timestamp_ms + 110) / 1000),
      sample_count: current.length,
      avg_signed_cents: average(cents),
      avg_abs_cents: average(cents.map(Math.abs)),
      median_cents: [...cents].sort((a, b) => a - b)[Math.floor(cents.length / 2)] ?? 0,
      stddev_cents: Math.sqrt(average(cents.map((value) => (value - average(cents)) ** 2))),
      min_cents: Math.min(...cents),
      max_cents: Math.max(...cents),
      in_tune_percentage: (cents.filter((value) => Math.abs(value) <= 5).length / cents.length) * 100,
      stability_score: Math.max(0, 100 - average(cents.map(Math.abs)) * 4),
      created_at: new Date().toISOString(),
    });
    current = [];
    currentLabel = '';
  };

  frames.forEach((frame) => {
    const label = noteLabel(frame);
    if (currentLabel && label !== currentLabel) flush();
    currentLabel = label;
    current.push(frame);
  });
  flush();
  return events;
}

function buildNoteStats(events: NoteEvent[]): NoteStats[] {
  const groups = new Map<string, NoteEvent[]>();
  events.forEach((event) => {
    const key = `${event.written_note}${event.written_octave}`;
    groups.set(key, [...(groups.get(key) ?? []), event]);
  });
  return [...groups.values()]
    .map((items) => {
      const first = items[0];
      const abs = items.map((item) => item.avg_abs_cents);
      const signed = items.map((item) => item.avg_signed_cents);
      const durationMs = items.reduce((sum, item) => sum + item.duration_ms, 0);
      const sampleCount = items.reduce((sum, item) => sum + item.sample_count, 0);
      const avgAbs = average(abs);
      const severity = avgAbs >= 16 ? 'red' : avgAbs >= 11 ? 'orange' : avgAbs >= 7 ? 'yellow' : 'green';
      return {
        written_note: first.written_note,
        written_octave: first.written_octave,
        note_label: first.note_label,
        avg_signed_cents: average(signed),
        avg_abs_cents: avgAbs,
        median_cents: average(signed),
        stddev_cents: average(items.map((item) => item.stddev_cents)),
        in_tune_percentage: average(items.map((item) => item.in_tune_percentage)),
        duration_ms: durationMs,
        duration_seconds: durationMs / 1000,
        sample_count: sampleCount,
        event_count: items.length,
        stability_score: average(items.map((item) => item.stability_score)),
        trend: 'guest_local',
        severity,
        problem_severity: avgAbs,
        has_data: true,
        severity_color: severity,
        recommendation_summary: `${first.note_label} averaged ${avgAbs.toFixed(1)} cents in guest practice.`,
      } satisfies NoteStats;
    })
    .sort((a, b) => b.problem_severity - a.problem_severity);
}

function buildRecommendations(stats: NoteStats[]): Recommendation[] {
  return stats.slice(0, 3).map((row) => ({
    title: `${row.note_label}: center before moving on`,
    message: `${row.note_label} averaged ${row.avg_abs_cents.toFixed(1)} cents off center in this guest take.`,
    severity: row.severity,
    category: 'guest_practice',
    related_note: row.note_label,
    suggested_exercises: ['Hold the note for four slow counts', 'Breathe, reset, and repeat with a tuner drone', 'Compare first attack to sustained center'],
    suggested_focus: row.avg_signed_cents > 0 ? 'Bring the pitch slightly down' : 'Support the air and bring the pitch slightly up',
    explanation: 'This recommendation is generated from the guest session saved in this browser.',
  }));
}

export function createGuestSession(instrumentId: string, referencePitchHz: number, name?: string): GuestSessionDraft {
  const now = new Date().toISOString();
  return {
    id: guestId(),
    user_id: GUEST_USER_ID,
    instrument_id: instrumentId,
    name: name || `Guest practice ${new Date().toLocaleDateString()}`,
    started_at: now,
    ended_at: null,
    duration_seconds: 0,
    reference_pitch_hz: referencePitchHz,
    notes_count: 0,
    average_signed_cents: 0,
    average_abs_cents: 0,
    in_tune_percentage: 0,
    audio_available: false,
    guest_session: true,
    guest_audio_data_url: null,
    created_at: now,
  };
}

export function saveGuestSessionFromFrames(
  draft: GuestSessionDraft,
  frames: PitchFrame[],
  audio?: GuestAudio | null,
): GuestSessionDetail {
  const endedAt = new Date().toISOString();
  const recordingFrames = validFrames(frames);
  const noteEvents = buildNoteEvents(draft.id, recordingFrames);
  const noteStats = buildNoteStats(noteEvents);
  const cents = recordingFrames.map((frame) => frame.cents_deviation ?? 0);
  const durationSeconds = Math.max(
    1,
    audio?.durationSeconds ?? (recordingFrames[recordingFrames.length - 1]?.timestamp_ms ?? 0) / 1000,
    (new Date(endedAt).getTime() - new Date(draft.started_at).getTime()) / 1000,
  );
  const session: GuestSessionDetail = {
    ...draft,
    ended_at: endedAt,
    duration_seconds: durationSeconds,
    notes_count: noteEvents.length,
    average_signed_cents: average(cents),
    average_abs_cents: average(cents.map(Math.abs)),
    in_tune_percentage: cents.length ? (cents.filter((value) => Math.abs(value) <= 5).length / cents.length) * 100 : 0,
    audio_available: Boolean(audio?.dataUrl),
    audio_storage_provider: audio?.dataUrl ? 'browser_guest' : null,
    audio_mime_type: audio?.mimeType ?? null,
    audio_duration_seconds: audio?.durationSeconds ?? null,
    audio_size_bytes: audio?.sizeBytes ?? null,
    audio_uploaded_at: audio?.dataUrl ? endedAt : null,
    guest_audio_data_url: audio?.dataUrl ?? null,
    samples_count: recordingFrames.length,
    note_events: noteEvents,
    note_stats: noteStats,
    heatmap: noteStats,
    recommendations: buildRecommendations(noteStats),
    frames: recordingFrames,
  };
  const remaining = readStored().filter((item) => item.id !== session.id);
  writeStored([session, ...remaining]);
  return session;
}

export function listGuestSessions() {
  return readStored().sort((a, b) => new Date(b.started_at).getTime() - new Date(a.started_at).getTime());
}

export function getGuestSession(id: string | number) {
  const numeric = Number(id);
  return readStored().find((session) => session.id === numeric) ?? null;
}

export function isGuestSessionId(id: string | number | undefined | null) {
  if (id === undefined || id === null) return false;
  return Number(id) < 0;
}

export function clearGuestSessions() {
  memoryGuestSessions = [];
  if (typeof localStorage !== 'undefined') localStorage.removeItem(GUEST_SESSIONS_KEY);
}

export function deleteGuestSession(id: string | number) {
  const numeric = Number(id);
  const remaining = readStored().filter((session) => session.id !== numeric);
  writeStored(remaining);
}

export function guestSessionsExport() {
  return JSON.stringify({ exported_at: new Date().toISOString(), sessions: readStored() }, null, 2);
}
