import type { NoteEvent, NoteStats, PitchFrame, PracticeSession, Recommendation } from './types';

const GUEST_SESSIONS_KEY = 'brasstune.guestSessions.v1';
const GUEST_USER_ID = 0;
let memoryGuestSessions: GuestSessionDetail[] = [];
let lastGuestId = 0;

/**
 * Deliberate capability required for device-local guest data access. Account
 * surfaces must never pass this value. This makes accidental cross-account
 * list/review/export calls fail closed while guest-only domain code remains
 * explicit and testable.
 */
export const GUEST_WORKSPACE_ACCESS = Object.freeze({ scope: 'guest-workspace' as const });
export type GuestWorkspaceAccess = typeof GUEST_WORKSPACE_ACCESS;

function canAccessGuestWorkspace(access?: GuestWorkspaceAccess): boolean {
  return access === GUEST_WORKSPACE_ACCESS;
}

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
    return Array.isArray(parsed) ? parsed.map(normalizeGuestSession).filter((session): session is GuestSessionDetail => Boolean(session)) : [];
  } catch {
    return [];
  }
}

function normalizeGuestSession(value: unknown): GuestSessionDetail | null {
  if (!value || typeof value !== 'object') return null;
  const session = value as Partial<GuestSessionDetail>;
  if (typeof session.id !== 'number' || session.id >= 0 || typeof session.instrument_id !== 'string' || typeof session.started_at !== 'string') return null;
  return {
    ...(session as GuestSessionDetail),
    user_id: GUEST_USER_ID,
    name: session.name ?? 'Guest practice',
    ended_at: session.ended_at ?? null,
    duration_seconds: Number(session.duration_seconds ?? 0),
    reference_pitch_hz: Number(session.reference_pitch_hz ?? 440),
    notes_count: Number(session.notes_count ?? 0),
    average_signed_cents: Number(session.average_signed_cents ?? 0),
    average_abs_cents: Number(session.average_abs_cents ?? 0),
    in_tune_percentage: Number(session.in_tune_percentage ?? 0),
    audio_available: Boolean(session.audio_available),
    guest_session: true,
    created_at: session.created_at ?? session.started_at,
    samples_count: Number(session.samples_count ?? 0),
    note_events: Array.isArray(session.note_events) ? session.note_events : [],
    note_stats: Array.isArray(session.note_stats) ? session.note_stats : [],
    heatmap: Array.isArray(session.heatmap) ? session.heatmap : Array.isArray(session.note_stats) ? session.note_stats : [],
    recommendations: Array.isArray(session.recommendations) ? session.recommendations : [],
    frames: Array.isArray(session.frames) ? session.frames : [],
  };
}

function writeStored(sessions: GuestSessionDetail[]) {
  const next = sessions.slice(0, 30);
  if (typeof localStorage === 'undefined') {
    memoryGuestSessions = next;
    return;
  }
  const isQuotaError = (error: unknown) =>
    error instanceof Error && (error.name === 'QuotaExceededError' || error.name.includes('Quota'));
  const trySet = (value: GuestSessionDetail[]) => localStorage.setItem(GUEST_SESSIONS_KEY, JSON.stringify(value));
  try {
    trySet(next);
    return;
  } catch (error) {
    if (!isQuotaError(error)) throw error;
  }
  // Recovery step 1: drop the oldest sessions' inline audio first (newest last), retrying after each.
  const working = next.map((session) => ({ ...session }));
  for (let i = working.length - 1; i >= 0; i -= 1) {
    if (!working[i].guest_audio_data_url) continue;
    working[i] = { ...working[i], guest_audio_data_url: null, audio_available: false };
    try {
      trySet(working);
      return;
    } catch (error) {
      if (!isQuotaError(error)) throw error;
    }
  }
  // Recovery step 2: evict the oldest sessions entirely, one at a time, keeping the newest.
  const evicting = working.slice();
  while (evicting.length > 1) {
    evicting.pop();
    try {
      trySet(evicting);
      return;
    } catch (error) {
      if (!isQuotaError(error)) throw error;
    }
  }
  // Last resort: persist just the newest session; rethrow if even that fails.
  trySet(evicting);
}

