import type { InstrumentProfile, NoteEvent, NoteStats, PitchFrame, PracticePlan, PracticeSession, ProgressMetrics, Recommendation } from '../domain/types';

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? '';

export interface DateRangeParams {
  date_from?: string;
  date_to?: string;
}

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: { 'Content-Type': 'application/json', ...(options?.headers ?? {}) },
    ...options,
  });
  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || `Request failed: ${response.status}`);
  }
  return response.json() as Promise<T>;
}

export const exportUrl = (path: string) => `${API_BASE}${path}`;

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
  return request<{ id: number; name: string; role: string; primary_instrument_id: string }>('/api/users/current');
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

export function stopSession(sessionId: number) {
  return request<PracticeSession>(`/api/sessions/${sessionId}/stop`, { method: 'POST' });
}

export function listSessions() {
  return request<PracticeSession[]>('/api/sessions');
}

export function getSession(sessionId: string | number) {
  return request<PracticeSession & { samples_count: number; note_events: NoteEvent[] }>(`/api/sessions/${sessionId}`);
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

export function getEnsembleSummary() {
  return request<any>('/api/ensemble/summary');
}

export function getEnsembleReport() {
  return request<any>('/api/ensemble/report');
}

export function clearLocalSessions() {
  return request<{ cleared: Record<string, number> }>('/api/admin/sessions/clear', { method: 'POST' });
}

export function resetDemoData() {
  return request<{ reset: boolean; cleared: Record<string, number>; sessions: number }>('/api/admin/demo-data/reset', { method: 'POST' });
}

export function repairDemoData() {
  return request<{ repaired: boolean; reason?: string; cleared?: Record<string, number>; sessions?: number }>('/api/admin/demo-data/repair', { method: 'POST' });
}
