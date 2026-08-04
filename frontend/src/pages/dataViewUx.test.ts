import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { shouldShowCloudAudioExport } from '../components/ExportButtons';
import {
  invalidRangeOwnerTransition,
  ProgressRangeControls,
  progressDataBelongsToOwner,
  progressDataOwnerKey,
  validateProgressRange,
} from './ProgressPage';
import { classifySessionReviewError } from './SessionReviewPage';
import {
  deleteDialogMessageIds,
  executeSessionDeletion,
  resolveDeleteDialogReturnTarget,
  resolvePostDeleteFocusTarget,
  sessionAfterAudioDeletion,
  sessionAudioDeletionStatusId,
} from './SessionsPage';
import { LocaleProvider } from '../i18n/LocaleContext';

describe('recording and progress data-view safeguards', () => {
  it('distinguishes unavailable recordings from connection failures', () => {
    expect(classifySessionReviewError(new Error('That BrassTune item is not available for this account.'))).toBe('not-found');
    expect(classifySessionReviewError(new Error('Sign in to sync sessions and account features.'))).toBe('auth');
    expect(classifySessionReviewError(new Error('Failed to fetch'))).toBe('network');
  });

  it('never treats one account’s progress as another account’s data', () => {
    const accountA = progressDataOwnerKey(true, 17);
    const accountB = progressDataOwnerKey(true, 42);
    expect(progressDataBelongsToOwner(accountA, accountA)).toBe(true);
    expect(progressDataBelongsToOwner(accountA, accountB)).toBe(false);
    expect(progressDataBelongsToOwner(accountA, progressDataOwnerKey(false, null, true))).toBe(false);
  });

  it('keeps invalid custom-range controls mounted when account A switches to account B', () => {
    const accountA = progressDataOwnerKey(true, 17);
    const accountB = progressDataOwnerKey(true, 42);
    const range = { date_from: '2026-07-16', date_to: '2026-07-01' };
    const rangeError = validateProgressRange(range);
    const transition = invalidRangeOwnerTransition(accountA, accountB, Boolean(rangeError));

    expect(transition).toEqual({ dataOwnerKey: accountB, clearData: true });
    const markup = renderToStaticMarkup(createElement(LocaleProvider, null, createElement(ProgressRangeControls, {
      period: 'custom',
      range,
      rangeError,
      showHeading: false,
      onPeriodChange: () => undefined,
      onRangeChange: () => undefined,
    })));
    expect(markup.match(/type="date"/g)).toHaveLength(2);
    expect(markup).toContain('The start date must be on or before the end date.');
  });

  it('restores recording-delete focus to the visible More-options summary', () => {
    const summary = { focus: () => undefined } as unknown as HTMLElement;
    const details = {
      querySelector: (selector: string) => (selector === 'summary' ? summary : null),
    };
    const deleteButton = {
      closest: (selector: string) => (selector === 'details' ? details : null),
    } as unknown as HTMLElement;
    const detachedButton = { closest: () => null } as unknown as HTMLElement;

    expect(resolveDeleteDialogReturnTarget(deleteButton)).toBe(summary);
    expect(resolveDeleteDialogReturnTarget(detachedButton)).toBeNull();
  });

  it('moves keyboard focus past a removed recording to the next visible More-options summary', () => {
    let focused = false;
    const removedSummary = {
      isConnected: false,
      getAttribute: () => null,
      closest: () => null,
    } as unknown as HTMLElement;
    const nextSummary = {
      isConnected: true,
      getAttribute: () => null,
      closest: () => null,
      focus: () => {
        focused = true;
      },
    } as unknown as HTMLElement;
    const root = {
      querySelectorAll: (selector: string) => (selector === '.ps-overflow > summary' ? [nextSummary] : []),
      querySelector: () => null,
    } as unknown as Document;

    const target = resolvePostDeleteFocusTarget(removedSummary, root);
    target?.focus();
    expect(target).toBe(nextSummary);
    expect(focused).toBe(true);
  });

  it('falls back to the new-recording action when the deleted row was the last recording', () => {
    const removedSummary = {
      isConnected: false,
      getAttribute: () => null,
      closest: () => null,
    } as unknown as HTMLElement;
    const newRecording = {
      isConnected: true,
      getAttribute: () => null,
      closest: () => null,
    } as unknown as HTMLElement;
    const root = {
      querySelectorAll: () => [],
      querySelector: (selector: string) => (selector === '[data-delete-focus-fallback]' ? newRecording : null),
    } as unknown as Document;

    expect(resolvePostDeleteFocusTarget(removedSummary, root)).toBe(newRecording);
  });

  it('removes cloud audio metadata without removing the practice session', () => {
    const session = {
      id: 24,
      user_id: 7,
      instrument_id: 'trumpet',
      name: 'Long tones',
      started_at: '2026-08-04T12:00:00Z',
      ended_at: '2026-08-04T12:01:00Z',
      duration_seconds: 60,
      reference_pitch_hz: 440,
      notes_count: 20,
      average_signed_cents: 1,
      average_abs_cents: 4,
      in_tune_percentage: 91,
      audio_available: true,
      audio_mime_type: 'audio/webm',
      audio_duration_seconds: 60,
      audio_size_bytes: 1024,
      audio_uploaded_at: '2026-08-04T12:01:00Z',
      created_at: '2026-08-04T12:00:00Z',
    };

    expect(sessionAfterAudioDeletion(session)).toMatchObject({
      id: 24,
      notes_count: 20,
      audio_available: false,
      audio_mime_type: null,
      audio_duration_seconds: null,
      audio_size_bytes: null,
      audio_uploaded_at: null,
    });
  });

  it('uses distinct destructive-confirmation copy for cloud audio and preserves guest recording copy', () => {
    expect(deleteDialogMessageIds(false)).toEqual({
      title: 'sessions.deleteAudioTitle',
      body: 'sessions.deleteAudioBody',
      cancel: 'sessions.keepAudio',
    });
    expect(deleteDialogMessageIds(true)).toEqual({
      title: 'sessions.deleteTitle',
      body: 'sessions.deleteBody',
      cancel: 'sessions.keep',
    });
  });

  it('distinguishes immediate and deferred cloud-audio cleanup status', () => {
    expect(sessionAudioDeletionStatusId(false)).toBe('sessions.audioDeleted');
    expect(sessionAudioDeletionStatusId(true)).toBe('sessions.audioDeletePending');
  });

  it('deletes a guest session locally without invoking the cloud audio endpoint', async () => {
    const deleteGuestSession = vi.fn(() => true);
    const deleteCloudAudio = vi.fn();
    const detachReflections = vi.fn();
    const session = {
      id: -24,
      user_id: 0,
      instrument_id: 'trumpet',
      name: 'Guest long tones',
      started_at: '2026-08-04T12:00:00Z',
      ended_at: '2026-08-04T12:01:00Z',
      duration_seconds: 60,
      reference_pitch_hz: 440,
      notes_count: 20,
      average_signed_cents: 1,
      average_abs_cents: 4,
      in_tune_percentage: 91,
      guest_session: true,
      created_at: '2026-08-04T12:00:00Z',
    };

    await expect(executeSessionDeletion(session, { deleteGuestSession, deleteCloudAudio, detachReflections })).resolves.toEqual({
      type: 'guest-session-deleted',
      updatedSession: null,
    });
    expect(deleteGuestSession).toHaveBeenCalledWith(-24);
    expect(detachReflections).toHaveBeenCalledWith('-24');
    expect(deleteCloudAudio).not.toHaveBeenCalled();
  });

  it('deletes only cloud audio and retains the session results for immediate and deferred cleanup', async () => {
    const session = {
      id: 24,
      user_id: 7,
      instrument_id: 'trumpet',
      name: 'Long tones',
      started_at: '2026-08-04T12:00:00Z',
      ended_at: '2026-08-04T12:01:00Z',
      duration_seconds: 60,
      reference_pitch_hz: 440,
      notes_count: 20,
      average_signed_cents: 1,
      average_abs_cents: 4,
      in_tune_percentage: 91,
      audio_available: true,
      audio_mime_type: 'audio/webm',
      audio_duration_seconds: 60,
      audio_size_bytes: 1024,
      audio_uploaded_at: '2026-08-04T12:01:00Z',
      created_at: '2026-08-04T12:00:00Z',
    };
    const deleteGuestSession = vi.fn();
    const detachReflections = vi.fn();
    const deleteCloudAudio = vi.fn()
      .mockResolvedValueOnce({ deleted: true, cleanup_pending: false })
      .mockResolvedValueOnce({ deleted: true, cleanup_pending: true });

    const immediate = await executeSessionDeletion(session, { deleteGuestSession, deleteCloudAudio, detachReflections });
    const deferred = await executeSessionDeletion(session, { deleteGuestSession, deleteCloudAudio, detachReflections });

    expect(immediate).toMatchObject({ type: 'cloud-audio-deleted', cleanupPending: false, updatedSession: { id: 24, notes_count: 20, audio_available: false } });
    expect(deferred).toMatchObject({ type: 'cloud-audio-deleted', cleanupPending: true, updatedSession: { id: 24, notes_count: 20, audio_available: false } });
    expect(deleteCloudAudio).toHaveBeenCalledTimes(2);
    expect(deleteCloudAudio).toHaveBeenCalledWith(24);
    expect(deleteGuestSession).not.toHaveBeenCalled();
    expect(detachReflections).not.toHaveBeenCalled();
  });

  it('keeps the delete dialog open with an alert contract when cloud audio deletion fails', async () => {
    const failure = new Error('network failed');
    const result = await executeSessionDeletion({
      id: 24,
      user_id: 7,
      instrument_id: 'trumpet',
      name: 'Long tones',
      started_at: '2026-08-04T12:00:00Z',
      ended_at: '2026-08-04T12:01:00Z',
      duration_seconds: 60,
      reference_pitch_hz: 440,
      notes_count: 20,
      average_signed_cents: 1,
      average_abs_cents: 4,
      in_tune_percentage: 91,
      audio_available: true,
      created_at: '2026-08-04T12:00:00Z',
    }, {
      deleteGuestSession: vi.fn(),
      deleteCloudAudio: vi.fn().mockRejectedValue(failure),
      detachReflections: vi.fn(),
    });

    expect(result).toEqual({ type: 'failed', error: failure, keepDialogOpen: true, alertRole: 'alert' });
  });

  it('rejects a custom range whose start is after its end', () => {
    expect(validateProgressRange({ date_from: '2026-07-16', date_to: '2026-07-01' })).toBe(
      'The start date must be on or before the end date.',
    );
    expect(validateProgressRange({ date_from: '2026-07-01', date_to: '2026-07-16' })).toBeNull();
    expect(validateProgressRange({ date_from: '2026-07-01', date_to: '' })).toBeNull();
  });

  it('only offers cloud audio export when audio is available', () => {
    expect(shouldShowCloudAudioExport(true)).toBe(true);
    expect(shouldShowCloudAudioExport(false)).toBe(false);
    expect(shouldShowCloudAudioExport()).toBe(false);
  });
});
