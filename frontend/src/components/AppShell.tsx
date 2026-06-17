import { Activity, BarChart3, Gauge, GraduationCap, Home, Music2, Settings, SlidersHorizontal, Users } from 'lucide-react';
import { NavLink } from 'react-router-dom';
import { useAppSettings } from '../state/AppSettingsContext';
import { InstrumentSelector } from './InstrumentSelector';

const nav = [
  { to: '/', label: 'Dashboard', icon: Home },
  { to: '/practice', label: 'Practice', icon: Gauge },
  { to: '/sessions', label: 'Sessions', icon: Music2 },
  { to: '/analytics', label: 'Analytics', icon: BarChart3 },
  { to: '/progress', label: 'Progress', icon: Activity },
  { to: '/coach', label: 'Coach', icon: GraduationCap },
  { to: '/ensemble', label: 'Ensemble', icon: Users },
  { to: '/settings', label: 'Settings', icon: Settings },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const { instrumentId, setInstrumentId, referencePitch, setReferencePitch, demoMode, setDemoMode } = useAppSettings();
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
          {nav.map((item) => (
            <NavLink to={item.to} key={item.to} className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
              <item.icon size={18} />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
      </aside>
      <div className="app-main">
        <header className="topbar">
          <div>
            <p className="topbar-label">Local MVP</p>
            <h1>BrassTune Analytics</h1>
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
          </div>
        </header>
        <main className="content">{children}</main>
      </div>
    </div>
  );
}

