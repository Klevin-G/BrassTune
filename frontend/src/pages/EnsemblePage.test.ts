import { describe, expect, it, vi } from 'vitest';
import type { EnsembleRosterStudent } from '../api/client';
import {
  acquireSynchronousClassGuard,
  classResourcePlan,
  classRosterKey,
  classShareScope,
  classViewMode,
  classViewerNeedsSharingConsent,
  copyClassShareText,
  filterAndSortClassRoster,
  showsTopLevelClassRetry,
} from './EnsemblePage';

function rosterStudent(overrides: Partial<EnsembleRosterStudent> = {}): EnsembleRosterStudent {
  const window = {
    sessions_count: 1,
    practice_minutes: 10,
    average_abs_cents: 8,
    in_tune_percentage: 80,
    last_practice_at: '2026-08-22T12:00:00Z',
  };
  return {
    member_id: 1,
    roster_row_id: 'roster-row-1',
    user_id: 10,
    username: 'avery',
    display_name: 'Avery Reed',
    instrument_id: 'trumpet',
    status: 'active',
    role_in_group: 'student',
    sessions_count: 3,
    practice_minutes: 30,
    average_abs_cents: 8,
    in_tune_percentage: 80,
    last_practice_at: window.last_practice_at,
    lifetime: { ...window, sessions_count: 3, practice_minutes: 30 },
    current_7d: window,
    previous_7d: { ...window, practice_minutes: 5 },
    delta: { sessions_count: 0, practice_minutes: 5, average_abs_cents: 0, in_tune_percentage: 0 },
    inactivity: { state: 'active_this_week', days_since_last_practice: 2, last_practice_at: window.last_practice_at },
    ...overrides,
  };
}

describe('class share clipboard behavior', () => {
  it('reports success only after the clipboard write resolves', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    await expect(copyClassShareText({ writeText }, 'BRASS1')).resolves.toBe(true);
    expect(writeText).toHaveBeenCalledWith('BRASS1');
  });

  it('requires a manual fallback when clipboard access is missing or rejects', async () => {
    await expect(copyClassShareText(undefined, 'BRASS1')).resolves.toBe(false);
    await expect(copyClassShareText({ writeText: vi.fn().mockRejectedValue(new Error('denied')) }, 'BRASS1')).resolves.toBe(false);
  });

  it('scopes manual fallback text to the exact active class and join code', () => {
    expect(classShareScope({ id: 7, join_code: 'brass1' })).toBe('7:BRASS1');
    expect(classShareScope({ id: 8, join_code: 'brass1' })).toBe('8:BRASS1');
    expect(classShareScope({ id: 7, join_code: 'brass2' })).toBe('7:BRASS2');
    expect(classShareScope({ id: 7, join_code: '' })).toBeNull();
  });
});

describe('capability-driven class views', () => {
  it('loads self progress only for a student view', () => {
    const group = { viewer_role: 'student' as const, viewer_can_manage: false, viewer_can_view_roster: false, viewer_can_view_class_analytics: false, viewer_has_aggregate_sharing_consent: true };
    expect(classViewMode(group)).toBe('student');
    expect(classResourcePlan(group)).toEqual({ analytics: false, roster: false, ownProgress: true });
  });

  it('gives assistants redacted analytics behavior without management', () => {
    const group = { viewer_role: 'assistant' as const, viewer_can_manage: false, viewer_can_view_roster: true, viewer_can_view_class_analytics: true, viewer_has_aggregate_sharing_consent: true };
    expect(classViewMode(group)).toBe('assistant');
    expect(classResourcePlan(group)).toEqual({ analytics: true, roster: true, ownProgress: false });
  });

  it('gates legacy student and assistant resources on explicit membership consent', () => {
    const legacyAssistant = { viewer_role: 'assistant' as const, viewer_can_manage: false, viewer_can_view_roster: true, viewer_can_view_class_analytics: true, viewer_has_aggregate_sharing_consent: false };
    expect(classViewerNeedsSharingConsent(legacyAssistant)).toBe(true);
    expect(classResourcePlan(legacyAssistant)).toEqual({ analytics: false, roster: false, ownProgress: false });
    expect(classViewerNeedsSharingConsent({ ...legacyAssistant, viewer_has_aggregate_sharing_consent: true })).toBe(false);
  });

  it('filters owner rosters by search, instrument, status, and inactivity, then sorts weekly minutes', () => {
    const rows = [
      rosterStudent(),
      rosterStudent({
        member_id: 2,
        username: 'mia',
        display_name: 'Mia Chen',
        instrument_id: 'horn',
        current_7d: { ...rosterStudent().current_7d, practice_minutes: 42 },
        inactivity: { state: 'active_today', days_since_last_practice: 0, last_practice_at: '2026-08-24T12:00:00Z' },
      }),
      rosterStudent({
        member_id: 3,
        username: 'noah',
        display_name: 'Noah Jones',
        instrument_id: 'horn',
        current_7d: { ...rosterStudent().current_7d, practice_minutes: 0 },
        inactivity: { state: 'inactive_7d', days_since_last_practice: 9, last_practice_at: '2026-08-15T12:00:00Z' },
      }),
    ];

    expect(filterAndSortClassRoster(rows, {
      search: '', instrument: 'horn', inactivity: 'active_week', status: 'active', sort: 'weekly_minutes', locale: 'en',
    }).map((student) => student.display_name)).toEqual(['Mia Chen']);
    expect(filterAndSortClassRoster(rows, {
      search: 'noah', instrument: 'all', inactivity: 'needs_attention', status: 'all', sort: 'name', locale: 'en',
    }).map((student) => student.display_name)).toEqual(['Noah Jones']);
  });

  it('shows top-level retry only for the current failed account and acquires rotate synchronously once', () => {
    expect(showsTopLevelClassRetry('account-a', 'account-a', 'error')).toBe(true);
    expect(showsTopLevelClassRetry('account-a', 'account-b', 'error')).toBe(false);
    const guard = { current: false };
    expect(acquireSynchronousClassGuard(guard)).toBe(true);
    expect(acquireSynchronousClassGuard(guard)).toBe(false);
  });

  it('uses opaque roster row IDs before legacy identity fallbacks', () => {
    const first = rosterStudent({ roster_row_id: 'opaque-a', display_name: 'Duplicate', instrument_id: 'horn' });
    const second = rosterStudent({ roster_row_id: 'opaque-b', display_name: 'Duplicate', instrument_id: 'horn' });
    expect(classRosterKey(first, 0)).toBe('opaque-a');
    expect(classRosterKey(second, 1)).toBe('opaque-b');
  });
});
