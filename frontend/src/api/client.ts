import type { InstrumentProfile, NoteEvent, NoteStats, PitchFrame, PracticePlan, PracticeSession, ProgressMetrics, Recommendation } from '../domain/types';
import { apiBase, UNRESOLVED_BASE, wsBase } from './runtimeConfig';
let authTokenProvider: (() => Promise<string | null>) | null = null;
export const MAX_PITCH_FRAMES_PER_BATCH = 1000;

export interface DateRangeParams {
  date_from?: string;
  date_to?: string;
}

export function setAuthTokenProvider(provider: (() => Promise<string | null>) | null) {
  authTokenProvider = provider;
}

function resolvedApiBase(): string {
  const base = apiBase();
  if (base === UNRESOLVED_BASE) {
    throw new Error('Cloud practice is not configured for this deployment.');
  }
  return base;
}

async function authHeaders(): Promise<Record<string, string>> {
  const token = authTokenProvider ? await authTokenProvider() : null;
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const body = options?.body;
  const isFormBody = typeof FormData !== 'undefined' && body instanceof FormData;
  const isBlobBody = typeof Blob !== 'undefined' && body instanceof Blob;
  const headers = new Headers({
    ...(isFormBody || isBlobBody ? {} : { 'Content-Type': 'application/json' }),
    ...(await authHeaders()),
  });
  new Headers(options?.headers).forEach((value, key) => headers.set(key, value));
  const response = await fetch(`${resolvedApiBase()}${path}`, {
    ...options,
    headers,
  });
  if (!response.ok) {
    const message = await response.text();
    throw new Error(friendlyRequestError(message, response.status));
  }
  return response.json() as Promise<T>;
}

export function friendlyUserFacingError(error: unknown, fallback = 'That action could not complete. Try again after reconnecting.') {
  const raw = error instanceof Error ? error.message : String(error ?? '');
  if (/quota|storage/i.test(raw)) return 'This browser could not save the latest local practice data. Export or delete old local sessions and try again.';
  if (/permission|denied|notallowed/i.test(raw)) return 'Permission was blocked. Check browser permissions and try again.';
  if (/network|failed to fetch|load failed|offline/i.test(raw)) return 'Network access is unavailable right now. Guest practice still works on this device.';
  if (/authentication required|sign in|unauthorized|forbidden|access/i.test(raw)) return 'Sign in with the right account to use that cloud feature.';
  if (/too many|413|payload/i.test(raw)) return 'That request is too large. Try a shorter recording or smaller file.';
  if (/fastapi|traceback|stack|sql|relation|supabase|env var|vite|render|vercel|http:|https:/i.test(raw) || raw.length > 180) return fallback;
  return raw || fallback;
}

function friendlyRequestError(message: string, status: number) {
  let raw = message;
  try {
    const parsed = JSON.parse(message);
    raw = parsed.detail ?? parsed.message ?? message;
  } catch {
    raw = message;
  }
  if (status === 401 || /authentication required|auth|token|supabase/i.test(raw)) {
    return 'Sign in to sync sessions and account features. Guest practice still works on this device.';
  }
  if (/fastapi|backend|env var|SUPABASE_|VITE_/i.test(raw)) {
    return 'Cloud practice is unavailable right now. Guest practice still works on this device.';
  }
  if (status === 403) return 'You do not have access to that BrassTune resource.';
  if (status === 404) return 'That BrassTune item is not available for this account.';
  if (status === 409) return 'That change conflicts with existing account or ensemble data.';
  if (status === 413) return 'That request is too large. Try a shorter recording or smaller file.';
  if (status >= 500) return 'Cloud practice is unavailable right now. Guest practice still works on this device.';
  return friendlyUserFacingError(raw, `Request failed with status ${status}.`);
}

export const exportUrl = (path: string) => `${apiBase()}${path}`;

export async function pitchWebSocketUrl() {
  const configuredBase = wsBase();
  if (configuredBase === UNRESOLVED_BASE) {
    // Hosted/production build with no resolvable WS base: never derive wss from
    // the static frontend host, which has no pitch backend.
    throw new Error('Pitch streaming is not configured for this deployment.');
  }
  const base = configuredBase || `${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.host}`;
  const url = new URL('/ws/pitch', base);
  return url.toString();
}

export async function pitchWebSocketAuthPayload() {
  const token = authTokenProvider ? await authTokenProvider() : null;
  return token ? { type: 'authenticate', token } : null;
}

function queryString(params: Record<string, string | number | undefined>) {
  const search = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== '') {
      search.set(key, String(value));
    }
  });
  const serialized = search.toString();
  return serialized ? `?${serialized}` : '';
}

export function getInstruments() {
  return request<InstrumentProfile[]>('/api/instruments');
}

export function getCurrentUser() {
  return request<{
    id: number;
    supabase_user_id?: string | null;
    username: string | null;
    name: string;
    display_name: string;
    email: string | null;
    role: string;
    primary_instrument_id: string;
    onboarding_completed_at?: string | null;
  }>('/api/users/current');
}

