import { Activity, FileText, GraduationCap, LogIn, LogOut, Music2, Settings, Timer, UserRound, Users } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';

const moreItems = [
  { to: '/coach', title: 'Coach', detail: 'Personalized practice plan and recommendations.', icon: GraduationCap },
  { to: '/metronome', title: 'Metronome', detail: 'Tempo, count-in, subdivisions, and ramp practice.', icon: Timer },
  { to: '/practice/sheet-music', title: 'Sheet music', detail: 'Read imported PDF or photo sheet music while you practice.', icon: FileText },
  { to: '/sessions', title: 'Sessions', detail: 'Review practice history and open saved takes.', icon: Music2 },
  { to: '/progress', title: 'Progress', detail: 'See weekly pulse, improvement, and consistency.', icon: Activity },
  { to: '/ensemble', title: 'Ensemble', detail: 'Create a class, add students, and track their practice.', icon: Users },
  { to: '/settings', title: 'Settings', detail: 'Instrument, A4 reference, and practice preferences.', icon: Settings },
  { to: '/privacy', title: 'Privacy', detail: 'Data use, export, deletion, and recording handling.', icon: FileText },
  { to: '/terms', title: 'Terms', detail: 'Use rules for practice analytics and account data.', icon: FileText },
  { to: '/support', title: 'Support', detail: 'Help guidance for accounts, recording, playback, and ensembles.', icon: FileText },
];

export function MorePage() {
  const auth = useAuth();
  const [status, setStatus] = useState('');
  return (
    <ScreenContainer className="more-screen">
      <PageHeader
        eyebrow="Secondary hub"
        title="More"
        description="The core practice loop stays close at hand. Reporting, saved work, and configuration live here when you need them."
      />
      <SectionCard title="Workspace">
        <div className="more-grid">
          {moreItems.map((item) => (
            <Link className="action-tile" key={item.to} to={item.to}>
              <span className="action-icon">
                <item.icon size={19} />
              </span>
              <span>
                <strong>{item.title}</strong>
                <em>{item.detail}</em>
              </span>
            </Link>
          ))}
        </div>
      </SectionCard>
      <SectionCard title="Account" eyebrow={auth.isSignedIn ? 'Signed in' : 'Guest practice'}>
        <div className="account-card">
          <span className="insight-icon">
            <UserRound size={18} />
          </span>
          <div>
            <strong>{auth.profile?.display_name ?? auth.user?.email ?? 'Guest player'}</strong>
            <em>{auth.profile?.username ? `@${auth.profile.username}` : 'Guest practice mode'}</em>
          </div>
          {auth.isSignedIn ? (
            <button className="ghost-button" type="button" onClick={() => auth.signOut().then(() => setStatus('Signed out.')).catch(() => setStatus('Sign-out could not complete. Try again.'))}>
              <LogOut size={17} />
              Sign out
            </button>
          ) : (
            <Link className="primary-button" to={auth.configured ? '/' : '/home'} onClick={!auth.configured ? auth.continueAsGuest : undefined}>
              <LogIn size={17} />
              {auth.configured ? 'Sign in' : 'Continue as guest'}
            </Link>
          )}
        </div>
        {status && <p className="settings-status" aria-live="polite">{status}</p>}
      </SectionCard>
      <SectionCard title="Quick export" eyebrow="Reports">
        <div className="insight-grid">
          <article className="insight-card tone-gold">
            <div className="insight-heading">
              <span className="insight-icon">
                <FileText size={18} />
              </span>
              <div>
                <h3>Session reports</h3>
                <span>CSV and JSON exports stay available inside each session review.</span>
              </div>
            </div>
            <p>Use review screens for handoff-ready evidence: averages, heatmaps, note tables, and coach notes.</p>
          </article>
        </div>
      </SectionCard>
    </ScreenContainer>
  );
}
