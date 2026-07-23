import type { Session, User } from '@supabase/supabase-js';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { deleteMyAccount, getCurrentUser, setAuthTokenProvider } from '../api/client';
import { apiBase } from '../api/runtimeConfig';
import { authProviders, supabase, supabaseConfigured } from '../lib/supabase';

interface BackendProfile {
  id: number;
  supabase_user_id?: string | null;
  username: string | null;
  display_name: string;
  email: string | null;
  role: string;
  primary_instrument_id: string;
  onboarding_completed_at?: string | null;
}

interface SignUpPayload {
  email: string;
  password: string;
  username: string;
  displayName: string;
  primaryInstrumentId: string;
}

interface AuthState {
  configured: boolean;
  loading: boolean;
  session: Session | null;
  user: User | null;
  profile: BackendProfile | null;
  profileError: string | null;
  hasAuthSession: boolean;
  isSignedIn: boolean;
  cloudReady: boolean;
  guestMode: boolean;
  guestEntrySequence: number;
  providers: typeof authProviders;
  continueAsGuest: () => void;
  exitGuest: () => void;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (payload: SignUpPayload) => Promise<void>;
  signInWithGoogle: (redirectTo?: string) => Promise<void>;
  signInWithApple: (redirectTo?: string) => Promise<void>;
  requestPasswordReset: (email: string) => Promise<void>;
  updatePassword: (password: string) => Promise<void>;
  signOut: () => Promise<void>;
  deleteAccount: (confirmation: string) => Promise<{ deletionStatus?: string }>;
  refreshProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);
const accountsDisabledMessage = 'Accounts are not enabled in this build yet. You can still use guest practice.';
const guestAccessKey = 'brasstune.guestAccess';

export function friendlyAuthError(error: unknown) {
  const raw = error instanceof Error ? error.message : typeof error === 'string' ? error : '';
  const message = raw.trim();
  const lower = message.toLowerCase();
  if (!message) return 'Account access is unavailable right now. You can still use guest practice.';
  if (lower.includes('invalid login credentials') || lower.includes('invalid credentials')) {
    return 'Email or password did not match. Check your details and try again.';
  }
  if (lower.includes('already registered') || lower.includes('already exists') || lower.includes('duplicate')) {
    return 'An account already exists for that email. Sign in or reset your password.';
  }
  if (lower.includes('weak password') || lower.includes('password should')) {
    return 'Choose a stronger password and try again.';
  }
  if (lower.includes('email not confirmed') || lower.includes('confirmation')) {
    return 'Confirm your email before signing in, then try again.';
  }
  if (lower.includes('expired') || lower.includes('invalid refresh token') || lower.includes('session')) {
    return 'That account link or session expired. Request a new link and try again.';
  }
  if (lower.includes('cancel') || lower.includes('popup closed')) {
    return 'Sign-in was cancelled. You can try again or continue as guest.';
  }
  if (lower.includes('network') || lower.includes('fetch') || lower.includes('failed to send')) {
    return 'Account access could not reach the server. Check your connection and try again.';
  }
  if (
    lower.includes('supabase') ||
    lower.includes('env') ||
    lower.includes('api key') ||
    lower.includes('authapierror') ||
    lower.includes('database') ||
    lower.includes('provider') ||
    lower.includes('oauth') ||
    lower.includes('redirect') ||
    lower.includes('jwks') ||
    lower.includes('jwt') ||
    lower.includes('schema') ||
    lower.includes('sql') ||
    lower.includes('relation') ||
    lower.includes('http://') ||
    lower.includes('https://') ||
    lower.includes('stack') ||
    message.length > 180
  ) {
    return 'Account access is unavailable right now. You can still use guest practice.';
  }
  return message;
}

