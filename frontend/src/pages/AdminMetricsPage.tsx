import { Activity } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Navigate } from 'react-router-dom';
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
  const isAdmin = auth.profile?.role === 'admin';
  const [metrics, setMetrics] = useState<AdminMetrics | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!isAdmin) {
      setLoading(false);
      return;
    }
    getAdminMetrics()
      .then(setMetrics)
      .catch((err) => setError(friendlyUserFacingError(err, 'Could not load the dashboard right now.')))
      .finally(() => setLoading(false));
  }, [isAdmin]);

  if (!isAdmin) {
    return <Navigate to="/practice" replace />;
  }

  const maxSignups = Math.max(1, ...(metrics?.signups_by_day ?? []).map((row) => row.count));

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Admin"
        title="Usage dashboard"
        description="Who's using BrassTune and how active they are."
        meta={metrics ? <span className="muted-copy">as of {new Date(metrics.generated_at).toLocaleString()}</span> : undefined}
      />
      {loading && <p className="settings-status" role="status">Loading metrics…</p>}
      {!loading && error && (
        <SectionCard title="Couldn't load metrics">
          <p className="muted-copy">{error}</p>
        </SectionCard>
      )}
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
              Basic in-app counts only. No third-party trackers. Activity is based on each account's last sign-in.
            </p>
          </SectionCard>
        </>
      )}
    </ScreenContainer>
  );
}
