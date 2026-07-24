import { AlertCircle, ArrowLeft, ArrowRight, CheckCircle2, Eye, EyeOff, KeyRound, LockKeyhole, LogIn, Mail, Music2, UserPlus } from 'lucide-react';
import { appleSignInLogo } from '../assets/appleSignInLogo';
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

function DirectionalArrow({ dir }: { dir: 'ltr' | 'rtl' }) {
  return dir === 'rtl' ? <ArrowLeft size={18} /> : <ArrowRight size={18} />;
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
  const { t } = useI18n();
  const [show, setShow] = useState(false);
  return (
    <label>
      {label}
      <span className="au-pass-wrap">
        <input
          value={value}
          onChange={(event) => onChange(event.target.value)}
          type={show ? 'text' : 'password'}
          dir="ltr"
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
          aria-label={t(show ? 'auth.hidePassword' : 'auth.showPassword')}
          title={t(show ? 'auth.hidePassword' : 'auth.showPassword')}
        >
          {show ? <EyeOff size={18} /> : <Eye size={18} />}
        </button>
      </span>
      {hint && <span className="au-field-hint">{hint}</span>}
    </label>
  );
}

function localizedAuthError(error: unknown, t: ReturnType<typeof useI18n>['t']): string {
  const message = error instanceof Error ? error.message : '';
  const lower = message.toLowerCase();
  if (lower.includes('email or password') || lower.includes('credentials')) return t('auth.errorCredentials');
  if (lower.includes('already exists') || lower.includes('already registered')) return t('auth.errorExists');
  if (lower.includes('stronger password') || lower.includes('weak password')) return t('auth.errorWeakPassword');
  if (lower.includes('confirm your email')) return t('auth.errorConfirmEmail');
  if (lower.includes('expired')) return t('auth.errorExpired');
  if (lower.includes('cancel')) return t('auth.errorCancelled');
  if (lower.includes('network') || lower.includes('reach the server')) return t('auth.errorNetwork');
  return t('auth.failure');
}

export function localizedOAuthError(
  error: unknown,
  t: ReturnType<typeof useI18n>['t'],
  providerFailure: 'auth.googleFailure' | 'auth.appleFailure',
): string {
  const message = error instanceof Error ? error.message.toLowerCase() : '';
  if (message.includes('cancel') || message.includes('popup closed')) return t('auth.errorCancelled');
  if (message.includes('network') || message.includes('fetch') || message.includes('reach the server')) return t('auth.errorNetwork');
  return t(providerFailure);
}

