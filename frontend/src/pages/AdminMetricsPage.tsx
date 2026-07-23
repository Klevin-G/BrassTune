import { Activity } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Navigate } from 'react-router-dom';
import { friendlyUserFacingError, getAdminMetrics, type AdminMetrics } from '../api/client';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { useAuth } from '../state/AuthContext';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';

function StatTile({ label, value, hint }: { label: string; value: string | number; hint?: string }) {
  return (
    <article className="stat-card">
      <span>{label}</span>
      <strong>{value}</strong>
      {hint && <p>{hint}</p>}
    </article>
  );
}

const EVENT_LABELS: Record<string, MessageId> = {
  signup: 'admin.signups',
  session_started: 'admin.sessionsStarted',
  session_completed: 'admin.sessionsCompleted',
  group_created: 'admin.ensemblesCreated',
};

export function AdminMetricsPage() {
  const { locale, t, formatDate, formatNumber } = useI18n();
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
      .catch((err) => setError(locale === 'en' ? friendlyUserFacingError(err, t('admin.loadFailedBody')) : t('admin.loadFailedBody')))
      .finally(() => setLoading(false));
  }, [isAdmin, locale, t]);

  if (!isAdmin) {
    return <Navigate to="/practice" replace />;
  }

  const maxSignups = Math.max(1, ...(metrics?.signups_by_day ?? []).map((row) => row.count));

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow={t('admin.eyebrow')}
        title={t('admin.title')}
        description={t('admin.description')}
        meta={metrics ? <span className="muted-copy">{t('admin.asOf', { date: formatDate(metrics.generated_at, { dateStyle: 'medium', timeStyle: 'short' }) })}</span> : undefined}
      />
      {loading && <p className="settings-status" role="status">{t('admin.loading')}</p>}
      {!loading && error && (
        <SectionCard title={t('admin.loadFailed')}>
          <p className="muted-copy">{error}</p>
        </SectionCard>
      )}
      {metrics && (
        <>
          <SectionCard title={t('admin.atGlance')} eyebrow={t('admin.totals')}>
            <div className="metrics-grid">
              <StatTile label={t('admin.totalUsers')} value={formatNumber(metrics.totals.users)} hint={t('admin.inSevenDays', { count: formatNumber(metrics.new_users.last_7d) })} />
              <StatTile label={t('admin.activeToday')} value={formatNumber(metrics.active_users.dau)} hint={t('admin.signedInHours', { count: formatNumber(24) })} />
              <StatTile label={t('admin.activeWeek')} value={formatNumber(metrics.active_users.wau)} hint={t('admin.signedInDays', { count: formatNumber(7) })} />
              <StatTile label={t('admin.activeMonth')} value={formatNumber(metrics.active_users.mau)} hint={t('admin.signedInDays', { count: formatNumber(30) })} />
              <StatTile label={t('admin.practiceSessions')} value={formatNumber(metrics.totals.sessions)} hint={t('admin.inSevenDaysPlain', { count: formatNumber(metrics.sessions.last_7d) })} />
              <StatTile label={t('admin.ensembles')} value={formatNumber(metrics.totals.ensembles)} />
            </div>
          </SectionCard>

          <SectionCard title={t('admin.newSignups')} eyebrow={t('admin.lastDays', { count: formatNumber(14) })}>
            {metrics.signups_by_day.length === 0 ? (
              <p className="muted-copy">{t('admin.noSignups')}</p>
            ) : (
              <div className="signup-bars">
                {metrics.signups_by_day.map((row) => (
                  <div className="signup-bar" key={row.date} title={t('admin.signupCount', { date: formatDate(row.date), count: formatNumber(row.count) })}>
                    <span className="signup-bar-fill" style={{ height: `${Math.round((row.count / maxSignups) * 100)}%` }} />
                    <span className="signup-bar-count"><bdi dir="ltr">{formatNumber(row.count)}</bdi></span>
                    <span className="signup-bar-date">{row.date.slice(5)}</span>
                  </div>
                ))}
              </div>
            )}
          </SectionCard>

          <SectionCard title={t('admin.featureUsage')} eyebrow={t('admin.eventsLastDays', { count: formatNumber(30) })}>
            <div className="metrics-grid">
              {Object.keys(EVENT_LABELS).map((key) => (
                <StatTile key={key} label={t(EVENT_LABELS[key])} value={formatNumber(metrics.events_30d[key] ?? 0)} />
              ))}
            </div>
            <p className="muted-copy" style={{ marginTop: '12px' }}>
              <Activity size={14} style={{ verticalAlign: 'middle', marginRight: 6 }} />
              {t('admin.privacyNote')}
            </p>
          </SectionCard>
        </>
      )}
    </ScreenContainer>
  );
}
