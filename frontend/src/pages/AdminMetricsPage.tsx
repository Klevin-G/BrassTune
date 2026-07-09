import { Activity, BarChart3, Users } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { friendlyUserFacingError, getAdminMetrics, type AdminMetrics } from '../api/client';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';

function StatTile({ label, value, hint }: { label: string; value: string | number; hint?: string }) {
  return (
    <article className="stat-card">
      <span>{label}</span>
      <strong>{value}</strong>
      {hint && <p>{hint}</p>}
    </article>
  );
}

const EVENT_LABELS: Record<string, string> = {
  signup: 'Sign-ups',
  session_started: 'Sessions started',
  session_completed: 'Sessions completed',
  group_created: 'Ensembles created',
};

export function AdminMetricsPage() {
  const auth = useAuth();
  const [metrics, setMetrics] = useState<AdminMetrics | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!auth.isSignedIn) {
      setLoading(false);
      return;
    }
    getAdminMetrics()
      .then(setMetrics)
      .catch((err) => setError(friendlyUserFacingError(err, 'This dashboard is only available to admins.')))
      .finally(() => setLoading(false));
  }, [auth.isSignedIn]);

  if (!auth.isSignedIn || (!metrics && !loading)) {
    return (
      <ScreenContainer>
        <PageHeader eyebrow="Admin" title="Usage dashboard" description="Private product metrics for BrassTune admins." />
        <SectionCard title="Admins only" eyebrow="Restricted">
          <p className="muted-copy">{error || 'This dashboard is only available to admin accounts.'}</p>
          <Link to="/settings" className="ghost-button">Back to Settings</Link>
        </SectionCard>
      </ScreenContainer>
    );
  }

  const maxSignups = Math.max(1, ...(metrics?.signups_by_day ?? []).map((row) => row.count));

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Admin"
        title="Usage dashboard"
        description="How many people are using BrassTune, how active they are, and what they use. Private to admins."
        meta={metrics ? <span className="muted-copy">as of {new Date(metrics.generated_at).toLocaleString()}</span> : undefined}
      />
      {loading && <p className="settings-status" role="status">Loading metrics…</p>}
      {metrics && (
        <>
          <SectionCard title="At a glance" eyebrow="Totals">
            <div className="metrics-grid">
              <StatTile label="Total users" value={metrics.totals.users} hint={`+${metrics.new_users.last_7d} in 7d`} />
              <StatTile label="Active today" value={metrics.active_users.dau} hint="signed in ≤24h" />
              <StatTile label="Active this week" value={metrics.active_users.wau} hint="signed in ≤7d" />
              <StatTile label="Active this month" value={metrics.active_users.mau} hint="signed in ≤30d" />
              <StatTile label="Practice sessions" value={metrics.totals.sessions} hint={`${metrics.sessions.last_7d} in 7d`} />
              <StatTile label="Ensembles" value={metrics.totals.ensembles} />
            </div>
          </SectionCard>

          <SectionCard title="New sign-ups" eyebrow="Last 14 days">
            {metrics.signups_by_day.length === 0 ? (
              <p className="muted-copy">No sign-ups in the last 14 days.</p>
            ) : (
              <div className="signup-bars">
                {metrics.signups_by_day.map((row) => (
                  <div className="signup-bar" key={row.date} title={`${row.date}: ${row.count}`}>
                    <span className="signup-bar-fill" style={{ height: `${Math.round((row.count / maxSignups) * 100)}%` }} />
                    <span className="signup-bar-count">{row.count}</span>
                    <span className="signup-bar-date">{row.date.slice(5)}</span>
                  </div>
                ))}
              </div>
            )}
          </SectionCard>

          <SectionCard title="Feature usage" eyebrow="Events, last 30 days">
            <div className="metrics-grid">
              {Object.keys(EVENT_LABELS).map((key) => (
                <StatTile key={key} label={EVENT_LABELS[key]} value={metrics.events_30d[key] ?? 0} />
              ))}
            </div>
            <p className="muted-copy" style={{ marginTop: '12px' }}>
              <Activity size={14} style={{ verticalAlign: 'middle', marginRight: 6 }} />
              Counts come from lightweight in-app events. Sign-ins refresh the “active” numbers above.
            </p>
          </SectionCard>

          <SectionCard title="Where this comes from" eyebrow="How it works">
            <div className="insight-grid">
              <article className="insight-card">
                <span className="insight-icon"><Users size={18} /></span>
                <h3>Users &amp; activity</h3>
                <p>Counted from the users table; “active” uses each account’s last sign-in timestamp.</p>
              </article>
              <article className="insight-card tone-gold">
                <span className="insight-icon"><BarChart3 size={18} /></span>
                <h3>Feature events</h3>
                <p>Coarse server-side events (sign-up, sessions, ensembles). No third-party tracker, no per-note logging.</p>
              </article>
            </div>
          </SectionCard>
        </>
      )}
    </ScreenContainer>
  );
}