export function AuthPage({ mode }: { mode: 'sign-in' | 'sign-up' | 'reset' | 'callback' }) {
  const auth = useAuth();
  const { dir, locale, t } = useI18n();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const storedRecoveryNext = (mode === 'callback' || (mode === 'reset' && auth.hasAuthSession))
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
  const [oauthProvider, setOauthProvider] = useState<'google' | 'apple' | null>(null);
  const [pendingSignup, setPendingSignup] = useState(false);
  const [callbackStalled, setCallbackStalled] = useState(false);
  const [callbackErrored, setCallbackErrored] = useState(false);
  const [passwordUpdated, setPasswordUpdated] = useState(false);

  const isSignup = mode === 'sign-up';
  const isPasswordRecovery = mode === 'reset' && auth.hasAuthSession;
  const callbackProviderError = mode === 'callback'
    ? callbackParams().get('error_description') || callbackParams().get('error')
    : null;

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
    if (callbackProviderError) {
      clearPendingAuthReturn();
      setCallbackErrored(true);
    }
  }, [callbackProviderError, mode]);

  // Callback: auto-redirect the moment the session is ready.
  useEffect(() => {
    if (mode !== 'callback') return;
    if (auth.isSignedIn && !callbackProviderError) {
      clearPendingAuthReturn();
      navigate(next, { replace: true });
    }
  }, [mode, auth.isSignedIn, callbackProviderError, navigate, next]);

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
      setMessage({ type: 'success', text: t('auth.signupReady') });
      const timer = setTimeout(() => {
        clearPendingAuthReturn();
        navigate(next, { replace: true });
      }, 1100);
      return () => clearTimeout(timer);
    }
    setMessage({
      type: 'success',
      text: t('auth.confirmationSent', { email }),
    });
  }, [pendingSignup, auth.hasAuthSession, navigate, next, email, t]);

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
          setMessage({ type: 'error', text: t('auth.passwordMinError', { count: PASSWORD_MIN }) });
          return;
        }
        await auth.updatePassword(newPassword);
        setMessage({ type: 'success', text: t('auth.passwordUpdated') });
        setPasswordUpdated(true);
        setNewPassword('');
      } else {
        rememberPendingAuthReturn(next);
        await auth.requestPasswordReset(email, next);
        setMessage({ type: 'success', text: t('auth.resetSent') });
      }
    } catch (error) {
      setMessage({ type: 'error', text: localizedAuthError(error, t) });
    } finally {
      setBusy(false);
    }
  }

  async function continueAsGuest() {
    setBusy(true);
    setMessage(null);
    try {
      clearPendingAuthReturn();
      await auth.continueAsGuest();
      navigate(next, { replace: true });
    } catch (error) {
      setMessage({ type: 'error', text: localizedAuthError(error, t) });
      if (mode === 'callback') setCallbackErrored(true);
    } finally {
      setBusy(false);
    }
  }

  async function beginOAuth(provider: 'google' | 'apple') {
    if (!auth.providers[provider]) return;
    setBusy(true);
    setOauthProvider(provider);
    setMessage(null);
    rememberPendingAuthReturn(next);
    try {
      await (provider === 'google' ? auth.signInWithGoogle() : auth.signInWithApple());
    } catch (error) {
      clearPendingAuthReturn();
      setMessage({
        type: 'error',
        text: localizedOAuthError(error, t, provider === 'google' ? 'auth.googleFailure' : 'auth.appleFailure'),
      });
    } finally {
      setBusy(false);
      setOauthProvider(null);
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
                <button className="primary-button au-block" disabled={busy} type="button" onClick={() => void continueAsGuest()}>
                  {t('auth.start')}
                  <DirectionalArrow dir={dir} />
                </button>
              </>
            ) : showError ? (
              <>
                <MessageBanner
                  message={{
                    type: 'error',
                    text: locale === 'en' ? auth.profileError ?? t('auth.callbackFailed') : t('auth.callbackFailed'),
                  }}
                />
                <div className="au-stack">
                  <Link className="primary-button au-block" to={`/auth/sign-in?next=${encodeURIComponent(next)}`}>
                    <LogIn size={18} />
                    {t('auth.tryAgain')}
                  </Link>
                  <button className="ghost-button au-block" disabled={busy} type="button" onClick={() => void continueAsGuest()}>
                    {t('auth.keepGuest')}
                  </button>
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
                      <DirectionalArrow dir={dir} />
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
                  <button className="primary-button au-block" disabled={busy} type="button" onClick={() => void continueAsGuest()}>
                    {t('auth.continueGuest')}
                    <DirectionalArrow dir={dir} />
                  </button>
                </>
              )}

              {mode !== 'reset' && auth.configured && (
                <>
                  <div className="provider-button-stack">
                    <button
                      className="google-button au-block"
                      disabled={busy || !auth.providers.google}
                      type="button"
                      onClick={() => void beginOAuth('google')}
                    >
                      <GoogleIcon size={18} />
                      {oauthProvider === 'google'
                        ? t('auth.googleLoading')
                        : !auth.providers.google
                          ? t('auth.googleUnavailable')
                          : isSignup ? t('auth.signupGoogle') : t('auth.google')}
                    </button>
                    <button
                      className="apple-button au-block"
                      disabled={busy || !auth.providers.apple}
                      type="button"
                      onClick={() => void beginOAuth('apple')}
                    >
                      {auth.providers.apple && <img src={appleSignInLogo} alt="" aria-hidden="true" />}
                      {oauthProvider === 'apple'
                        ? t('auth.appleLoading')
                        : auth.providers.apple ? t('auth.apple') : t('auth.appleUnavailable')}
                    </button>
                  </div>
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
                        dir="ltr"
                        name="email"
                        autoComplete="email"
                        inputMode="email"
                        required
                        placeholder={t('auth.emailPlaceholder')}
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
                      placeholder={t('auth.passwordPlaceholder')}
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
                        hint={t('auth.passwordMinHint', { count: PASSWORD_MIN })}
                      />
                      <label>
                        {t('auth.username')}
                        <input
                          value={username}
                          onChange={(event) => setUsername(event.target.value.toLowerCase())}
                          dir="ltr"
                          name="username"
                          autoComplete="username"
                          required
                          minLength={3}
                          placeholder={t('auth.usernamePlaceholder')}
                        />
                        <span className="au-field-hint">{t('auth.usernameHint')}</span>
                      </label>
                      <label>
                        {t('auth.displayName')}
                        <input
                          value={displayName}
                          onChange={(event) => setDisplayName(event.target.value)}
                          dir="auto"
                          name="name"
                          autoComplete="name"
                          required
                          placeholder={t('auth.displayNamePlaceholder')}
                        />
                        <span className="au-field-hint">{t('auth.displayNameHint')}</span>
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
                      hint={t('auth.passwordMinHint', { count: PASSWORD_MIN })}
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
                  <DirectionalArrow dir={dir} />
                </button>
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
                    <button
                      className="ghost-button au-block"
                      disabled={busy}
                      type="button"
                      onClick={() => void continueAsGuest()}
                    >
                      {t('auth.keepGuest')}
                      <DirectionalArrow dir={dir} />
                    </button>
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
