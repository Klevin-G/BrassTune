import { describe, expect, it, vi } from 'vitest';
import {
  readVerifiedPracticeNamespace,
  startOAuthProviderSignIn,
  transitionToGuest,
  verifiedPracticeNamespaceKey,
  writeVerifiedPracticeNamespace,
} from './AuthContext';
import { practiceLibraryGateState } from './PracticeLibraryContext';

describe('guest session transition', () => {
  it('clears an unresolved authenticated session before guest navigation can continue', async () => {
    const events: string[] = [];
    const account = { hasAuthSession: true, profile: null as null };

    await transitionToGuest({
      hasAuthSession: account.hasAuthSession,
      clearInMemoryAccount: () => {
        account.hasAuthSession = false;
        account.profile = null;
        events.push('account-cleared');
      },
      signOutLocal: async () => {
        events.push('sign-out-started');
        await Promise.resolve();
        events.push('sign-out-finished');
        return { error: null };
      },
      clearPersistedSession: vi.fn(),
      activateGuest: () => events.push('guest-active'),
      reportError: vi.fn(),
    });
    events.push('navigate');

    expect(account.hasAuthSession).toBe(false);
    expect(practiceLibraryGateState({
      loading: false,
      hasAuthSession: account.hasAuthSession,
      hasProfile: Boolean(account.profile),
      ownerReady: true,
    })).toBe('ready');
    expect(events).toEqual([
      'account-cleared',
      'sign-out-started',
      'sign-out-finished',
      'guest-active',
      'navigate',
    ]);
  });

  it('falls back to clearing persisted auth data and represents the recoverable sign-out error', async () => {
    const events: string[] = [];
    const reportError = vi.fn();

    await transitionToGuest({
      hasAuthSession: true,
      clearInMemoryAccount: () => events.push('account-cleared'),
      signOutLocal: async () => ({ error: new Error('network request failed') }),
      clearPersistedSession: () => events.push('storage-cleared'),
      activateGuest: () => events.push('guest-active'),
      reportError,
    });

    expect(events).toEqual(['account-cleared', 'storage-cleared', 'guest-active']);
    expect(reportError).toHaveBeenCalledWith(
      'Account access could not reach the server. Check your connection and try again.',
    );
  });

  it('does not enter guest mode when both provider and persisted-session cleanup fail', async () => {
    const activateGuest = vi.fn();
    const reportError = vi.fn();

    await expect(transitionToGuest({
      hasAuthSession: true,
      clearInMemoryAccount: vi.fn(),
      signOutLocal: async () => ({ error: new Error('network request failed') }),
      clearPersistedSession: () => {
        throw new Error('storage unavailable');
      },
      activateGuest,
      reportError,
    })).rejects.toThrow('browser could not clear');

    expect(activateGuest).not.toHaveBeenCalled();
    expect(reportError).toHaveBeenCalledWith(
      'This browser could not clear the saved account session. Try again or clear BrassTune site data.',
    );
  });

  it('keeps an existing guest transition quick when no account session exists', async () => {
    const clearInMemoryAccount = vi.fn();
    const signOutLocal = vi.fn();
    const activateGuest = vi.fn();

    await transitionToGuest({
      hasAuthSession: false,
      clearInMemoryAccount,
      signOutLocal,
      clearPersistedSession: vi.fn(),
      activateGuest,
      reportError: vi.fn(),
    });

    expect(clearInMemoryAccount).not.toHaveBeenCalled();
    expect(signOutLocal).not.toHaveBeenCalled();
    expect(activateGuest).toHaveBeenCalledOnce();
  });
});

describe('verified local practice namespace cache', () => {
  it('restores only the namespace stored for the exact verified auth subject', () => {
    const values = new Map<string, string>();
    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => values.set(key, value),
    };

    expect(writeVerifiedPracticeNamespace(storage, 'subject-a', 42)).toBe('account:42');
    expect(readVerifiedPracticeNamespace(storage, 'subject-a')).toBe('account:42');
    expect(readVerifiedPracticeNamespace(storage, 'subject-b')).toBeNull();
    expect(values.has(verifiedPracticeNamespaceKey('subject-a'))).toBe(true);
  });

  it('rejects malformed, cross-subject, oversized, and extra-field cache values', () => {
    const values = new Map<string, string>();
    const storage = { getItem: (key: string) => values.get(key) ?? null };
    const key = verifiedPracticeNamespaceKey('subject-a');

    values.set(key, JSON.stringify({ version: 1, subject: 'subject-b', ownerId: 'account:42' }));
    expect(readVerifiedPracticeNamespace(storage, 'subject-a')).toBeNull();
    values.set(key, JSON.stringify({ version: 1, subject: 'subject-a', ownerId: 'guest' }));
    expect(readVerifiedPracticeNamespace(storage, 'subject-a')).toBeNull();
    values.set(key, JSON.stringify({ version: 1, subject: 'subject-a', ownerId: 'account:42', injected: true }));
    expect(readVerifiedPracticeNamespace(storage, 'subject-a')).toBeNull();
    expect(readVerifiedPracticeNamespace(storage, 'x'.repeat(201))).toBeNull();
  });
});

describe('social OAuth provider launch', () => {
  it('starts Google and Apple with the exact allow-listed PKCE callback URL', async () => {
    const signInWithOAuth = vi.fn().mockResolvedValue({ error: null });

    await startOAuthProviderSignIn({ signInWithOAuth }, 'google', 'https://brasstune.test');
    await startOAuthProviderSignIn({ signInWithOAuth }, 'apple', 'https://brasstune.test');

    expect(signInWithOAuth).toHaveBeenNthCalledWith(1, {
      provider: 'google',
      options: {
        redirectTo: 'https://brasstune.test/auth/callback',
        scopes: 'openid email profile',
        queryParams: { prompt: 'select_account' },
      },
    });
    expect(signInWithOAuth).toHaveBeenNthCalledWith(2, {
      provider: 'apple',
      options: {
        redirectTo: 'https://brasstune.test/auth/callback',
      },
    });
  });

  it('surfaces provider launch errors for localized recoverable handling', async () => {
    const failure = new Error('network request failed');
    await expect(startOAuthProviderSignIn({
      signInWithOAuth: vi.fn().mockResolvedValue({ error: failure }),
    }, 'google', 'https://brasstune.test')).rejects.toBe(failure);
  });
});
