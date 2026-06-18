import { ArrowRight, KeyRound, LogIn, Mail, ShieldCheck, UserPlus } from 'lucide-react';
import { FormEvent, useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { EmptyActionState, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';

export function AuthPage({ mode }: { mode: 'sign-in' | 'sign-up' | 'reset' | 'callback' }) {
  const auth = useAuth();
  const navigate = useNavigate();
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
    setMessage(error ? `Sign-in was not completed: ${error}` : 'Supabase is restoring your session. Continue when the session is ready.');
  }, [mode]);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      if (mode === 'sign-in') {
        await auth.signIn(email, password);
        navigate('/');
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
        <SectionCard title="Finishing sign in" eyebrow="Auth callback">
          <p className="muted-copy" role="status">{message ?? 'Supabase will restore the browser session automatically.'}</p>
          <Link className="primary-button" to="/">
            Continue
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
            Sign in keeps your sessions, audio playback, analytics, and ensemble membership tied to your account. Guest practice remains available on this device.
          </p>
        </section>
        <SectionCard title={isSignup ? 'Sign up' : mode === 'reset' ? 'Reset password' : 'Sign in'} eyebrow={auth.configured ? 'Account access' : 'Guest mode active'}>
          {!auth.configured && (
            <EmptyActionState
              title="Account sign-in is unavailable"
              body="Sign-in is temporarily unavailable. Guest practice remains available on this device."
              icon={Mail}
            />
          )}
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
            <button className="primary-button" disabled={busy || !auth.configured} type="submit">
              {isSignup ? <UserPlus size={18} /> : mode === 'reset' ? <KeyRound size={18} /> : <LogIn size={18} />}
              {busy ? 'Working...' : isSignup ? 'Create account' : mode === 'reset' && auth.isSignedIn && newPassword ? 'Update password' : mode === 'reset' ? 'Send reset link' : 'Sign in'}
            </button>
          </form>
          {mode !== 'reset' && (
            <button className="ghost-button full-width-action" disabled={busy || !auth.configured} type="button" onClick={() => auth.signInWithApple().catch((error) => setMessage(error instanceof Error ? error.message : 'Apple sign-in failed.'))}>
              <ShieldCheck size={18} />
              Continue with Apple
            </button>
          )}
          {message && <div className="alert" role="status">{message}</div>}
          <div className="auth-switcher">
            {isSignup ? <Link to="/auth/sign-in">Already have an account?</Link> : <Link to="/auth/sign-up">Create an account</Link>}
            <Link to="/auth/reset-password">Reset password</Link>
          </div>
        </SectionCard>
      </div>
    </ScreenContainer>
  );
}
