import { ArrowRight, CheckCircle2, ChevronDown, KeyRound, LogIn, Mail, Music2, UserPlus } from 'lucide-react';
import { appleSignInLogo } from '../assets/appleSignInLogo';
import { GoogleIcon } from '../components/GoogleIcon';
import { FormEvent, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { EmptyActionState, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';
import { clearPendingAuthReturn, readPendingAuthReturn, rememberPendingAuthReturn, safeReturnPath } from '../domain/authNavigation';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';
import './AuthGatewayPage.css';

function consumePendingAuthNext() {
  return readPendingAuthReturn({ consume: true });
}

export function AuthGatewayPage() {
  const auth = useAuth();
  const { dir, t } = useI18n();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const next = useMemo(() => safeReturnPath(params.get('next')), [params]);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [oauthProvider, setOauthProvider] = useState<'google' | 'apple' | null>(null);
  const [showEmail, setShowEmail] = useState(false);

  function localizeAuthError(error: unknown, fallback: MessageId) {
    const raw = error instanceof Error ? error.message : typeof error === 'string' ? error : '';
    const lower = raw.toLowerCase();
    if (lower.includes('email or password') || lower.includes('credentials')) return t('auth.errorCredentials');
    if (lower.includes('already exists') || lower.includes('already registered')) return t('auth.errorExists');
    if (lower.includes('stronger password') || lower.includes('weak password')) return t('auth.errorWeakPassword');
    if (lower.includes('confirm your email')) return t('auth.errorConfirmEmail');
    if (lower.includes('expired')) return t('auth.errorExpired');
    if (lower.includes('cancel')) return t('auth.errorCancelled');
    if (lower.includes('network') || lower.includes('reach the server')) return t('auth.errorNetwork');
    return t(fallback);
  }

  useEffect(() => {
    if (!auth.loading && auth.isSignedIn) {
      const storedNext = consumePendingAuthNext();
      const destination = params.has('next') ? next : safeReturnPath(storedNext);
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
      setMessage(localizeAuthError(error, 'auth.failure'));
    } finally {
      setBusy(false);
    }
  }

  async function continueAsGuest() {
    setBusy(true);
    setMessage(null);
    try {
      await auth.continueAsGuest();
      navigate(next, { replace: true });
    } catch (error) {
      setMessage(localizeAuthError(error, 'auth.failure'));
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
      setMessage(localizeAuthError(error, provider === 'google' ? 'auth.googleFailure' : 'auth.appleFailure'));
    } finally {
      setBusy(false);
      setOauthProvider(null);
    }
  }

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
          <h1>{t('auth.heading')}</h1>
          <p className="ag-lead">
            {t('auth.lead')}
          </p>
          <span className="ag-noaccount">
            <CheckCircle2 size={16} />
            {t('auth.noAccount')}
          </span>
        </section>

        <div className="gateway-stack">
          <SectionCard>
            {auth.loading && <p className="muted-copy" role="status">{t('auth.restore')}</p>}

            {!auth.loading && !auth.configured && (
              <>
                <EmptyActionState
                  title={t('auth.ready')}
                  body={t('auth.readyBody')}
                  icon={Music2}
                />
                <button className="primary-button ag-block ag-guest" disabled={busy} type="button" onClick={() => void continueAsGuest()}>
                  {t('auth.start')}
                  <ArrowRight size={18} style={{ transform: dir === 'rtl' ? 'scaleX(-1)' : undefined }} />
                </button>
              </>
            )}

            {!auth.loading && auth.configured && (
              <>
                <div className="ag-providers">
                  <button
                    className="google-button ag-block"
                    disabled={busy || !auth.providers.google}
                    type="button"
                    onClick={() => void beginOAuth('google')}
                  >
                    <GoogleIcon size={18} />
                    {oauthProvider === 'google'
                      ? t('auth.googleLoading')
                      : auth.providers.google ? t('auth.google') : t('auth.googleUnavailable')}
                  </button>
                  <button
                    className="apple-button ag-block"
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
                <div className="auth-divider" aria-hidden="true"><span>{t('auth.or')}</span></div>

                <button className="primary-button ag-block ag-guest" disabled={busy} type="button" onClick={() => void continueAsGuest()}>
                  {t('auth.start')}
                  <ArrowRight size={18} style={{ transform: dir === 'rtl' ? 'scaleX(-1)' : undefined }} />
                </button>
                <p className="ag-nudge">{t('auth.newHere')}</p>

                <button
                  type="button"
                  className="ghost-button ag-block ag-email-toggle"
                  aria-expanded={showEmail}
                  aria-controls="ag-email-region"
                  onClick={() => setShowEmail((open) => !open)}
                >
                  <span className="ag-email-toggle-label">
                    <Mail size={16} />
                    {t('auth.emailToggle')}
                  </span>
                  <ChevronDown className="ag-chevron" size={16} />
                </button>

                {showEmail && (
                  <div className="ag-email-region" id="ag-email-region">
                    <form className="auth-form" onSubmit={signIn}>
                      <label>
                        {t('auth.email')}
                        <input dir="ltr" value={email} onChange={(event) => setEmail(event.target.value)} type="email" required placeholder={t('auth.emailPlaceholder')} />
                      </label>
                      <label>
                        {t('auth.password')}
                        <input value={password} onChange={(event) => setPassword(event.target.value)} type="password" required minLength={6} placeholder={t('auth.passwordMinHint', { count: 6 })} />
                      </label>
                      <button className="primary-button ag-block" disabled={busy} type="submit">
                        <LogIn size={18} />
                        {busy ? t('auth.signingIn') : t('nav.signIn')}
                      </button>
                    </form>
                    <div className="auth-switcher">
                      <Link to={`/auth/sign-up?next=${encodeURIComponent(next)}`}>
                        <UserPlus size={16} />
                        {t('auth.create')}
                      </Link>
                      <Link to={`/auth/reset-password?next=${encodeURIComponent(next)}`}>
                        <KeyRound size={16} />
                        {t('auth.forgot')}
                      </Link>
                    </div>
                  </div>
                )}
              </>
            )}
            {(message || auth.profileError) && (
              <div className="alert" role="status">
                {message ?? localizeAuthError(auth.profileError, 'auth.failure')}
              </div>
            )}
          </SectionCard>
        </div>
      </div>

      <footer className="ag-footer" aria-label={t('auth.legal')}>
        <Link to="/privacy">{t('legal.privacy')}</Link>
        <Link to="/terms">{t('legal.terms')}</Link>
        <Link to="/support">{t('legal.support')}</Link>
      </footer>
    </ScreenContainer>
  );
}
