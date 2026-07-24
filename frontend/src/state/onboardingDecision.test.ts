import { describe, expect, it } from 'vitest';
import {
  MAX_REFERENCE_PITCH,
  MIN_REFERENCE_PITCH,
  accountOnboardingDecision,
  clampReferencePitch,
  guestOnboardingDecision,
} from './AppSettingsContext';

describe('account onboarding decisions', () => {
  it('waits while auth or the backend profile is still restoring', () => {
    expect(accountOnboardingDecision({
      authLoading: true,
      hasAuthSession: true,
      isSignedIn: false,
      onboardingCompletedAt: null,
    })).toBeNull();
    expect(accountOnboardingDecision({
      authLoading: false,
      hasAuthSession: true,
      isSignedIn: false,
      onboardingCompletedAt: null,
    })).toBeNull();
  });

  it('opens for a restored account whose backend completion is null', () => {
    expect(accountOnboardingDecision({
      authLoading: false,
      hasAuthSession: true,
      isSignedIn: true,
      onboardingCompletedAt: null,
    })).toEqual({ completed: false, open: true });
  });

  it('stays closed for a restored account completed by the backend', () => {
    expect(accountOnboardingDecision({
      authLoading: false,
      hasAuthSession: true,
      isSignedIn: true,
      onboardingCompletedAt: '2026-07-16T12:00:00Z',
    })).toEqual({ completed: true, open: false });
  });
});

describe('guest onboarding decisions', () => {
  it('does not let a stale legacy completion suppress an unset guest setup', () => {
    // A missing guest key is the explicit first-use/reset state. The legacy
    // key remains available for older app releases, but is not guest state.
    expect(guestOnboardingDecision(null)).toEqual({ completed: false, open: true });
  });

  it('only treats a completed guest setup as complete', () => {
    expect(guestOnboardingDecision('false')).toEqual({ completed: false, open: true });
    expect(guestOnboardingDecision('true')).toEqual({ completed: true, open: false });
  });
});

describe('reference pitch bounds', () => {
  it('clamps finite values to the supported A4 range', () => {
    expect(clampReferencePitch(100)).toBe(MIN_REFERENCE_PITCH);
    expect(clampReferencePitch(440)).toBe(440);
    expect(clampReferencePitch(1000)).toBe(MAX_REFERENCE_PITCH);
  });

  it('rejects non-finite values', () => {
    expect(clampReferencePitch(Number.NaN)).toBeNull();
    expect(clampReferencePitch(Number.POSITIVE_INFINITY)).toBeNull();
  });
});
