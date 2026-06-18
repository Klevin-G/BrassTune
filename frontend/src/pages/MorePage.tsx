import { Activity, Bug, FileText, LogIn, LogOut, Music2, Settings, UserRound, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';

const moreItems = [
  { to: '/sessions', title: 'Sessions', detail: 'Review practice history and open saved takes.', icon: Music2 },
  { to: '/progress', title: 'Progress', detail: 'See weekly pulse, improvement, and consistency.', icon: Activity },
  { to: '/ensemble', title: 'Ensemble', detail: 'Director briefing cards and rehearsal focus.', icon: Users },
  { to: '/settings', title: 'Settings', detail: 'Instrument, A4 reference, and practice preferences.', icon: Settings },
  { to: '/settings/audio-lab', title: 'Audio Lab', detail: 'Microphone and detector diagnostics for live tuning checks.', icon: Bug },
  { to: '/privacy', title: 'Privacy', detail: 'Data use, export, deletion, and recording handling.', icon: FileText },
  { to: '/terms', title: 'Terms', detail: 'Use rules for practice analytics and account data.', icon: FileText },
  { to: '/support', title: 'Support', detail: 'Help guidance for accounts, recording, playback, and ensembles.', icon: FileText },
];

export function MorePage() {
  const auth = useAuth();
  return (
    <ScreenContainer>
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
            <button className="ghost-button" type="button" onClick={() => auth.signOut()}>
              <LogOut size={17} />
              Sign out
            </button>
          ) : (
            <Link className="primary-button" to="/auth/sign-in">
              <LogIn size={17} />
              Sign in
            </Link>
          )}
        </div>
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
