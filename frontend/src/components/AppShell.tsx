import type { ReactNode } from 'react';
import { Activity, BarChart3, Gauge, GraduationCap, Home, MoreHorizontal, Music2, Settings, SlidersHorizontal, Users } from 'lucide-react';
import { NavLink, useLocation } from 'react-router-dom';
import { useAppSettings } from '../state/AppSettingsContext';
import { InstrumentSelector } from './InstrumentSelector';
import { FloatingTabBar, StatusBadge } from './ui/AppPrimitives';

const primaryNav = [
  { to: '/', label: 'Home', icon: Home },
  { to: '/practice', label: 'Practice', icon: Gauge },
  { to: '/analytics', label: 'Analytics', icon: BarChart3 },
  { to: '/coach', label: 'Coach', icon: GraduationCap },
  { to: '/more', label: 'More', icon: MoreHorizontal },
];

const secondaryNav = [
  { to: '/sessions', label: 'Sessions', icon: Music2 },
  { to: '/progress', label: 'Progress', icon: Activity },
  { to: '/ensemble', label: 'Ensemble', icon: Users },
  { to: '/settings', label: 'Settings', icon: Settings },
];

export function AppShell({ children }: { children: ReactNode }) {
  const { instrumentId, setInstrumentId, referencePitch, setReferencePitch, demoMode, setDemoMode } = useAppSettings();
  const location = useLocation();
  const moreActive = location.pathname === '/more' || secondaryNav.some((item) => location.pathname.startsWith(item.to));

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <NavLink to="/" className="brand">
          <span className="brand-mark">
            <SlidersHorizontal size={19} />
          </span>
          <span>
            <strong>BrassTune</strong>
            <small>Analytics</small>
          </span>
        </NavLink>
        <nav className="nav-list" aria-label="Primary navigation">
          {primaryNav.map((item) => (
            <NavLink
              to={item.to}
              key={item.to}
              className={({ isActive }) => `nav-item ${item.to === '/more' ? (moreActive ? 'active' : '') : isActive ? 'active' : ''}`}
              end={item.to === '/'}
            >
              <item.icon size={18} />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
        <p className="sidebar-section-label">More</p>
        <nav className="secondary-nav" aria-label="Secondary navigation">
          {secondaryNav.map((item) => (
            <NavLink to={item.to} key={item.to} className={({ isActive }) => `secondary-nav-item ${isActive ? 'active' : ''}`}>
              <item.icon size={17} />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
      </aside>
      <div className="app-main">
        <header className="topbar">
          <div>
            <p className="topbar-label">Practice cockpit</p>
            <h1>BrassTune</h1>
          </div>
          <div className="topbar-controls">
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} compact />
            <label className="control-inline">
              A4
              <input
                className="number-input"
                type="number"
                min={430}
                max={450}
                step={0.5}
                value={referencePitch}
                onChange={(event) => setReferencePitch(Number(event.target.value))}
              />
            </label>
            <button className={`toggle ${demoMode ? 'on' : ''}`} onClick={() => setDemoMode(!demoMode)} type="button">
              Demo
            </button>
            <StatusBadge tone={demoMode ? 'gold' : 'green'}>{demoMode ? 'Seeded audio' : 'Mic ready'}</StatusBadge>
          </div>
        </header>
        <main className="content">{children}</main>
        <FloatingTabBar>
          {primaryNav.map((item) => (
            <NavLink
              to={item.to}
              key={item.to}
              className={({ isActive }) => (item.to === '/more' ? (moreActive ? 'active' : '') : isActive ? 'active' : '')}
              end={item.to === '/'}
            >
              <item.icon size={19} />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </FloatingTabBar>
      </div>
    </div>
  );
}
