import { ArrowLeft, Gauge, Music2, Percent, SlidersHorizontal, Timer } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useParams } from 'react-router-dom';
import { getSession, getSessionAnalytics } from '../api/client';
import { ExportButtons } from '../components/ExportButtons';
import { HeatMapGrid } from '../components/HeatMapGrid';
import { NoteStatsTable } from '../components/NoteStatsTable';
import { RecommendationCard } from '../components/RecommendationCard';
import { SessionAudioPlayer } from '../components/SessionAudioPlayer';
import { PracticeReflectionCard } from '../components/practice/PracticeReflectionCard';
import { WeakTransitionCard } from '../components/practice/WeakTransitionCard';
import { LoadingSkeleton, MetricTile, PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import { describeCents, describeInTunePercent } from '../domain/tuningLanguage';
import { getGuestSession, GUEST_WORKSPACE_ACCESS, isGeneratedGuestSessionName, isGuestSessionId, type GuestSessionDetail } from '../domain/guestSessions';
import type { NoteEvent, NoteStats, PracticeSession, Recommendation } from '../domain/types';
import { useAuth } from '../state/AuthContext';
import { authPathWithReturn } from '../domain/authNavigation';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';
import './SessionReviewPage.css';

type SessionDetail = PracticeSession & { samples_count: number; note_events: NoteEvent[] };
type ReviewLoadError = 'not-found' | 'auth' | 'network' | null;

export function classifySessionReviewError(error: unknown): Exclude<ReviewLoadError, null> {
  const message = error instanceof Error ? error.message : String(error ?? '');
  if (/sign in|authentication required|unauthorized|session expired/i.test(message)) return 'auth';
  if (/not available for this account|not found|do not have access/i.test(message)) return 'not-found';
  return 'network';
}

export function SessionReviewPage() {
  const { t, formatDate, formatNumber } = useI18n();
  const { id } = useParams();
  const auth = useAuth();
  const guestAccess = !auth.loading && !auth.isSignedIn && auth.guestMode ? GUEST_WORKSPACE_ACCESS : undefined;
  const [session, setSession] = useState<SessionDetail | null>(null);
  const [stats, setStats] = useState<NoteStats[]>([]);
  const [heatmap, setHeatmap] = useState<NoteStats[]>([]);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<ReviewLoadError>(null);
  const [retryKey, setRetryKey] = useState(0);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setLoadError(null);
    setSession(null);
    setStats([]);
    setHeatmap([]);
    setRecommendations([]);
    if (!id) {
      setLoadError('not-found');
      setLoading(false);
      return () => {
        active = false;
      };
    }
    if (isGuestSessionId(id)) {
      const guestSession = getGuestSession(id, guestAccess);
      if (guestSession) {
        setSession(guestSession);
        setStats(guestSession.note_stats);
        setHeatmap(guestSession.heatmap);
        setRecommendations(guestSession.recommendations);
        setLoading(false);
      } else {
        setLoadError('not-found');
        setLoading(false);
      }
      return () => {
        active = false;
      };
    }
    if (auth.loading) {
      return () => {
        active = false;
      };
    }
    if (!auth.isSignedIn) {
      setLoadError('auth');
      setLoading(false);
      return () => {
        active = false;
      };
    }
    Promise.all([getSession(id), getSessionAnalytics(id)])
      .then(([sessionData, analytics]) => {
        if (!active) return;
        setSession(sessionData);
        setStats(analytics.note_stats);
        setHeatmap(analytics.heatmap);
        setRecommendations(analytics.recommendations);
        setLoading(false);
      })
      .catch((error) => {
        if (!active) return;
        setLoadError(classifySessionReviewError(error));
        setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [auth.guestMode, auth.isSignedIn, auth.loading, auth.profile?.id, guestAccess, id, retryKey]);

  if (loading) {
    return (
      <ScreenContainer>
        <SectionCard title={t('sessionReview.loading')}>
          <LoadingSkeleton rows={4} label={t('sessionReview.loading')} />
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (loadError === 'network') {
    return (
      <ScreenContainer>
        <SectionCard title={t('sessionReview.loadFailed')} eyebrow={t('sessionReview.connection')}>
          <p className="muted-copy">{t('sessionReview.connectionBody')}</p>
          <div className="settings-actions">
            <button className="primary-button" type="button" onClick={() => setRetryKey((current) => current + 1)}>{t('auth.tryAgain')}</button>
            <Link className="ghost-button" to="/sessions">{t('sessionReview.all')}</Link>
          </div>
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (loadError === 'auth') {
    const next = id ? `/sessions/${id}` : '/sessions';
    return (
      <ScreenContainer>
        <SectionCard title={t('sessionReview.signInTitle')} eyebrow={t('sessionReview.accountRequired')}>
          <p className="muted-copy">{t('sessionReview.signInBody')}</p>
          <div className="settings-actions">
            <Link className="primary-button" to={authPathWithReturn('/auth/sign-in', next)} onClick={auth.exitGuest}>{t('nav.signIn')}</Link>
            <Link className="ghost-button" to="/sessions">{t('sessionReview.all')}</Link>
          </div>
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (!session || loadError === 'not-found') {
    return (
      <ScreenContainer>
        <SectionCard title={t('sessionReview.notFound')} eyebrow={t('sessionReview.review')}>
          <p className="muted-copy">{t('sessionReview.notFoundBody')}</p>
          <div className="settings-actions">
            <Link className="primary-button" to="/practice">{t('auth.start')}</Link>
            <Link className="ghost-button" to="/sessions">{t('sessionReview.all')}</Link>
          </div>
        </SectionCard>
      </ScreenContainer>
    );
  }

  const pct = Math.round(session.in_tune_percentage);
  const verdict = describeInTunePercent(session.in_tune_percentage);
  const tone = verdict.tone === 'muted' ? 'default' : verdict.tone;
  const centsVerdict = describeCents(session.average_signed_cents);
  const lead = t(pct >= 85 ? 'sessionReview.leadGreat' : pct >= 60 ? 'sessionReview.leadMostly' : 'sessionReview.leadWork');
  const drift =
    session.notes_count === 0
      ? ''
      : centsVerdict.direction === 'center'
        ? ` ${t('sessionReview.driftCentered')}`
        : ` ${t(centsVerdict.direction === 'sharp' ? 'sessionReview.driftSharp' : 'sessionReview.driftFlat')}`;
  const signedDirection =
    t(session.average_signed_cents > 5 ? 'tuning.sharp' : session.average_signed_cents < -5 ? 'tuning.flat' : 'sessionReview.centered');
  const when = formatDate(new Date(session.started_at), { dateStyle: 'medium', timeStyle: 'short' });
  const verdictLabel = centsVerdict.tone === 'green' ? t('tuning.inTune') : centsVerdict.direction === 'sharp' ? t(centsVerdict.tone === 'amber' ? 'tuning.littleSharp' : 'tuning.sharp') : t(centsVerdict.tone === 'amber' ? 'tuning.littleFlat' : 'tuning.flat');
  const sessionTitle = session.guest_session && isGeneratedGuestSessionName(session.name)
    ? t('sessionReview.review')
    : session.name;

  return (
    <ScreenContainer className="sr-screen">
      <PageHeader
        title={sessionTitle}
        description={
          session.guest_session
            ? t('sessionReview.deviceDescription', { when, count: formatNumber(session.notes_count) })
            : t('sessionReview.cloudDescription', { when, count: formatNumber(session.notes_count) })
        }
        action={
          <Link className="ghost-button" to="/sessions">
            <ArrowLeft size={16} />
            {t('sessionReview.all')}
          </Link>
        }
        meta={
          <>
            <StatusBadge tone="gold">{t(`instrument.${session.instrument_id}` as MessageId)}</StatusBadge>
            {session.guest_session && <StatusBadge tone="muted">{t('sessionReview.savedDevice')}</StatusBadge>}
          </>
        }
      />

      <section className={`sr-hero tone-${verdict.tone}`}>
        <div className="sr-hero-score">
          <strong><bdi dir="ltr">{pct}%</bdi></strong>
          <span>{t('tuning.inTune')}</span>
        </div>
        <div className="sr-hero-copy">
          <StatusBadge tone={verdict.tone}>{verdictLabel}</StatusBadge>
          <p>{lead}{drift}</p>
        </div>
        <div className="sr-hero-audio">
          <SessionAudioPlayer session={session} />
        </div>
      </section>

      <div className="stats-grid">
        <MetricTile label={t('tuning.inTune')} value={<bdi dir="ltr">{formatNumber(pct)}%</bdi>} icon={Percent} tone={tone} />
        <MetricTile label={t('sessionReview.howClose')} value={<bdi dir="ltr">{formatNumber(session.average_abs_cents, { maximumFractionDigits: 1 })}¢</bdi>} detail={t('sessionReview.offCenter')} icon={Gauge} />
        <MetricTile
          label={t('sessionReview.sharpFlat')}
          value={<bdi dir="ltr">{session.average_signed_cents > 0 ? '+' : ''}{formatNumber(session.average_signed_cents, { maximumFractionDigits: 1 })}¢</bdi>}
          detail={signedDirection}
          icon={Music2}
        />
        <MetricTile label={t('sessionReview.length')} value={<bdi dir="ltr">{t('sessionReview.secondsShort', { count: formatNumber(Math.round(session.duration_seconds)) })}</bdi>} detail={t('playAlong.noteCount', { count: session.notes_count })} icon={Timer} />
      </div>
      <p className="sr-cents-note">
        {t('sessionReview.centsHelp')}
      </p>

      <div className="two-column-grid">
        {heatmap.length > 0 && (
          <SectionCard title={t('sessionReview.eachNote')} eyebrow={t('sessionReview.byNote')}>
            <HeatMapGrid rows={heatmap} />
            <div className="sr-legend">
              <span className="sr-legend-item"><i className="sr-swatch sr-swatch-green" /> {t('tuning.inTune')}</span>
              <span className="sr-legend-item"><i className="sr-swatch sr-swatch-amber" /> {t('playAlong.grade.close')}</span>
              <span className="sr-legend-item"><i className="sr-swatch sr-swatch-red" /> {t('sessionReview.needsWork')}</span>
              <span className="sr-legend-note">{t('sessionReview.legendHelp')}</span>
            </div>
          </SectionCard>
        )}
        {session.note_events.length > 0 && (
          <SectionCard title={t('sessionReview.timeline')} eyebrow={t('sessionReview.firstNotes', { count: formatNumber(8) })}>
            <div className="timeline-stack">
              {session.note_events.slice(0, 8).map((event) => (
                <div className="timeline-row" key={event.id}>
                  <strong><bdi dir="ltr">{event.note_label}</bdi></strong>
                  <span><bdi dir="ltr">{event.avg_signed_cents > 0 ? '+' : ''}{event.avg_signed_cents.toFixed(1)}¢</bdi></span>
                  <em><bdi dir="ltr">{event.duration_seconds.toFixed(1)}s</bdi></em>
                </div>
              ))}
            </div>
          </SectionCard>
        )}
      </div>

      {recommendations.length > 0 && (
        <SectionCard title={t('sessionReview.nextWork')}>
          <div className="recommendation-grid">
            {recommendations.map((recommendation) => (
              <RecommendationCard
                key={`${recommendation.related_note}-${recommendation.category}`}
                recommendation={recommendation}
                localizeGuestRecommendation={Boolean(session.guest_session)}
              />
            ))}
          </div>
        </SectionCard>
      )}

      <WeakTransitionCard events={session.note_events} />
      <PracticeReflectionCard sessionId={String(session.id)} />

      <details className="sr-advanced">
        <summary>
          <SlidersHorizontal size={16} />
          {t('sessionReview.advanced')}
        </summary>
        <div className="sr-advanced-body">
          <div>
            <h3 className="sr-advanced-heading">{t('sessionReview.everyNote')}</h3>
            <NoteStatsTable rows={stats} />
          </div>
          <div>
            <h3 className="sr-advanced-heading">{t('sessionReview.downloadData')}</h3>
            <ExportButtons
              sessionId={session.id}
              guestSession={session.guest_session ? (session as GuestSessionDetail) : null}
              audioAvailable={Boolean(session.audio_available)}
            />
          </div>
        </div>
      </details>
    </ScreenContainer>
  );
}
