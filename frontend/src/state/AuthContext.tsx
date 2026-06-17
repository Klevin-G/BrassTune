import type { Session, User } from '@supabase/supabase-js';
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { getCurrentUser, setAuthTokenProvider } from '../api/client';
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
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<BackendProfile | null>(null);
  const [loading, setLoading] = useState(true);

  const refreshProfile = useCallback(async () => {
    try {
      const current = await getCurrentUser();
      setProfile(current);
    } catch {
      setProfile(null);
    }
  }, []);

  useEffect(() => {
    setAuthTokenProvider(async () => {
      if (!supabase) return null;
      const { data } = await supabase.auth.getSession();
      return data.session?.access_token ?? null;
    });
    if (!supabase) {
      refreshProfile().finally(() => setLoading(false));
      return () => setAuthTokenProvider(null);
    }
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session ?? null);
      setUser(data.session?.user ?? null);
      refreshProfile().finally(() => setLoading(false));
    });
    const { data: subscription } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setUser(nextSession?.user ?? null);
      refreshProfile();
    });
    return () => {
      subscription.subscription.unsubscribe();
      setAuthTokenProvider(null);
    };
  }, [refreshProfile]);

  const signIn = useCallback(async (email: string, password: string) => {
    if (!supabase) throw new Error('Supabase Auth is not configured for this environment.');
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    await refreshProfile();
  }, [refreshProfile]);

  const signUp = useCallback(async (payload: SignUpPayload) => {
    if (!supabase) throw new Error('Supabase Auth is not configured for this environment.');
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
  }, [refreshProfile]);

  const signOut = useCallback(async () => {
    if (supabase) {
      await supabase.auth.signOut();
    }
    setSession(null);
    setUser(null);
    await refreshProfile();
  }, [refreshProfile]);

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
      signOut,
      refreshProfile,
    }),
    [loading, profile, refreshProfile, session, signIn, signOut, signUp, user],
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
