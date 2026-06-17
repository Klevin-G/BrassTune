import { ArrowRight, LogIn, Mail, ShieldCheck, UserPlus } from 'lucide-react';
import { FormEvent, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { EmptyActionState, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';

export function AuthPage({ mode }: { mode: 'sign-in' | 'sign-up' | 'reset' | 'callback' }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [instrumentId, setInstrumentId] = useState('trumpet');
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const isSignup = mode === 'sign-up';

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
      } else {
        setMessage('Password reset is configured in Supabase. Use the Supabase dashboard email templates for production redirects.');
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
          <p className="muted-copy">Supabase will restore the browser session automatically. You can return to BrassTune once the session is ready.</p>
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
            Sign in keeps your sessions, audio playback, analytics, and ensemble membership tied to your account. Guest demo mode stays available for local testing.
          </p>
        </section>
        <SectionCard title={isSignup ? 'Sign up' : mode === 'reset' ? 'Reset password' : 'Sign in'} eyebrow={auth.configured ? 'Supabase Auth' : 'Guest mode active'}>
          {!auth.configured && (
            <EmptyActionState
              title="Supabase env vars are not configured"
              body="Set VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY to enable real sign up/sign in. You can keep using the local demo now."
              icon={Mail}
            />
          )}
          <form className="auth-form" onSubmit={onSubmit}>
            <label>
              Email
              <input value={email} onChange={(event) => setEmail(event.target.value)} type="email" required={mode !== 'reset'} placeholder="you@example.com" />
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
            <button className="primary-button" disabled={busy || !auth.configured} type="submit">
              {isSignup ? <UserPlus size={18} /> : <LogIn size={18} />}
              {busy ? 'Working...' : isSignup ? 'Create account' : mode === 'reset' ? 'Send reset link' : 'Sign in'}
            </button>
          </form>
          {message && <div className="alert">{message}</div>}
          <div className="auth-switcher">
            {isSignup ? <Link to="/auth/sign-in">Already have an account?</Link> : <Link to="/auth/sign-up">Create an account</Link>}
            <Link to="/auth/reset-password">Reset password</Link>
          </div>
        </SectionCard>
      </div>
    </ScreenContainer>
  );
}
