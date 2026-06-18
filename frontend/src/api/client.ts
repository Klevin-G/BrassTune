import type { InstrumentProfile, NoteEvent, NoteStats, PitchFrame, PracticePlan, PracticeSession, ProgressMetrics, Recommendation } from '../domain/types';

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? '';
const WS_BASE = import.meta.env.VITE_WS_BASE_URL ?? '';
let authTokenProvider: (() => Promise<string | null>) | null = null;

export interface DateRangeParams {
  date_from?: string;
  date_to?: string;
}

export function setAuthTokenProvider(provider: (() => Promise<string | null>) | null) {
  authTokenProvider = provider;
}

async function authHeaders(): Promise<Record<string, string>> {
  const token = authTokenProvider ? await authTokenProvider() : null;
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const body = options?.body;
  const isFormBody = typeof FormData !== 'undefined' && body instanceof FormData;
  const isBlobBody = typeof Blob !== 'undefined' && body instanceof Blob;
  const headers = {
    ...(isFormBody || isBlobBody ? {} : { 'Content-Type': 'application/json' }),
    ...(await authHeaders()),
    ...(options?.headers ?? {}),
  };
  const response = await fetch(`${API_BASE}${path}`, {
    headers,
    ...options,
  });
  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || `Request failed: ${response.status}`);
  }
  return response.json() as Promise<T>;
}

export const exportUrl = (path: string) => `${API_BASE}${path}`;

export async function pitchWebSocketUrl() {
  const base = WS_BASE || `${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.host}`;
  const url = new URL('/ws/pitch', base);
  const token = authTokenProvider ? await authTokenProvider() : null;
  if (token) {
    url.searchParams.set('token', token);
  }
  return url.toString();
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

export function recordPitchFrames(sessionId: number, frames: PitchFrame[]) {
  return request<{ saved: number; rejected: number }>(`/api/sessions/${sessionId}/samples/batch`, {
    method: 'POST',
    body: JSON.stringify(frames),
  });
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
  const response = await fetch(`${API_BASE}${path}`, { headers: await authHeaders() });
  if (!response.ok) {
    throw new Error(await response.text());
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
  const response = await fetch(`${API_BASE}${path}`, { headers: await authHeaders() });
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

export function addEnsembleMemberByUsername(groupId: number, payload: { username: string; instrument_id: string; role_in_group?: string }) {
  return request<any>(`/api/ensemble/groups/${groupId}/members/by-username`, { method: 'POST', body: JSON.stringify(payload) });
}

export function updateEnsembleMember(groupId: number, memberId: number, payload: { instrument_id?: string; role_in_group?: string; status?: string }) {
  return request<any>(`/api/ensemble/groups/${groupId}/members/${memberId}`, { method: 'PATCH', body: JSON.stringify(payload) });
}

export function clearLocalSessions() {
  return request<{ cleared: Record<string, number> }>('/api/users/me/clear-sessions', { method: 'POST' });
}

export function deleteMyAccount(confirmation: string) {
  return request<{
    deleted: boolean;
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
