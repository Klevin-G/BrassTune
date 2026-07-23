import { AlertCircle, ArrowRight, CheckCircle2, Eye, EyeOff, KeyRound, LockKeyhole, LogIn, Mail, Music2, ShieldCheck, UserPlus } from 'lucide-react';
import { GoogleIcon } from '../components/GoogleIcon';
import { FormEvent, useEffect, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { EmptyActionState, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';
import {
  authPathWithReturn,
  clearPendingAuthReturn,
  readPendingAuthReturn,
  rememberPendingAuthReturn,
  safeReturnPath,
} from '../domain/authNavigation';
import { useI18n } from '../i18n/LocaleContext';
import './AuthPage.css';

const PASSWORD_MIN = 8;

export const safeAuthNext = safeReturnPath;
export const authPathWithNext = authPathWithReturn;

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
  const { t } = useI18n();
  return (
    <footer className="au-footer" aria-label={t('auth.legal')}>
      <Link to="/privacy">{t('legal.privacy')}</Link>
      <Link to="/terms">{t('legal.terms')}</Link>
      <Link to="/support">{t('legal.support')}</Link>
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
  const { t } = useI18n();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const storedRecoveryNext = mode === 'reset' && auth.hasAuthSession
    ? readPendingAuthReturn()
    : null;
  const next = safeReturnPath(params.get('next') ?? storedRecoveryNext);
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
  const [passwordUpdated, setPasswordUpdated] = useState(false);

  const isSignup = mode === 'sign-up';
  const isPasswordRecovery = mode === 'reset' && auth.hasAuthSession;

  // Clear any leftover message when switching between form modes via the links.
  useEffect(() => {
    if (mode === 'callback') return;
    setMessage(null);
    setPendingSignup(false);
    setPasswordUpdated(false);
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
    if (auth.isSignedIn) {
      clearPendingAuthReturn();
      navigate(next, { replace: true });
    }
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
      const timer = setTimeout(() => {
        clearPendingAuthReturn();
        navigate(next, { replace: true });
      }, 1100);
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
        clearPendingAuthReturn();
        navigate(next);
      } else if (mode === 'sign-up') {
        rememberPendingAuthReturn(next);
        await auth.signUp({ email, password, username, displayName, primaryInstrumentId: instrumentId });
        setPendingSignup(true);
      } else if (isPasswordRecovery) {
        if (newPassword.length < PASSWORD_MIN) {
          setMessage({ type: 'error', text: `Enter a new password with at least ${PASSWORD_MIN} characters.` });
          return;
        }
        await auth.updatePassword(newPassword);
        setMessage({ type: 'success', text: "Password updated. You're signed in and ready to continue." });
        setPasswordUpdated(true);
        setNewPassword('');
      } else {
        rememberPendingAuthReturn(next);
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
          <SectionCard title={showError ? t('auth.callbackFailedTitle') : t('auth.callbackTitle')}>
            {!auth.configured ? (
              <>
                <p className="muted-copy" role="status">
                  {t('auth.accountsOffBody')}
                </p>
                <Link className="primary-button au-block" to={next} onClick={auth.continueAsGuest}>
                  {t('auth.start')}
                  <ArrowRight size={18} />
                </Link>
              </>
            ) : showError ? (
              <>
                <MessageBanner
                  message={{
                    type: 'error',
                    text: auth.profileError ?? t('auth.callbackFailed'),
                  }}
                />
                <div className="au-stack">
                  <Link className="primary-button au-block" to={`/auth/sign-in?next=${encodeURIComponent(next)}`}>
                    <LogIn size={18} />
                    {t('auth.tryAgain')}
                  </Link>
                  <Link className="ghost-button au-block" to={next} onClick={auth.continueAsGuest}>
                    {t('auth.keepGuest')}
                  </Link>
                </div>
              </>
            ) : (
              <div className="au-callback-progress">
                <span className="au-spinner" role="status" aria-live="polite" aria-label={t('auth.callbackTitle')} />
                <p>{t('auth.signingIn')}</p>
                {callbackStalled && (
                  <div className="au-stack">
                    <Link className="primary-button au-block" to={next}>
                      {t('auth.continue')}
                      <ArrowRight size={18} />
                    </Link>
                    <Link className="ghost-button au-block" to={`/auth/sign-in?next=${encodeURIComponent(next)}`}>
                      {t('auth.tryAgain')}
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
    ? t('auth.heroSignup')
    : mode === 'reset'
      ? t('auth.heroReset')
      : t('auth.heroWelcome');
  const heroBody = isPasswordRecovery
    ? t('auth.heroRecoveryBody')
    : mode === 'reset'
      ? t('auth.heroResetBody')
    : t('auth.heroBody');
  const cardTitle = isSignup ? t('auth.create') : isPasswordRecovery ? t('auth.setPassword') : mode === 'reset' ? t('auth.resetPassword') : t('nav.signIn');

  return (
    <ScreenContainer>
      <div className="au-page">
        <div className="au-grid">
          <div className="au-form-col">
            <SectionCard title={cardTitle}>
              {!auth.configured && (
                <>
                  <EmptyActionState
                    title={t('auth.accountsOff')}
                    body={t('auth.accountsOffBody')}
                    icon={Mail}
                  />
                  <Link className="primary-button au-block" to={next} onClick={auth.continueAsGuest}>
                    {t('auth.continueGuest')}
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
                        .catch((error) => setMessage({ type: 'error', text: error instanceof Error ? error.message : t('auth.googleFailure') }))
                    }
                  >
                    <GoogleIcon size={18} />
                    {isSignup ? t('auth.signupGoogle') : t('auth.google')}
                  </button>
                  <div className="auth-divider" aria-hidden="true"><span>{t('auth.orEmail')}</span></div>
                </>
              )}

              {auth.configured && !passwordUpdated && (
                <form className="auth-form" onSubmit={onSubmit}>
                  {!isPasswordRecovery && (
                    <label>
                      {t('auth.email')}
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
                      label={t('auth.password')}
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
                        label={t('auth.password')}
                        value={password}
                        onChange={setPassword}
                        name="new-password"
                        autoComplete="new-password"
                        minLength={PASSWORD_MIN}
                        hint={`At least ${PASSWORD_MIN} characters.`}
                      />
                      <label>
                        {t('auth.username')}
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
                        {t('auth.displayName')}
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
                      label={t('auth.newPassword')}
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
                    {busy ? t('auth.working') : isSignup ? t('auth.create') : isPasswordRecovery ? t('auth.updatePassword') : mode === 'reset' ? t('auth.sendReset') : t('nav.signIn')}
                  </button>
                </form>
              )}

              {passwordUpdated && (
                <button
                  className="primary-button au-block"
                  type="button"
                  onClick={() => {
                    clearPendingAuthReturn();
                    navigate(next, { replace: true });
                  }}
                >
                  {t('auth.continueApp')}
                  <ArrowRight size={18} />
                </button>
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
                        .catch((error) => setMessage({ type: 'error', text: error instanceof Error ? error.message : t('auth.appleFailure') }))
                    }
                  >
                    <ShieldCheck size={18} />
                    {t('auth.apple')}
                  </button>
                </div>
              )}

              {message && <MessageBanner message={message} />}

              {auth.configured && !passwordUpdated && (
                <>
                  <div className="auth-switcher">
                    {isSignup ? (
                      <Link to={authPathWithNext('/auth/sign-in', next)}>{t('auth.haveAccount')}</Link>
                    ) : (
                      <Link to={authPathWithNext('/auth/sign-up', next)}>{t('auth.create')}</Link>
                    )}
                    {mode !== 'reset' && <Link to={authPathWithNext('/auth/reset-password', next)}>{t('auth.forgot')}?</Link>}
                  </div>
                  {!isPasswordRecovery && (
                    <Link
                      className="ghost-button au-block"
                      to={next}
                      onClick={() => {
                        clearPendingAuthReturn();
                        auth.continueAsGuest();
                      }}
                    >
                      {t('auth.keepGuest')}
                      <ArrowRight size={18} />
                    </Link>
                  )}
                </>
              )}
            </SectionCard>

            {auth.configured && (
              <p className="au-reassure">
                <LockKeyhole size={15} />
                {t('auth.reassure')}
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
