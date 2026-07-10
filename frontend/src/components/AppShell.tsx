import type { ReactNode } from 'react';
import { Activity, BarChart3, FileText, Gauge, GraduationCap, Home, LogIn, MoreHorizontal, Music2, Settings, Target, Timer, UserRound, Users } from 'lucide-react';
import { Link, NavLink, useLocation } from 'react-router-dom';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { InstrumentSelector } from './InstrumentSelector';
import { OnboardingFlow } from './OnboardingFlow';
import { FloatingTabBar } from './ui/AppPrimitives';

const primaryNav = [
  { to: '/home', label: 'Home', icon: Home },
  { to: '/practice', label: 'Practice', icon: Gauge },
  { to: '/practice/play-along', label: 'Play-Along', icon: Target },
  { to: '/analytics', label: 'Analytics', icon: BarChart3 },
  { to: '/more', label: 'More', icon: MoreHorizontal },
];

const secondaryNav = [
  { to: '/coach', label: 'Coach', icon: GraduationCap },
  { to: '/metronome', label: 'Metronome', icon: Timer },
  { to: '/practice/score', label: 'Score', icon: FileText },
  { to: '/sessions', label: 'Sessions', icon: Music2 },
  { to: '/progress', label: 'Progress', icon: Activity },
  { to: '/ensemble', label: 'Ensemble', icon: Users },
  { to: '/settings', label: 'Settings', icon: Settings },
];

export function AppShell({ children }: { children: ReactNode }) {
  const { instrumentId, setInstrumentId, demoMode, setDemoMode } = useAppSettings();
  const auth = useAuth();
  const location = useLocation();
  const moreActive = location.pathname === '/more' || secondaryNav.some((item) => location.pathname.startsWith(item.to));
  const authRoute = location.pathname === '/' || location.pathname.startsWith('/auth/');

  return (
    <div className={`app-shell ${authRoute ? 'auth-shell' : ''}`}>
      {!authRoute && <aside className="sidebar">
        <NavLink to="/home" className="brand" aria-label="BrassTune home">
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
              className={({ isActive }) => `nav-item ${item.to === '/more' ? (moreActive ? 'active' : '') : isActive ? 'active' : ''}`}
              end={item.to === '/' || item.to === '/practice'}
            >
              <item.icon size={18} />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
        <p className="sidebar-section-label">More</p>
        <nav className="secondary-nav" aria-label="Secondary navigation">
          {secondaryNav.map((item) => (
            <NavLink to={item.to} key={item.to} aria-label={item.label} className={({ isActive }) => `secondary-nav-item ${isActive ? 'active' : ''}`}>
              <item.icon size={17} />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
      </aside>}
      <div className="app-main">
        {!authRoute && <header className="topbar">
          <div>
            <p className="topbar-label">Practice cockpit</p>
            <h1>BrassTune</h1>
          </div>
          <div className="topbar-controls">
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} compact />
            <button
              className={`toggle ${demoMode ? 'on' : ''}`}
              onClick={() => setDemoMode(!demoMode)}
              type="button"
              aria-pressed={demoMode}
              aria-label={demoMode ? 'Switch to microphone mode' : 'Switch to guided audio mode'}
            >
              {demoMode ? 'Guided audio' : 'Microphone'}
            </button>
            {auth.isSignedIn ? (
              <Link to="/settings" className="icon-button labeled" aria-label="Open profile settings">
                <UserRound size={18} />
                <span>{auth.profile?.username ?? 'Profile'}</span>
              </Link>
            ) : !auth.configured ? (
              <Link to="/home" className="icon-button labeled" aria-label="Continue as guest" onClick={auth.continueAsGuest}>
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
        </header>}
        <main className="content">{children}</main>
        {!authRoute && <OnboardingFlow />}
        {!authRoute && <FloatingTabBar>
          {primaryNav.map((item) => (
            <NavLink
              to={item.to}
              key={item.to}
              aria-label={item.label}
              className={({ isActive }) => (item.to === '/more' ? (moreActive ? 'active' : '') : isActive ? 'active' : '')}
              end={item.to === '/' || item.to === '/practice'}
            >
              <item.icon size={19} />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </FloatingTabBar>}
      </div>
    </div>
  );
}
