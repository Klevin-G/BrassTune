import type { ReactNode } from 'react';
import { BarChart3, FolderOpen, Gauge, LogIn, Music2, Settings, Target, UserRound, Users } from 'lucide-react';
import { Link, NavLink, useLocation } from 'react-router-dom';
import { gatewayPathWithReturn } from '../domain/authNavigation';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { usePracticeLibrary } from '../state/PracticeLibraryContext';
import { InstrumentSelector } from './InstrumentSelector';
import { OnboardingFlow } from './OnboardingFlow';
import { FocusedWorkspaceBar } from './practice/FocusedWorkspaceBar';
import './practice/PracticeFeatures.css';
import { FloatingTabBar } from './ui/AppPrimitives';
import { useI18n } from '../i18n/LocaleContext';

// One flat set of destinations, identical on the desktop sidebar and the mobile
// tab bar. Metronome and Sheet music are in-page tools launched from the Tuner,
// not top-level nav; Coach/Sessions are folded into Progress.
const primaryNav = [
  { to: '/practice', labelId: 'nav.tuner' as const, icon: Gauge },
  { to: '/practice/scorer', labelId: 'nav.playAlong' as const, icon: Target },
  { to: '/progress', labelId: 'nav.progress' as const, icon: BarChart3 },
  { to: '/ensemble', labelId: 'nav.class' as const, icon: Users },
  { to: '/settings', labelId: 'nav.settings' as const, icon: Settings },
];

export function AppShell({ children }: { children: ReactNode }) {
  const { instrumentId, setInstrumentId } = useAppSettings();
  const auth = useAuth();
  const { workspace } = usePracticeLibrary();
  const { t } = useI18n();
  const location = useLocation();
  const authRoute = location.pathname === '/' || location.pathname.startsWith('/auth/');
  const currentReturnPath = `${location.pathname}${location.search}${location.hash}`;

  return (
    <div className={`app-shell ${authRoute ? 'auth-shell' : ''} ${workspace ? 'focus-mode' : ''}`}>
      {!authRoute && <a className="skip-link" href="#main-content">{t('a11y.skip')}</a>}
      {!authRoute && !workspace && (
        <aside className="sidebar">
          <NavLink to="/practice" className="brand" aria-label={t('app.home')}>
            <span className="brand-mark">
              <Music2 size={19} />
            </span>
            <span>
              <strong>BrassTune</strong>
              <small>{t('app.subtitle')}</small>
            </span>
          </NavLink>
          <nav className="nav-list" aria-label={t('nav.primary')}>
            {primaryNav.map((item) => (
              <NavLink
                to={item.to}
                key={item.to}
                aria-label={t(item.labelId)}
                className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}
                end={item.to === '/practice'}
              >
                <item.icon size={18} />
                <span>{t(item.labelId)}</span>
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
              <Link to="/sessions" className="icon-button labeled" aria-label={t('nav.recordings')}>
                <FolderOpen size={18} />
                <span>{t('nav.recordings')}</span>
              </Link>
              {auth.isSignedIn ? (
                <Link to="/settings" className="icon-button labeled" aria-label={t('nav.profile')}>
                  <UserRound size={18} />
                  <span>{auth.profile?.username ?? t('nav.profile')}</span>
                </Link>
              ) : !auth.configured ? (
                <Link to="/practice" className="icon-button labeled" aria-label={t('nav.guest')} onClick={auth.continueAsGuest}>
                  <UserRound size={18} />
                  <span>{t('nav.guest')}</span>
                </Link>
              ) : (
                <Link to={gatewayPathWithReturn(currentReturnPath)} className="icon-button labeled" aria-label={t('nav.signIn')} onClick={auth.exitGuest}>
                  <LogIn size={18} />
                  <span>{t('nav.signIn')}</span>
                </Link>
              )}
            </div>
          </header>
        )}
        <main className="content" id="main-content" tabIndex={-1}>{children}</main>
        {!authRoute && <FocusedWorkspaceBar />}
        {!authRoute && !auth.loading && (auth.isSignedIn || auth.guestMode) && <OnboardingFlow />}
        {!authRoute && !workspace && (
          <FloatingTabBar ariaLabel={t('nav.primary')}>
            {primaryNav.map((item) => (
              <NavLink
                to={item.to}
                key={item.to}
                aria-label={t(item.labelId)}
                className={({ isActive }) => (isActive ? 'active' : '')}
                end={item.to === '/practice'}
              >
                <item.icon size={19} />
                <span>{t(item.labelId)}</span>
              </NavLink>
            ))}
          </FloatingTabBar>
        )}
      </div>
    </div>
  );
}
