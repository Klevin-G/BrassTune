import { AlertCircle, ArrowRight, CheckCircle2, Eye, EyeOff, KeyRound, LockKeyhole, LogIn, Mail, Music2, ShieldCheck, UserPlus } from 'lucide-react';
import { GoogleIcon } from '../components/GoogleIcon';
import { FormEvent, useEffect, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { EmptyActionState, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';
import './AuthPage.css';

const PASSWORD_MIN = 8;

type Message = { type: 'success' | 'error'; text: string };

function callbackParams() {
  const merged = new URLSearchParams(window.location.search);
  const hash = window.location.hash.replace(/^#/, '');
  if (hash) {
    new URLSearchParams(hash.startsWith('?') ? hash : `?${hash}`).forEach((value, key) => {
      merged.set(key, value);
    });
  }
  return merged;
}

function AuthFooter() {
  return (
    <footer className="au-footer" aria-label="Legal and support links">
      <Link to="/privacy">Privacy</Link>
      <Link to="/terms">Terms</Link>
      <Link to="/support">Support</Link>
    </footer>
  );
}

function MessageBanner({ message }: { message: Message }) {
  const isError = message.type === 'error';
  return (
    <div
      className={`au-message ${isError ? 'au-message--error' : 'au-message--success'}`}
      role={isError ? 'alert' : 'status'}
      aria-live={isError ? 'assertive' : 'polite'}
    >
      {isError ? <AlertCircle size={18} /> : <CheckCircle2 size={18} />}
      <span>{message.text}</span>
    </div>
  );
}

function PasswordField({
  label,
  value,
  onChange,
  name,
  autoComplete,
  minLength,
  hint,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  name: string;
  autoComplete: string;
  minLength?: number;
  hint?: string;
  placeholder?: string;
}) {
  const [show, setShow] = useState(false);
  return (
    <label>
      {label}
      <span className="au-pass-wrap">
        <input
          value={value}
          onChange={(event) => onChange(event.target.value)}
          type={show ? 'text' : 'password'}
          name={name}
          autoComplete={autoComplete}
          required
          minLength={minLength}
          placeholder={placeholder}
        />
        <button
          type="button"
          className="au-pass-toggle"
          onClick={() => setShow((open) => !open)}
          aria-pressed={show}
          aria-label={show ? 'Hide password' : 'Show password'}
          title={show ? 'Hide password' : 'Show password'}
        >
          {show ? <EyeOff size={18} /> : <Eye size={18} />}
        </button>
      </span>
      {hint && <span className="au-field-hint">{hint}</span>}
    </label>
  );
}

export function AuthPage({ mode }: { mode: 'sign-in' | 'sign-up' | 'reset' | 'callback' }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const next = (() => {
    const value = params.get('next');
    if (!value || !value.startsWith('/') || value.startsWith('//') || value === '/' || value.startsWith('/auth/')) return '/home';
    return value;
  })();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [instrumentId, setInstrumentId] = useState('trumpet');
  const [message, setMessage] = useState<Message | null>(null);
  const [busy, setBusy] = useState(false);
  const [pendingSignup, setPendingSignup] = useState(false);
  const [callbackStalled, setCallbackStalled] = useState(false);
  const [callbackErrored, setCallbackErrored] = useState(false);

  const isSignup = mode === 'sign-up';
  const isPasswordRecovery = mode === 'reset' && auth.hasAuthSession;

  // Clear any leftover message when switching between form modes via the links.
  useEffect(() => {
    if (mode === 'callback') return;
    setMessage(null);
    setPendingSignup(false);
  }, [mode]);

  // Callback: detect an OAuth error once on entry.
  useEffect(() => {
    if (mode !== 'callback') return;
    const error = callbackParams().get('error_description') || callbackParams().get('error');
    if (error) setCallbackErrored(true);
  }, [mode]);

  // Callback: auto-redirect the moment the session is ready.
  useEffect(() => {
    if (mode !== 'callback') return;
    if (auth.isSignedIn) navigate(next, { replace: true });
  }, [mode, auth.isSignedIn, navigate, next]);

  // Callback: if it hasn't resolved after a while, reveal a manual escape hatch.
  useEffect(() => {
    if (mode !== 'callback') return;
    const timer = setTimeout(() => setCallbackStalled(true), 8000);
    return () => clearTimeout(timer);
  }, [mode]);

  // Sign-up: branch on the ACTUAL Supabase state (session returned vs. confirmation required).
  useEffect(() => {
    if (!pendingSignup) return;
    if (auth.hasAuthSession) {
      setMessage({ type: 'success', text: "You're all set — taking you to practice…" });
      const timer = setTimeout(() => navigate(next, { replace: true }), 1100);
      return () => clearTimeout(timer);
    }
    setMessage({
      type: 'success',
      text: `Check your email — we sent a confirmation link to ${email}. Click it, then come back and sign in.`,
    });
  }, [pendingSignup, auth.hasAuthSession, navigate, next, email]);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      if (mode === 'sign-in') {
        await auth.signIn(email, password);
        navigate(next);
      } else if (mode === 'sign-up') {
        await auth.signUp({ email, password, username, displayName, primaryInstrumentId: instrumentId });
        setPendingSignup(true);
      } else if (isPasswordRecovery) {
        if (newPassword.length < PASSWORD_MIN) {
          setMessage({ type: 'error', text: `Enter a new password with at least ${PASSWORD_MIN} characters.` });
          return;
        }
        await auth.updatePassword(newPassword);
        setMessage({ type: 'success', text: 'Password updated. You can now sign in with it.' });
        setNewPassword('');
      } else {
        await auth.requestPasswordReset(email);
        setMessage({ type: 'success', text: 'Check your email — we sent you a link to set a new password.' });
      }
    } catch (error) {
      setMessage({ type: 'error', text: error instanceof Error ? error.message : 'Authentication failed.' });
    } finally {
      setBusy(false);
    }
  }

  if (mode === 'callback') {
    const showError = callbackErrored || Boolean(auth.profileError);
    return (
      <ScreenContainer>
        <div className="au-callback">
          <SectionCard title={showError ? "Sign-in didn't finish" : 'Signing you in'}>
            {!auth.configured ? (
              <>
                <p className="muted-copy" role="status">
                  Accounts aren't turned on yet — you can start practicing right now as a guest.
                </p>
                <Link className="primary-button au-block" to={next} onClick={auth.continueAsGuest}>
                  Start practicing
                  <ArrowRight size={18} />
                </Link>
              </>
            ) : showError ? (
              <>
                <MessageBanner
                  message={{
                    type: 'error',
                    text: auth.profileError ?? "That sign-in didn't finish. Try again, or keep practicing as a guest.",
                  }}
                />
                <div className="au-stack">
                  <Link className="primary-button au-block" to={`/auth/sign-in?next=${encodeURIComponent(next)}`}>
                    <LogIn size={18} />
                    Try again
                  </Link>
                  <Link className="ghost-button au-block" to={next} onClick={auth.continueAsGuest}>
                    Keep practicing as a guest
                  </Link>
                </div>
              </>
            ) : (
              <div className="au-callback-progress">
                <span className="au-spinner" role="status" aria-live="polite" aria-label="Signing you in" />
                <p>Signing you in…</p>
                {callbackStalled && (
                  <div className="au-stack">
                    <Link className="primary-button au-block" to={next}>
                      Continue
                      <ArrowRight size={18} />
                    </Link>
                    <Link className="ghost-button au-block" to={`/auth/sign-in?next=${encodeURIComponent(next)}`}>
                      Try again
                    </Link>
                  </div>
                )}
              </div>
            )}
          </SectionCard>
          <AuthFooter />
        </div>
      </ScreenContainer>
    );
  }

  const heroTitle = isSignup
    ? 'Create your free BrassTune account.'
    : mode === 'reset'
      ? 'Reset your password.'
      : 'Welcome back.';
  const heroBody = mode === 'reset'
    ? "Enter your email and we'll send you a link to choose a new password."
    : 'Save your practice history and progress, and join your band’s ensemble. You can also keep practicing as a guest.';
  const cardTitle = isSignup ? 'Create account' : isPasswordRecovery ? 'Set a new password' : mode === 'reset' ? 'Reset password' : 'Sign in';

  return (
    <ScreenContainer>
      <div className="au-page">
        <div className="au-grid">
          <div className="au-form-col">
            <SectionCard title={cardTitle}>
              {!auth.configured && (
                <>
                  <EmptyActionState
                    title="Accounts aren't turned on yet"
                    body="You can start practicing right now as a guest."
                    icon={Mail}
                  />
                  <Link className="primary-button au-block" to={next} onClick={auth.continueAsGuest}>
                    Continue as guest
                    <ArrowRight size={18} />
                  </Link>
                </>
              )}

              {mode !== 'reset' && auth.configured && auth.providers.google && (
                <>
                  <button
                    className="google-button au-block"
                    disabled={busy}
                    type="button"
                    onClick={() =>
                      auth
                        .signInWithGoogle(`${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`)
                        .catch((error) => setMessage({ type: 'error', text: error instanceof Error ? error.message : 'Google sign-in could not start. Try again later.' }))
                    }
                  >
                    <GoogleIcon size={18} />
                    {isSignup ? 'Sign up with Google' : 'Continue with Google'}
                  </button>
                  <div className="auth-divider" aria-hidden="true"><span>or use your email</span></div>
                </>
              )}

              {auth.configured && (
                <form className="auth-form" onSubmit={onSubmit}>
                  {!isPasswordRecovery && (
                    <label>
                      Email
                      <input
                        value={email}
                        onChange={(event) => setEmail(event.target.value)}
                        type="email"
                        name="email"
                        autoComplete="email"
                        inputMode="email"
                        required
                        placeholder="you@example.com"
                      />
                    </label>
                  )}

                  {mode === 'sign-in' && (
                    <PasswordField
                      label="Password"
                      value={password}
                      onChange={setPassword}
                      name="password"
                      autoComplete="current-password"
                      placeholder="Your password"
                    />
                  )}

                  {isSignup && (
                    <>
                      <PasswordField
                        label="Password"
                        value={password}
                        onChange={setPassword}
                        name="new-password"
                        autoComplete="new-password"
                        minLength={PASSWORD_MIN}
                        hint={`At least ${PASSWORD_MIN} characters.`}
                      />
                      <label>
                        Username
                        <input
                          value={username}
                          onChange={(event) => setUsername(event.target.value.toLowerCase())}
                          name="username"
                          autoComplete="username"
                          required
                          minLength={3}
                          placeholder="avery"
                        />
                        <span className="au-field-hint">Your unique handle. Lowercase letters and numbers, e.g. avery.</span>
                      </label>
                      <label>
                        Display name
                        <input
                          value={displayName}
                          onChange={(event) => setDisplayName(event.target.value)}
                          name="name"
                          autoComplete="name"
                          required
                          placeholder="Avery Brass"
                        />
                        <span className="au-field-hint">The name your band director sees.</span>
                      </label>
                      <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
                    </>
                  )}

                  {isPasswordRecovery && (
                    <PasswordField
                      label="New password"
                      value={newPassword}
                      onChange={setNewPassword}
                      name="new-password"
                      autoComplete="new-password"
                      minLength={PASSWORD_MIN}
                      hint={`At least ${PASSWORD_MIN} characters.`}
                    />
                  )}

                  <button className="primary-button au-block" disabled={busy || (isPasswordRecovery && newPassword.length < PASSWORD_MIN)} type="submit">
                    {isSignup ? <UserPlus size={18} /> : mode === 'reset' ? <KeyRound size={18} /> : <LogIn size={18} />}
                    {busy ? 'Working…' : isSignup ? 'Create account' : isPasswordRecovery ? 'Update password' : mode === 'reset' ? 'Send reset link' : 'Sign in'}
                  </button>
                </form>
              )}

              {mode !== 'reset' && auth.configured && auth.providers.apple && (
                <div className="provider-button-stack">
                  <button
                    className="ghost-button au-block"
                    disabled={busy}
                    type="button"
                    onClick={() =>
                      auth
                        .signInWithApple(`${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`)
                        .catch((error) => setMessage({ type: 'error', text: error instanceof Error ? error.message : 'Apple sign-in could not start. Try again later.' }))
                    }
                  >
                    <ShieldCheck size={18} />
                    Continue with Apple
                  </button>
                </div>
              )}

              {message && <MessageBanner message={message} />}

              {auth.configured && (
                <div className="auth-switcher">
                  {isSignup ? (
                    <Link to="/auth/sign-in">Already have an account?</Link>
                  ) : (
                    <Link to="/auth/sign-up">Create account</Link>
                  )}
                  {mode !== 'reset' && <Link to="/auth/reset-password">Forgot password?</Link>}
                </div>
              )}
            </SectionCard>

            {auth.configured && (
              <p className="au-reassure">
                <LockKeyhole size={15} />
                We only use your email to save your practice. No spam.
              </p>
            )}
          </div>

          <section className="au-hero">
            <div className="brand au-hero-brand">
              <span className="brand-mark">
                <Music2 size={20} />
              </span>
              <span>
                <strong>BrassTune</strong>
              </span>
            </div>
            <h1 className="au-hero-title">{heroTitle}</h1>
            <p className="au-hero-body">{heroBody}</p>
          </section>
        </div>

        <AuthFooter />
      </div>
    </ScreenContainer>
  );
}