function guestId() {
  lastGuestId = Math.max(lastGuestId + 1, Date.now());
  return -lastGuestId;
}

function isValidFrame(frame: PitchFrame) {
  return Boolean(
    frame.is_valid_for_recording
    && frame.cents_deviation !== null
    && Number.isFinite(frame.cents_deviation)
    && frame.written_note_name
    && frame.written_octave !== null,
  );
}

function validFrames(frames: PitchFrame[]) {
  return frames.filter(isValidFrame).sort((left, right) => left.timestamp_ms - right.timestamp_ms);
}

function average(values: number[]) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
}

function median(values: number[]) {
  if (!values.length) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function populationStdDev(values: number[]) {
  if (values.length <= 1) return 0;
  const center = average(values);
  return Math.sqrt(average(values.map((value) => (value - center) ** 2)));
}

function noteLabel(frame: PitchFrame) {
  return `${frame.written_note_name ?? 'Note'}${frame.written_octave ?? ''}`;
}

export const GUEST_NOTE_MAX_MERGE_GAP_MS = 340;
export const GUEST_NOTE_MIN_DURATION_MS = 120;

function computeGuestNoteEvent(sessionId: number, eventIndex: number, frames: PitchFrame[]): NoteEvent | null {
  const current = validFrames(frames);
  if (!current.length) return null;
  const cents = current.map((frame) => frame.cents_deviation as number);
  const first = current[0];
  const last = current[current.length - 1];
  const gaps = current.slice(1).map((frame, index) => frame.timestamp_ms - current[index].timestamp_ms);
  const inferredTailMs = gaps.length ? Math.max(60, Math.min(Math.trunc(median(gaps)), 180)) : 0;
  const durationMs = Math.max(0, last.timestamp_ms - first.timestamp_ms) + inferredTailMs;
  const stddevCents = populationStdDev(cents);
  return {
    id: sessionId * 1000 - eventIndex - 1,
    session_id: sessionId,
    instrument_id: first.instrument_id,
    written_note: first.written_note_name ?? 'Note',
    written_octave: first.written_octave ?? 0,
    note_label: noteLabel(first),
    concert_note: first.concert_note_name ?? first.written_note_name ?? 'Note',
    concert_octave: first.concert_octave ?? first.written_octave ?? 0,
    started_at_ms: first.timestamp_ms,
    ended_at_ms: last.timestamp_ms,
    duration_ms: durationMs,
    duration_seconds: durationMs / 1000,
    sample_count: current.length,
    avg_signed_cents: average(cents),
    avg_abs_cents: average(cents.map(Math.abs)),
    median_cents: median(cents),
    stddev_cents: stddevCents,
    min_cents: Math.min(...cents),
    max_cents: Math.max(...cents),
    in_tune_percentage: (current.filter((frame) => frame.tuning_status === 'in_tune').length / current.length) * 100,
    stability_score: Math.max(0, Math.min(100, 100 - stddevCents * 5)),
    created_at: new Date().toISOString(),
  };
}

export function buildGuestNoteEvents(
  sessionId: number,
  frames: PitchFrame[],
  options: { maxMergeGapMs?: number; minDurationMs?: number } = {},
) {
  const maxMergeGapMs = options.maxMergeGapMs ?? GUEST_NOTE_MAX_MERGE_GAP_MS;
  const minDurationMs = options.minDurationMs ?? GUEST_NOTE_MIN_DURATION_MS;
  const events: NoteEvent[] = [];
  let current: PitchFrame[] = [];
  let currentLabel: string | null = null;
  let lastValidTimestamp: number | null = null;
  const flush = () => {
    if (current.length === 0) return;
    const event = computeGuestNoteEvent(sessionId, events.length, current);
    if (event && event.duration_ms >= minDurationMs) events.push(event);
    current = [];
  };

  [...frames].sort((left, right) => left.timestamp_ms - right.timestamp_ms).forEach((frame) => {
    if (!isValidFrame(frame)) {
      if (current.length && lastValidTimestamp !== null && frame.timestamp_ms - lastValidTimestamp > maxMergeGapMs) {
        flush();
        currentLabel = null;
      }
      return;
    }
    const label = noteLabel(frame);
    if (!current.length) {
      current = [frame];
      currentLabel = label;
      lastValidTimestamp = frame.timestamp_ms;
      return;
    }
    const gap = frame.timestamp_ms - (lastValidTimestamp ?? frame.timestamp_ms);
    if (label !== currentLabel || gap > maxMergeGapMs) flush();
    currentLabel = label;
    current.push(frame);
    lastValidTimestamp = frame.timestamp_ms;
  });
  flush();
  return events;
}

export function classifyGuestNoteProblem(noteStats: Partial<NoteStats>): string {
  const avgAbs = Number(noteStats.avg_abs_cents ?? 0);
  const inTune = Number(noteStats.in_tune_percentage ?? 0);
  if (avgAbs <= 5 && inTune >= 80) return 'excellent';
  if (avgAbs <= 8) return 'good';
  if (avgAbs <= 15) return 'moderate issue';
  return 'severe issue';
}

export function classifyGuestNoteTrend(noteStats: Partial<NoteStats>): string {
  const signed = Number(noteStats.avg_signed_cents ?? 0);
  const stddev = Number(noteStats.stddev_cents ?? 0);
  const stability = Number(noteStats.stability_score ?? 100);
  if (stddev >= 12 || stability < 50) return 'Unstable';
  if (signed >= 6) return 'Mostly sharp';
  if (signed <= -6) return 'Mostly flat';
  return 'Centered';
}

export function guestProblemScore(noteStats: Partial<NoteStats>): number {
  const avgAbs = Number(noteStats.avg_abs_cents ?? 0);
  const stddev = Number(noteStats.stddev_cents ?? 0);
  const inTune = Number(noteStats.in_tune_percentage ?? 0);
  return Math.round((avgAbs * 2 + stddev + Math.max(0, 80 - inTune) * 0.25) * 100) / 100;
}

export function guestHeatmapSeverity(noteStats: Partial<NoteStats> | null): NoteStats['severity_color'] {
  if (!noteStats) return 'insufficient';
  if (Number(noteStats.duration_seconds ?? 0) < 3 || Number(noteStats.sample_count ?? 0) < 8) return 'insufficient';
  const avgAbs = Number(noteStats.avg_abs_cents ?? 0);
  if (avgAbs <= 5) return 'green';
  if (avgAbs <= 10) return 'yellow';
  if (avgAbs <= 15) return 'orange';
  return 'red';
}

function recommendationSummary(row: Partial<NoteStats>) {
  const trend = classifyGuestNoteTrend(row);
  const avg = Math.abs(Number(row.avg_signed_cents ?? 0));
  if (trend === 'Mostly sharp') return `Tends sharp by ${avg.toFixed(0)} cents`;
  if (trend === 'Mostly flat') return `Tends flat by ${avg.toFixed(0)} cents`;
  if (trend === 'Unstable') return 'Pitch is inconsistent';
  return 'Generally centered';
}

export function calculateGuestNoteStats(events: NoteEvent[]): NoteStats[] {
  const groups = new Map<string, NoteEvent[]>();
  events.forEach((event) => {
    const key = `${event.written_note}${event.written_octave}`;
    groups.set(key, [...(groups.get(key) ?? []), event]);
  });
  return [...groups.values()]
    .map((items) => {
      const first = items[0];
      const durationMs = items.reduce((sum, item) => sum + item.duration_ms, 0);
      const denominator = durationMs > 0 ? durationMs : items.length;
      const weight = (item: NoteEvent) => (durationMs > 0 ? item.duration_ms : 1);
      const sampleCount = items.reduce((sum, item) => sum + item.sample_count, 0);
      const eventCenters = items.map((item) => item.avg_signed_cents);
      const row: NoteStats = {
        written_note: first.written_note,
        written_octave: first.written_octave,
        note_label: first.note_label,
        avg_signed_cents: items.reduce((sum, item) => sum + item.avg_signed_cents * weight(item), 0) / denominator,
        avg_abs_cents: items.reduce((sum, item) => sum + item.avg_abs_cents * weight(item), 0) / denominator,
        median_cents: median(eventCenters),
        stddev_cents: items.length > 1 ? populationStdDev(eventCenters) : first.stddev_cents,
        in_tune_percentage: items.reduce((sum, item) => sum + item.in_tune_percentage * weight(item), 0) / denominator,
        duration_ms: denominator,
        duration_seconds: denominator / 1000,
        sample_count: sampleCount,
        event_count: items.length,
        stability_score: items.reduce((sum, item) => sum + item.stability_score * weight(item), 0) / denominator,
        trend: '',
        severity: '',
        problem_severity: 0,
        has_data: true,
        severity_color: 'insufficient',
        recommendation_summary: '',
      };
      row.trend = classifyGuestNoteTrend(row);
      row.severity = classifyGuestNoteProblem(row);
      row.problem_severity = guestProblemScore(row);
      row.severity_color = guestHeatmapSeverity(row);
      row.recommendation_summary = recommendationSummary(row);
      return row;
    })
    .sort((left, right) => left.written_octave - right.written_octave || left.written_note.localeCompare(right.written_note));
}

export function generateGuestNoteRecommendation(row: NoteStats): Recommendation {
  const label = row.note_label;
  const signed = row.avg_signed_cents;
  const avgAbs = row.avg_abs_cents;
  const trend = classifyGuestNoteTrend(row);
  const severity = classifyGuestNoteProblem(row);
  let title: string;
  let message: string;
  let category: string;
  let suggestions: string[];
  if (row.duration_seconds < 3) {
    title = `More data needed for ${label}`;
    message = `This guest workspace needs more recorded attempts on written ${label} before BrassTune can identify a reliable pattern.`;
    category = 'Insufficient data';
    suggestions = ['Record at least three steady long-tone attempts on this note.'];
  } else if (trend === 'Unstable') {
    title = `${label} is inconsistent`;
    message = `In this guest workspace, written ${label} changes too much for BrassTune to call it centered yet.`;
    category = 'Inconsistent pitch';
    suggestions = ['Hold the note for 8-12 seconds and aim for a steady needle.', 'Use a drone and focus on minimizing motion.', 'Record several repetitions with full breaths.'];
  } else if (signed >= 10) {
    title = `${label} tends sharp`;
    message = `In this guest workspace, written ${label} averages ${Math.abs(signed).toFixed(0)} cents sharp.`;
    category = 'Sharp tendency';
    suggestions = ['Practice slow long tones on this note with a drone.', 'Start slightly below the pitch and gently center upward.', 'Check whether you are over-tightening your embouchure.'];
  } else if (signed <= -10) {
    title = `${label} tends flat`;
    message = `In this guest workspace, written ${label} averages ${Math.abs(signed).toFixed(0)} cents flat.`;
    category = 'Flat tendency';
    suggestions = ['Practice long tones with a drone.', 'Support the air stream and avoid letting the pitch sag.', 'Check posture and breath support.'];
  } else if (severity === 'severe issue') {
    title = `${label} needs focused intonation work`;
    message = `In this guest workspace, written ${label} averages ${avgAbs.toFixed(0)} cents away from center.`;
    category = 'Severe problem note';
    suggestions = ['Use a drone and repeat the note in short sets of five.', 'Approach the note from a neighboring pitch, then sustain it.'];
  } else {
    title = `${label} is improving`;
    message = `In this guest workspace, written ${label} is generally centered. Keep reinforcing it in context.`;
    category = 'Good progress';
    suggestions = ['Play the note inside simple scale patterns.', 'Try one repetition with the tuner hidden, then check your result.'];
  }
  return {
    title,
    message,
    severity,
    category,
    related_note: label,
    suggested_exercises: suggestions.slice(0, 5),
    suggested_focus: trend,
    explanation: 'Generated from duration-weighted cents, in-tune percentage, and stability in guest sessions stored in this browser.',
  };
}

export function buildGuestRecommendations(stats: NoteStats[], limit = 3): Recommendation[] {
  return [...stats]
    .sort((left, right) => right.problem_severity - left.problem_severity)
    .slice(0, limit)
    .map(generateGuestNoteRecommendation);
}

function computeGuestSessionSummary(events: NoteEvent[]) {
  if (!events.length) {
    return { duration_seconds: 0, notes_count: 0, average_signed_cents: 0, average_abs_cents: 0, in_tune_percentage: 0 };
  }
  const durationMs = events.reduce((sum, event) => sum + event.duration_ms, 0) || events.length;
  const weighted = (key: 'avg_signed_cents' | 'avg_abs_cents' | 'in_tune_percentage') =>
    events.reduce((sum, event) => sum + event[key] * (event.duration_ms || 1), 0) / durationMs;
  return {
    duration_seconds: Math.round((durationMs / 1000) * 100) / 100,
    notes_count: events.length,
    average_signed_cents: weighted('avg_signed_cents'),
    average_abs_cents: weighted('avg_abs_cents'),
    in_tune_percentage: weighted('in_tune_percentage'),
  };
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
  const noteEvents = buildGuestNoteEvents(draft.id, frames);
  const noteStats = calculateGuestNoteStats(noteEvents);
  const summary = computeGuestSessionSummary(noteEvents);
  const elapsedWallSeconds = Math.max(0, (new Date(endedAt).getTime() - new Date(draft.started_at).getTime()) / 1000);
  const session: GuestSessionDetail = {
    ...draft,
    ended_at: endedAt,
    duration_seconds: noteEvents.length ? summary.duration_seconds : elapsedWallSeconds,
    notes_count: summary.notes_count,
    average_signed_cents: summary.average_signed_cents,
    average_abs_cents: summary.average_abs_cents,
    in_tune_percentage: summary.in_tune_percentage,
    audio_available: Boolean(audio?.dataUrl),
    audio_mime_type: audio?.mimeType ?? null,
    audio_duration_seconds: audio?.durationSeconds ?? null,
    audio_size_bytes: audio?.sizeBytes ?? null,
    audio_uploaded_at: audio?.dataUrl ? endedAt : null,
    guest_audio_data_url: audio?.dataUrl ?? null,
    samples_count: recordingFrames.length,
    note_events: noteEvents,
    note_stats: noteStats,
    heatmap: noteStats,
    recommendations: buildGuestRecommendations(noteStats, 6),
    frames: recordingFrames,
  };
  const remaining = readStored().filter((item) => item.id !== session.id);
  writeStored([session, ...remaining]);
  return session;
}

export function listGuestSessions(access?: GuestWorkspaceAccess) {
  if (!canAccessGuestWorkspace(access)) return [];
  return readStored().sort((a, b) => new Date(b.started_at).getTime() - new Date(a.started_at).getTime());
}

export function getGuestSession(id: string | number, access?: GuestWorkspaceAccess) {
  if (!canAccessGuestWorkspace(access)) return null;
  const numeric = Number(id);
  if (!Number.isFinite(numeric) || numeric >= 0) return null;
  return readStored().find((session) => session.id === numeric) ?? null;
}

export function isGuestSessionId(id: string | number | undefined | null) {
  if (id === undefined || id === null) return false;
  return Number(id) < 0;
}

export function clearGuestSessions(access?: GuestWorkspaceAccess) {
  if (!canAccessGuestWorkspace(access)) return false;
  memoryGuestSessions = [];
  if (typeof localStorage !== 'undefined') localStorage.removeItem(GUEST_SESSIONS_KEY);
  return true;
}

export function deleteGuestSession(id: string | number, access?: GuestWorkspaceAccess) {
  if (!canAccessGuestWorkspace(access)) return false;
  const numeric = Number(id);
  if (!Number.isFinite(numeric) || numeric >= 0) return false;
  const remaining = readStored().filter((session) => session.id !== numeric);
  if (remaining.length === readStored().length) return false;
  writeStored(remaining);
  return true;
}

export function guestSessionsExport(access?: GuestWorkspaceAccess) {
  const sessions = canAccessGuestWorkspace(access) ? readStored() : [];
  return JSON.stringify({ exported_at: new Date().toISOString(), sessions }, null, 2);
}
