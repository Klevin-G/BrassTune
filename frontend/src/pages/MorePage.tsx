import { Activity, Bug, FileText, LogIn, LogOut, Music2, Settings, UserRound, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';

const moreItems = [
  { to: '/sessions', title: 'Sessions', detail: 'Review practice history and open saved takes.', icon: Music2 },
  { to: '/progress', title: 'Progress', detail: 'See weekly pulse, improvement, and consistency.', icon: Activity },
  { to: '/ensemble', title: 'Ensemble', detail: 'Director briefing cards and rehearsal focus.', icon: Users },
  { to: '/settings', title: 'Settings', detail: 'Instrument, A4 reference, and demo preferences.', icon: Settings },
  { to: '/settings/audio-lab', title: 'Audio Lab', detail: 'Developer calibration readout for real-device tuning tests.', icon: Bug },
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
      <SectionCard title="Account" eyebrow={auth.isSignedIn ? 'Signed in' : 'Guest demo'}>
        <div className="account-card">
          <span className="insight-icon">
            <UserRound size={18} />
          </span>
          <div>
            <strong>{auth.profile?.display_name ?? auth.user?.email ?? 'Guest player'}</strong>
            <em>{auth.profile?.username ? `@${auth.profile.username}` : 'Local demo mode'}</em>
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
      <SectionCard title="Quick export" eyebrow="Local MVP">
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