export function updateCurrentUser(payload: { username?: string; display_name?: string; primary_instrument_id?: string; onboarding_completed?: boolean }) {
  return request('/api/users/me', {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

export function startSession(instrumentId: string, referencePitchHz: number, name?: string) {
  return request<PracticeSession>('/api/sessions/start', {
    method: 'POST',
    body: JSON.stringify({ instrument_id: instrumentId, reference_pitch_hz: referencePitchHz, name }),
  });
}

export function recordPitchFrame(sessionId: number, frame: PitchFrame) {
  return request<{ saved: boolean }>(`/api/sessions/${sessionId}/samples`, {
    method: 'POST',
    body: JSON.stringify(frame),
  });
}

export function recordPitchFrames(sessionId: number, frames: PitchFrame[], options: { signal?: AbortSignal } = {}) {
  return request<{ saved: number; rejected: number }>(`/api/sessions/${sessionId}/samples/batch`, {
    method: 'POST',
    body: JSON.stringify(frames),
    signal: options.signal,
  });
}

export async function recordPitchFramesInBatches(
  sessionId: number,
  frames: PitchFrame[],
  options: {
    batchSize?: number;
    signal?: AbortSignal;
    onProgress?: (saved: number, attempted: number) => void;
  } = {},
) {
  const batchSize = Math.max(1, Math.min(options.batchSize ?? MAX_PITCH_FRAMES_PER_BATCH, MAX_PITCH_FRAMES_PER_BATCH));
  let saved = 0;
  let rejected = 0;
  let attempted = 0;
  for (let index = 0; index < frames.length; index += batchSize) {
    if (options.signal?.aborted) {
      throw new DOMException('Pitch frame save was canceled.', 'AbortError');
    }
    const batch = frames.slice(index, index + batchSize);
    let result: { saved: number; rejected: number };
    try {
      result = await recordPitchFrames(sessionId, batch, { signal: options.signal });
    } catch (error) {
      const failure = error instanceof Error ? error : new Error('Pitch frame save failed.');
      Object.assign(failure, { saved, rejected, attempted, failedFrames: frames.slice(attempted) });
      throw failure;
    }
    saved += result.saved;
    rejected += result.rejected;
    attempted += batch.length;
    options.onProgress?.(saved, attempted);
  }
  return { saved, rejected, attempted };
}

export function stopSession(sessionId: number) {
  return request<PracticeSession>(`/api/sessions/${sessionId}/stop`, { method: 'POST' });
}

export function listSessions() {
  return request<PracticeSession[]>('/api/sessions');
}

export function getSession(sessionId: string | number) {
  return request<PracticeSession & { samples_count: number; note_events: NoteEvent[] }>(`/api/sessions/${sessionId}`);
}

export function uploadSessionAudio(sessionId: number, blob: Blob, durationSeconds?: number) {
  const headers: Record<string, string> = { 'Content-Type': blob.type || 'audio/webm' };
  if (durationSeconds !== undefined) headers['X-Audio-Duration-Seconds'] = String(durationSeconds);
  return request<{ uploaded: boolean; audio: PracticeSession }>(`/api/sessions/${sessionId}/audio`, {
    method: 'POST',
    headers,
    body: blob,
  });
}

export function sessionAudioUrl(sessionId: number | string) {
  return exportUrl(`/api/sessions/${sessionId}/audio`);
}

export async function downloadExport(path: string, filename: string) {
  const response = await fetch(`${resolvedApiBase()}${path}`, { headers: await authHeaders() });
  if (!response.ok) {
    throw new Error(friendlyRequestError(await response.text(), response.status));
  }
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

export async function objectUrlFor(path: string) {
  const response = await fetch(`${resolvedApiBase()}${path}`, { headers: await authHeaders() });
  if (!response.ok) {
    throw new Error(await response.text());
  }
  return URL.createObjectURL(await response.blob());
}

export function getSessionAnalytics(sessionId: string | number) {
  return request<{ session: PracticeSession; note_stats: NoteStats[]; heatmap: NoteStats[]; recommendations: Recommendation[] }>(`/api/sessions/${sessionId}/analytics`);
}

export function getNoteStats(instrumentId?: string, range: DateRangeParams = {}) {
  const params = queryString({ instrument_id: instrumentId, ...range });
  return request<NoteStats[]>(`/api/analytics/notes${params}`);
}

export function getHeatmap(instrumentId?: string, range: DateRangeParams = {}) {
  const params = queryString({ instrument_id: instrumentId, ...range });
  return request<NoteStats[]>(`/api/analytics/heatmap${params}`);
}

export function getProgress(instrumentId?: string, range: DateRangeParams = {}) {
  const params = queryString({ instrument_id: instrumentId, ...range });
  return request<ProgressMetrics>(`/api/analytics/progress${params}`);
}

export function getRecommendations(instrumentId: string) {
  return request<Recommendation[]>(`/api/recommendations?instrument_id=${instrumentId}`);
}

export function getPracticePlan(instrumentId: string) {
  return request<PracticePlan>(`/api/practice-plan?instrument_id=${instrumentId}`);
}

export function getEnsembleSummary(groupId?: number) {
  const params = queryString({ group_id: groupId });
  return request<any>(`/api/ensemble/summary${params}`);
}

export function getEnsembleReport(groupId?: number) {
  const params = queryString({ group_id: groupId });
  return request<any>(`/api/ensemble/report${params}`);
}

export function getEnsembleGroups() {
  return request<any[]>('/api/ensemble/groups');
}

export function createEnsembleGroup(name: string) {
  return request<any>('/api/ensemble/groups', { method: 'POST', body: JSON.stringify({ name }) });
}

export function getEnsembleGroup(groupId: number) {
  return request<any>(`/api/ensemble/groups/${groupId}`);
}

export function addEnsembleMemberByUsername(groupId: number, payload: { username: string; instrument_id?: string; role_in_group?: string }) {
  return request<any>(`/api/ensemble/groups/${groupId}/members/by-username`, { method: 'POST', body: JSON.stringify(payload) });
}

export function joinEnsembleByCode(code: string, instrumentId?: string) {
  return request<{ joined: boolean; group_id: number; group_name: string }>(`/api/ensemble/join`, {
    method: 'POST',
    body: JSON.stringify({ code, instrument_id: instrumentId }),
  });
}

export function leaveEnsembleGroup(groupId: number) {
  return request<{ left: boolean; group_id: number }>(`/api/ensemble/groups/${groupId}/membership`, { method: 'DELETE' });
}

export function updateEnsembleMember(groupId: number, memberId: number, payload: { instrument_id?: string; role_in_group?: string; status?: string }) {
  return request<any>(`/api/ensemble/groups/${groupId}/members/${memberId}`, { method: 'PATCH', body: JSON.stringify(payload) });
}

export function removeEnsembleMember(groupId: number, memberId: number) {
  return request<{ removed: boolean }>(`/api/ensemble/groups/${groupId}/members/${memberId}`, { method: 'DELETE' });
}

export function rotateEnsembleJoinCode(groupId: number) {
  return request<{ group_id: number; join_code: string }>(`/api/ensemble/groups/${groupId}/join-code/rotate`, { method: 'POST' });
}

export interface EnsembleInvitation {
  member_id: number;
  group_id: number;
  group_name: string;
  instrument_id: string;
  role_in_group: string;
  invited_at: string | null;
  director_name: string | null;
}

export function getEnsembleInvitations() {
  return request<{ invitations: EnsembleInvitation[] }>('/api/ensemble/invitations');
}

export function acceptEnsembleInvitation(memberId: number, instrumentId?: string) {
  return request<{ accepted: boolean; group_id: number }>(`/api/ensemble/invitations/${memberId}/accept`, {
    method: 'POST',
    body: JSON.stringify({ instrument_id: instrumentId }),
  });
}

export function declineEnsembleInvitation(memberId: number) {
  return request<{ declined: boolean }>(`/api/ensemble/invitations/${memberId}/decline`, { method: 'POST' });
}

export interface EnsembleRosterStudent {
  member_id: number;
  user_id: number;
  username: string | null;
  display_name: string | null;
  instrument_id: string;
  status: string;
  role_in_group: string;
  sessions_count: number;
  practice_minutes: number;
  average_abs_cents: number | null;
  in_tune_percentage: number | null;
  last_practice_at: string | null;
  last_active_at: string | null;
}

export function getEnsembleRoster(groupId: number) {
  return request<{ group_id: number; students: EnsembleRosterStudent[] }>(`/api/ensemble/groups/${groupId}/roster`);
}

export interface AdminMetrics {
  generated_at: string;
  totals: { users: number; sessions: number; ensembles: number };
  new_users: { last_7d: number; last_30d: number };
  active_users: { dau: number; wau: number; mau: number };
  sessions: { last_7d: number; last_30d: number };
  events_30d: Record<string, number>;
  signups_by_day: { date: string; count: number }[];
}

export function getAdminMetrics() {
  return request<AdminMetrics>('/api/admin/metrics');
}

export function clearLocalSessions() {
  return request<{ cleared: Record<string, number> }>('/api/users/me/clear-sessions', { method: 'POST' });
}

export function deleteMyAccount(confirmation: string) {
  return request<{
    deleted: boolean;
    deletion_status?: string;
    deletion_stage?: string;
    counts: Record<string, number>;
    supabase_sessions_revoked: boolean;
    supabase_identity_deleted: boolean;
    teacher_owned_group_policy: string;
  }>('/api/users/me', {
    method: 'DELETE',
    body: JSON.stringify({ confirmation }),
  });
}

export function resetDemoData() {
  return request<{ reset: boolean; cleared: Record<string, number>; sessions: number }>('/api/admin/demo-data/reset', { method: 'POST' });
}

export function repairDemoData() {
  return request<{ repaired: boolean; reason?: string; cleared?: Record<string, number>; sessions?: number }>('/api/admin/demo-data/repair', { method: 'POST' });
}
