import { describe, expect, it } from 'vitest';
import { appRouteAccessState } from '../App';
import { practiceLibraryGateState } from './PracticeLibraryContext';

describe('restored-session identity recovery gates', () => {
  it('allows a valid session without a profile to reach the recovery provider', () => {
    expect(appRouteAccessState({
      loading: false,
      hasAuthSession: true,
      isSignedIn: false,
      guestMode: false,
    })).toBe('allow');
  });

  it('shows recovery before checking whether an account practice owner is ready', () => {
    expect(practiceLibraryGateState({
      loading: false,
      hasAuthSession: true,
      hasProfile: false,
      ownerReady: false,
    })).toBe('recovery');
  });

  it('keeps unresolved session restoration and ordinary anonymous access separate', () => {
    expect(appRouteAccessState({
      loading: true,
      hasAuthSession: false,
      isSignedIn: false,
      guestMode: false,
    })).toBe('loading');
    expect(appRouteAccessState({
      loading: false,
      hasAuthSession: false,
      isSignedIn: false,
      guestMode: false,
    })).toBe('redirect');
    expect(practiceLibraryGateState({
      loading: false,
      hasAuthSession: false,
      hasProfile: false,
      ownerReady: true,
    })).toBe('ready');
  });
});
