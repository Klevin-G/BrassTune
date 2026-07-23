import { ArrowRight, CheckCircle2, ChevronDown, KeyRound, LogIn, Mail, Music2, ShieldCheck, UserPlus } from 'lucide-react';
import { GoogleIcon } from '../components/GoogleIcon';
import { FormEvent, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { EmptyActionState, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';
import './AuthGatewayPage.css';

const pendingAuthNextKey = 'brasstune.pendingAuthNext';

function consumePendingAuthNext() {
  try {
    const value = sessionStorage.getItem(pendingAuthNextKey);
    sessionStorage.removeItem(pendingAuthNextKey);
    return value;
  } catch {
    return null;
  }
}

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
  const [showEmail, setShowEmail] = useState(false);

  useEffect(() => {
    if (!auth.loading && auth.isSignedIn) {
      const storedNext = consumePendingAuthNext();
      const destination = params.has('next') ? next : safeNext(storedNext);
      navigate(destination, { replace: true });
    }
  }, [auth.isSignedIn, auth.loading, navigate, next, params]);

  async function signIn(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      await auth.signIn(email, password);
      consumePendingAuthNext();
      navigate(next, { replace: true });
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Couldn’t sign in right now. You can start as a guest instead.');
    } finally {
      setBusy(false);
    }
  }

  function continueAsGuest() {
    auth.continueAsGuest();
    navigate(next, { replace: true });
  }

  const callbackNext = `${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`;
  const hasProviders = auth.providers.google || auth.providers.apple;

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
            </span>
          </div>
          <h1>Tune up, play along, and see how you sound.</h1>
          <p className="ag-lead">
            A tuner, metronome, and play-along grader for brass players — solo or with your band. Guest mode saves your work on this device only.
          </p>
          <span className="ag-noaccount">
            <CheckCircle2 size={16} />
            No account needed to start.
          </span>
        </section>

        <div className="gateway-stack">
          <SectionCard>
            {auth.loading && <p className="muted-copy" role="status">Restoring your session…</p>}

            {!auth.loading && !auth.configured && (
              <>
                <EmptyActionState
                  title="Ready when you are"
                  body="Just start practicing — no sign-in needed."
                  icon={Music2}
                />
                <button className="primary-button ag-block ag-guest" type="button" onClick={continueAsGuest}>
                  Start practicing
                  <ArrowRight size={18} />
                </button>
              </>
            )}

            {!auth.loading && auth.configured && (
              <>
                {hasProviders && (
                  <>
                    <div className="ag-providers">
                      {auth.providers.google && (
                        <button className="google-button ag-block" disabled={busy} type="button" onClick={() => auth.signInWithGoogle(callbackNext).catch((error) => setMessage(error instanceof Error ? error.message : 'Google sign-in could not start. Try again later.'))}>
                          <GoogleIcon size={18} />
                          Continue with Google
                        </button>
                      )}
                      {auth.providers.apple && (
                        <button className="ghost-button ag-block" disabled={busy} type="button" onClick={() => auth.signInWithApple(callbackNext).catch((error) => setMessage(error instanceof Error ? error.message : 'Apple sign-in could not start. Try again later.'))}>
                          <ShieldCheck size={18} />
                          Continue with Apple
                        </button>
                      )}
                    </div>
                    <div className="auth-divider" aria-hidden="true"><span>or</span></div>
                  </>
                )}

                <button className="primary-button ag-block ag-guest" type="button" onClick={continueAsGuest}>
                  Start practicing
                  <ArrowRight size={18} />
                </button>
                <p className="ag-nudge">New here? Jump right in — no account needed.</p>

                <button
                  type="button"
                  className="ghost-button ag-block ag-email-toggle"
                  aria-expanded={showEmail}
                  aria-controls="ag-email-region"
                  onClick={() => setShowEmail((open) => !open)}
                >
                  <span className="ag-email-toggle-label">
                    <Mail size={16} />
                    Sign in with email
                  </span>
                  <ChevronDown className="ag-chevron" size={16} />
                </button>

                {showEmail && (
                  <div className="ag-email-region" id="ag-email-region">
                    <form className="auth-form" onSubmit={signIn}>
                      <label>
                        Email
                        <input value={email} onChange={(event) => setEmail(event.target.value)} type="email" required placeholder="you@example.com" />
                      </label>
                      <label>
                        Password
                        <input value={password} onChange={(event) => setPassword(event.target.value)} type="password" required minLength={6} placeholder="At least 6 characters" />
                      </label>
                      <button className="primary-button ag-block" disabled={busy} type="submit">
                        <LogIn size={18} />
                        {busy ? 'Signing in…' : 'Sign in'}
                      </button>
                    </form>
                    <div className="auth-switcher">
                      <Link to={`/auth/sign-up?next=${encodeURIComponent(next)}`}>
                        <UserPlus size={16} />
                        Create account
                      </Link>
                      <Link to={`/auth/reset-password?next=${encodeURIComponent(next)}`}>
                        <KeyRound size={16} />
                        Forgot password
                      </Link>
                    </div>
                  </div>
                )}
              </>
            )}
            {(message || auth.profileError) && <div className="alert" role="status">{message ?? auth.profileError}</div>}
          </SectionCard>
        </div>
      </div>

      <footer className="ag-footer" aria-label="Legal and support links">
        <Link to="/privacy">Privacy</Link>
        <Link to="/terms">Terms</Link>
        <Link to="/support">Support</Link>
      </footer>
    </ScreenContainer>
  );
}
