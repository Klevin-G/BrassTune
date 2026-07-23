import type { ReactNode } from 'react';
import { BarChart3, FolderOpen, Gauge, LogIn, Music2, Settings, Target, UserRound, Users } from 'lucide-react';
import { Link, NavLink, useLocation } from 'react-router-dom';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { usePracticeLibrary } from '../state/PracticeLibraryContext';
import { InstrumentSelector } from './InstrumentSelector';
import { OnboardingFlow } from './OnboardingFlow';
import { FocusedWorkspaceBar } from './practice/FocusedWorkspaceBar';
import './practice/PracticeFeatures.css';
import { FloatingTabBar } from './ui/AppPrimitives';

// One flat set of destinations, identical on the desktop sidebar and the mobile
// tab bar. Metronome and Sheet music are in-page tools launched from the Tuner,
// not top-level nav; Coach/Sessions are folded into Progress.
const primaryNav = [
  { to: '/practice', label: 'Tuner', icon: Gauge },
  { to: '/practice/play-along', label: 'Play-Along', icon: Target },
  { to: '/progress', label: 'Progress', icon: BarChart3 },
  { to: '/ensemble', label: 'Class', icon: Users },
  { to: '/settings', label: 'Settings', icon: Settings },
];

export function AppShell({ children }: { children: ReactNode }) {
  const { instrumentId, setInstrumentId } = useAppSettings();
  const auth = useAuth();
  const { workspace } = usePracticeLibrary();
  const location = useLocation();
  const authRoute = location.pathname === '/' || location.pathname.startsWith('/auth/');

  return (
    <div className={`app-shell ${authRoute ? 'auth-shell' : ''} ${workspace ? 'focus-mode' : ''}`}>
      {!authRoute && !workspace && (
        <aside className="sidebar">
          <NavLink to="/practice" className="brand" aria-label="BrassTune home">
            <span className="brand-mark">
              <Music2 size={19} />
            </span>
            <span>
              <strong>BrassTune</strong>
              <small>Brass tuner</small>
            </span>
          </NavLink>
          <nav className="nav-list" aria-label="Primary navigation">
            {primaryNav.map((item) => (
              <NavLink
                to={item.to}
                key={item.to}
                aria-label={item.label}
                className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}
                end={item.to === '/practice'}
              >
                <item.icon size={18} />
                <span>{item.label}</span>
              </NavLink>
            ))}
          </nav>
        </aside>
      )}
      <div className="app-main">
        {!authRoute && !workspace && (
          <header className="topbar">
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} compact />
            <div className="topbar-controls">
              <Link to="/sessions" className="icon-button labeled" aria-label="Open recordings">
                <FolderOpen size={18} />
                <span>Recordings</span>
              </Link>
              {auth.isSignedIn ? (
                <Link to="/settings" className="icon-button labeled" aria-label="Open profile settings">
                  <UserRound size={18} />
                  <span>{auth.profile?.username ?? 'Profile'}</span>
                </Link>
              ) : !auth.configured ? (
                <Link to="/practice" className="icon-button labeled" aria-label="Continue as guest" onClick={auth.continueAsGuest}>
                  <UserRound size={18} />
                  <span>Guest</span>
                </Link>
              ) : (
                <Link to="/" className="icon-button labeled" aria-label="Sign in">
                  <LogIn size={18} />
                  <span>Sign in</span>
                </Link>
              )}
            </div>
          </header>
        )}
        <main className="content">{children}</main>
        {!authRoute && <FocusedWorkspaceBar />}
        {!authRoute && !auth.loading && (auth.isSignedIn || auth.guestMode) && <OnboardingFlow />}
        {!authRoute && !workspace && (
          <FloatingTabBar>
            {primaryNav.map((item) => (
              <NavLink
                to={item.to}
                key={item.to}
                aria-label={item.label}
                className={({ isActive }) => (isActive ? 'active' : '')}
                end={item.to === '/practice'}
              >
                <item.icon size={19} />
                <span>{item.label}</span>
              </NavLink>
            ))}
          </FloatingTabBar>
        )}
      </div>
    </div>
  );
}