function throwFriendlyAuthError(error: unknown): never {
  throw new Error(friendlyAuthError(error));
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<BackendProfile | null>(null);
  const [profileError, setProfileError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [guestMode, setGuestMode] = useState(() => localStorage.getItem(guestAccessKey) === 'true');
  const [guestEntrySequence, setGuestEntrySequence] = useState(0);
  const profileRequestId = useRef(0);
  const profileRef = useRef(profile);
  const profileUserIdRef = useRef<string | null>(null);
  const sessionUserIdRef = useRef<string | null>(null);

  const clearProfileState = useCallback((clearError = true) => {
    profileRef.current = null;
    profileUserIdRef.current = null;
    setProfile(null);
    if (clearError) setProfileError(null);
  }, []);

  const resetAccountState = useCallback(() => {
    profileRequestId.current += 1;
    sessionUserIdRef.current = null;
    setSession(null);
    setUser(null);
    clearProfileState();
  }, [clearProfileState]);

  const adoptSession = useCallback((nextSession: Session | null) => {
    const nextUserId = nextSession?.user.id ?? null;
    if (sessionUserIdRef.current !== nextUserId) {
      profileRequestId.current += 1;
      clearProfileState();
      sessionUserIdRef.current = nextUserId;
    }
    setSession(nextSession);
    setUser(nextSession?.user ?? null);
    if (nextSession) {
      localStorage.removeItem(guestAccessKey);
      setGuestMode(false);
    }
  }, [clearProfileState]);

  const loadProfile = useCallback(async (activeSession: Session | null, options: { required?: boolean } = {}) => {
    const requestId = ++profileRequestId.current;
    if (supabase && !activeSession) {
      clearProfileState();
      return null;
    }
    if (!supabase && apiBase()) {
      clearProfileState();
      return null;
    }
    try {
      const current = await getCurrentUser();
      if (supabase && activeSession) {
        const { data } = await supabase.auth.getSession();
        if (requestId !== profileRequestId.current || data.session?.user.id !== activeSession.user.id) {
          return null;
        }
        if (current.supabase_user_id && current.supabase_user_id !== activeSession.user.id) {
          throw new Error('Account profile did not match the active session.');
        }
      } else if (requestId !== profileRequestId.current) {
        return null;
      }
      profileRef.current = current;
      profileUserIdRef.current = activeSession?.user.id ?? null;
      setProfile(current);
      setProfileError(null);
      return current;
    } catch (error) {
      if (requestId !== profileRequestId.current) {
        return null;
      }
      const message = friendlyAuthError(error);
      setProfileError(message);
      const requestedUserId = activeSession?.user.id ?? null;
      if (options.required || !profileRef.current || profileUserIdRef.current !== requestedUserId) {
        clearProfileState(false);
      }
      if (options.required) {
        throw new Error(message);
      }
      return null;
    }
  }, [clearProfileState]);

  const refreshProfile = useCallback(async () => {
    await loadProfile(session);
  }, [loadProfile, session]);

  useEffect(() => {
    setAuthTokenProvider(async () => {
      if (!supabase) return null;
      const { data } = await supabase.auth.getSession();
      return data.session?.access_token ?? null;
    });
    if (!supabase) {
      loadProfile(null).finally(() => setLoading(false));
      return () => setAuthTokenProvider(null);
    }
    supabase.auth
      .getSession()
      .then(({ data }) => {
        adoptSession(data.session ?? null);
        loadProfile(data.session ?? null).finally(() => setLoading(false));
      })
      .catch(() => {
        resetAccountState();
        setLoading(false);
      });
    const { data: subscription } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      adoptSession(nextSession);
      loadProfile(nextSession);
    });
    return () => {
      subscription.subscription.unsubscribe();
      setAuthTokenProvider(null);
    };
  }, [adoptSession, loadProfile, resetAccountState]);

  const signIn = useCallback(async (email: string, password: string) => {
    if (!supabase) throw new Error(accountsDisabledMessage);
    try {
      const { data, error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
      adoptSession(data.session ?? null);
      const loadedProfile = await loadProfile(data.session ?? null, { required: Boolean(data.session) });
      if (data.session && !loadedProfile) {
        throw new Error('Account profile is not ready yet. Try again in a moment.');
      }
      localStorage.removeItem(guestAccessKey);
      setGuestMode(false);
    } catch (error) {
      await supabase.auth.signOut({ scope: 'local' }).catch(() => undefined);
      resetAccountState();
      throwFriendlyAuthError(error);
    }
  }, [adoptSession, loadProfile, resetAccountState]);

  const signUp = useCallback(async (payload: SignUpPayload) => {
    if (!supabase) throw new Error(accountsDisabledMessage);
    try {
      const { data, error } = await supabase.auth.signUp({
        email: payload.email,
        password: payload.password,
        options: {
          data: {
            username: payload.username,
            display_name: payload.displayName,
            primary_instrument_id: payload.primaryInstrumentId,
          },
        },
      });
      if (error) throw error;
      adoptSession(data.session ?? null);
      const loadedProfile = await loadProfile(data.session ?? null, { required: Boolean(data.session) });
      if (data.session && !loadedProfile) {
        throw new Error('Account profile is not ready yet. Try again in a moment.');
      }
      localStorage.removeItem(guestAccessKey);
      setGuestMode(false);
    } catch (error) {
      await supabase.auth.signOut({ scope: 'local' }).catch(() => undefined);
      resetAccountState();
      throwFriendlyAuthError(error);
    }
  }, [adoptSession, loadProfile, resetAccountState]);

  const signInWithApple = useCallback(async (redirectTo = `${window.location.origin}/auth/callback`) => {
    if (!supabase) throw new Error(accountsDisabledMessage);
    if (!authProviders.apple) throw new Error('Apple sign-in is not available in this release.');
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'apple',
        options: {
          redirectTo,
        },
      });
      if (error) throw error;
    } catch (error) {
      throwFriendlyAuthError(error);
    }
  }, []);

  const signInWithGoogle = useCallback(async (redirectTo = `${window.location.origin}/auth/callback`) => {
    if (!supabase) throw new Error(accountsDisabledMessage);
    if (!authProviders.google) throw new Error('Google sign-in is not available in this release.');
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo,
          scopes: 'openid email profile',
          queryParams: {
            prompt: 'select_account',
          },
        },
      });
      if (error) throw error;
    } catch (error) {
      throwFriendlyAuthError(error);
    }
  }, []);

  const requestPasswordReset = useCallback(async (email: string) => {
    if (!supabase) throw new Error(accountsDisabledMessage);
    try {
      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}/auth/reset-password`,
      });
      if (error) throw error;
    } catch (error) {
      throwFriendlyAuthError(error);
    }
  }, []);

  const updatePassword = useCallback(async (password: string) => {
    if (!supabase) throw new Error(accountsDisabledMessage);
    try {
      const { error } = await supabase.auth.updateUser({ password });
      if (error) throw error;
    } catch (error) {
      throwFriendlyAuthError(error);
    }
  }, []);

  const signOut = useCallback(async () => {
    try {
      if (supabase) {
        const { error } = await supabase.auth.signOut({ scope: 'local' });
        if (error) throw new Error(friendlyAuthError(error));
      }
    } finally {
      localStorage.removeItem(guestAccessKey);
      setGuestMode(false);
      resetAccountState();
      if (!supabase) {
        await loadProfile(null);
      }
    }
  }, [loadProfile, resetAccountState]);

  const deleteAccount = useCallback(async (confirmation: string) => {
    const result = await deleteMyAccount(confirmation);
    if (supabase) {
      await supabase.auth.signOut({ scope: 'local' }).catch(() => undefined);
    }
    localStorage.removeItem(guestAccessKey);
    setGuestMode(false);
    resetAccountState();
    return { deletionStatus: result.deletion_status };
  }, [resetAccountState]);

  const continueAsGuest = useCallback(() => {
    localStorage.setItem(guestAccessKey, 'true');
    setGuestMode(true);
    setGuestEntrySequence((value) => value + 1);
  }, []);

  const exitGuest = useCallback(() => {
    localStorage.removeItem(guestAccessKey);
    setGuestMode(false);
  }, []);

  const value = useMemo<AuthState>(
    () => ({
      configured: supabaseConfigured,
      loading,
      session,
      user,
      profile,
      profileError,
      hasAuthSession: Boolean(session),
      isSignedIn: Boolean(session && profile),
      cloudReady: Boolean(session && profile),
      guestMode,
      guestEntrySequence,
      providers: authProviders,
      continueAsGuest,
      exitGuest,
      signIn,
      signUp,
      signInWithGoogle,
      signInWithApple,
      requestPasswordReset,
      updatePassword,
      signOut,
      deleteAccount,
      refreshProfile,
    }),
    [continueAsGuest, deleteAccount, exitGuest, guestEntrySequence, guestMode, loading, profile, profileError, refreshProfile, requestPasswordReset, session, signIn, signInWithApple, signInWithGoogle, signOut, signUp, updatePassword, user],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}
