import { ArrowRight, KeyRound, LogIn, Mail, ShieldCheck, UserPlus } from 'lucide-react';
import { FormEvent, useEffect, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { EmptyActionState, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';

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
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const isSignup = mode === 'sign-up';

  useEffect(() => {
    if (mode !== 'callback') return;
    const params = new URLSearchParams(window.location.search || window.location.hash.replace(/^#/, '?'));
    const error = params.get('error_description') || params.get('error');
    setMessage(error ? 'Sign-in was not completed. You can keep using guest practice and try account access again later.' : 'Finishing sign-in. Continue when your account session is ready.');
  }, [mode]);

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
        setMessage('Account created. If email confirmation is enabled, confirm your email before signing in.');
      } else if (auth.isSignedIn && newPassword) {
        await auth.updatePassword(newPassword);
        setMessage('Password updated. Use the new password the next time you sign in.');
        setNewPassword('');
      } else {
        await auth.requestPasswordReset(email);
        setMessage('Password reset email sent. Open the link on this device to choose a new password.');
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Authentication failed.');
    } finally {
      setBusy(false);
    }
  }

  if (mode === 'callback') {
    return (
      <ScreenContainer>
        <SectionCard title="Finishing sign in" eyebrow="Account access">
          <p className="muted-copy" role="status">{auth.configured ? message ?? 'Finishing sign-in. Continue when your account session is ready.' : 'Accounts are not enabled in this build yet. You can still use guest practice.'}</p>
          <Link className="primary-button" to={auth.configured ? next : next} onClick={!auth.configured ? auth.continueAsGuest : undefined}>
            {auth.configured ? 'Continue' : 'Continue as guest'}
            <ArrowRight size={18} />
          </Link>
        </SectionCard>
      </ScreenContainer>
    );
  }

  return (
    <ScreenContainer>
      <div className="auth-layout">
        <section className="auth-panel">
          <div className="brand auth-brand">
            <span className="brand-mark">
              <ShieldCheck size={20} />
            </span>
            <span>
              <strong>BrassTune</strong>
              <small>{isSignup ? 'Create account' : mode === 'reset' ? 'Reset access' : 'Sign in'}</small>
            </span>
          </div>
          <h1>{isSignup ? 'Start tracking your tuning patterns.' : 'Welcome back to your practice cockpit.'}</h1>
          <p>
            Account access keeps your sessions, audio playback, analytics, and ensemble membership synced. Guest practice remains available on this device.
          </p>
        </section>
        <SectionCard title={isSignup ? 'Sign up' : mode === 'reset' ? 'Reset password' : 'Sign in'} eyebrow={auth.configured ? 'Account access' : 'Guest mode active'}>
          {!auth.configured && (
            <>
              <EmptyActionState
                title="Accounts are not enabled in this build yet"
                body="You can still use guest practice. Sign-in, syncing, and ensemble membership will be available when account access is enabled."
                icon={Mail}
              />
              <Link className="primary-button full-width-action" to="/home" onClick={auth.continueAsGuest}>
                Continue as guest
                <ArrowRight size={18} />
              </Link>
            </>
          )}
          {auth.configured && (
            <form className="auth-form" onSubmit={onSubmit}>
              <label>
                Email
                <input value={email} onChange={(event) => setEmail(event.target.value)} type="email" required={!auth.isSignedIn || mode !== 'reset'} placeholder="you@example.com" />
              </label>
              {mode !== 'reset' && (
                <label>
                  Password
                  <input value={password} onChange={(event) => setPassword(event.target.value)} type="password" required minLength={6} placeholder="Minimum 6 characters" />
                </label>
              )}
              {isSignup && (
                <>
                  <label>
                    Username
                    <input value={username} onChange={(event) => setUsername(event.target.value.toLowerCase())} required minLength={3} placeholder="avery" />
                  </label>
                  <label>
                    Display name
                    <input value={displayName} onChange={(event) => setDisplayName(event.target.value)} required placeholder="Avery Brass" />
                  </label>
                  <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
                </>
              )}
              {mode === 'reset' && auth.isSignedIn && (
                <label>
                  New password
                  <input value={newPassword} onChange={(event) => setNewPassword(event.target.value)} type="password" minLength={8} placeholder="Minimum 8 characters" />
                </label>
              )}
              <button className="primary-button" disabled={busy} type="submit">
                {isSignup ? <UserPlus size={18} /> : mode === 'reset' ? <KeyRound size={18} /> : <LogIn size={18} />}
                {busy ? 'Working...' : isSignup ? 'Create account' : mode === 'reset' && auth.isSignedIn && newPassword ? 'Update password' : mode === 'reset' ? 'Send reset link' : 'Sign in'}
              </button>
            </form>
          )}
          {mode !== 'reset' && auth.configured && (
            <div className="provider-button-stack">
              {auth.providers.google && (
                <button className="ghost-button full-width-action" disabled={busy} type="button" onClick={() => auth.signInWithGoogle(`${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`).catch((error) => setMessage(error instanceof Error ? error.message : 'Google sign-in could not start. Try again later.'))}>
                  Continue with Google
                </button>
              )}
              {auth.providers.apple && (
                <button className="ghost-button full-width-action" disabled={busy} type="button" onClick={() => auth.signInWithApple(`${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`).catch((error) => setMessage(error instanceof Error ? error.message : 'Apple sign-in could not start. Try again later.'))}>
                  <ShieldCheck size={18} />
                  Continue with Apple
                </button>
              )}
            </div>
          )}
          {message && <div className="alert" role="status">{message}</div>}
          {auth.configured && (
            <div className="auth-switcher">
              {isSignup ? <Link to="/auth/sign-in">Already have an account?</Link> : <Link to="/auth/sign-up">Create an account</Link>}
              <Link to="/auth/reset-password">Reset password</Link>
            </div>
          )}
        </SectionCard>
      </div>
    </ScreenContainer>
  );
}
