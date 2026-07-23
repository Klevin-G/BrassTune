import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { shouldShowCloudAudioExport } from '../components/ExportButtons';
import {
  invalidRangeOwnerTransition,
  ProgressRangeControls,
  progressDataBelongsToOwner,
  progressDataOwnerKey,
  validateProgressRange,
} from './ProgressPage';
import { classifySessionReviewError } from './SessionReviewPage';
import { resolveDeleteDialogReturnTarget, resolvePostDeleteFocusTarget } from './SessionsPage';
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
