import { ArrowRight, CheckCircle2, ChevronDown, KeyRound, LogIn, Mail, Music2, ShieldCheck, UserPlus } from 'lucide-react';
import { GoogleIcon } from '../components/GoogleIcon';
import { FormEvent, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { EmptyActionState, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';
import { readPendingAuthReturn, safeReturnPath } from '../domain/authNavigation';
import { useI18n } from '../i18n/LocaleContext';
import './AuthGatewayPage.css';

function consumePendingAuthNext() {
  return readPendingAuthReturn({ consume: true });
}

export function AuthGatewayPage() {
  const auth = useAuth();
  const { t } = useI18n();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const next = useMemo(() => safeReturnPath(params.get('next')), [params]);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [showEmail, setShowEmail] = useState(false);

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
      setMessage(error instanceof Error ? error.message : t('auth.failure'));
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
                <button className="primary-button ag-block ag-guest" type="button" onClick={continueAsGuest}>
                  {t('auth.start')}
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
                        <button className="google-button ag-block" disabled={busy} type="button" onClick={() => auth.signInWithGoogle(callbackNext).catch((error) => setMessage(error instanceof Error ? error.message : t('auth.googleFailure')))}>
                          <GoogleIcon size={18} />
                          {t('auth.google')}
                        </button>
                      )}
                      {auth.providers.apple && (
                        <button className="ghost-button ag-block" disabled={busy} type="button" onClick={() => auth.signInWithApple(callbackNext).catch((error) => setMessage(error instanceof Error ? error.message : t('auth.appleFailure')))}>
                          <ShieldCheck size={18} />
                          {t('auth.apple')}
                        </button>
                      )}
                    </div>
                    <div className="auth-divider" aria-hidden="true"><span>{t('auth.or')}</span></div>
                  </>
                )}

                <button className="primary-button ag-block ag-guest" type="button" onClick={continueAsGuest}>
                  {t('auth.start')}
                  <ArrowRight size={18} />
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
                        <input value={email} onChange={(event) => setEmail(event.target.value)} type="email" required placeholder="you@example.com" />
                      </label>
                      <label>
                        {t('auth.password')}
                        <input value={password} onChange={(event) => setPassword(event.target.value)} type="password" required minLength={6} placeholder="At least 6 characters" />
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
            {(message || auth.profileError) && <div className="alert" role="status">{message ?? auth.profileError}</div>}
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
