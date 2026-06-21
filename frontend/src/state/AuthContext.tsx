import type { Session, User } from '@supabase/supabase-js';
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { deleteMyAccount, getCurrentUser, setAuthTokenProvider } from '../api/client';
import { apiBase } from '../api/runtimeConfig';
import { supabase, supabaseConfigured } from '../lib/supabase';

interface BackendProfile {
  id: number;
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
  isSignedIn: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (payload: SignUpPayload) => Promise<void>;
  signInWithGoogle: () => Promise<void>;
  signInWithApple: () => Promise<void>;
  requestPasswordReset: (email: string) => Promise<void>;
  updatePassword: (password: string) => Promise<void>;
  signOut: () => Promise<void>;
  deleteAccount: (confirmation: string) => Promise<void>;
  refreshProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);
const accountsDisabledMessage = 'Accounts are not enabled in this build yet. You can still use guest practice.';

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
  const [loading, setLoading] = useState(true);

  const loadProfile = useCallback(async (activeSession: Session | null) => {
    if (supabase && !activeSession) {
      setProfile(null);
      return;
    }
    if (!supabase && apiBase()) {
      setProfile(null);
      return;
    }
    try {
      const current = await getCurrentUser();
      setProfile(current);
    } catch {
      setProfile(null);
    }
  }, []);

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
        setSession(data.session ?? null);
        setUser(data.session?.user ?? null);
        loadProfile(data.session ?? null).finally(() => setLoading(false));
      })
      .catch(() => {
        setSession(null);
        setUser(null);
        setProfile(null);
        setLoading(false);
      });
    const { data: subscription } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setUser(nextSession?.user ?? null);
      loadProfile(nextSession);
    });
    return () => {
      subscription.subscription.unsubscribe();
      setAuthTokenProvider(null);
    };
  }, [loadProfile]);

  const signIn = useCallback(async (email: string, password: string) => {
    if (!supabase) throw new Error(accountsDisabledMessage);
    try {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
      await refreshProfile();
    } catch (error) {
      throwFriendlyAuthError(error);
    }
  }, [refreshProfile]);

  const signUp = useCallback(async (payload: SignUpPayload) => {
    if (!supabase) throw new Error(accountsDisabledMessage);
    try {
      const { error } = await supabase.auth.signUp({
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
      await refreshProfile();
    } catch (error) {
      throwFriendlyAuthError(error);
    }
  }, [refreshProfile]);

  const signInWithApple = useCallback(async () => {
    if (!supabase) throw new Error(accountsDisabledMessage);
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'apple',
        options: {
          redirectTo: `${window.location.origin}/auth/callback`,
        },
      });
      if (error) throw error;
    } catch (error) {
      throwFriendlyAuthError(error);
    }
  }, []);

  const signInWithGoogle = useCallback(async () => {
    if (!supabase) throw new Error(accountsDisabledMessage);
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: `${window.location.origin}/auth/callback`,
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
    if (supabase) {
      await supabase.auth.signOut();
    }
    setSession(null);
    setUser(null);
    if (supabase) {
      setProfile(null);
    } else {
      await loadProfile(null);
    }
  }, [loadProfile]);

  const deleteAccount = useCallback(async (confirmation: string) => {
    await deleteMyAccount(confirmation);
    if (supabase) {
      await supabase.auth.signOut();
    }
    setSession(null);
    setUser(null);
    setProfile(null);
  }, []);

  const value = useMemo<AuthState>(
    () => ({
      configured: supabaseConfigured,
      loading,
      session,
      user,
      profile,
      isSignedIn: Boolean(session),
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
    [deleteAccount, loading, profile, refreshProfile, requestPasswordReset, session, signIn, signInWithApple, signInWithGoogle, signOut, signUp, updatePassword, user],
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
