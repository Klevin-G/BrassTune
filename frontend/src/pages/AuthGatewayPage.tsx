import { ArrowRight, KeyRound, LogIn, Mail, Music2, ShieldCheck, UserPlus } from 'lucide-react';
import { FormEvent, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { ThemeSelector } from '../components/ThemeSelector';
import { EmptyActionState, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';

function safeNext(value: string | null) {
  if (!value || !value.startsWith('/') || value.startsWith('//')) return '/home';
  if (value === '/' || value.startsWith('/auth/')) return '/home';
  return value;
}

export function AuthGatewayPage() {
  const auth = useAuth();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const next = useMemo(() => safeNext(params.get('next')), [params]);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!auth.loading && auth.isSignedIn) {
      navigate(next, { replace: true });
    }
  }, [auth.isSignedIn, auth.loading, navigate, next]);

  async function signIn(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      await auth.signIn(email, password);
      navigate(next, { replace: true });
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Account access is unavailable right now. You can still use guest practice.');
    } finally {
      setBusy(false);
    }
  }

  function continueAsGuest() {
    auth.continueAsGuest();
    navigate(next, { replace: true });
  }

  const callbackNext = `${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`;

  return (
    <ScreenContainer>
      <div className="auth-layout gateway-layout">
        <section className="auth-panel gateway-panel">
          <div className="brand auth-brand">
            <span className="brand-mark">
              <Music2 size={20} />
            </span>
            <span>
              <strong>BrassTune</strong>
              <small>Practice gateway</small>
            </span>
          </div>
          <h1>Sign in or start a guest practice session.</h1>
          <p>
            Keep your warmups, recordings, score practice, and ensemble work in one focused brass cockpit. Guest practice stays on this device.
          </p>
          <div className="gateway-links" aria-label="Legal and support links">
            <Link to="/privacy">Privacy</Link>
            <Link to="/terms">Terms</Link>
            <Link to="/support">Support</Link>
          </div>
        </section>

        <div className="gateway-stack">
          <SectionCard title={auth.configured ? 'Sign in' : 'Continue as guest'} eyebrow={auth.configured ? 'Account access' : 'Guest-first release'}>
            {auth.loading && <p className="muted-copy" role="status">Restoring your session...</p>}
            {!auth.loading && !auth.configured && (
              <>
                <EmptyActionState
                  title="Accounts are not enabled in this release yet"
                  body="Accounts aren’t enabled in this release yet. Guest practice is fully available."
                  icon={Mail}
                />
                <button className="primary-button full-width-action" type="button" onClick={continueAsGuest}>
                  Continue as guest
                  <ArrowRight size={18} />
                </button>
              </>
            )}

            {!auth.loading && auth.configured && (
              <>
                <form className="auth-form" onSubmit={signIn}>
                  <label>
                    Email
                    <input value={email} onChange={(event) => setEmail(event.target.value)} type="email" required placeholder="you@example.com" />
                  </label>
                  <label>
                    Password
                    <input value={password} onChange={(event) => setPassword(event.target.value)} type="password" required minLength={6} placeholder="Password" />
                  </label>
                  <button className="primary-button" disabled={busy} type="submit">
                    <LogIn size={18} />
                    {busy ? 'Signing in...' : 'Sign in'}
                  </button>
                </form>
                <div className="provider-button-stack">
                  {auth.providers.google && (
                    <button className="ghost-button full-width-action" disabled={busy} type="button" onClick={() => auth.signInWithGoogle(callbackNext).catch((error) => setMessage(error instanceof Error ? error.message : 'Google sign-in could not start. Try again later.'))}>
                      Continue with Google
                    </button>
                  )}
                  {auth.providers.apple && (
                    <button className="ghost-button full-width-action" disabled={busy} type="button" onClick={() => auth.signInWithApple(callbackNext).catch((error) => setMessage(error instanceof Error ? error.message : 'Apple sign-in could not start. Try again later.'))}>
                      <ShieldCheck size={18} />
                      Continue with Apple
                    </button>
                  )}
                  <button className="ghost-button full-width-action" type="button" onClick={continueAsGuest}>
                    Continue as guest
                  </button>
                </div>
                <div className="auth-switcher">
                  <Link to="/auth/sign-up">
                    <UserPlus size={16} />
                    Create account
                  </Link>
                  <Link to="/auth/reset-password">
                    <KeyRound size={16} />
                    Forgot password
                  </Link>
                </div>
              </>
            )}
            {(message || auth.profileError) && <div className="alert" role="status">{message ?? auth.profileError}</div>}
          </SectionCard>

          <SectionCard title="Appearance" eyebrow="Theme">
            <ThemeSelector />
          </SectionCard>
        </div>
      </div>
    </ScreenContainer>
  );
}
