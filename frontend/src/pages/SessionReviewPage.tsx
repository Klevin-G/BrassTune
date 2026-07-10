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
import { LoadingSkeleton, MetricTile, PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import { instrumentDisplayName } from '../domain/instrumentNames';
import { describeCents, describeInTunePercent } from '../domain/tuningLanguage';
import { getGuestSession, isGuestSessionId, type GuestSessionDetail } from '../domain/guestSessions';
import type { NoteEvent, NoteStats, PracticeSession, Recommendation } from '../domain/types';
import './SessionReviewPage.css';

type SessionDetail = PracticeSession & { samples_count: number; note_events: NoteEvent[] };

export function SessionReviewPage() {
  const { id } = useParams();
  const [session, setSession] = useState<SessionDetail | null>(null);
  const [stats, setStats] = useState<NoteStats[]>([]);
  const [heatmap, setHeatmap] = useState<NoteStats[]>([]);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    setNotFound(false);
    if (isGuestSessionId(id)) {
      const guestSession = getGuestSession(id);
      if (guestSession) {
        setSession(guestSession);
        setStats(guestSession.note_stats);
        setHeatmap(guestSession.heatmap);
        setRecommendations(guestSession.recommendations);
        setLoading(false);
      } else {
        setNotFound(true);
        setLoading(false);
      }
      return;
    }
    Promise.all([getSession(id), getSessionAnalytics(id)])
      .then(([sessionData, analytics]) => {
        setSession(sessionData);
        setStats(analytics.note_stats);
        setHeatmap(analytics.heatmap);
        setRecommendations(analytics.recommendations);
        setLoading(false);
      })
      .catch(() => {
        const guestSession = getGuestSession(id);
        if (!guestSession) {
          setNotFound(true);
          setLoading(false);
          return;
        }
        setSession(guestSession);
        setStats(guestSession.note_stats);
        setHeatmap(guestSession.heatmap);
        setRecommendations(guestSession.recommendations);
        setLoading(false);
      });
  }, [id]);

  if (!session && loading) {
    return (
      <ScreenContainer>
        <SectionCard title="Loading recording">
          <LoadingSkeleton rows={4} />
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (!session || notFound) {
    return (
      <ScreenContainer>
        <SectionCard title="Recording not found" eyebrow="Review">
          <p className="muted-copy">We couldn&apos;t find this recording. It may have been deleted.</p>
          <div className="settings-actions">
            <Link className="primary-button" to="/practice">Start practicing</Link>
            <Link className="ghost-button" to="/sessions">All recordings</Link>
          </div>
        </SectionCard>
      </ScreenContainer>
    );
  }

  const pct = Math.round(session.in_tune_percentage);
  const verdict = describeInTunePercent(session.in_tune_percentage);
  const tone = verdict.tone === 'muted' ? 'default' : verdict.tone;
  const centsVerdict = describeCents(session.average_signed_cents);
  const lead = pct >= 85 ? 'Nicely in tune!' : pct >= 60 ? 'You were mostly in tune.' : 'This one needs some work — keep at it.';
  const drift =
    session.notes_count === 0
      ? ''
      : centsVerdict.direction === 'center'
        ? ' Your pitch stayed right in the middle.'
        : ` You tended to play ${centsVerdict.label.toLowerCase()}.`;
  const signedDirection =
    session.average_signed_cents > 5 ? 'sharp' : session.average_signed_cents < -5 ? 'flat' : 'centered';
  const when = new Date(session.started_at).toLocaleString();

  return (
    <ScreenContainer className="sr-screen">
      <PageHeader
        title={session.name}
        description={
          session.guest_session
            ? `Saved on this device ${when} · ${session.notes_count} notes played`
            : `Recorded ${when} · ${session.notes_count} notes played`
        }
        action={
          <Link className="ghost-button" to="/sessions">
            <ArrowLeft size={16} />
            All recordings
          </Link>
        }
        meta={
          <>
            <StatusBadge tone="gold">{instrumentDisplayName(session.instrument_id)}</StatusBadge>
            {session.guest_session && <StatusBadge tone="muted">Saved on this device</StatusBadge>}
          </>
        }
      />

      <section className={`sr-hero tone-${verdict.tone}`}>
        <div className="sr-hero-score">
          <strong>{pct}%</strong>
          <span>in tune</span>
        </div>
        <div className="sr-hero-copy">
          <StatusBadge tone={verdict.tone}>{verdict.label}</StatusBadge>
          <p>{lead}{drift}</p>
        </div>
        <div className="sr-hero-audio">
          <SessionAudioPlayer session={session} />
        </div>
      </section>

      <div className="stats-grid">
        <MetricTile label="In tune" value={`${pct}%`} icon={Percent} tone={tone} />
        <MetricTile label="How close (avg)" value={`${session.average_abs_cents.toFixed(1)}¢`} detail="off center" icon={Gauge} />
        <MetricTile
          label="Sharp / flat (avg)"
          value={`${session.average_signed_cents > 0 ? '+' : ''}${session.average_signed_cents.toFixed(1)}¢`}
          detail={signedDirection}
          icon={Music2}
        />
        <MetricTile label="Length" value={`${Math.round(session.duration_seconds)}s`} detail={`${session.notes_count} notes`} icon={Timer} />
      </div>
      <p className="sr-cents-note">
        Cents (¢) measure how sharp or flat a note is. 0 is perfectly in tune, and under 5 sounds in tune. A minus number means flat (too low); a plus number means sharp (too high).
      </p>

      <div className="two-column-grid">
        {heatmap.length > 0 && (
          <SectionCard title="How each note went" eyebrow="By note">
            <HeatMapGrid rows={heatmap} />
            <div className="sr-legend">
              <span className="sr-legend-item"><i className="sr-swatch sr-swatch-green" /> In tune</span>
              <span className="sr-legend-item"><i className="sr-swatch sr-swatch-amber" /> A little off</span>
              <span className="sr-legend-item"><i className="sr-swatch sr-swatch-red" /> Needs work</span>
              <span className="sr-legend-note">Number = cents. A minus is flat, a plus is sharp.</span>
            </div>
          </SectionCard>
        )}
        {session.note_events.length > 0 && (
          <SectionCard title="Note timeline" eyebrow="First 8 notes">
            <div className="timeline-stack">
              {session.note_events.slice(0, 8).map((event) => (
                <div className="timeline-row" key={event.id}>
                  <strong>{event.note_label}</strong>
                  <span>{event.avg_signed_cents > 0 ? '+' : ''}{event.avg_signed_cents.toFixed(1)}¢</span>
                  <em>{event.duration_seconds.toFixed(1)}s</em>
                </div>
              ))}
            </div>
          </SectionCard>
        )}
      </div>

      {recommendations.length > 0 && (
        <SectionCard title="What to work on next">
          <div className="recommendation-grid">
            {recommendations.map((recommendation) => (
              <RecommendationCard key={`${recommendation.related_note}-${recommendation.category}`} recommendation={recommendation} />
            ))}
          </div>
        </SectionCard>
      )}

      <details className="sr-advanced">
        <summary>
          <SlidersHorizontal size={16} />
          Advanced · for teachers
        </summary>
        <div className="sr-advanced-body">
          <div>
            <h3 className="sr-advanced-heading">Every note</h3>
            <NoteStatsTable rows={stats} />
          </div>
          <div>
            <h3 className="sr-advanced-heading">Download data</h3>
            <ExportButtons sessionId={session.id} guestSession={session.guest_session ? (session as GuestSessionDetail) : null} />
          </div>
        </div>
      </details>
    </ScreenContainer>
  );
}
